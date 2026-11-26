//
//  DriverDocumentsView.swift
//  KHERJA
//
//  Driver document upload (private Storage bucket + submit_driver_document RPC).
//  Uploads use URLSession with the session token so they do not depend on a specific
//  supabase-swift Storage signature.
//

import SwiftUI
import UniformTypeIdentifiers

nonisolated struct DriverDocument: Codable, Identifiable, Sendable, Equatable {
    let id: UUID
    var docType: String
    var storagePath: String
    var status: String
    var reason: String?

    enum CodingKeys: String, CodingKey {
        case id, status, reason
        case docType = "doc_type"
        case storagePath = "storage_path"
    }
}

nonisolated struct SubmitDocumentParams: Encodable, Sendable {
    var type: String
    var path: String
    var mime: String

    enum CodingKeys: String, CodingKey {
        case type = "p_type"
        case path = "p_path"
        case mime = "p_mime"
    }
}

nonisolated enum DriverDocumentError: Error { case unsupportedType, tooLarge, unreadable, noSession, upload(String) }

extension SupabaseService {
    static let documentTypes = ["id_card", "license", "registration", "insurance", "vehicle_photo"]
    static let maxDocumentBytes = 10 * 1024 * 1024 // matches the bucket limit

    func driverDocuments(userId: UUID) async throws -> [DriverDocument] {
        try await client
            .from("driver_documents")
            .select("id,doc_type,storage_path,status,reason")
            .eq("driver_id", value: userId.uuidString)
            .order("uploaded_at", ascending: false)
            .execute()
            .decoded(Self.decoder())
    }

    /// Uploads to `driver-documents/<userId>/<type>.<ext>`, then registers it for admin review.
    func uploadDriverDocument(userId: UUID, docType: String, data: Data, mime: String) async throws {
        let ext: String
        switch mime {
        case "image/png": ext = "png"
        case "image/heic": ext = "heic"
        case "application/pdf": ext = "pdf"
        case "image/jpeg": ext = "jpg"
        default: throw DriverDocumentError.unsupportedType
        }
        guard data.count <= Self.maxDocumentBytes else { throw DriverDocumentError.tooLarge }
        guard let token = await SessionManager.shared.validAccessToken() else { throw DriverDocumentError.noSession }

        let path = "\(userId.uuidString.lowercased())/\(docType).\(ext)"
        var request = URLRequest(url: URL(string: "\(Config.EXPO_PUBLIC_SUPABASE_URL)/storage/v1/object/driver-documents/\(path)")!)
        request.httpMethod = "POST"
        request.setValue(Config.EXPO_PUBLIC_SUPABASE_ANON_KEY, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(mime, forHTTPHeaderField: "Content-Type")
        request.setValue("true", forHTTPHeaderField: "x-upsert")
        let (body, response) = try await URLSession.shared.upload(for: request, from: data)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw DriverDocumentError.upload(String(data: body, encoding: .utf8) ?? "upload failed")
        }
        try await rpcVoid("submit_driver_document", params: SubmitDocumentParams(type: docType, path: path, mime: mime))
    }
}

struct DriverDocumentsSection: View {
    @EnvironmentObject var store: AppState
    @State private var docs: [DriverDocument]?
    @State private var busyType: String?
    @State private var pickingType: String?
    @State private var showPicker = false
    @State private var errorText: String?

    private let allowed: [UTType] = [.jpeg, .png, .heic, .pdf]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(store.l("docs_title"))
                .font(.system(size: 17, weight: .heavy))
                .foregroundStyle(KJ.ink)
            Text(store.l("docs_hint"))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(KJ.muted)

            if docs == nil {
                ProgressView().tint(KJ.blue).frame(maxWidth: .infinity)
            } else {
                ForEach(SupabaseService.documentTypes, id: \.self) { type in
                    row(type)
                }
            }

            if let errorText {
                Text(errorText)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(KJ.danger)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 12).fill(KJ.dangerBg))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task { await load() }
        .fileImporter(isPresented: $showPicker, allowedContentTypes: allowed, allowsMultipleSelection: false) { result in
            handle(result)
        }
    }

    private func row(_ type: String) -> some View {
        let doc = docs?.first { $0.docType == type }
        let approved = doc?.status == "approved"
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(store.l("doc_\(type)"))
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(KJ.ink)
                Spacer()
                statusPill(doc?.status)
            }
            if doc?.status == "rejected", let reason = doc?.reason, !reason.isEmpty {
                Text(reason)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(KJ.danger)
            }
            if !approved {
                Button {
                    pickingType = type
                    showPicker = true
                } label: {
                    if busyType == type {
                        ProgressView().tint(KJ.blue)
                    } else {
                        Text(store.l(doc == nil ? "doc_upload" : "doc_replace"))
                    }
                }
                .buttonStyle(.bordered)
                .tint(KJ.blue)
                .disabled(busyType != nil)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .kjCard()
    }

    private func statusPill(_ status: String?) -> some View {
        let (key, fg, bg): (String, Color, Color) = switch status ?? "" {
        case "approved": ("doc_approved", KJ.success, KJ.successBg)
        case "rejected": ("doc_rejected", KJ.danger, KJ.dangerBg)
        case "pending": ("doc_pending", KJ.warning, KJ.warningBg)
        default: ("doc_not_sent", KJ.muted, KJ.softBlue)
        }
        return Text(store.l(key))
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(fg)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(bg))
    }

    private func load() async {
        guard let uid = store.session.userId else { return }
        do {
            docs = try await SupabaseService.shared.driverDocuments(userId: uid)
        } catch {
            docs = []
            errorText = store.l("doc_load_failed")
        }
    }

    private func handle(_ result: Result<[URL], Error>) {
        guard let type = pickingType, let uid = store.session.userId else { return }
        pickingType = nil
        guard case .success(let urls) = result, let url = urls.first else { return }
        guard let utType = UTType(filenameExtension: url.pathExtension.lowercased()),
              let mime = Self.mime(for: utType) else {
            errorText = store.l("doc_bad_type")
            return
        }
        busyType = type
        errorText = nil
        Task {
            defer { busyType = nil }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                guard let data = try? Data(contentsOf: url) else { throw DriverDocumentError.unreadable }
                try await SupabaseService.shared.uploadDriverDocument(userId: uid, docType: type, data: data, mime: mime)
                docs = try await SupabaseService.shared.driverDocuments(userId: uid)
            } catch DriverDocumentError.tooLarge {
                errorText = store.l("doc_too_large")
            } catch DriverDocumentError.unsupportedType {
                errorText = store.l("doc_bad_type")
            } catch DriverDocumentError.unreadable {
                errorText = store.l("doc_read_failed")
            } catch {
                errorText = store.serverErrorMessage(error)
            }
        }
    }

    private static func mime(for type: UTType) -> String? {
        if type.conforms(to: .jpeg) { return "image/jpeg" }
        if type.conforms(to: .png) { return "image/png" }
        if type.conforms(to: .heic) { return "image/heic" }
        if type.conforms(to: .pdf) { return "application/pdf" }
        return nil
    }
}
