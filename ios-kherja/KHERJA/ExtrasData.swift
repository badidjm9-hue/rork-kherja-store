//
//  ExtrasData.swift
//  KHERJA
//
//  Models and Supabase calls for saved places, notifications, vehicles, receipts, support and SOS.
//  Mirrors the Android data layer; backend is migrations 0010 and 0011. Not compiled in this environment.
//

import Foundation

nonisolated struct SavedPlace: Codable, Identifiable, Sendable, Equatable {
    let id: UUID
    var kind: String
    var label: String
    var address: String
    var lat: Double
    var lng: Double
}

nonisolated struct AppNotification: Codable, Identifiable, Sendable, Equatable {
    let id: UUID
    var kind: String
    var title: String
    var body: String
    var readAt: Date?
    var createdAt: Date?
    var isUnread: Bool { readAt == nil }

    enum CodingKeys: String, CodingKey {
        case id, kind, title, body
        case readAt = "read_at"
        case createdAt = "created_at"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        kind = (try? c.decode(String.self, forKey: .kind)) ?? "system"
        title = try c.decode(String.self, forKey: .title)
        body = (try? c.decode(String.self, forKey: .body)) ?? ""
        readAt = try? c.decode(Date.self, forKey: .readAt)
        createdAt = try? c.decode(Date.self, forKey: .createdAt)
    }
}

nonisolated struct NotificationPrefs: Codable, Sendable, Equatable {
    var rides: Bool = true
    var promotions: Bool = true
}

nonisolated struct Vehicle: Codable, Identifiable, Sendable, Equatable {
    let id: UUID
    var category: String
    var make: String
    var model: String
    var year: Int?
    var plate: String
    var color: String?
    var seats: Int?
    var isPrimary: Bool
    var status: String
    var suspendedReason: String?

    enum CodingKeys: String, CodingKey {
        case id, category, make, model, year, plate, color, seats, status
        case isPrimary = "is_primary"
        case suspendedReason = "suspended_reason"
    }
}

nonisolated struct RideReceipt: Codable, Sendable, Equatable {
    let rideId: UUID
    let reference: String
    var vehicle: String?
    var fare: Int
    var distanceKm: Double?
    var pickupLabel: String
    var destLabel: String
    var createdAt: Date?
    var startedAt: Date?
    var completedAt: Date?
    var driverName: String?
    var vehicleMake: String?
    var vehicleModel: String?
    var vehiclePlate: String?
    var payment: String?

    enum CodingKeys: String, CodingKey {
        case rideId = "ride_id", reference, vehicle, fare, payment
        case distanceKm = "distance_km"
        case pickupLabel = "pickup_label", destLabel = "dest_label"
        case createdAt = "created_at", startedAt = "started_at", completedAt = "completed_at"
        case driverName = "driver_name", vehicleMake = "vehicle_make"
        case vehicleModel = "vehicle_model", vehiclePlate = "vehicle_plate"
    }
}

nonisolated struct SupportContact: Codable, Sendable, Equatable {
    var phone: String = ""
    var email: String = ""
}

// MARK: Parameter / row encoders

nonisolated struct SavedPlaceInsert: Encodable, Sendable {
    let user_id: UUID, kind: String, label: String, address: String, lat: Double, lng: Double
}
nonisolated struct NotificationPrefsRow: Encodable, Sendable {
    let user_id: UUID, rides: Bool, promotions: Bool
}
nonisolated struct VehicleWrite: Encodable, Sendable {
    var driver_id: UUID?
    let category: String, make: String, model: String
    let year: Int?, plate: String, color: String, seats: Int
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        if let driver_id { try c.encode(driver_id, forKey: .driver_id) }
        try c.encode(category, forKey: .category); try c.encode(make, forKey: .make)
        try c.encode(model, forKey: .model); try c.encode(year, forKey: .year)
        try c.encode(plate, forKey: .plate); try c.encode(color, forKey: .color); try c.encode(seats, forKey: .seats)
    }
    enum Keys: String, CodingKey { case driver_id, category, make, model, year, plate, color, seats }
}
nonisolated struct NotificationIdParams: Encodable, Sendable { let p_id: UUID }
nonisolated struct ReceiptParams: Encodable, Sendable { let p_ride: UUID }
nonisolated struct SosParams: Encodable, Sendable {
    let p_ride_id: UUID?, p_lat: Double?, p_lng: Double?
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        try c.encode(p_ride_id, forKey: .p_ride_id); try c.encode(p_lat, forKey: .p_lat); try c.encode(p_lng, forKey: .p_lng)
    }
    enum Keys: String, CodingKey { case p_ride_id, p_lat, p_lng }
}
nonisolated struct TicketInsert: Encodable, Sendable {
    let user_id: UUID, category: String, message: String, ride_id: UUID?
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        try c.encode(user_id, forKey: .user_id); try c.encode(category, forKey: .category)
        try c.encode(message, forKey: .message); try c.encode(ride_id, forKey: .ride_id)
    }
    enum Keys: String, CodingKey { case user_id, category, message, ride_id }
}

