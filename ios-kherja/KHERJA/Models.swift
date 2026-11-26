//
//  Models.swift
//  KHERJA
//
//  Database models (snake_case columns) — all nonisolated + Sendable.
//

import Foundation

nonisolated struct Profile: Codable, Identifiable, Sendable, Equatable {
    let id: UUID
    var role: String
    var name: String
    var city: String
    var language: String
    var vehicleMake: String?
    var vehicleModel: String?
    var vehiclePlate: String?
    var vehicleColor: String?
    var isOnline: Bool
    var currentLat: Double?
    var currentLng: Double?
    var ratingAvg: Double
    var ratingCount: Int
    var tripsCount: Int
    let createdAt: Date
    var driverStatus: String? = nil
    var accountStatus: String? = nil
    var statusReason: String? = nil

    enum CodingKeys: String, CodingKey {
        case id, role, name, city, language
        case driverStatus = "driver_status"
        case accountStatus = "account_status"
        case statusReason = "status_reason"
        case vehicleMake = "vehicle_make"
        case vehicleModel = "vehicle_model"
        case vehiclePlate = "vehicle_plate"
        case vehicleColor = "vehicle_color"
        case isOnline = "is_online"
        case currentLat = "current_lat"
        case currentLng = "current_lng"
        case ratingAvg = "rating_avg"
        case ratingCount = "rating_count"
        case tripsCount = "trips_count"
        case createdAt = "created_at"
    }
}

nonisolated struct RideRequest: Codable, Identifiable, Sendable, Equatable {
    let id: UUID
    let passengerId: UUID
    var pickupLabel: String
    var pickupLat: Double
    var pickupLng: Double
    var destLabel: String
    var destLat: Double
    var destLng: Double
    var city: String
    var distanceKm: Double
    var vehicle: VehicleKind
    var proposedFare: Int
    var status: String
    let createdAt: Date
    var expiresAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case passengerId = "passenger_id"
        case pickupLabel = "pickup_label"
        case pickupLat = "pickup_lat"
        case pickupLng = "pickup_lng"
        case destLabel = "dest_label"
        case destLat = "dest_lat"
        case destLng = "dest_lng"
        case city
        case distanceKm = "distance_km"
        case vehicle
        case proposedFare = "proposed_fare"
        case status
        case createdAt = "created_at"
        case expiresAt = "expires_at"
    }
}

nonisolated struct Offer: Codable, Identifiable, Sendable, Equatable {
    let id: UUID
    let requestId: UUID
    let driverId: UUID
    var price: Int
    var kind: String
    var status: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case requestId = "request_id"
        case driverId = "driver_id"
        case price, kind, status
        case createdAt = "created_at"
    }
}

nonisolated struct OfferWithDriver: Codable, Identifiable, Sendable {
    let id: UUID
    let requestId: UUID
    let driverId: UUID
    var price: Int
    var kind: String
    var status: String
    let createdAt: Date
    var driver: Profile?

    enum CodingKeys: String, CodingKey {
        case id
        case requestId = "request_id"
        case driverId = "driver_id"
        case price, kind, status
        case createdAt = "created_at"
        case driver
    }
}

nonisolated struct Ride: Codable, Identifiable, Sendable, Equatable {
    let id: UUID
    let requestId: UUID
    let passengerId: UUID
    let driverId: UUID
    var vehicle: VehicleKind
    var fare: Int
    var status: String
    var pickupLabel: String
    var pickupLat: Double
    var pickupLng: Double
    var destLabel: String
    var destLat: Double
    var destLng: Double
    var startedAt: Date?
    var completedAt: Date?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case requestId = "request_id"
        case passengerId = "passenger_id"
        case driverId = "driver_id"
        case vehicle, fare, status
        case pickupLabel = "pickup_label"
        case pickupLat = "pickup_lat"
        case pickupLng = "pickup_lng"
        case destLabel = "dest_label"
        case destLat = "dest_lat"
        case destLng = "dest_lng"
        case startedAt = "started_at"
        case completedAt = "completed_at"
        case createdAt = "created_at"
    }
}

