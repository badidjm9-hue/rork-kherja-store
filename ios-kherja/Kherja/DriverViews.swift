//
//  DriverViews.swift
//  Kherja
//
//  Driver experience: online toggle + live requests feed, offer sheet,
//  active ride control, earnings, profile/vehicle.
//

import CoreLocation
import MapKit
import Supabase
import SwiftUI

struct DriverMainView: View {
    @EnvironmentObject var store: AppState
    @State private var tab = 0

    var body: some View {
        TabView(selection: $tab) {
            driverHome
                .tabItem { Label(store.l("tab_home"), systemImage: "car.fill") }
                .tag(0)
            DriverRidesView()
                .tabItem { Label(store.l("tab_jobs"), systemImage: "clock.fill") }
                .tag(1)
            WalletView()
                .tabItem { Label(store.l("tab_earnings"), systemImage: "banknote.fill") }
                .tag(2)
            DriverProfileView()
                .tabItem { Label(store.l("tab_profile"), systemImage: "gearshape.fill") }
                .tag(3)
        }
        .tint(KJ.blue)
        .task { await store.refreshProfile() }
    }

    /// Only approved, active drivers get the live feed; others see their account status.
    @ViewBuilder
    private var driverHome: some View {
        let p = store.profile
        if p?.accountStatus == "suspended" {
            DriverStatusView(kind: .suspended, reason: p?.statusReason)
        } else if let status = p?.driverStatus, status != "approved" {
            DriverStatusView(kind: status == "rejected" ? .rejected : .pending, reason: p?.statusReason)
        } else {
            DriverHomeView()
        }
    }
}

// MARK: - Driver account status (pending / rejected / suspended)

struct DriverStatusView: View {
    enum Kind { case pending, rejected, suspended }

    @EnvironmentObject var store: AppState
    let kind: Kind
    let reason: String?
    @State private var refreshing = false
    @State private var pulse = false

    private var icon: String {
        switch kind {
        case .pending: "hourglass"
        case .rejected: "xmark.seal.fill"
        case .suspended: "lock.fill"
        }
    }

    private var tint: Color {
        switch kind {
        case .pending: KJ.blue
        case .rejected, .suspended: KJ.burgundy
        }
    }

    private var titleKey: String {
        switch kind {
        case .pending: "driver_pending_title"
        case .rejected: "driver_rejected_title"
        case .suspended: "account_suspended_title"
        }
    }

    private var bodyKey: String {
        switch kind {
        case .pending: "driver_pending_body"
        case .rejected: "driver_rejected_body"
        case .suspended: "account_suspended_body"
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                ZStack {
                    Circle()
                        .fill(tint.opacity(0.10))
                        .frame(width: 150, height: 150)
                        .scaleEffect(pulse ? 1.08 : 0.94)
                    Circle()
                        .fill(tint.opacity(0.16))
                        .frame(width: 104, height: 104)
                    Image(systemName: icon)
                        .font(.system(size: 40, weight: .bold))
                        .foregroundStyle(tint)
                        .symbolEffect(.pulse, isActive: kind == .pending)
                }
                .padding(.top, 60)
                .onAppear {
                    withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) { pulse = true }
                }

                VStack(spacing: 10) {
                    Text(store.l(titleKey))
                        .font(.system(size: 24, weight: .heavy))
                        .foregroundStyle(KJ.ink)
                        .multilineTextAlignment(.center)
                    Text(store.l(bodyKey))
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(KJ.muted)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 28)

                if let reason, !reason.isEmpty, kind != .pending {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(store.l("reason"))
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(KJ.muted)
                        Text(reason)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(KJ.ink)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .kjCard()
                    .padding(.horizontal, 20)
                }

                Button {
                    refreshing = true
                    Task {
                        await store.refreshProfile()
                        refreshing = false
                    }
                } label: {
                    if refreshing {
                        ProgressView().tint(.white)
                    } else {
                        HStack {
                            Text(store.l("check_status"))
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                }
                .buttonStyle(KJButtonStyle())
                .disabled(refreshing)
                .padding(.horizontal, 20)
            }
            .frame(maxWidth: .infinity)
        }
        .background(KJ.canvasGradient.ignoresSafeArea())
        .refreshable { await store.refreshProfile() }
    }
}

// MARK: - Driver home (online toggle + feed)

