//
//  SupabaseService.swift
//  KHERJA
//
//  Supabase client with a custom phone-OTP session (access + refresh tokens in
//  Keychain, transparent refresh), RPC helpers, and polling data access.
//

import Combine
import Foundation
import Supabase

// MARK: - Keychain token store

nonisolated enum TokenStore {
    private static let service = "app.kherja.tokens"
    private static let accessKey = "access_token"
    private static let refreshKey = "refresh_token"

    private static func set(_ value: String?, forKey key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        if let value {
            var attrs = query
            attrs[kSecValueData as String] = Data(value.utf8)
            let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: Data(value.utf8)] as CFDictionary)
            if status == errSecItemNotFound {
                SecItemAdd(attrs as CFDictionary, nil)
            }
        } else {
            SecItemDelete(query as CFDictionary)
        }
    }

    private static func read(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func saveSession(access: String, refresh: String) {
        set(access, forKey: accessKey)
        set(refresh, forKey: refreshKey)
    }

    static var accessToken: String? { read(accessKey) }
    static var refreshToken: String? { read(refreshKey) }

    static func clear() {
        set(nil, forKey: accessKey)
        set(nil, forKey: refreshKey)
    }

    /// Decode the `sub` claim (auth user id) of a JWT without verifying.
    static func subject(of token: String) -> UUID? {
        let parts = token.split(separator: ".")
        guard parts.count == 3 else { return nil }
        var payload = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while payload.count % 4 != 0 { payload += "=" }
        guard let data = Data(base64Encoded: payload),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sub = obj["sub"] as? String else { return nil }
        return UUID(uuidString: sub)
    }

    /// Decode the `exp` claim of a JWT without verifying (verified server-side).
    static func expiry(of token: String) -> Date? {
        let parts = token.split(separator: ".")
        guard parts.count == 3 else { return nil }
        var payload = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while payload.count % 4 != 0 { payload += "=" }
        guard let data = Data(base64Encoded: payload),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let exp = obj["exp"] as? Double else { return nil }
        return Date(timeIntervalSince1970: exp)
    }
}

// MARK: - Session manager (token refresh)

@MainActor
final class SessionManager: ObservableObject {
    static let shared = SessionManager()

    @Published var isSignedIn: Bool = TokenStore.accessToken != nil
    @Published var userId: UUID?

    private var refreshing: Task<String?, Never>?

    private static let ephemeralKey = "kherja.session_ephemeral"

    init() {
        // "Remember me" off: the previous run asked for a session that ends with the app.
        if UserDefaults.standard.bool(forKey: Self.ephemeralKey) {
            TokenStore.clear()
            UserDefaults.standard.set(false, forKey: Self.ephemeralKey)
        }
        isSignedIn = TokenStore.accessToken != nil
        // Restore the user id encoded in the stored token.
        if let token = TokenStore.accessToken {
            userId = TokenStore.subject(of: token)
            isSignedIn = true
        }
    }

    /// `remember: false` keeps the session only until the app is launched again.
    func saveSession(access: String, refresh: String, remember: Bool = true) {
        TokenStore.saveSession(access: access, refresh: refresh)
        UserDefaults.standard.set(!remember, forKey: Self.ephemeralKey)
        userId = TokenStore.subject(of: access)
        isSignedIn = true
    }

    func signOut() {
        TokenStore.clear()
        isSignedIn = false
        userId = nil
    }

    /// Returns a valid access token, refreshing it when near expiry.
    func validAccessToken() async -> String? {
        guard let token = TokenStore.accessToken else { return nil }
        if let exp = TokenStore.expiry(of: token), exp.timeIntervalSinceNow > 60 {
            return token
        }
        if let refreshing {
            return await refreshing.value
        }
        let task = Task<String?, Never> { [weak self] in
            await self?.performRefresh()
        }
        refreshing = task
        let result = await task.value
        refreshing = nil
        return result
    }