// MARK: - Parcel delivery
nonisolated struct DeliveryOrder: Codable, Identifiable, Sendable, Equatable {
    let id: UUID
    var passengerId: UUID
    var driverId: UUID?
    var pickupLabel: String
    var pickupLat: Double
    var pickupLng: Double
    var destLabel: String
    var destLat: Double
    var destLng: Double
    var city: String
    var distanceKm: Double
    var vehicle: String
    var packageDescription: String
    var recipientName: String?
    var recipientPhone: String?
    var senderNote: String?
    var deliveryFee: Int
    var paymentMethod: String
    var status: String
    var createdAt: Date?
    var expiresAt: Date?
    var acceptedAt: Date?
    var pickedUpAt: Date?
    var deliveredAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, city, vehicle, status
        case passengerId = "passenger_id"
        case driverId = "driver_id"
        case pickupLabel = "pickup_label"
        case pickupLat = "pickup_lat"
        case pickupLng = "pickup_lng"
        case destLabel = "dest_label"
        case destLat = "dest_lat"
        case destLng = "dest_lng"
        case distanceKm = "distance_km"
        case packageDescription = "package_description"
        case recipientName = "recipient_name"
        case recipientPhone = "recipient_phone"
        case senderNote = "sender_note"
        case deliveryFee = "delivery_fee"
        case paymentMethod = "payment_method"
        case createdAt = "created_at"
        case expiresAt = "expires_at"
        case acceptedAt = "accepted_at"
        case pickedUpAt = "picked_up_at"
        case deliveredAt = "delivered_at"
    }
}

nonisolated struct DeliveryQuote: Codable, Sendable {
    var distanceKm: Double
    var vehicle: String
    var ratePerKm: Int
    var minimumFee: Int
    var deliveryFee: Int
    var currency: String
    var paymentMethod: String

    enum CodingKeys: String, CodingKey {
        case vehicle, currency
        case distanceKm = "distance_km"
        case ratePerKm = "rate_per_km"
        case minimumFee = "minimum_fee"
        case deliveryFee = "delivery_fee"
        case paymentMethod = "payment_method"
    }
}

nonisolated struct RideMessage: Codable, Identifiable, Sendable, Equatable {
    let id: UUID
    let requestId: UUID
    let senderId: UUID
    var body: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case requestId = "request_id"
        case senderId = "sender_id"
        case body
        case createdAt = "created_at"
    }
}

nonisolated struct Transaction: Codable, Identifiable, Sendable, Equatable {
    let id: UUID
    let userId: UUID
    let rideId: UUID?
    var kind: String
    var amount: Int
    var method: String
    var label: String?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case rideId = "ride_id"
        case kind, amount, method, label
        case createdAt = "created_at"
    }
}

// Embedded passenger/driver summary for feeds.
nonisolated struct ProfileStub: Codable, Sendable {
    var name: String
    var ratingAvg: Double
    var tripsCount: Int
    var vehicleMake: String?
    var vehicleModel: String?
    var vehiclePlate: String?

    enum CodingKeys: String, CodingKey {
        case name
        case ratingAvg = "rating_avg"
        case tripsCount = "trips_count"
        case vehicleMake = "vehicle_make"
        case vehicleModel = "vehicle_model"
        case vehiclePlate = "vehicle_plate"
    }
}

nonisolated struct RequestWithPassenger: Codable, Identifiable, Sendable {
    let id: UUID
    let passengerId: UUID
    var pickupLabel: String
    var pickupLat: Double
    var pickupLng: Double
    var destLabel: String
    var destLat: Double
    var destLng: Double
    var distanceKm: Double
    var vehicle: VehicleKind
    var proposedFare: Int
    var status: String
    let createdAt: Date
    var expiresAt: Date
    var passenger: ProfileStub?
    var estimatedFare: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case passengerId = "passenger_id"
        case pickupLabel = "pickup_label"
        case pickupLat = "pickup_lat"
        case pickupLng = "pickup_lng"
        case destLabel = "dest_label"
        case destLat = "dest_lat"
        case destLng = "dest_lng"
        case distanceKm = "distance_km"
        case vehicle
        case proposedFare = "proposed_fare"
        case estimatedFare = "estimated_fare"
        case status
        case createdAt = "created_at"
        case expiresAt = "expires_at"
        case passenger
    }
}

