//
//  PassengerHomeView.swift
//  KHERJA
//
//  Home: map, pickup/destination, vehicle + fare proposal, live request status.
//

import CoreLocation
import MapKit
import SwiftUI

struct PassengerHomeView: View {
    @EnvironmentObject var store: AppState
    @ObservedObject private var location = LocationService.shared

    // Address selection
    @State private var pickup: PickPoint?
    @State private var destination: PickPoint?
    @State private var pickingFor: Field?
    @State private var pickSheet = false

    // Fare
    @State private var vehicle: VehicleKind = .car
    @State private var fare = 0
    @State private var quote: PassengerQuote?
    @State private var quoting = false
    @State private var quoteError = false
    @State private var submitting = false
    @State private var submitError: String?

    // Live request
    @State private var activeRequest: RideRequest?
    @State private var requestTimer: Timer?
    @State private var showNegotiation = false

    enum Field { case pickup, destination }

    struct PickPoint: Equatable {
        var coordinate: CLLocationCoordinate2D
        var label: String
    }

    var distanceKm: Double? {
        guard let pickup, let destination else { return nil }
        return Geo.roadDistanceKm(from: pickup.coordinate, to: destination.coordinate)
    }

    var canSubmit: Bool { pickup != nil && destination != nil && quote != nil && !quoting && !submitting }

    private var city: String { store.profile?.city ?? "Alger" }

    /// Changes whenever the trip or vehicle changes, to refetch the server quote.
    private var quoteKey: String {
        guard let pickup, let destination else { return "none" }
        return "\(pickup.coordinate.latitude),\(pickup.coordinate.longitude)|\(destination.coordinate.latitude),\(destination.coordinate.longitude)|\(vehicle.rawValue)|\(city)"
    }

    var body: some View {
        ZStack {
            KJ.canvasGradient.ignoresSafeArea()

            if let rideId = store.activeRideId {
                RideTrackingView(rideId: rideId)
            } else if let request = activeRequest, request.status == "open" || request.status == "negotiating" {
                waitingView(request)
            } else {
                homeView
            }
        }
        .task { await store.refreshProfile() }
        .onAppear { location.requestPermission() }
        .onDisappear { requestTimer?.invalidate() }
        .task(id: quoteKey) { await loadQuote() }
    }

    // MARK: Home

    private var homeView: some View {
        VStack(spacing: 0) {
            header

            VStack(spacing: 16) {
                addressCard

                vehicleRow

                if let km = distanceKm {
                    HStack(spacing: 16) {
                        Label("\(String(format: "%.1f", km)) \(store.l("km"))", systemImage: "point.topleft.down.curvedto.point.bottomright.up.fill")
                        Label("\(Geo.estimatedMinutes(km: km, vehicle: vehicle)) \(store.l("min"))", systemImage: "clock")
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(KJ.inkSoft)
                }

                priceCard

                if let submitError {
                    Text(submitError)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(KJ.danger)
                        .multilineTextAlignment(.center)
                }

                Button(action: submitRequest) {
                    if submitting {
                        ProgressView().tint(.white)
                    } else {
                        HStack {
                            Text(store.l("send_request"))
                            Image(systemName: "paperplane.fill")
                        }
                    }
                }
                .buttonStyle(KJButtonStyle())
                .disabled(!canSubmit)
                .opacity(canSubmit ? 1 : 0.55)
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(store.l("hello")) \(store.profile?.name ?? "") 👋")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(KJ.muted)
            Text(store.l("where_to"))
                .font(.system(size: 30, weight: .heavy))
                .foregroundStyle(KJ.ink)
            Text(store.l("find_driver"))
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(KJ.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 22)
        .padding(.top, 14)
    }

    private var addressCard: some View {
        VStack(spacing: 0) {
            addressRow(
                icon: "location.fill",
                color: KJ.blue,
                label: store.l("pickup"),
                value: pickup?.label ?? store.l("my_position")
            ) { pickingFor = .pickup; pickSheet = true }

            Divider().padding(.leading, 56)

            addressRow(
                icon: "mappin.circle.fill",
                color: KJ.burgundy,
                label: store.l("destination"),
                value: destination?.label ?? store.l("choose_on_map")
            ) { pickingFor = .destination; pickSheet = true }
        }
        .kjCard(padding: 6)
    }

    private func addressRow(icon: String, color: Color, label: String, value: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(width: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(KJ.muted)
                    Text(value)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(KJ.ink)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(KJ.muted.opacity(0.6))
            }
            .padding(14)
        }
        .buttonStyle(.plain)
    }

    private var vehicleRow: some View {
        HStack(spacing: 14) {
            vehicleButton(.car, icon: "car.fill", label: store.vehicleName(.car))
            vehicleButton(.moto, icon: "motorcycle.fill", label: store.vehicleName(.moto))
        }
    }

    private func vehicleButton(_ kind: VehicleKind, icon: String, label: String) -> some View {
        Button { vehicle = kind } label: {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                Text(label)
                    .font(.system(size: 15, weight: .bold))
            }
            .foregroundStyle(vehicle == kind ? .white : KJ.ink)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(vehicle == kind ? AnyShapeStyle(KJ.buttonGradient) : AnyShapeStyle(Color.white))
                    .shadow(color: Color(hex: 0x075BFF).opacity(0.10), radius: 10, y: 5)
            )
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: vehicle)
    }

