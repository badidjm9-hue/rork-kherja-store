//
//  DeliveryView.swift
//  KHERJA
//
//  Parcel delivery for passengers and approved drivers.
//  Server owns all pricing and delivery state transitions.
//

import CoreLocation
import MapKit
import SwiftUI

private struct DeliveryPlace: Identifiable {
    let id = UUID()
    let label: String
    let coordinate: CLLocationCoordinate2D
}

struct DeliveryView: View {
    @EnvironmentObject var store: AppState
    @ObservedObject private var location = LocationService.shared

    @State private var pickup: DeliveryPlace?
    @State private var destinationQuery = ""
    @State private var destination: DeliveryPlace?
    @State private var suggestions: [DeliveryPlace] = []
    @State private var packageDescription = ""
    @State private var recipientName = ""
    @State private var recipientPhone = ""
    @State private var senderNote = ""
    @State private var vehicle = "moto"
    @State private var quote: DeliveryQuote?
    @State private var orders: [DeliveryOrder] = []
    @State private var openOrders: [DeliveryOrder] = []
    @State private var busy = false
    @State private var loading = true
    @State private var errorText: String?
    @State private var infoText: String?

    private var isDriver: Bool { store.role == "driver" }
    private var activeOrder: DeliveryOrder? {
        orders.first { isDriver ? ["accepted", "picked_up"].contains($0.status) : ["open", "accepted", "picked_up"].contains($0.status) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(store.l("delivery_title"))
                        .font(.system(size: 26, weight: .heavy))
                        .foregroundStyle(KJ.ink)
                    Text(store.l(isDriver ? "delivery_driver_hint" : "delivery_passenger_hint"))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(KJ.muted)
                }
                .padding(.top, 12)

                if let errorText {
                    Text(errorText).font(.system(size: 13, weight: .semibold)).foregroundStyle(KJ.danger)
                }
                if let infoText {
                    Text(infoText).font(.system(size: 13, weight: .semibold)).foregroundStyle(KJ.success)
                }

                if isDriver {
                    driverContent
                } else if let activeOrder {
                    orderCard(activeOrder, passenger: true)
                } else {
                    passengerForm
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 28)
        }
        .background(KJ.canvasGradient.ignoresSafeArea())
        .task {
            location.requestPermission()
            await refresh()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(6))
                await refresh()
            }
        }
        .task(id: location.location?.timestamp) {
            guard pickup == nil, let value = location.location else { return }
            let label = await Geo.reverseGeocode(value.coordinate)
            pickup = DeliveryPlace(label: label, coordinate: value.coordinate)
            await updateQuote()
        }
        .onChange(of: vehicle) { _, _ in Task { await updateQuote() } }
        .onChange(of: destination?.id) { _, _ in Task { await updateQuote() } }
    }

    private var passengerForm: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(store.l("delivery_pickup")).font(.system(size: 14, weight: .bold)).foregroundStyle(KJ.ink)
                Text(pickup?.label ?? store.l("delivery_wait_location"))
                    .font(.system(size: 14, weight: .medium)).foregroundStyle(KJ.muted)
            }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading).kjCard()

            VStack(alignment: .leading, spacing: 10) {
                Text(store.l("delivery_destination")).font(.system(size: 14, weight: .bold)).foregroundStyle(KJ.ink)
                TextField(store.l("delivery_destination"), text: $destinationQuery)
                    .textFieldStyle(.roundedBorder)
                Button(store.l("delivery_search")) { Task { await searchDestination() } }
                    .buttonStyle(GhostButtonStyle())
                ForEach(suggestions) { place in
                    Button {
                        destination = place
                        destinationQuery = place.label
                        suggestions = []
                    } label: {
                        HStack {
                            Image(systemName: "mappin.and.ellipse").foregroundStyle(KJ.blue)
                            Text(place.label).foregroundStyle(KJ.ink).multilineTextAlignment(.leading)
                            Spacer()
                        }
                        .padding(10)
                    }
                    .buttonStyle(.plain)
                }
                if let pickup, let destination {
                    RideMapView(points: [
                        MapPoint(coordinate: pickup.coordinate, kind: .pickup, title: pickup.label),
                        MapPoint(coordinate: destination.coordinate, kind: .destination, title: destination.label)
                    ])
                    .frame(height: 180)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
            }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading).kjCard()

            VStack(alignment: .leading, spacing: 10) {
                Text(store.l("delivery_package")).font(.system(size: 14, weight: .bold)).foregroundStyle(KJ.ink)
                TextField(store.l("delivery_package_hint"), text: $packageDescription, axis: .vertical)
                    .lineLimit(2...4).textFieldStyle(.roundedBorder)
                TextField(store.l("delivery_recipient"), text: $recipientName).textFieldStyle(.roundedBorder)
                TextField(store.l("delivery_phone"), text: $recipientPhone)
                    .keyboardType(.phonePad).textFieldStyle(.roundedBorder)
                TextField(store.l("delivery_note"), text: $senderNote, axis: .vertical)
                    .lineLimit(1...3).textFieldStyle(.roundedBorder)
            }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading).kjCard()

            VStack(alignment: .leading, spacing: 10) {
                Text(store.l("delivery_vehicle")).font(.system(size: 14, weight: .bold)).foregroundStyle(KJ.ink)
                Picker(store.l("delivery_vehicle"), selection: $vehicle) {
                    Text("Moto").tag("moto")
                    Text("Voiture").tag("car")
                }
                .pickerStyle(.segmented)
                Text(store.l("delivery_cash_only"))
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(KJ.muted)
                if let quote {
                    Text("\(store.l("delivery_fee")): \(quote.deliveryFee) DZD")
                        .font(.system(size: 21, weight: .heavy)).foregroundStyle(KJ.blue)
                } else {
                    Text(store.l("computing_price")).font(.system(size: 13, weight: .medium)).foregroundStyle(KJ.muted)
                }
                Button {
                    Task { await createOrder() }
                } label: {
                    if busy { ProgressView().tint(.white) } else { Text(store.l("delivery_create")) }
                }
                .buttonStyle(KJButtonStyle())
                .disabled(busy || pickup == nil || destination == nil || quote == nil ||
                          packageDescription.trimmingCharacters(in: .whitespacesAndNewlines).count < 2 ||
                          recipientName.trimmingCharacters(in: .whitespacesAndNewlines).count < 2 ||
                          recipientPhone.filter(\.isNumber).count < 8)
            }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading).kjCard()
        }
    }

    @ViewBuilder
    private var driverContent: some View {
        if let activeOrder {
            orderCard(activeOrder, passenger: false)
        } else if store.profile?.isOnline != true {
            Text(store.l("go_online_first"))
                .font(.system(size: 15, weight: .semibold)).foregroundStyle(KJ.muted)
                .padding(18).frame(maxWidth: .infinity).kjCard()
        } else if loading {
            ProgressView().frame(maxWidth: .infinity).padding(30)
        } else if openOrders.isEmpty {
            Text(store.l("delivery_no_orders"))
                .font(.system(size: 15, weight: .semibold)).foregroundStyle(KJ.muted)
                .padding(18).frame(maxWidth: .infinity).kjCard()
        } else {
            ForEach(openOrders) { order in
                VStack(alignment: .leading, spacing: 10) {
                    Text("\(order.pickupLabel) → \(order.destLabel)")
                        .font(.system(size: 15, weight: .bold)).foregroundStyle(KJ.ink)
                    Text(order.packageDescription).font(.system(size: 13)).foregroundStyle(KJ.muted)
                    Text("\(String(format: "%.1f", order.distanceKm)) km · \(order.deliveryFee) DZD · \(order.vehicle.uppercased())")
                        .font(.system(size: 14, weight: .bold)).foregroundStyle(KJ.blue)
                    Button(store.l("delivery_accept")) { Task { await claim(order) } }
                        .buttonStyle(KJButtonStyle()).disabled(busy)
                }
                .padding(16).frame(maxWidth: .infinity, alignment: .leading).kjCard()
            }
        }
    }

    private func orderCard(_ order: DeliveryOrder, passenger: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(store.l("delivery_active")).font(.system(size: 17, weight: .heavy)).foregroundStyle(KJ.ink)
            Text("\(order.pickupLabel) → \(order.destLabel)")
                .font(.system(size: 14, weight: .semibold)).foregroundStyle(KJ.ink)
            Text(order.packageDescription).font(.system(size: 13)).foregroundStyle(KJ.muted)
            if !passenger {
                Text("\(order.recipientName ?? "") · \(order.recipientPhone ?? "")")
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(KJ.ink)
            }
            Text("\(order.deliveryFee) DZD · \(store.l("delivery_cash_only"))")
                .font(.system(size: 15, weight: .bold)).foregroundStyle(KJ.blue)
            Text(store.l("delivery_status_\(order.status)"))
                .font(.system(size: 13, weight: .semibold)).foregroundStyle(KJ.muted)

            if !passenger && order.status == "accepted" {
                Button(store.l("delivery_picked_up")) { Task { await updateStatus(order, to: "picked_up") } }
                    .buttonStyle(KJButtonStyle()).disabled(busy)
            } else if !passenger && order.status == "picked_up" {
                Button(store.l("delivery_delivered")) { Task { await updateStatus(order, to: "delivered") } }
                    .buttonStyle(KJButtonStyle()).disabled(busy)
            } else if passenger && order.status == "open" {
                Button(store.l("delivery_cancel"), role: .destructive) { Task { await cancel(order) } }
                    .buttonStyle(GhostButtonStyle())
                    .disabled(busy)
            }
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading).kjCard()
    }

    private func refresh() async {
        do {
            orders = try await SupabaseService.shared.myDeliveryOrders()
            if isDriver, store.profile?.isOnline == true {
                openOrders = try await SupabaseService.shared.openDeliveryFeed()
            } else {
                openOrders = []
            }
            errorText = nil
        } catch {
            errorText = store.l("error_generic")
        }
        loading = false
    }

    private func searchDestination() async {
        let query = destinationQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 3 else { return }
        busy = true
        errorText = nil
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.region = MKCoordinateRegion(
            center: pickup?.coordinate ?? CLLocationCoordinate2D(latitude: 36.7538, longitude: 3.0588),
            span: MKCoordinateSpan(latitudeDelta: 0.35, longitudeDelta: 0.35)
        )
        do {
            let response = try await MKLocalSearch(request: request).start()
            suggestions = response.mapItems.prefix(8).map { item in
                DeliveryPlace(
                    label: [item.name, item.placemark.locality].compactMap { $0 }.joined(separator: ", "),
                    coordinate: item.placemark.coordinate
                )
            }
        } catch {
            errorText = store.l("error_generic")
        }
        busy = false
    }

    private func updateQuote() async {
        guard let pickup, let destination else { quote = nil; return }
        do {
            let km = Geo.roadDistanceKm(from: pickup.coordinate, to: destination.coordinate)
            quote = try await SupabaseService.shared.quoteDelivery(
                pickupLat: pickup.coordinate.latitude, pickupLng: pickup.coordinate.longitude,
                destLat: destination.coordinate.latitude, destLng: destination.coordinate.longitude,
                distanceKm: km, vehicle: vehicle
            )
        } catch {
            quote = nil
            errorText = store.l("quote_error")
        }
    }

    private func createOrder() async {
        guard let pickup, let selectedDestination = destination else { return }
        busy = true
        errorText = nil
        do {
            let km = Geo.roadDistanceKm(from: pickup.coordinate, to: selectedDestination.coordinate)
            _ = try await SupabaseService.shared.createDeliveryOrder(CreateDeliveryParams(
                p_pickup_label: pickup.label, p_pickup_lat: pickup.coordinate.latitude, p_pickup_lng: pickup.coordinate.longitude,
                p_dest_label: selectedDestination.label, p_dest_lat: selectedDestination.coordinate.latitude, p_dest_lng: selectedDestination.coordinate.longitude,
                p_distance_km: km, p_vehicle: vehicle,
                p_package_description: packageDescription.trimmingCharacters(in: .whitespacesAndNewlines),
                p_recipient_name: recipientName.trimmingCharacters(in: .whitespacesAndNewlines),
                p_recipient_phone: recipientPhone.trimmingCharacters(in: .whitespacesAndNewlines),
                p_sender_note: senderNote.isEmpty ? nil : senderNote, p_city: store.profile?.city ?? "Alger"
            ))
            infoText = store.l("delivery_created")
            destination = nil
            destinationQuery = ""
            packageDescription = ""
            recipientName = ""
            recipientPhone = ""
            senderNote = ""
            await refresh()
        } catch {
            errorText = store.l("error_generic")
        }
        busy = false
    }

    private func claim(_ order: DeliveryOrder) async {
        busy = true
        do {
            try await SupabaseService.shared.claimDeliveryOrder(order.id)
            await refresh()
        } catch { errorText = store.l("error_generic") }
        busy = false
    }

    private func updateStatus(_ order: DeliveryOrder, to status: String) async {
        busy = true
        do {
            try await SupabaseService.shared.updateDeliveryStatus(order.id, status: status)
            await refresh()
        } catch { errorText = store.l("error_generic") }
        busy = false
    }

    private func cancel(_ order: DeliveryOrder) async {
        busy = true
        do {
            try await SupabaseService.shared.cancelDeliveryOrder(order.id)
            await refresh()
        } catch { errorText = store.l("error_generic") }
        busy = false
    }
}