// MARK: - Server pricing (no rates, no commission exposed)

/// Passenger quote from `quote_fare`: estimate, discount, total and allowed range.
nonisolated struct PassengerQuote: Codable, Sendable, Equatable {
    var estimatedTotal: Int
    var discount: Int
    var total: Int
    var minProposal: Int
    var maxProposal: Int

    enum CodingKeys: String, CodingKey {
        case estimatedTotal = "estimated_total"
        case discount, total
        case minProposal = "min_proposal"
        case maxProposal = "max_proposal"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        estimatedTotal = try c.decodeFlexibleInt(.estimatedTotal)
        discount = try c.decodeFlexibleInt(.discount)
        total = try c.decodeFlexibleInt(.total)
        minProposal = try c.decodeFlexibleInt(.minProposal)
        maxProposal = try c.decodeFlexibleInt(.maxProposal)
    }
}

extension KeyedDecodingContainer {
    /// Postgres numerics can arrive as 290 or 290.0; accept both.
    nonisolated func decodeFlexibleInt(_ key: Key) throws -> Int {
        if let i = try? decode(Int.self, forKey: key) { return i }
        return Int(try decode(Double.self, forKey: key).rounded())
    }
}

/// Driver preview from `driver_offer_preview`: suggested price, net gain and allowed range.
nonisolated struct DriverOfferPreview: Codable, Sendable, Equatable {
    var suggested: Int
    var net: Int
    var minPrice: Int
    var maxPrice: Int

    enum CodingKeys: String, CodingKey {
        case suggested, net
        case minPrice = "min_price"
        case maxPrice = "max_price"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        suggested = try c.decodeFlexibleInt(.suggested)
        net = try c.decodeFlexibleInt(.net)
        minPrice = try c.decodeFlexibleInt(.minPrice)
        maxPrice = try c.decodeFlexibleInt(.maxPrice)
    }
}

// MARK: - Auth responses

nonisolated struct OtpRequestResponse: Codable, Sendable {
    var ok: Bool
    var phone: String?
    var devCode: String?
    var dev: Bool?
    var error: String?

    enum CodingKeys: String, CodingKey {
        case ok, phone, error, dev
        case devCode = "dev_code"
    }

    /// Error responses from the function carry only `{ "error": ... }`, so `ok` defaults to false.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ok = try c.decodeIfPresent(Bool.self, forKey: .ok) ?? false
        phone = try c.decodeIfPresent(String.self, forKey: .phone)
        devCode = try c.decodeIfPresent(String.self, forKey: .devCode)
        dev = try c.decodeIfPresent(Bool.self, forKey: .dev)
        error = try c.decodeIfPresent(String.self, forKey: .error)
    }
}

nonisolated struct OtpVerifyResponse: Codable, Sendable {
    var ok: Bool
    var accessToken: String?
    var refreshToken: String?
    var expiresIn: Int?
    var userId: String?
    var isNew: Bool?
    var error: String?

    enum CodingKeys: String, CodingKey {
        case ok, error
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case userId = "user_id"
        case isNew = "is_new"
    }

    /// Error responses from the function carry only `{ "error": ... }`, so `ok` defaults to false.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ok = try c.decodeIfPresent(Bool.self, forKey: .ok) ?? false
        accessToken = try c.decodeIfPresent(String.self, forKey: .accessToken)
        refreshToken = try c.decodeIfPresent(String.self, forKey: .refreshToken)
        expiresIn = try c.decodeIfPresent(Int.self, forKey: .expiresIn)
        userId = try c.decodeIfPresent(String.self, forKey: .userId)
        isNew = try c.decodeIfPresent(Bool.self, forKey: .isNew)
        error = try c.decodeIfPresent(String.self, forKey: .error)
    }
}