    @ViewBuilder
    private var priceCard: some View {
        if destination == nil {
            HStack(spacing: 10) {
                Image(systemName: "mappin.and.ellipse")
                    .foregroundStyle(KJ.blue)
                Text(store.l("choose_destination_for_price"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(KJ.muted)
                Spacer()
            }
            .kjCard()
        } else if let q = quote {
            VStack(spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(store.l("proposed_price"))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(KJ.muted)
                        Text(KJFormat.dzd(fare))
                            .font(.system(size: 34, weight: .heavy))
                            .foregroundStyle(KJ.ink)
                            .contentTransition(.numericText())
                    }
                    Spacer()
                    HStack(spacing: 12) {
                        stepButton("minus", enabled: fare > q.minProposal) { step(-1, q) }
                        stepButton("plus", enabled: fare < q.maxProposal) { step(1, q) }
                    }
                }
                .opacity(quoting ? 0.5 : 1)

                Divider()

                VStack(spacing: 6) {
                    summaryRow(store.l("estimate"), KJFormat.dzd(q.estimatedTotal), strike: q.discount > 0)
                    if q.discount > 0 {
                        summaryRow(store.l("discount"), "−\(KJFormat.dzd(q.discount))", color: KJ.success)
                    }
                    summaryRow(store.l("total"), KJFormat.dzd(q.total), bold: true)
                }

                if fare != q.total {
                    Button { withAnimation { fare = q.total } } label: {
                        Text(store.l("use_suggested"))
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(KJ.blue)
                    }
                    .buttonStyle(.plain)
                }
            }
            .kjCard()
        } else {
            HStack(spacing: 10) {
                if quoteError {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(KJ.warning)
                    Text(store.l("quote_error"))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(KJ.inkSoft)
                    Spacer()
                    Button(store.l("retry")) { Task { await loadQuote() } }
                        .font(.system(size: 14, weight: .bold))
                } else {
                    ProgressView()
                    Text(store.l("computing_price"))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(KJ.muted)
                    Spacer()
                }
            }
            .kjCard()
        }
    }

