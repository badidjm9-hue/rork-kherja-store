//
//  NegotiationView.swift
//  KHERJA
//
//  Fare negotiation: live offers, quick replies, chat, countdown, price lock.
//

import Supabase
import SwiftUI

struct NegotiationView: View {
    @EnvironmentObject var store: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let request: RideRequest
    var onAccepted: () -> Void

    @State private var offers: [OfferWithDriver] = []
    @State private var messages: [RideMessage] = []
    @State private var draft = ""
    @State private var loading = true
    @State private var acceptingOfferId: UUID?
    @State private var errorText: String?
    @State private var now = Date()
    @State private var ticker: Timer?
    @State private var pollTimer: Timer?

    var remaining: TimeInterval {
        max(0, request.expiresAt.timeIntervalSince(now))
    }

    var pendingOffers: [OfferWithDriver] {
        offers.filter { $0.status == "pending" }
    }

    var bestOffer: OfferWithDriver? {
        pendingOffers.first
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0)

            ScrollView {
                VStack(spacing: 14) {
                    negotiationBanner

                    if loading {
                        PulsingDots().padding(.top, 30)
                    } else if let offer = bestOffer {
                        OfferCard(
                            offer: offer,
                            accepted: false,
                            accepting: acceptingOfferId == offer.id
                        ) { accept(offer) }
                    }

                    if !messages.isEmpty {
                        chatSection
                    }

                    if !loading && pendingOffers.isEmpty {
                        VStack(spacing: 8) {
                            PulsingDots()
                            Text(store.l("no_offers_yet"))
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(KJ.muted)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.vertical, 26)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
            }
            .scrollBounceBehavior(.basedOnSize)

            Spacer(minLength: 0)

            countdownBar

            quickReplies

            inputBar
        }
        .background(KJ.canvasGradient.ignoresSafeArea())
        .onAppear { start() }
        .onDisappear {
            ticker?.invalidate()
            pollTimer?.invalidate()
        }
        .alert(store.l("error_generic"), isPresented: .constant(errorText != nil)) {
            Button(store.l("ok"), role: .cancel) { errorText = nil }
        }
    }

    // MARK: Sections

    private var header: some View {
        VStack(spacing: 2) {
            HStack(spacing: 10) {
                Image(systemName: "hand.raised.app.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(KJ.blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.l("negotiation_open"))
                        .font(.system(size: 18, weight: .heavy))
                        .foregroundStyle(KJ.ink)
                    Text("\(request.pickupLabel) → \(request.destLabel) · \(KJFormat.dzd(request.proposedFare))")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(KJ.muted)
                        .lineLimit(1)
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)

            Text(store.l("negotiation_hint"))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(KJ.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 4)
        }
    }

    private var negotiationBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "figure.hand.wave")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(KJ.blue)
            VStack(alignment: .leading, spacing: 2) {
                Text(store.l("negotiation_open"))
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(KJ.blue)
                Text(store.l("negotiation_hint"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(KJ.muted)
            }
            Spacer()
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(KJ.softBlue))
    }

    private var chatSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(messages) { message in
                let mine = message.senderId == store.session.userId
                if message.body.hasPrefix("OFFRE_ACCEPTEE:") {
                    HStack {
                        Spacer()
                        Label("\(store.l("offer_accepted")) · \(KJFormat.dzd(Int(message.body.dropFirst(15)) ?? 0))", systemImage: "lock.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(KJ.success)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Capsule().fill(KJ.successBg))
                        Spacer()
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                } else {
                    ChatBubble(
                        text: message.body,
                        time: message.createdAt,
                        mine: mine
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
    }

    private var countdownBar: some View {
        let total: TimeInterval = 600
        let progress = total > 0 ? remaining / total : 0
        return VStack(spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: "timer")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(KJ.blue)
                VStack(spacing: 0) {
                    Text(Self.clock(remaining))
                        .font(.system(size: 30, weight: .heavy, design: .monospaced))
                        .foregroundStyle(KJ.ink)
                    Text(store.l("time_left"))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(KJ.muted)
                }
                Spacer()
            }
            GeometryReader { geo in
                Capsule()
                    .fill(KJ.softBlueMid)
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(progress > 0.2 ? AnyShapeStyle(KJ.blue) : AnyShapeStyle(KJ.danger))
                            .frame(width: geo.size.width * progress)
                            .animation(.linear(duration: 0.5), value: progress)
                    }
            }
            .frame(height: 6)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(.white))
        .padding(.horizontal, 20)
    }

    private var quickReplies: some View {
        HStack(spacing: 10) {
            QuickReply(label: store.l("propose")) { proposeCounter() }
            QuickReply(label: store.l("can_you_lower")) { send(text: store.l("can_you_lower")) }
            QuickReply(label: store.l("deal")) {
                if let offer = bestOffer { accept(offer) }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField(store.l("write_message"), text: $draft)
                .font(.system(size: 15, weight: .medium))
                .padding(.horizontal, 18)
                .frame(height: 50)
                .background(Capsule().fill(.white))
                .overlay(Capsule().strokeBorder(KJ.muted.opacity(0.2)))

            Button {
                send()
            } label: {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 50, height: 50)
                    .background(Circle().fill(KJ.buttonGradient))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    // MARK: Actions

    private func start() {
        ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            Task { @MainActor in now = Date() }
        }
        pollTimer = Timer.scheduledTimer(withTimeInterval: 3.5, repeats: true) { _ in
            Task { @MainActor in await poll() }
        }
        Task { await poll() }
    }

    private func poll() async {
        do {
            let fetchedOffers: [OfferWithDriver] = try await SupabaseService.shared
                .client
                .from("offers")
                .select("*, driver:profiles!offers_driver_id_fkey(*)")
                .eq("request_id", value: request.id.uuidString)
                .order("created_at", ascending: false)
                .execute()
                .decoded(SupabaseService.decoder())
            offers = fetchedOffers
            let fetchedMessages = try await SupabaseService.shared.messages(requestId: request.id)
            if reduceMotion {
                messages = fetchedMessages
            } else {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.9)) {
                    messages = fetchedMessages
                }
            }
            errorText = nil
        } catch {
            print("KHERJA negotiation poll error: \(error)")
        }
        loading = false
    }

    private func send(text: String? = nil) {
        let body = text ?? draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty, let senderId = store.session.userId else { return }
        draft = ""
        Task {
            try? await SupabaseService.shared.sendMessage(requestId: request.id, senderId: senderId, body: body)
            await poll()
        }
    }

    private func proposeCounter() {
        // Passenger counter is a chat message; drivers answer with a new offer
        // (offers are created server-side by drivers only, within limits).
        let price = max(50, (bestOffer?.price ?? request.proposedFare) - 50)
        guard let senderId = store.session.userId else { return }
        Task {
            try? await SupabaseService.shared.sendMessage(requestId: request.id, senderId: senderId, body: "\(store.l("propose")) \(KJFormat.dzd(price))")
            await poll()
        }
    }

    private func accept(_ offer: OfferWithDriver) {
        acceptingOfferId = offer.id
        Task {
            do {
                let rideId = try await SupabaseService.shared.acceptOffer(offer.id)
                await MainActor.run {
                    acceptingOfferId = nil
                    onAccepted()
                    _ = rideId
                }
            } catch {
                await MainActor.run {
                    acceptingOfferId = nil
                    errorText = store.l("error_generic")
                }
            }
        }
    }

    private static func clock(_ interval: TimeInterval) -> String {
        let m = Int(interval) / 60
        let s = Int(interval) % 60
        return String(format: "%02d:%02d", m, s)
    }
}

// MARK: - Offer card

struct OfferCard: View {
    let offer: OfferWithDriver
    let accepted: Bool
    let accepting: Bool
    var onAccept: (() -> Void)?