struct DriverHomeView: View {
    @EnvironmentObject var store: AppState
    @ObservedObject private var location = LocationService.shared

    @State private var requests: [RequestWithPassenger] = []
    @State private var online = false
    @State private var loading = true
    @State private var selectedRequest: RequestWithPassenger?
    @State private var presenceTimer: Timer?
    @State private var feedTimer: Timer?
    @State private var myActiveRide: Ride?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(store.l("driver_space"))
                        .font(.system(size: 26, weight: .heavy))
                        .foregroundStyle(KJ.ink)
                    Text(online ? store.l("online_subtitle") : store.l("offline_subtitle"))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(online ? KJ.success : KJ.muted)
                }
                Spacer()
                OnlineToggle(isOn: online) { toggle() }
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 10)

            if let ride = myActiveRide {
                DriverActiveRideView(ride: ride) {
                    myActiveRide = nil
                    store.setActiveRide(nil)
                }
                .padding(.horizontal, 20)
                .padding(.top, 6)
            } else {
                feed
            }
        }
        .background(KJ.canvasGradient.ignoresSafeArea())
        .onAppear { start() }
        .onDisappear { stop() }
        .task {
            online = store.profile?.isOnline ?? false
            await store.refreshProfile()
            online = store.profile?.isOnline ?? false
        }
        .sheet(item: $selectedRequest) { request in
            DriverOfferSheet(request: request) {
                await refreshFeed()
            }
            .environmentObject(store)
            .presentationDragIndicator(.visible)
        }
    }

    private var feed: some View {
        VStack(spacing: 0) {
            HStack {
                Text(store.l("new_requests"))
                    .font(.system(size: 17, weight: .heavy))
                    .foregroundStyle(KJ.ink)
                Spacer()
                if !requests.isEmpty {
                    Text("\(requests.count)")
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(KJ.burgundy))
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 10)

            if !online {
                VStack(spacing: 12) {
                    Image(systemName: "power.circle.fill")
                        .font(.system(size: 52, weight: .semibold))
                        .foregroundStyle(KJ.softBlueMid)
                    Text(store.l("go_online_first"))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(KJ.muted)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if loading {
                Spacer()
                ProgressView().tint(KJ.blue).scaleEffect(1.2)
                Spacer()
            } else if requests.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "tray")
                        .font(.system(size: 40, weight: .semibold))
                        .foregroundStyle(KJ.softBlueMid)
                    Text(store.l("no_requests"))
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(KJ.ink)
                    Text(store.l("no_requests_hint"))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(KJ.muted)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 14) {
                        ForEach(requests) { request in
                            DriverRequestCard(request: request) {
                                selectedRequest = request
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
                .refreshable { await refreshFeed() }
            }
        }
    }

    // MARK: Logic

    private func start() {
        location.requestPermission()
        presenceTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { _ in
            Task { @MainActor in await pushPresence() }
        }
        feedTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in
            Task { @MainActor in await refreshFeed() }
        }
        Task {
            await pushPresence()
            await refreshFeed()
            await checkActiveRide()
        }
    }

    private func stop() {
        presenceTimer?.invalidate()
        feedTimer?.invalidate()
    }

    private func toggle() {
        online.toggle()
        Task {
            await pushPresence()
            await refreshFeed()
        }
    }

    private func pushPresence() async {
        guard store.role == "driver", let id = store.session.userId else { return }
        let update = DriverPresenceUpdate(
            currentLat: location.location?.coordinate.latitude,
            currentLng: location.location?.coordinate.longitude,
            isOnline: online,
            updatedAt: Date()
        )
        do {
            try await SupabaseService.shared.client
                .from("profiles")
                .update(update)
                .eq("id", value: id.uuidString)
                .execute()
        } catch {
            print("KHERJA presence error: \(error)")
        }
    }

    private func refreshFeed() async {
        guard online else {
            await MainActor.run { requests = []; loading = false }
            return
        }
        do {
            await SupabaseService.shared.expireStaleRequests()
            requests = try await SupabaseService.shared.openRequests()
        } catch {
            print("KHERJA feed error: \(error)")
        }
        loading = false
    }

    private func checkActiveRide() async {
        guard let userId = store.session.userId else { return }
        let rides = (try? await SupabaseService.shared.myRides(userId: userId, driver: true)) ?? []
        if let active = rides.first(where: { ["en_route", "arrived", "started"].contains($0.status) }) {
            await MainActor.run {
                myActiveRide = active
                store.setActiveRide(active.id)
            }
        }
    }
}