    private func summaryRow(_ label: String, _ value: String, strike: Bool = false, bold: Bool = false, color: Color = KJ.ink) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 14, weight: bold ? .bold : .medium))
                .foregroundStyle(bold ? KJ.ink : KJ.muted)
            Spacer()
            Text(value)
                .font(.system(size: 14, weight: bold ? .heavy : .semibold))
                .foregroundStyle(strike ? KJ.muted : color)
                .strikethrough(strike)
        }
    }

    private func step(_ direction: Int, _ q: PassengerQuote) {
        withAnimation(.snappy) {
            fare = min(q.maxProposal, max(q.minProposal, fare + direction * 50))
        }
    }

    private func pill(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(color.opacity(0.12)))
    }

    private func stepButton(_ symbol: String, enabled: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .heavy))
                .foregroundStyle(KJ.blue)
                .frame(width: 44, height: 44)
                .background(Circle().fill(KJ.softBlue))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
        .sensoryFeedback(.selection, trigger: fare)
    }

    // MARK: Waiting for offers

    private func waitingView(_ request: RideRequest) -> some View {
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                HStack {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(KJ.success)
                    Text(store.l("your_request"))
                        .font(.system(size: 17, weight: .heavy))
                        .foregroundStyle(KJ.ink)
                    Spacer()
                }
                HStack(spacing: 10) {
                    Text(request.pickupLabel).lineLimit(1)
                    Image(systemName: "arrow.right")
                    Text(request.destLabel).lineLimit(1)
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(KJ.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            RideMapView(points: [
                MapPoint(coordinate: CLLocationCoordinate2D(latitude: request.pickupLat, longitude: request.pickupLng), kind: .pickup, title: request.pickupLabel),
                MapPoint(coordinate: CLLocationCoordinate2D(latitude: request.destLat, longitude: request.destLng), kind: .destination, title: request.destLabel),
            ])
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .frame(height: 190)
            .padding(.top, 14)

            VStack(spacing: 10) {
                PulsingDots()
                Text(store.l("waiting_offers"))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(KJ.inkSoft)
                Text("\(KJFormat.dzd(request.proposedFare)) · \(String(format: "%.1f", request.distanceKm)) \(store.l("km"))")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(KJ.muted)

                Button {
                    showNegotiation = true
                } label: {
                    HStack {
                        Text(store.l("follow_ride"))
                        Image(systemName: "chevron.right")
                    }
                }
                .buttonStyle(KJButtonStyle())

                Button {
                    cancelRequest()
                } label: {
                    Text(store.l("cancel_request"))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(KJ.danger)
                }
                .padding(.top, 4)
            }
            .padding(.top, 20)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .sheet(isPresented: $showNegotiation, onDismiss: { startPolling() }) {
            NegotiationView(request: request, onAccepted: {
                Task { await onRideAccepted(requestId: request.id) }
            })
                .environmentObject(store)
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: Logic

    private func loadQuote() async {
        guard let pickup, let destination, let km = distanceKm else {
            quote = nil
            return
        }
        quoting = true
        quoteError = false
        submitError = nil
        defer { quoting = false }
        do {
            let q = try await SupabaseService.shared.quoteFare(
                pickupLat: pickup.coordinate.latitude, pickupLng: pickup.coordinate.longitude,
                destLat: destination.coordinate.latitude, destLng: destination.coordinate.longitude,
                distanceKm: km, vehicle: vehicle, city: city
            )
            if Task.isCancelled { return }
            quote = q
            fare = q.total
        } catch {
            if Task.isCancelled { return }
            print("KHERJA quote_fare error: \(error)")
            quote = nil
            quoteError = true
        }
    }

    private func submitRequest() {
        guard let pickup, let destination, let km = distanceKm, quote != nil else { return }
        submitting = true
        submitError = nil
        Task {
            defer { submitting = false }
            do {
                let id = try await SupabaseService.shared.createRequest(CreateRequestParams(
                    p_pickup_label: pickup.label,
                    p_pickup_lat: pickup.coordinate.latitude,
                    p_pickup_lng: pickup.coordinate.longitude,
                    p_dest_label: destination.label,
                    p_dest_lat: destination.coordinate.latitude,
                    p_dest_lng: destination.coordinate.longitude,
                    p_distance_km: (km * 100).rounded() / 100,
                    p_vehicle: vehicle.rawValue,
                    p_proposed_fare: fare,
                    p_city: city
                ))
                activeRequest = RideRequest(
                    id: id, passengerId: store.session.userId ?? UUID(),
                    pickupLabel: pickup.label, pickupLat: pickup.coordinate.latitude, pickupLng: pickup.coordinate.longitude,
                    destLabel: destination.label, destLat: destination.coordinate.latitude, destLng: destination.coordinate.longitude,
                    city: city, distanceKm: km, vehicle: vehicle, proposedFare: fare,
                    status: "open", createdAt: Date(),
                    expiresAt: Date().addingTimeInterval(600)
                )
                store.setActiveRequest(id)
                startPolling()
                showNegotiation = true
            } catch {
                print("KHERJA create_request error: \(error)")
                submitError = store.serverErrorMessage(error)
            }
        }
    }

    private func cancelRequest() {
        guard let request = activeRequest else { return }
        requestTimer?.invalidate()
        Task {
            try? await SupabaseService.shared.cancelRequest(request.id)
            await MainActor.run {
                activeRequest = nil
                store.setActiveRequest(nil)
            }
        }
    }

    private func onRideAccepted(requestId: UUID) async {
        if let ride = try? await SupabaseService.shared.ride(requestId: requestId) {
            store.setActiveRide(ride.id)
            store.setActiveRequest(nil)
            activeRequest = nil
            showNegotiation = false
        }
    }

    private func startPolling() {
        requestTimer?.invalidate()
        requestTimer = Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { _ in
            Task { @MainActor in
                await pollRequest()
            }
        }
    }

    private func pollRequest() async {
        guard let id = activeRequest?.id ?? store.activeRequestId else { return }
        let requests = (try? await SupabaseService.shared.myRequests(passengerId: store.session.userId ?? UUID())) ?? []
        guard let req = requests.first(where: { $0.id == id }) else { return }
        activeRequest = req
        if req.status == "accepted" {
            // accepted elsewhere; the ride sheet took over
            requestTimer?.invalidate()
        }
    }
}

// MARK: - Small pieces

struct PulsingDots: View {
    @State private var animating = false

    var body: some View {
        HStack(spacing: 7) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(KJ.blue)
                    .frame(width: 9, height: 9)
                    .scaleEffect(animating ? 1.0 : 0.55)
                    .opacity(animating ? 1 : 0.4)
                    .animation(
                        .easeInOut(duration: 0.6)
                        .repeatForever(autoreverses: true)
                        .delay(Double(i) * 0.18),
                        value: animating
                    )
            }
        }
        .onAppear { animating = true }
    }
}

extension AppState {
    func vehicleName(_ kind: VehicleKind) -> String {
        kind == .car ? "Voiture" : "Moto"
    }
}
