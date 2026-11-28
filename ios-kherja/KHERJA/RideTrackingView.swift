//
//  RideTrackingView.swift
//  KHERJA
//
//  Active ride: driver en route → arrived → started → completed + rating.
//

import CoreLocation
import MapKit
import SwiftUI

struct RideTrackingView: View {
    @EnvironmentObject var store: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let rideId: UUID

    @State private var ride: Ride?
    @State private var driver: Profile?
    @State private var pollTimer: Timer?
    @State private var showRating = false
    @State private var finished = false
    @State private var loading = true

    var body: some View {
        ZStack {
            KJ.canvasGradient.ignoresSafeArea()

            if let ride {
                ScrollView {
                    VStack(spacing: 16) {
                        if ride.status == "completed" {
                            completedView(ride)
                                .transition(.opacity.combined(with: .scale(scale: 0.97)))
                        } else {
                            activeView(ride)
                                .transition(.opacity)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                }
            } else if loading {
                ProgressView().tint(KJ.blue).scaleEffect(1.3)
            } else {
                Text(store.l("error_generic"))
                    .foregroundStyle(KJ.muted)
            }
        }
        .animation(reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.88), value: ride?.status)
        .sheet(isPresented: $showRating, onDismiss: { if finished { store.setActiveRide(nil) } }) {
            RatingSheet(ride: ride) { store.setActiveRide(nil) }
                .environmentObject(store)
                .presentationDragIndicator(.visible)
        }
        .onAppear { Task { await load() } }
        .onDisappear { pollTimer?.invalidate() }
    }

    // MARK: Active ride

    private func activeView(_ ride: Ride) -> some View {
        VStack(spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.l("follow_ride"))
                        .font(.system(size: 24, weight: .heavy))
                        .foregroundStyle(KJ.ink)
                    Text(statusLabel(ride.status))
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(KJ.blue)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 0) {
                    Text(KJFormat.dzd(ride.fare))
                        .font(.system(size: 26, weight: .heavy))
                        .foregroundStyle(KJ.ink)
                    Text(store.l("agreed_price"))
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(KJ.blue)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(KJ.softBlue))
                }
            }

            RideMapView(points: routePoints(ride))
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .frame(height: 210)

            driverCard

            HStack(spacing: 14) {
                actionCell(icon: "clock", lines: [statusLabel(ride.status)])
                actionCell(icon: "creditcard", lines: [store.l("cash_on_delivery")])
            }
        }
    }

    private var driverCard: some View {
        HStack(spacing: 14) {
            Circle()
                .fill(KJ.softBlue)
                .frame(width: 60, height: 60)
                .overlay(
                    Text(driverInitials)
                        .font(.system(size: 21, weight: .heavy))
                        .foregroundStyle(KJ.blue)
                )
                .overlay(alignment: .bottomTrailing) {
                    HStack(spacing: 3) {
                        Image(systemName: "star.fill").font(.system(size: 10))
                        Text(String(format: "%.1f", driver?.ratingAvg ?? 5))
                            .font(.system(size: 12, weight: .heavy))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(KJ.blue))
                    .offset(x: 6, y: 6)
                }

            VStack(alignment: .leading, spacing: 3) {
                Text(driver?.name ?? "—")
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(KJ.ink)
                HStack(spacing: 6) {
                    Image(systemName: ride?.vehicle == .moto ? "motorcycle.fill" : "car.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(KJ.blue)
                    Text(vehicleLine)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(KJ.muted)
                }
                if let plate = driver?.vehiclePlate, !plate.isEmpty {
                    Text(plate)
                        .font(.system(size: 13, weight: .heavy, design: .monospaced))
                        .foregroundStyle(KJ.ink)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 6).fill(KJ.softBlue))
                }
            }
            Spacer()
        }
        .kjCard()
    }

    private func actionCell(icon: String, lines: [String]) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(KJ.blue)
            ForEach(lines, id: \.self) { line in
                Text(line)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(KJ.inkSoft)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.white))
    }

    // MARK: Completed

    private func completedView(_ ride: Ride) -> some View {
        VStack(spacing: 18) {
            VStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(KJ.buttonGradient)
                        .frame(width: 92, height: 92)
                    Image(systemName: "checkmark")
                        .font(.system(size: 40, weight: .heavy))
                        .foregroundStyle(.white)
                        .symbolEffect(.bounce, value: ride.status == "completed")
                }
                Text(store.l("arrived_destination"))
                    .font(.system(size: 26, weight: .heavy))
                    .foregroundStyle(KJ.ink)
                    .multilineTextAlignment(.center)
                Text(store.l("ride_done"))
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(KJ.muted)
            }
            .padding(.top, 30)

            driverSummaryCard(ride)

            summaryCard(ride)

            Button {
                showRating = true
            } label: {
                Text(store.l("rate_ride"))
            }
            .buttonStyle(KJButtonStyle())

            Button {
                store.setActiveRide(nil)
            } label: {
                HStack {
                    Image(systemName: "house.fill")
                    Text(store.l("back_home"))
                }
            }
            .buttonStyle(GhostButtonStyle())
            .padding(.bottom, 30)
        }
    }

    private func driverSummaryCard(_ ride: Ride) -> some View {
        HStack(spacing: 14) {
            Circle()
                .fill(KJ.softBlue)
                .frame(width: 60, height: 60)
                .overlay(
                    Text(driverInitials)
                        .font(.system(size: 21, weight: .heavy))
                        .foregroundStyle(KJ.blue)
                )
            VStack(alignment: .leading, spacing: 3) {
                Text(driver?.name ?? "—")
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(KJ.ink)
                HStack(spacing: 6) {
                    Image(systemName: ride.vehicle == .moto ? "motorcycle.fill" : "car.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(KJ.blue)
                    Text(vehicleLine)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(KJ.muted)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(KJFormat.dzd(ride.fare))
                    .font(.system(size: 26, weight: .heavy))
                    .foregroundStyle(KJ.ink)
                Label(store.l("paid"), systemImage: "checkmark.circle.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(KJ.success)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(KJ.successBg))
            }
        }
        .kjCard()
    }

    private func summaryCard(_ ride: Ride) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(store.l("summary"))
                .font(.system(size: 18, weight: .heavy))
                .foregroundStyle(KJ.ink)

            HStack(spacing: 10) {
                summaryCell(icon: "mappin", label: store.l("pickup"), value: ride.pickupLabel)
                summaryCell(icon: "flag.checkered", label: store.l("destination"), value: ride.destLabel)
            }

            HStack(spacing: 10) {
                summaryCell(icon: "clock", label: store.l("duration"), value: durationText(ride))
                summaryCell(icon: "point.topleft.down.curvedto.point.bottomright.up.fill",
                            label: store.l("distance"),
                            value: "\(String(format: "%.1f", rideDistanceKm(ride))) \(store.l("km"))")
            }

            Divider()
            HStack {
                Text(store.l("total_paid"))
                    .font(.system(size: 17, weight: .heavy))
                    .foregroundStyle(KJ.ink)
                Spacer()
                Text(KJFormat.dzd(ride.fare))
                    .font(.system(size: 22, weight: .heavy))
                    .foregroundStyle(KJ.blue)
            }
        }
        .kjCard()
    }

    private func summaryCell(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(KJ.blue)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(KJ.muted)
                Text(value)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(KJ.ink)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12).fill(KJ.softBlue.opacity(0.5)))
    }

    // MARK: Data

    private var driverInitials: String {
        (driver?.name ?? "K").split(separator: " ").compactMap { $0.first }.prefix(2).map(String.init).joined().uppercased()
    }

    private var vehicleLine: String {
        let parts = [driver?.vehicleMake, driver?.vehicleModel].compactMap { $0 }
        return parts.isEmpty ? "KHERJA" : parts.joined(separator: " ")
    }

    private func routePoints(_ ride: Ride) -> [MapPoint] {
        var points: [MapPoint] = [
            MapPoint(coordinate: CLLocationCoordinate2D(latitude: ride.pickupLat, longitude: ride.pickupLng), kind: .pickup, title: ride.pickupLabel),
            MapPoint(coordinate: CLLocationCoordinate2D(latitude: ride.destLat, longitude: ride.destLng), kind: .destination, title: ride.destLabel),
        ]
        if let driver, let lat = driver.currentLat, let lng = driver.currentLng {
            points.append(MapPoint(coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lng), kind: .driver, title: driver.name))
        }
        return points
    }

    private func statusLabel(_ status: String) -> String {
        switch status {
        case "en_route": return store.l("status_en_route")
        case "arrived": return store.l("status_arrived")
        case "started": return store.l("status_started")
        case "completed": return store.l("status_completed")
        default: return status
        }
    }

    private func rideDistanceKm(_ ride: Ride) -> Double {
        Geo.roadDistanceKm(
            from: CLLocationCoordinate2D(latitude: ride.pickupLat, longitude: ride.pickupLng),
            to: CLLocationCoordinate2D(latitude: ride.destLat, longitude: ride.destLng)
        )
    }

    private func durationText(_ ride: Ride) -> String {
        guard let start = ride.startedAt, let end = ride.completedAt else { return "—" }
        let minutes = Int(end.timeIntervalSince(start) / 60)
        return "\(minutes) \(store.l("min"))"
    }

    private func load() async {
        await refresh()
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in
            Task { @MainActor in await refresh() }
        }
    }

    private func refresh() async {
        do {
            let fetched = try await SupabaseService.shared.ride(id: rideId)
            ride = fetched
            loading = false
            if let fetched {
                driver = try await SupabaseService.shared.profile(id: fetched.driverId)
                if fetched.status == "completed" {
                    pollTimer?.invalidate()
                    finished = true
                    // Auto-open the rating sheet once.
                    if !showRating { showRating = true }
                }
            }
        } catch {
            print("KHERJA ride load error: \(error)")
            loading = false
        }
    }
}