struct OnlineToggle: View {
    let isOn: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Circle()
                    .fill(isOn ? KJ.success : KJ.muted.opacity(0.4))
                    .frame(width: 10, height: 10)
                Text(isOn ? "En ligne" : "Hors ligne")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(isOn ? KJ.success : KJ.muted)
            }
            .padding(.horizontal, 16)
            .frame(height: 44)
            .background(Capsule().fill(.white))
            .overlay(Capsule().strokeBorder(isOn ? KJ.success.opacity(0.4) : .clear))
            .shadow(color: Color(hex: 0x075BFF).opacity(0.08), radius: 8, y: 4)
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isOn)
    }
}

// MARK: - Driver request card

struct DriverRequestCard: View {
    @EnvironmentObject var store: AppState
    let request: RequestWithPassenger
    var onTap: () -> Void

    var body: some View {
        Button {
            onTap()
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Circle().fill(KJ.success).frame(width: 9, height: 9)
                    Text("Nouvelle course")
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(KJ.success)
                    Spacer()
                    Text(String(format: "%.1f km", request.distanceKm))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(KJ.muted)
                }

                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 10) {
                        pointRow(color: KJ.blue, title: request.pickupLabel)
                        pointRow(color: KJ.burgundy, title: request.destLabel)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(KJFormat.dzd(request.proposedFare))
                            .font(.system(size: 22, weight: .heavy))
                            .foregroundStyle(KJ.ink)
                        if let estimate = request.estimatedFare {
                            Text(request.proposedFare >= estimate ? store.l("price_ok") : store.l("price_low"))
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(request.proposedFare >= estimate ? KJ.success : KJ.warning)
                        }
                    }
                }

                if let passenger = request.passenger {
                    HStack(spacing: 8) {
                        Image(systemName: "person.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(KJ.blue)
                        Text(passenger.name)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(KJ.ink)
                        HStack(spacing: 3) {
                            Image(systemName: "star.fill").font(.system(size: 10))
                            Text(String(format: "%.1f", passenger.ratingAvg))
                                .font(.system(size: 12, weight: .bold))
                        }
                        .foregroundStyle(KJ.warning)
                        Spacer()
                        Image(systemName: request.vehicle == .moto ? "motorcycle.fill" : "car.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(KJ.blue)
                    }
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(.white)
                    .shadow(color: Color(hex: 0x075BFF).opacity(0.10), radius: 12, y: 6)
            )
        }
        .buttonStyle(.plain)
    }

    private func pointRow(color: Color, title: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "mappin.circle.fill")
                .font(.system(size: 15))
                .foregroundStyle(color)
            Text(title)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(KJ.ink)
                .lineLimit(1)
        }
        .frame(maxWidth: 150, alignment: .leading)
    }
}

// MARK: - Offer sheet (accept or counter)

struct DriverOfferSheet: View {
    @EnvironmentObject var store: AppState
    let request: RequestWithPassenger
    var onDone: () async -> Void

    @State private var price: Int
    @State private var preview: DriverOfferPreview?
    @State private var previewError = false
    @State private var submitting = false
    @State private var errorText: String?

    init(request: RequestWithPassenger, onDone: @escaping () async -> Void) {
        self.request = request
        self.onDone = onDone
        _price = State(initialValue: request.proposedFare)
    }

    private func loadPreview() async {
        do {
            try await Task.sleep(for: .milliseconds(250))
            let p = try await SupabaseService.shared.driverOfferPreview(requestId: request.id, price: price)
            if Task.isCancelled { return }
            previewError = false
            if preview == nil, price < p.minPrice || price > p.maxPrice {
                // First load: bring the passenger's price into the allowed range.
                price = min(p.maxPrice, max(p.minPrice, price))
            }
            preview = p
        } catch {
            if Task.isCancelled { return }
            previewError = true
        }
    }

