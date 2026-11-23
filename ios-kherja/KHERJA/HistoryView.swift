//
//  HistoryView.swift
//  KHERJA
//
//  Trips history with filters (Tous / Terminés / En cours / Annulés) + details.
//

import MapKit
import SwiftUI

struct HistoryView: View {
    @EnvironmentObject var store: AppState
    @State private var rides: [Ride] = []
    @State private var filter = "all"
    @State private var loading = true
    @State private var selectedRide: Ride?

    private var isDriver: Bool { store.role == "driver" }

    private var filtered: [Ride] {
        rides.filter { ride in
            switch filter {
            case "completed": return ride.status == "completed"
            case "in_progress": return ride.status == "en_route" || ride.status == "arrived" || ride.status == "started"
            case "cancelled": return ride.status == "cancelled"
            default: return true
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(isDriver ? store.l("tab_jobs") : store.l("my_trips"))
                        .font(.system(size: 28, weight: .heavy))
                        .foregroundStyle(KJ.ink)
                    Text(isDriver ? store.l("trips_subtitle") : store.l("trips_subtitle"))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(KJ.muted)
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 12)

            filterBar

            if loading {
                Spacer()
                ProgressView().tint(KJ.blue).scaleEffect(1.2)
                Spacer()
            } else if filtered.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "clock.badge.questionmark")
                        .font(.system(size: 40, weight: .semibold))
                        .foregroundStyle(KJ.softBlueMid)
                    Text(store.l("no_trips"))
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(KJ.ink)
                    Text(store.l("no_trips_hint"))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(KJ.muted)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 14) {
                        ForEach(filtered) { ride in
                            RideCard(ride: ride, lang: store.language) {
                                selectedRide = ride
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 20)
                }
            }
        }
        .background(KJ.canvasGradient.ignoresSafeArea())
        .task { await load() }
        .refreshable { await load() }
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                filterChip("all", icon: "clock", label: store.l("all"))
                filterChip("completed", icon: "car.fill", label: store.l("completed"))
                filterChip("in_progress", icon: "hourglass", label: store.l("in_progress"))
                filterChip("cancelled", icon: "xmark", label: store.l("cancelled"))
            }
            .padding(.horizontal, 20)
        }
    }

    private func filterChip(_ id: String, icon: String, label: String) -> some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { filter = id }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                Text(label)
                    .font(.system(size: 14, weight: .bold))
            }
            .foregroundStyle(filter == id ? .white : KJ.ink)
            .padding(.horizontal, 16)
            .frame(height: 44)
            .background(
                Capsule().fill(filter == id ? AnyShapeStyle(KJ.buttonGradient) : AnyShapeStyle(Color.white))
            )
            .shadow(color: Color(hex: 0x075BFF).opacity(0.08), radius: 8, y: 4)
        }
        .buttonStyle(.plain)
    }

    private func load() async {
        guard let userId = store.session.userId else { return }
        do {
            rides = try await SupabaseService.shared.myRides(userId: userId, driver: isDriver)
        } catch {
            print("KHERJA history error: \(error)")
        }
        loading = false
    }
}

// MARK: - Ride card

struct RideCard: View {
    let ride: Ride
    let lang: AppLanguage
    var onTap: (() -> Void)?