    private func performRefresh() async -> String? {
        guard let refreshToken = TokenStore.refreshToken else {
            await MainActor.run { signOut() }
            return nil
        }
        var request = URLRequest(url: URL(string: "\(Config.EXPO_PUBLIC_SUPABASE_URL)/auth/v1/token?grant_type=refresh_token")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Config.EXPO_PUBLIC_SUPABASE_ANON_KEY, forHTTPHeaderField: "apikey")
        request.httpBody = try? JSONEncoder().encode(["refresh_token": refreshToken])
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let access = obj["access_token"] as? String,
                  let refresh = obj["refresh_token"] as? String else {
                await MainActor.run { signOut() }
                return nil
            }
            TokenStore.saveSession(access: access, refresh: refresh)
            return access
        } catch {
            // Network hiccup: keep the old token if it is still technically valid.
            if let token = TokenStore.accessToken, let exp = TokenStore.expiry(of: token), exp > Date() {
                return token
            }
            return nil
        }
    }
}

// MARK: - Supabase client

@MainActor
final class SupabaseService: ObservableObject {
    static let shared = SupabaseService()

    let client: SupabaseClient
    private let session = SessionManager.shared

    private init() {
        client = SupabaseClient(
            supabaseURL: URL(string: Config.EXPO_PUBLIC_SUPABASE_URL)!,
            supabaseKey: Config.EXPO_PUBLIC_SUPABASE_ANON_KEY,
            options: .init(
                auth: .init(
                    accessToken: {
                        // Async closure; SessionManager handles refresh.
                        // Read the current token synchronously first to avoid
                        // a network hop on every request.
                        if let token = TokenStore.accessToken,
                           let exp = TokenStore.expiry(of: token),
                           exp.timeIntervalSinceNow > 60 {
                            return token
                        }
                        return await SessionManager.shared.validAccessToken()
                    }
                )
            )
        )
    }

    // MARK: JSON helpers (tolerant ISO-8601 dates)