    var body: some View {
        VStack(spacing: 16) {
            Capsule().fill(KJ.softBlueMid).frame(width: 44, height: 5).padding(.top, 10)

            VStack(spacing: 4) {
                Text(store.l("new_ride_request"))
                    .font(.system(size: 20, weight: .heavy))
                    .foregroundStyle(KJ.ink)
                Text("\(request.pickupLabel) → \(request.destLabel)")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(KJ.muted)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: 12) {
                infoCell(icon: "point.topleft.down.curvedto.point.bottomright.up.fill", value: String(format: "%.1f", request.distanceKm), unit: store.l("km"))
                infoCell(icon: "clock", value: "\(Geo.estimatedMinutes(km: request.distanceKm, vehicle: request.vehicle))", unit: store.l("min"))
                infoCell(icon: request.vehicle == .moto ? "motorcycle.fill" : "car.fill", value: request.vehicle == .moto ? "Moto" : "Voiture", unit: "")
            }
            .padding(.horizontal, 20)

            priceBlock

            if let errorText {
                Text(errorText)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(KJ.danger)
            }

            Button {
                submit(kind: "initial")
            } label: {
                if submitting { ProgressView().tint(.white) } else {
                    HStack {
                        Text(store.l("accept_making"))
                        Image(systemName: "paperplane.fill")
                    }
                }
            }
            .buttonStyle(KJButtonStyle())
            .padding(.horizontal, 20)
            .disabled(submitting || preview == nil)
            .opacity(preview == nil ? 0.55 : 1)

            Button {
                Task { await onDone() }
            } label: {
                Text(store.l("cancel"))
                    .foregroundStyle(KJ.muted)
            }
            .padding(.bottom, 24)
        }
        .background(KJ.canvasGradient.ignoresSafeArea())
        .task(id: price) { await loadPreview() }
    }

    private var priceBlock: some View {
        VStack(spacing: 10) {
            Text(store.l("your_price"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(KJ.muted)
            Text(KJFormat.dzd(price))
                .font(.system(size: 36, weight: .heavy))
                .foregroundStyle(KJ.ink)
                .contentTransition(.numericText())
            HStack(spacing: 12) {
                Button { adjust(-50) } label: {
                    Image(systemName: "minus").font(.system(size: 16, weight: .heavy)).foregroundStyle(KJ.blue)
                        .frame(width: 52, height: 44).background(Circle().fill(KJ.softBlue))
                }
                .buttonStyle(.plain)
                .disabled(preview.map { price <= $0.minPrice } ?? true)

                Button { if let s = preview?.suggested { withAnimation { price = s } } } label: {
                    VStack(spacing: 1) {
                        Text("\(store.l("min_fare_note"))")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(KJ.muted)
                        Text(preview.map { KJFormat.dzd($0.suggested) } ?? "…")
                            .font(.system(size: 13, weight: .heavy))
                            .foregroundStyle(KJ.blue)
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 44)
                    .background(Capsule().fill(KJ.softBlue))
                }
                .buttonStyle(.plain)

                Button { adjust(50) } label: {
                    Image(systemName: "plus").font(.system(size: 16, weight: .heavy)).foregroundStyle(KJ.blue)
                        .frame(width: 52, height: 44).background(Circle().fill(KJ.softBlue))
                }
                .buttonStyle(.plain)
                .disabled(preview.map { price >= $0.maxPrice } ?? true)
            }
            .sensoryFeedback(.selection, trigger: price)

            Divider().padding(.vertical, 2)

            VStack(spacing: 6) {
                HStack {
                    Text(store.l("agreed_price"))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(KJ.muted)
                    Spacer()
                    Text(KJFormat.dzd(price))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(KJ.ink)
                }
                HStack {
                    Text(store.l("net_gain"))
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(KJ.ink)
                    Spacer()
                    if let preview {
                        Text(KJFormat.dzd(preview.net))
                            .font(.system(size: 17, weight: .heavy))
                            .foregroundStyle(KJ.success)
                            .contentTransition(.numericText())
                    } else if previewError {
                        Button(store.l("retry")) { Task { await loadPreview() } }
                            .font(.system(size: 14, weight: .bold))
                    } else {
                        ProgressView()
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(.white))
        .padding(.horizontal, 20)
    }

    private func infoCell(icon: String, value: String, unit: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(KJ.blue)
            Text("\(value) \(unit)")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(KJ.ink)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 14).fill(.white))
    }

    private func adjust(_ delta: Int) {
        guard let p = preview else { return }
        withAnimation(.snappy) {
            price = min(p.maxPrice, max(p.minPrice, price + delta))
        }
    }

    private func submit(kind: String) {
        submitting = true
        errorText = nil
        Task {
            do {
                _ = try await SupabaseService.shared.makeOffer(requestId: request.id, price: price, kind: kind)
                await onDone()
                submitting = false
            } catch {
                errorText = store.serverErrorMessage(error)
                submitting = false
            }
        }
    }
}

// MARK: - Active ride (driver side)

struct DriverActiveRideView: View {
    @EnvironmentObject var store: AppState
    let ride: Ride
    var onFinish: () -> Void

    @State private var submitting = false

    private var nextAction: (label: String, icon: String, status: String)? {
        switch ride.status {
        case "en_route": return (store.l("mark_arrived"), "mappin.and.ellipse", "arrived")
        case "arrived": return (store.l("start_ride"), "car.fill", "started")
        case "started": return (store.l("finish_ride"), "flag.checkered", "completed")
        default: return nil
        }
    }

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.l("active_ride"))
                        .font(.system(size: 20, weight: .heavy))
                        .foregroundStyle(KJ.ink)
                    Text("\(ride.pickupLabel) → \(ride.destLabel)")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(KJ.muted)
                        .lineLimit(1)
                }
                Spacer()
                Text(KJFormat.dzd(ride.fare))
                    .font(.system(size: 24, weight: .heavy))
                    .foregroundStyle(KJ.blue)
            }