// MARK: - Rating sheet

struct RatingSheet: View {
    @EnvironmentObject var store: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let ride: Ride?
    var onDone: () -> Void

    @State private var stars = 5
    @State private var comment = ""
    @State private var submitting = false
    @State private var submitted = false

    var body: some View {
        VStack(spacing: 20) {
            Text(store.l("rate_ride"))
                .font(.system(size: 22, weight: .heavy))
                .foregroundStyle(KJ.ink)
                .padding(.top, 24)

            HStack(spacing: 14) {
                ForEach(1...5, id: \.self) { i in
                    Button {
                        withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.6)) { stars = i }
                    } label: {
                        Image(systemName: "star.fill")
                            .font(.system(size: 32, weight: .semibold))
                            .foregroundStyle(i <= stars ? KJ.blue : KJ.softBlueMid)
                            .scaleEffect(i == stars ? 1.15 : 1)
                    }
                    .buttonStyle(.plain)
                }
            }

            Text(store.l("rate_hint"))
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(KJ.muted)

            TextField(store.l("add_comment"), text: $comment)
                .font(.system(size: 15, weight: .medium))
                .padding(.horizontal, 16)
                .frame(height: 50)
                .background(Capsule().fill(KJ.softBlue.opacity(0.6)))
                .padding(.horizontal, 20)

            if submitted {
                Label(store.l("saved"), systemImage: "checkmark.circle.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(KJ.success)
            }

            Button {
                submit()
            } label: {
                if submitting { ProgressView().tint(.white) } else { Text(store.l("submit_rating")) }
            }
            .buttonStyle(KJButtonStyle())
            .padding(.horizontal, 20)

            Button {
                onDone()
            } label: {
                Text(store.l("back_home"))
            }
            .buttonStyle(GhostButtonStyle())
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .background(KJ.canvasGradient.ignoresSafeArea())
    }

    private func submit() {
        guard let ride else { return }
        submitting = true
        Task {
            try? await SupabaseService.shared.submitRating(rideId: ride.id, stars: stars, comment: comment.isEmpty ? nil : comment)
            await MainActor.run {
                submitted = true
                submitting = false
            }
            try? await Task.sleep(nanoseconds: 800_000_000)
            await MainActor.run { onDone() }
        }
    }
}