extension SupabaseService {
    // Saved places (RLS: own rows only)
    func savedPlaces() async throws -> [SavedPlace] {
        try await client.from("saved_places").select("id,kind,label,address,lat,lng")
            .order("created_at", ascending: true).limit(50).execute().decoded(Self.decoder())
    }
    func addSavedPlace(userId: UUID, kind: String, label: String, address: String, lat: Double, lng: Double) async throws {
        try await client.from("saved_places")
            .insert(SavedPlaceInsert(user_id: userId, kind: kind, label: label, address: address, lat: lat, lng: lng)).execute()
    }
    func deleteSavedPlace(id: UUID) async throws {
        try await client.from("saved_places").delete().eq("id", value: id.uuidString).execute()
    }

    // Notifications
    func notifications() async throws -> [AppNotification] {
        try await client.from("notifications").select("id,kind,title,body,read_at,created_at")
            .order("created_at", ascending: false).limit(100).execute().decoded(Self.decoder())
    }
    func unreadNotificationCount() async throws -> Int { try await rpc("unread_notification_count", params: NoParams()) }
    func markNotificationRead(id: UUID) async throws { try await rpcVoid("mark_notification_read", params: NotificationIdParams(p_id: id)) }
    func markAllNotificationsRead() async throws { try await rpcVoid("mark_all_notifications_read") }
    func deleteNotification(id: UUID) async throws {
        try await client.from("notifications").delete().eq("id", value: id.uuidString).execute()
    }
    func notificationPrefs(userId: UUID) async throws -> NotificationPrefs {
        let rows: [NotificationPrefs] = try await client.from("notification_prefs").select("rides,promotions")
            .eq("user_id", value: userId.uuidString).limit(1).execute().decoded(Self.decoder())
        return rows.first ?? NotificationPrefs()
    }
    func saveNotificationPrefs(userId: UUID, prefs: NotificationPrefs) async throws {
        try await client.from("notification_prefs")
            .upsert(NotificationPrefsRow(user_id: userId, rides: prefs.rides, promotions: prefs.promotions), onConflict: "user_id")
            .execute()
    }

    // Driver vehicles
    func myVehicles(driverId: UUID) async throws -> [Vehicle] {
        try await client.from("vehicles").select().eq("driver_id", value: driverId.uuidString)
            .order("created_at", ascending: true).execute().decoded(Self.decoder())
    }
    func addVehicle(_ v: VehicleWrite) async throws { try await client.from("vehicles").insert(v).execute() }
    func updateVehicle(id: UUID, _ v: VehicleWrite) async throws {
        try await client.from("vehicles").update(v).eq("id", value: id.uuidString).execute()
    }
    func deleteVehicle(id: UUID) async throws { try await client.from("vehicles").delete().eq("id", value: id.uuidString).execute() }
    func setPrimaryVehicle(id: UUID) async throws { try await rpcVoid("set_primary_vehicle", params: NotificationIdParams(p_id: id)) }

    // Receipts, support, SOS
    func rideReceipt(rideId: UUID) async throws -> RideReceipt { try await rpc("ride_receipt", params: ReceiptParams(p_ride: rideId)) }
    func supportContact() async throws -> SupportContact { try await rpc("get_support_contact", params: NoParams()) }
    func createTicket(userId: UUID, category: String, message: String, rideId: UUID?) async throws {
        try await client.from("support_tickets")
            .insert(TicketInsert(user_id: userId, category: category, message: message, ride_id: rideId)).execute()
    }
    @discardableResult
    func raiseSOS(rideId: UUID?, lat: Double?, lng: Double?) async throws -> UUID {
        try await rpc("raise_sos", params: SosParams(p_ride_id: rideId, p_lat: lat, p_lng: lng))
    }
}