    static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            for fmt in ["yyyy-MM-dd'T'HH:mm:ss.SSSSSSXXXXX", "yyyy-MM-dd'T'HH:mm:ss.SSSSSSXXXX", "yyyy-MM-dd'T'HH:mm:ssXXXXX", "yyyy-MM-dd'T'HH:mm:ssXXX", "yyyy-MM-dd'T'HH:mm:ss.SSSXXXX"] {
                let f = DateFormatter()
                f.locale = Locale(identifier: "en_US_POSIX")
                f.dateFormat = fmt
                if let date = f.date(from: raw) { return date }
            }
            if let t = Double(raw) { return Date(timeIntervalSince1970: t) }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Bad date \(raw)")
        }
        return d
    }

    /// Call a Postgres RPC and decode its result.
    func rpc<T: Decodable>(_ name: String, params: some Encodable) async throws -> T {
        let builder = try client.rpc(name, params: params)
        let response = try await builder.execute()
        return try Self.decoder().decode(T.self, from: response.data)
    }

    func rpcVoid(_ name: String, params: some Encodable) async throws {
        _ = try await client.rpc(name, params: params).execute()
    }

    // MARK: Phone OTP via edge function

    nonisolated struct OtpRequest: Encodable, Sendable {
        var action: String
        var phone: String
    }

    /// Body for every auth-otp action. Optional fields are omitted when nil, so the legacy
    /// {action, phone, code} payload is byte-for-byte what older clients send.
    nonisolated struct OtpVerify: Encodable, Sendable {
        var action: String
        var phone: String
        var code: String? = nil
        var purpose: String? = nil
        var password: String? = nil
        var email: String? = nil
    }

    func requestOtp(phone: String) async throws -> OtpRequestResponse {
        try await Self.callFunction("auth-otp", body: OtpRequest(action: "request", phone: phone))
    }

    /// With only (phone, code) this is the original passwordless OTP login.
    /// purpose "register" / "reset" additionally sets the password (hashed by Supabase Auth).
    func verifyOtp(phone: String, code: String, purpose: String? = nil, password: String? = nil, email: String? = nil) async throws -> OtpVerifyResponse {
        let cleanEmail = (email ?? "").trimmingCharacters(in: .whitespaces)
        let result: OtpVerifyResponse = try await Self.callFunction(
            "auth-otp",
            body: OtpVerify(action: "verify", phone: phone, code: code, purpose: purpose, password: password, email: cleanEmail.isEmpty ? nil : cleanEmail)
        )
        if result.ok, let access = result.accessToken, let refresh = result.refreshToken {
            session.saveSession(access: access, refresh: refresh)
        }
        return result
    }

    /// Phone + password sign-in (server rate-limited; generic error on any failure).
    func loginWithPassword(phone: String, password: String, remember: Bool) async throws -> OtpVerifyResponse {
        let result: OtpVerifyResponse = try await Self.callFunction(
            "auth-otp",
            body: OtpVerify(action: "login", phone: phone, password: password)
        )
        if result.ok, let access = result.accessToken, let refresh = result.refreshToken {
            session.saveSession(access: access, refresh: refresh, remember: remember)
        }
        return result
    }

    /// Social accounts, step 1: sends an SMS code to `phone` (needs the signed-in user's token).
    func linkRequest(phone: String) async throws -> OtpRequestResponse {
        guard let token = await session.validAccessToken() else { throw SocialError.failed }
        return try await Self.callFunction("auth-otp", body: OtpRequest(action: "link_request", phone: phone), bearer: token)
    }

    /// Social accounts, step 2: proves ownership with the code; the server records the verified phone.
    func linkVerify(phone: String, code: String) async throws -> OtpVerifyResponse {
        guard let token = await session.validAccessToken() else { throw SocialError.failed }
        return try await Self.callFunction("auth-otp", body: OtpVerify(action: "link_verify", phone: phone, code: code), bearer: token)
    }

    nonisolated struct NoParams: Encodable, Sendable {}

    /// Whether the signed-in account has a verified phone (RPC my_phone_verified, migration 0007).
    func phoneVerified() async throws -> Bool {
        try await rpc("my_phone_verified", params: NoParams())
    }

    // MARK: Social sign-in (Supabase Auth)

    /// Native Sign in with Apple: exchanges Apple's identity token (and the raw nonce) for a session.
    func signInWithApple(idToken: String, nonce: String) async throws -> Bool {
        try await exchangeForSession(
            path: "/auth/v1/token?grant_type=id_token",
            body: ["provider": "apple", "id_token": idToken, "nonce": nonce]
        )
    }

    /// Google (PKCE): exchanges the `code` from the OAuth redirect for a session.
    func completeOAuth(authCode: String, verifier: String) async throws -> Bool {
        try await exchangeForSession(
            path: "/auth/v1/token?grant_type=pkce",
            body: ["auth_code": authCode, "code_verifier": verifier]
        )
    }

    private func exchangeForSession(path: String, body: [String: String]) async throws -> Bool {
        var request = URLRequest(url: URL(string: "\(Config.EXPO_PUBLIC_SUPABASE_URL)\(path)")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Config.EXPO_PUBLIC_SUPABASE_ANON_KEY, forHTTPHeaderField: "apikey")
        request.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let access = obj["access_token"] as? String,
              let refresh = obj["refresh_token"] as? String else { return false }
        session.saveSession(access: access, refresh: refresh)
        return true
    }

    static func callFunction<B: Encodable, R: Decodable>(_ name: String, body: B, bearer: String? = nil) async throws -> R {
        var request = URLRequest(url: URL(string: "\(Config.EXPO_PUBLIC_SUPABASE_URL)/functions/v1/\(name)")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Config.EXPO_PUBLIC_SUPABASE_ANON_KEY, forHTTPHeaderField: "apikey")
        if let bearer { request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization") }
        request.httpBody = try JSONEncoder().encode(body)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch let urlError as URLError where urlError.code == .cancelled {
            // The user/task cancelled the request: not a connectivity problem.
            throw CancellationError()
        } catch {
            throw AuthServiceError.network
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if let failure = AuthServiceError.classify(status: status, body: data) { throw failure }
        do {
            return try decoder().decode(R.self, from: data)
        } catch {
            throw AuthServiceError.service
        }
    }

    // MARK: Profile

    func updateProfile(id: UUID, update: ProfileUpdate) async throws {
        try await client
            .from("profiles")
            .update(update)
            .eq("id", value: id.uuidString)
            .execute()
    }

    // MARK: Driver documents

    func myDriverDocuments(driverId: UUID) async throws -> [DriverDocument] {
        try await client
            .from("driver_documents")
            .select()
            .eq("driver_id", value: driverId.uuidString)
            .order("uploaded_at", ascending: false)
            .execute()
            .decoded(Self.decoder())
    }

    func uploadDriverDocument(driverId: UUID, type: String, data: Data) async throws {
        guard ["id_card", "license", "registration", "insurance", "vehicle_photo"].contains(type) else {
            throw NSError(domain: "KHERJA.Documents", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid document type"])
        }
        guard !data.isEmpty, data.count <= 10 * 1024 * 1024 else {
            throw NSError(domain: "KHERJA.Documents", code: 2, userInfo: [NSLocalizedDescriptionKey: "File must be smaller than 10 MB"])
        }
        let path = "\(driverId.uuidString.lowercased())/\(type)_\(UUID().uuidString.lowercased()).jpg"
        try await client.storage
            .from("driver-documents")
            .upload(path: path, file: data, options: FileOptions(contentType: "image/jpeg", upsert: false))
        try await rpcVoid("submit_driver_document", params: SubmitDriverDocumentParams(type: type, path: path, mime: "image/jpeg"))
    }

    // MARK: Passenger flow

    func createRequest(_ params: CreateRequestParams) async throws -> UUID {
        let id: String = try await rpc("create_request", params: params)
        return UUID(uuidString: id.replacingOccurrences(of: "\"", with: ""))!
    }

    /// Server-side fare quote. The client never computes prices.
    func quoteFare(pickupLat: Double, pickupLng: Double, destLat: Double, destLng: Double, distanceKm: Double, vehicle: VehicleKind, city: String) async throws -> PassengerQuote {
        try await rpc("quote_fare", params: QuoteFareParams(
            p_pickup_lat: pickupLat, p_pickup_lng: pickupLng,
            p_dest_lat: destLat, p_dest_lng: destLng,
            p_distance_km: (distanceKm * 100).rounded() / 100,
            p_vehicle: vehicle.rawValue, p_city: city
        ))
    }

    func cancelRequest(_ requestId: UUID) async throws {
        try await rpcVoid("cancel_request", params: RequestIdParams(pRequest: requestId))
    }

    func offers(requestId: UUID) async throws -> [OfferWithDriver] {
        try await client
            .from("offers")
            .select("*, driver:profiles!offers_driver_id_fkey(*)")
            .eq("request_id", value: requestId.uuidString)
            .order("created_at", ascending: false)
            .execute()
            .decoded(Self.decoder())
    }

    func acceptOffer(_ offerId: UUID) async throws -> UUID {
        let id: String = try await rpc("accept_offer", params: OfferIdParams(pOffer: offerId))
        return UUID(uuidString: id.replacingOccurrences(of: "\"", with: ""))!
    }

    func ride(id: UUID) async throws -> Ride? {
        let rides: [Ride] = try await client
            .from("rides")
            .select()
            .eq("id", value: id.uuidString)
            .execute()
            .decoded(Self.decoder())
        return rides.first
    }

    func profile(id: UUID) async throws -> Profile? {
        let profiles: [Profile] = try await client
            .from("profiles")
            .select()
            .eq("id", value: id.uuidString)
            .execute()
            .decoded(Self.decoder())
        return profiles.first
    }

    func messages(requestId: UUID, after: Date? = nil) async throws -> [RideMessage] {
        var query = client
            .from("ride_messages")
            .select()
            .eq("request_id", value: requestId.uuidString)
        if let after {
            query = query.gt("created_at", value: Self.iso(after))
        }
        return try await query
            .order("created_at", ascending: true)
            .execute()
            .decoded(Self.decoder())
    }

    func sendMessage(requestId: UUID, senderId: UUID, body: String) async throws {
        let insert = MessageInsert(requestId: requestId, senderId: senderId, body: body)
        try await client.from("ride_messages").insert(insert).execute()
    }

    func myRequests(passengerId: UUID, limit: Int = 50) async throws -> [RideRequest] {
        try await client
            .from("ride_requests")
            .select()
            .eq("passenger_id", value: passengerId.uuidString)
            .order("created_at", ascending: false)
            .limit(limit)
            .execute()
            .decoded(Self.decoder())
    }

    func myTransactions(userId: UUID) async throws -> [Transaction] {
        try await client
            .from("transactions")
            .select()
            .eq("user_id", value: userId.uuidString)
            .order("created_at", ascending: false)
            .limit(100)
            .execute()
            .decoded(Self.decoder())
    }

    func submitRating(rideId: UUID, stars: Int, comment: String?) async throws {
        try await rpcVoid("submit_rating", params: RatingParams(pRide: rideId, pStars: stars, pComment: comment))
    }

    // MARK: Driver flow

    func openRequests() async throws -> [RequestWithPassenger] {
        try await client
            .from("ride_requests")
            .select("*, passenger:profiles!ride_requests_passenger_id_fkey(name, rating_avg, trips_count, vehicle_make, vehicle_model, vehicle_plate)")
            .in("status", values: ["open", "negotiating"])
            .gt("expires_at", value: Self.iso(Date()))
            .order("created_at", ascending: false)
            .limit(30)
            .execute()
            .decoded(Self.decoder())
    }

    func makeOffer(requestId: UUID, price: Int, kind: String) async throws -> UUID {
        let id: String = try await rpc("make_offer", params: MakeOfferParams(pRequest: requestId, pPrice: price, pKind: kind))
        return UUID(uuidString: id.replacingOccurrences(of: "\"", with: ""))!
    }

    /// Net gain and allowed range for a driver's price, computed by the server.
    func driverOfferPreview(requestId: UUID, price: Int) async throws -> DriverOfferPreview {
        try await rpc("driver_offer_preview", params: OfferPreviewParams(p_request_id: requestId.uuidString, p_price: price))
    }

    func myDriverOffers(driverId: UUID) async throws -> [Offer] {
        try await client
            .from("offers")
            .select()
            .eq("driver_id", value: driverId.uuidString)
            .in("status", values: ["pending", "accepted"])
            .order("created_at", ascending: false)
            .limit(30)
            .execute()
            .decoded(Self.decoder())
    }

    func myRides(userId: UUID, driver: Bool) async throws -> [Ride] {
        try await client
            .from("rides")
            .select()
            .eq(driver ? "driver_id" : "passenger_id", value: userId.uuidString)
            .order("created_at", ascending: false)
            .limit(100)
            .execute()
            .decoded(Self.decoder())
    }

    func updateRide(rideId: UUID, status: String) async throws {
        try await rpcVoid("update_ride", params: RideStatusParams(pRide: rideId, pStatus: status))
    }

    func updateDriverPresence(lat: Double?, lng: Double?, online: Bool) async throws {
        guard let id = session.userId else { return }
        let update = DriverPresenceUpdate(
            currentLat: lat, currentLng: lng, isOnline: online, updatedAt: Date()
        )
        try await client
            .from("profiles")
            .update(update)
            .eq("id", value: id.uuidString)
            .execute()
    }

    // MARK: Parcel delivery

    func quoteDelivery(pickupLat: Double, pickupLng: Double, destLat: Double, destLng: Double, distanceKm: Double, vehicle: String) async throws -> DeliveryQuote {
        try await rpc("quote_delivery", params: DeliveryQuoteParams(
            p_pickup_lat: pickupLat, p_pickup_lng: pickupLng,
            p_dest_lat: destLat, p_dest_lng: destLng,
            p_distance_km: distanceKm, p_vehicle: vehicle
        ))
    }

    func createDeliveryOrder(_ params: CreateDeliveryParams) async throws -> UUID {
        let id: String = try await rpc("create_delivery_order", params: params)
        guard let uuid = UUID(uuidString: id.replacingOccurrences(of: "\"", with: "")) else {
            throw NSError(domain: "KHERJA.Delivery", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid delivery response"])
        }
        return uuid
    }

    func myDeliveryOrders() async throws -> [DeliveryOrder] {
        try await rpcVoid("expire_delivery_orders", params: EmptyDeliveryParams())
        return try await client.from("delivery_orders").select()
            .order("created_at", ascending: false).limit(50)
            .execute().decoded(Self.decoder())
    }

    func openDeliveryFeed() async throws -> [DeliveryOrder] {
        try await rpc("open_delivery_feed", params: EmptyDeliveryParams())
    }

    func claimDeliveryOrder(_ id: UUID) async throws {
        try await rpcVoid("claim_delivery_order", params: DeliveryOrderIdParams(pOrder: id))
    }

    func updateDeliveryStatus(_ id: UUID, status: String) async throws {
        try await rpcVoid("update_delivery_status", params: DeliveryStatusParams(pOrder: id, pStatus: status))
    }

    func cancelDeliveryOrder(_ id: UUID) async throws {
        try await rpcVoid("cancel_delivery_order", params: DeliveryOrderIdParams(pOrder: id))
    }

    // MARK: Misc

    static func iso(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: date)
    }
}

// MARK: - Delivery RPC parameters

nonisolated struct EmptyDeliveryParams: Encodable, Sendable {}

nonisolated struct DeliveryQuoteParams: Encodable, Sendable {
    var p_pickup_lat: Double
    var p_pickup_lng: Double
    var p_dest_lat: Double
    var p_dest_lng: Double
    var p_distance_km: Double
    var p_vehicle: String
}

nonisolated struct CreateDeliveryParams: Encodable, Sendable {
    var p_pickup_label: String
    var p_pickup_lat: Double
    var p_pickup_lng: Double
    var p_dest_label: String
    var p_dest_lat: Double
    var p_dest_lng: Double
    var p_distance_km: Double
    var p_vehicle: String
    var p_package_description: String
    var p_recipient_name: String
    var p_recipient_phone: String
    var p_sender_note: String?
    var p_city: String
}

nonisolated struct DeliveryOrderIdParams: Encodable, Sendable {
    var p_order_id: String
    init(pOrder: UUID) { p_order_id = pOrder.uuidString }
}

nonisolated struct DeliveryStatusParams: Encodable, Sendable {
    var p_order_id: String
    var p_status: String
    init(pOrder: UUID, pStatus: String) {
        p_order_id = pOrder.uuidString
        p_status = pStatus
    }
}

nonisolated struct SubmitDriverDocumentParams: Encodable, Sendable {
    var p_type: String
    var p_path: String
    var p_mime: String
    init(type: String, path: String, mime: String) {
        p_type = type
        p_path = path
        p_mime = mime
    }
}

// MARK: - RPC param structs

nonisolated struct CreateRequestParams: Encodable, Sendable {
    var p_pickup_label: String
    var p_pickup_lat: Double
    var p_pickup_lng: Double
    var p_dest_label: String
    var p_dest_lat: Double
    var p_dest_lng: Double
    var p_distance_km: Double
    var p_vehicle: String
    var p_proposed_fare: Int
    var p_city: String
}

nonisolated struct QuoteFareParams: Encodable, Sendable {
    var p_pickup_lat: Double
    var p_pickup_lng: Double
    var p_dest_lat: Double
    var p_dest_lng: Double
    var p_distance_km: Double
    var p_vehicle: String
    var p_city: String
}

nonisolated struct OfferPreviewParams: Encodable, Sendable {
    var p_request_id: String
    var p_price: Int
}

nonisolated struct MakeOfferParams: Encodable, Sendable {
    var p_request_id: String
    var p_price: Int
    var p_kind: String

    init(pRequest: UUID, pPrice: Int, pKind: String) {
        p_request_id = pRequest.uuidString
        p_price = pPrice
        p_kind = pKind
    }
}

nonisolated struct OfferIdParams: Encodable, Sendable {
    var p_offer_id: String
    init(pOffer: UUID) { p_offer_id = pOffer.uuidString }
}

nonisolated struct RequestIdParams: Encodable, Sendable {
    var p_request_id: String
    init(pRequest: UUID) { p_request_id = pRequest.uuidString }
}

nonisolated struct PingLocationParams: Encodable, Sendable {
    var p_lat: Double
    var p_lng: Double
}

nonisolated struct RideStatusParams: Encodable, Sendable {
    var p_ride_id: String
    var p_status: String
    init(pRide: UUID, pStatus: String) {
        p_ride_id = pRide.uuidString
        p_status = pStatus
    }
}

nonisolated struct RatingParams: Encodable, Sendable {
    var p_ride_id: String
    var p_stars: Int
    var p_comment: String?
    init(pRide: UUID, pStars: Int, pComment: String?) {
        p_ride_id = pRide.uuidString
        p_stars = pStars
        p_comment = pComment
    }
}

// MARK: - Table write structs

nonisolated struct ProfileUpdate: Encodable, Sendable {
    var name: String?
    var city: String?
    var language: String?
    var role: String?
    var vehicleMake: String?
    var vehicleModel: String?
    var vehiclePlate: String?
    var vehicleColor: String?

    enum CodingKeys: String, CodingKey {
        case name, city, language, role
        case vehicleMake = "vehicle_make"
        case vehicleModel = "vehicle_model"
        case vehiclePlate = "vehicle_plate"
        case vehicleColor = "vehicle_color"
    }
}

nonisolated struct DriverPresenceUpdate: Encodable, Sendable {
    var currentLat: Double?
    var currentLng: Double?
    var isOnline: Bool
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case currentLat = "current_lat"
        case currentLng = "current_lng"
        case isOnline = "is_online"
        case updatedAt = "updated_at"
    }
}

nonisolated struct MessageInsert: Encodable, Sendable {
    var requestId: UUID
    var senderId: UUID
    var body: String

    enum CodingKeys: String, CodingKey {
        case requestId = "request_id"
        case senderId = "sender_id"
        case body
    }
}

// Decode raw PostgREST responses with the tolerant date decoder.
extension PostgrestResponse where T == Data {
    func decoded<D: Decodable>(_ decoder: JSONDecoder) throws -> D {
        try decoder.decode(D.self, from: data)
    }
}

extension SupabaseService {
    func ride(requestId: UUID) async throws -> Ride? {
        let rides: [Ride] = try await client
            .from("rides")
            .select()
            .eq("request_id", value: requestId.uuidString)
            .order("created_at", ascending: false)
            .limit(1)
            .execute()
            .decoded(Self.decoder())
        return rides.first
    }
}

extension SupabaseService {
    func rpcVoid(_ name: String) async throws {
        _ = try await client.rpc(name).execute()
    }

    /// Closes and anonymises the signed-in account (RPC delete_my_account, migration 0013).
    func deleteMyAccount() async throws {
        try await rpcVoid("delete_my_account")
    }

    /// Driver live position via the validated server RPC (also stamps location_updated_at), like Android.
    func pingLocation(lat: Double, lng: Double) async {
        try? await rpcVoid("ping_location", params: PingLocationParams(p_lat: lat, p_lng: lng))
    }

    /// Expire stale open requests and their pending offers before feeding drivers.
    func expireStaleRequests() async {
        try? await rpcVoid("expire_stale_requests")
    }
}


/// Transport / gateway failures of the auth-otp call (never business outcomes such as a wrong code).
/// Mirrors Android's AuthServiceException (b998493), plus explicit 429 handling.
nonisolated enum AuthServiceError: Error, Equatable, Sendable {
    case network      // no connectivity / timeout
    case service      // 404 (not deployed), 5xx, non-JSON, or a gateway 401/403 rejection
    case rateLimited  // 429 without a function-level message

    /// The function answers JSON containing `ok` or `error` for every business outcome
    /// (wrong code, rate limit...), whatever the status. Anything else is a service problem.
    static func classify(status: Int, body: Data) -> AuthServiceError? {
        if status == 404 || status >= 500 { return .service }
        let obj = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
        guard let obj else { return status == 429 ? .rateLimited : .service }
        let isFunctionReply = obj["ok"] != nil || obj["error"] is String
        if isFunctionReply { return nil }
        if status == 429 { return .rateLimited }
        // 401/403 or any other non-2xx without the function's shape (e.g. gateway "Invalid JWT").
        if !(200..<300).contains(status) { return .service }
        return nil
    }

    var messageKey: String {
        switch self {
        case .network: return "err_network"
        case .service: return "err_auth_service"
        case .rateLimited: return "err_too_many"
        }
    }
}