    var body: some View {
        HStack(spacing: 14) {
            Circle()
                .fill(KJ.softBlue)
                .frame(width: 54, height: 54)
                .overlay(
                    Text(initials)
                        .font(.system(size: 19, weight: .heavy))
                        .foregroundStyle(KJ.blue)
                )

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(driverName)
                        .font(.system(size: 17, weight: .heavy))
                        .foregroundStyle(KJ.ink)
                    HStack(spacing: 3) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(KJ.warning)
                        Text(String(format: "%.1f", driverRating))
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(KJ.ink)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(KJ.warning.opacity(0.12)))
                }
                if let vehicle = vehicleLine {
                    HStack(spacing: 6) {
                        Image(systemName: "car.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(KJ.blue)
                        Text(vehicle)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(KJ.muted)
                    }
                }
            }
            Spacer()

            VStack(alignment: .trailing, spacing: 6) {
                Text(KJFormat.dzd(offer.price))
                    .font(.system(size: 24, weight: .heavy))
                    .foregroundStyle(KJ.ink)
                Text("Prix")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(KJ.muted)
            }
        }
        .kjCard()

        if let onAccept, !accepted {
            Button {
                onAccept()
            } label: {
                HStack {
                    if accepting { ProgressView().tint(.white) }
                    else {
                        Image(systemName: "checkmark")
                        Text("Accepter l'offre")
                    }
                }
            }
            .buttonStyle(KJButtonStyle())
            .disabled(accepting)
            .padding(.top, 4)
        }
    }

    private var driverName: String { offer.driver?.name ?? "Chauffeur" }
    private var driverRating: Double { offer.driver?.ratingAvg ?? 5.0 }

    private var initials: String {
        driverName.split(separator: " ")
            .compactMap { $0.first }
            .prefix(2)
            .map(String.init)
            .joined()
            .uppercased()
    }

    private var vehicleLine: String? {
        guard let d = offer.driver else { return nil }
        let parts = [d.vehicleMake, d.vehicleModel].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }
}

// MARK: - Chat bubble + quick reply

struct ChatBubble: View {
    let text: String
    let time: Date
    let mine: Bool

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if mine { Spacer(minLength: 60) }
            if !mine {
                Circle()
                    .fill(KJ.softBlue)
                    .frame(width: 34, height: 34)
                    .overlay(Image(systemName: "person.fill").font(.system(size: 14)).foregroundStyle(KJ.blue))
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(text)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(mine ? .white : KJ.ink)
                Text(Self.clock(time))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(mine ? .white.opacity(0.7) : KJ.muted)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(mine ? AnyShapeStyle(KJ.buttonGradient) : AnyShapeStyle(Color.white))
                    .shadow(color: .black.opacity(0.05), radius: 6, y: 3)
            )
            if !mine { Spacer(minLength: 60) }
        }
    }

    private static func clock(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }
}

struct QuickReply: View {
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(KJ.ink)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.white)
                        .shadow(color: Color(hex: 0x075BFF).opacity(0.08), radius: 8, y: 4)
                )
        }
        .buttonStyle(.plain)
    }
}