            Text(store.l("ride_flow_hint"))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(KJ.muted)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let next = nextAction {
                Button {
                    Task { await advance(next.status) }
                } label: {
                    HStack {
                        Image(systemName: next.icon)
                        Text(next.label)
                    }
                }
                .buttonStyle(KJButtonStyle())
                .disabled(submitting)
            }

            Button {
                Task { await advance("cancelled") }
            } label: {
                Text(store.l("cancel_ride"))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(KJ.danger)
            }
            .padding(.bottom, 8)
        }
        .kjCard(padding: 18)
    }

    private func advance(_ status: String) async {
        submitting = true
        do {
            try await SupabaseService.shared.updateRide(rideId: ride.id, status: status)
            if status == "completed" || status == "cancelled" {
                if status == "completed" { await store.refreshProfile() }
                onFinish()
            } else {
                await store.refreshProfile()
            }
        } catch {
            print("KHERJA update_ride error: \(error)")
        }
        submitting = false
    }
}

// MARK: - Driver rides + profile

struct DriverRidesView: View {
    var body: some View {
        HistoryView()
    }
}

struct DriverProfileView: View {
    @EnvironmentObject var store: AppState
    @State private var make = ""
    @State private var model = ""
    @State private var plate = ""
    @State private var savedFlash = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.l("my_vehicle"))
                        .font(.system(size: 28, weight: .heavy))
                        .foregroundStyle(KJ.ink)
                }
                .padding(.top, 16)

                Image(store.profile?.vehicleModel == "Moto" ? "moto_art" : "car_hero")
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 20))

                field(store.l("brand"), $make)
                field(store.l("model"), $model)
                field(store.l("plate"), $plate)

                Button {
                    save()
                } label: {
                    Text(store.l("save"))
                }
                .buttonStyle(KJButtonStyle())

                if savedFlash {
                    Label(store.l("saved"), systemImage: "checkmark.circle.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(KJ.success)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 30)
        }
        .background(KJ.canvasGradient.ignoresSafeArea())
        .task {
            make = store.profile?.vehicleMake ?? ""
            model = store.profile?.vehicleModel ?? ""
            plate = store.profile?.vehiclePlate ?? ""
        }
    }

    private func field(_ label: String, _ binding: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(KJ.muted)
            TextField(label, text: binding)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(KJ.ink)
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(.white)
                        .shadow(color: Color(hex: 0x075BFF).opacity(0.07), radius: 8, y: 4)
                )
        }
    }

    private func save() {
        guard let id = store.session.userId else { return }
        let update = ProfileUpdate(vehicleMake: make, vehicleModel: model, vehiclePlate: plate)
        Task {
            try? await SupabaseService.shared.updateProfile(id: id, update: update)
            await store.refreshProfile()
            await MainActor.run {
                savedFlash = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { savedFlash = false }
            }
        }
    }
}
