//
//  AddressPicker.swift
//  KHERJA
//
//  Pickup / destination chooser for the passenger home screen: saved places first, current location
//  (pickup only), then Apple Maps search. Not compiled in this environment.
//

import CoreLocation
import MapKit
import SwiftUI

struct AddressPickerSheet: View {
    @EnvironmentObject var store: AppState
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var location = LocationService.shared
    let title: String
    let allowCurrentLocation: Bool
    let onSelect: (_ label: String, _ coordinate: CLLocationCoordinate2D) -> Void

    @State private var query = ""
    @State private var results: [MKMapItem] = []
    @State private var saved: [SavedPlace] = []
    @State private var searching = false
    @State private var errorText: String?
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                BackCircleButton { dismiss() }
                Text(title).font(.system(size: 22, weight: .heavy)).foregroundStyle(KJ.ink)
                Spacer()
            }
            .padding(.horizontal, 20).padding(.top, 12)

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(KJ.muted)
                TextField(store.l("search_address"), text: $query)
                    .submitLabel(.search)
                    .onChange(of: query) { _, _ in scheduleSearch() }
                if !query.isEmpty {
                    Button { query = ""; results = [] } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(KJ.muted) }
                }
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.white))
            .padding(.horizontal, 20).padding(.vertical, 12)

            ScrollView {
                VStack(spacing: 0) {
                    if let errorText {
                        Text(errorText).font(.system(size: 13, weight: .bold)).foregroundStyle(KJ.danger).padding(.bottom, 8)
                    }
                    if allowCurrentLocation && query.trimmingCharacters(in: .whitespaces).count < 3 {
                        row(icon: "location.fill", title: store.l("use_my_location"), subtitle: nil) { Task { await useCurrentLocation() } }
                    }
                    if query.trimmingCharacters(in: .whitespaces).count < 3 {
                        ForEach(saved) { p in
                            row(icon: icon(p.kind), title: p.label, subtitle: p.address) {
                                onSelect(p.address, CLLocationCoordinate2D(latitude: p.lat, longitude: p.lng)); dismiss()
                            }
                        }
                    }
                    if searching { PulsingDots().padding(.top, 16) }
                    ForEach(results.indices, id: \.self) { i in
                        let item = results[i]
                        row(icon: "mappin.circle.fill", title: item.name ?? "", subtitle: item.placemark.title) {
                            let label = [item.name, item.placemark.locality].compactMap { $0 }.joined(separator: ", ")
                            onSelect(label, item.placemark.coordinate); dismiss()
                        }
                    }
                    if !searching && results.isEmpty && query.trimmingCharacters(in: .whitespaces).count >= 3 && errorText == nil {
                        Text(store.l("no_results")).font(.system(size: 14)).foregroundStyle(KJ.muted).padding(.top, 24)
                    }
                }
                .padding(.horizontal, 20)
            }
        }
        .background(KJ.canvasGradient.ignoresSafeArea())
        .task { saved = (try? await SupabaseService.shared.savedPlaces()) ?? [] }
    }

    private func icon(_ kind: String) -> String {
        switch kind { case "home": return "house.fill"; case "work": return "briefcase.fill"; default: return "star.fill" }
    }

    private func row(icon: String, title: String, subtitle: String?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon).foregroundStyle(KJ.blue).frame(width: 38, height: 38).background(Circle().fill(KJ.softBlue))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 15, weight: .bold)).foregroundStyle(KJ.ink)
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle).font(.system(size: 12)).foregroundStyle(KJ.muted).lineLimit(1)
                    }
                }
                Spacer()
            }
            .padding(.vertical, 8).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func scheduleSearch() {
        searchTask?.cancel()
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 3 else { results = []; searching = false; return }
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 350_000_000)
            if Task.isCancelled { return }
            await search(q)
        }
    }

    private func search(_ q: String) async {
        searching = true; errorText = nil
        let req = MKLocalSearch.Request()
        req.naturalLanguageQuery = q
        let center = location.location?.coordinate ?? CLLocationCoordinate2D(latitude: 36.7538, longitude: 3.0588)
        req.region = MKCoordinateRegion(center: center, span: MKCoordinateSpan(latitudeDelta: 0.6, longitudeDelta: 0.6))
        do {
            let resp = try await MKLocalSearch(request: req).start()
            if Task.isCancelled { return }
            results = Array(resp.mapItems.prefix(8))
        } catch {
            if !Task.isCancelled { errorText = store.l("error_generic"); results = [] }
        }
        searching = false
    }

    private func useCurrentLocation() async {
        errorText = nil
        location.requestPermission()
        location.refreshOnce()
        for _ in 0..<20 where location.location == nil { try? await Task.sleep(nanoseconds: 250_000_000) }
        guard let loc = location.location else { errorText = store.l("location_unavailable"); return }
        let label = await Geo.reverseGeocode(loc.coordinate)
        onSelect(label.isEmpty ? store.l("my_position") : label, loc.coordinate)
        dismiss()
    }
}