    var body: some View {
        Button {
            onTap?()
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    statusBadge
                    Text(dateText)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(KJ.muted)
                    Spacer()
                    Text("#TRK-\(trkNumber)")
                        .font(.system(size: 12, weight: .heavy, design: .monospaced))
                        .foregroundStyle(KJ.muted)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(KJ.softBlue))
                }

                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 10) {
                        pointRow(color: KJ.blue, title: ride.pickupLabel)
                        pointRow(color: KJ.burgundy, title: ride.destLabel)
                    }

                    Image(ride.vehicle == .moto ? "moto_art" : "car_hero")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 110, height: ride.vehicle == .moto ? 70 : 54)
                        .clipShape(RoundedRectangle(cornerRadius: 10))

                    VStack(alignment: .trailing, spacing: 6) {
                        Text(KJFormat.dzd(ride.fare))
                            .font(.system(size: 22, weight: .heavy))
                            .foregroundStyle(KJ.ink)
                        if ride.status == "completed" {
                            Label("Payé", systemImage: "creditcard.fill")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(KJ.success)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(KJ.successBg))
                        }
                    }
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(.white)
                    .shadow(color: Color(hex: 0x075BFF).opacity(0.08), radius: 12, y: 6)
            )
        }
        .buttonStyle(.plain)
    }

    private var trkNumber: Int {
        abs(ride.id.hashValue % 10000)
    }

    private var dateText: String {
        let f = DateFormatter()
        f.locale = lang == .ar ? Locale(identifier: "ar_DZ") : Locale(identifier: "fr_FR")
        f.dateFormat = "d MMM. yyyy 'à' HH:mm"
        return f.string(from: ride.createdAt)
    }

    private var statusBadge: some View {
        Group {
            switch ride.status {
            case "completed":
                Label("Terminée", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(KJ.success)
            case "cancelled":
                Label("Annulée", systemImage: "xmark.circle.fill")
                    .foregroundStyle(KJ.danger)
            default:
                Label("En cours", systemImage: "arrow.triangle.2.circlepath")
                    .foregroundStyle(KJ.blue)
            }
        }
        .font(.system(size: 13, weight: .bold))
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
        .frame(maxWidth: 130, alignment: .leading)
    }
}

// MARK: - Ride detail (receipt)

struct RideDetailView: View {
    @EnvironmentObject var store: AppState
    let ride: Ride
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                BackCircleButton { dismiss() }
                Spacer()
            }
            .padding(.horizontal, 20)

            ScrollView {
                VStack(spacing: 16) {
                    VStack(spacing: 6) {
                        ZStack {
                            Circle().fill(KJ.success).frame(width: 60, height: 60)
                            Image(systemName: "checkmark")
                                .font(.system(size: 26, weight: .heavy))
                                .foregroundStyle(.white)
                        }
                        Text(store.l("ride_done_success"))
                            .font(.system(size: 22, weight: .heavy))
                            .foregroundStyle(KJ.success)
                        Text(store.l("thanks_kherja"))
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(KJ.muted)
                    }
                    .padding(.top, 8)

                    RideMapView(points: [
                        MapPoint(coordinate: CLLocationCoordinate2D(latitude: ride.pickupLat, longitude: ride.pickupLng), kind: .pickup, title: ride.pickupLabel),
                        MapPoint(coordinate: CLLocationCoordinate2D(latitude: ride.destLat, longitude: ride.destLng), kind: .destination, title: ride.destLabel),
                    ])
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .frame(height: 180)

                    VStack(alignment: .leading, spacing: 14) {
                        Text(store.l("summary"))
                            .font(.system(size: 18, weight: .heavy))
                            .foregroundStyle(KJ.ink)

                        receiptRow(icon: "car.fill", label: store.l("ride_fare"), amount: ride.fare)
                        receiptRow(icon: "tag.fill", label: store.l("discount"), amount: 0, minus: true)

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

                    Button {
                        dismiss()
                    } label: {
                        HStack {
                            Image(systemName: "calendar.badge.clock")
                            Text(store.l("ride_again"))
                        }
                    }
                    .buttonStyle(GhostButtonStyle())
                    .padding(.bottom, 24)
                }
                .padding(.horizontal, 20)
            }
        }
        .background(KJ.canvasGradient.ignoresSafeArea())
        .overlay(alignment: .top) { CornerBlobs().frame(height: 160) }
    }

    private func receiptRow(icon: String, label: String, amount: Int, minus: Bool = false) -> some View {
        HStack {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(KJ.blue)
                .frame(width: 28)
            Text(label)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(KJ.ink)
            Spacer()
            Text(minus ? "- \(KJFormat.dzd(amount))" : KJFormat.dzd(amount))
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(KJ.ink)
        }
    }
}
