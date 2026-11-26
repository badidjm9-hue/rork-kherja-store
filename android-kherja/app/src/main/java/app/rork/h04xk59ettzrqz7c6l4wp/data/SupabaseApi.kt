package app.rork.h04xk59ettzrqz7c6l4wp.data

import app.rork.h04xk59ettzrqz7c6l4wp.Config
import io.ktor.client.HttpClient
import io.ktor.client.engine.android.Android
import io.ktor.client.request.HttpRequestBuilder
import io.ktor.client.request.header
import io.ktor.client.request.request
import io.ktor.client.request.setBody
import io.ktor.client.statement.bodyAsText
import io.ktor.http.ContentType
import io.ktor.http.HttpMethod
import io.ktor.http.contentType
import io.ktor.http.encodeURLQueryComponent
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

class ApiException(message: String, val status: Int) : Exception(message)

val KJson = Json {
    ignoreUnknownKeys = true
    coerceInputValues = true
    explicitNulls = false
    isLenient = true
}

fun jsonOf(vararg pairs: Pair<String, Any?>): JsonObject = JsonObject(pairs.associate { (k, v) ->
    k to when (v) {
        null -> JsonNull
        is JsonElement -> v
        is String -> JsonPrimitive(v)
        is Number -> JsonPrimitive(v)
        is Boolean -> JsonPrimitive(v)
        else -> JsonPrimitive(v.toString())
    }
})

const val OAUTH_REDIRECT = "kherja://auth-callback"

/** RFC 7636 PKCE helpers (S256). */
object Pkce {
    fun newVerifier(): String {
        val bytes = ByteArray(48)
        java.security.SecureRandom().nextBytes(bytes)
        return b64(bytes)
    }

    fun challenge(verifier: String): String =
        b64(java.security.MessageDigest.getInstance("SHA-256").digest(verifier.toByteArray(Charsets.US_ASCII)))

    private fun b64(b: ByteArray) =
        android.util.Base64.encodeToString(b, android.util.Base64.URL_SAFE or android.util.Base64.NO_PADDING or android.util.Base64.NO_WRAP)
}

/** Thin REST/RPC client for Supabase (PostgREST + edge functions), no SDK. */
class SupabaseApi(private val session: SessionStore) {
    private val base = Config.EXPO_PUBLIC_SUPABASE_URL.trimEnd('/')
    private val anon = Config.EXPO_PUBLIC_SUPABASE_ANON_KEY
    val http = HttpClient(Android) {
        expectSuccess = false
        engine {
            connectTimeout = 15_000
            socketTimeout = 20_000
        }
    }
    private val refreshLock = Mutex()

    var onSessionExpired: (() -> Unit)? = null

    // ---------- core ----------

    private suspend fun validToken(): String? {
        val exp = session.accessExpiry()
        val now = System.currentTimeMillis() / 1000
        if (session.accessToken != null && exp != null && exp - now > 60) return session.accessToken
        return refresh()
    }

    private suspend fun refresh(): String? = refreshLock.withLock {
        val exp = session.accessExpiry()
        val now = System.currentTimeMillis() / 1000
        if (session.accessToken != null && exp != null && exp - now > 60) return@withLock session.accessToken
        val rt = session.refreshToken ?: return@withLock null
        val res = http.request("$base/auth/v1/token?grant_type=refresh_token") {
            method = HttpMethod.Post
            header("apikey", anon)
            contentType(ContentType.Application.Json)
            setBody(jsonOf("refresh_token" to rt).toString())
        }
        val text = res.bodyAsText()
        if (res.status.value in 200..299) {
            val t = KJson.decodeFromString<TokenResponse>(text)
            if (t.accessToken != null && t.refreshToken != null) {
                session.save(t.accessToken, t.refreshToken)
                return@withLock t.accessToken
            }
        }
        if (res.status.value in 400..499) {
            session.clear()
            onSessionExpired?.invoke()
        }
        null
    }

    private suspend fun send(
        method: HttpMethod,
        path: String,
        body: String? = null,
        prefer: String? = null,
        authed: Boolean = true,
        retry: Boolean = true,
    ): String {
        val token = if (authed) validToken() else null
        val res = http.request("$base$path") {
            this.method = method
            header("apikey", anon)
            header("Authorization", "Bearer ${token ?: anon}")
            prefer?.let { header("Prefer", it) }
            if (body != null) {
                contentType(ContentType.Application.Json)
                setBody(body)
            }
        }
        val text = res.bodyAsText()
        if (res.status.value == 401 && authed && retry && text.contains("JWT", ignoreCase = true)) {
            refresh()
            return send(method, path, body, prefer, authed, retry = false)
        }
        if (res.status.value !in 200..299) throw ApiException(errorMessage(text), res.status.value)
        return text
    }

    private fun errorMessage(text: String): String = try {
        val o = KJson.parseToJsonElement(text).jsonObject
        (o["message"] ?: o["error"] ?: o["msg"])?.jsonPrimitive?.content ?: text
    } catch (_: Exception) {
        text
    }

    private suspend inline fun <reified T> get(path: String): T = KJson.decodeFromString(send(HttpMethod.Get, path))

    private suspend inline fun <reified T> rpc(name: String, args: JsonObject = JsonObject(emptyMap())): T =
        KJson.decodeFromString(send(HttpMethod.Post, "/rest/v1/rpc/$name", args.toString()))

    private suspend fun rpcVoid(name: String, args: JsonObject = JsonObject(emptyMap())) {
        send(HttpMethod.Post, "/rest/v1/rpc/$name", args.toString())
    }

    fun q(v: String) = v.encodeURLQueryComponent()

    // ---------- auth ----------

    suspend fun requestOtp(phone: String): OtpRequestResponse = otp(jsonOf("action" to "request", "phone" to phone))

    /**
     * Backward compatible: with only (phone, code) this is the original passwordless OTP login.
     * purpose = "register" | "reset" additionally sets the password (hashed server-side by Supabase Auth).
     */
    suspend fun verifyOtp(
        phone: String,
        code: String,
        purpose: String? = null,
        password: String? = null,
        email: String? = null,
    ): OtpVerifyResponse {
        val fields = mutableListOf<Pair<String, Any?>>("action" to "verify", "phone" to phone, "code" to code)
        if (purpose != null) fields += "purpose" to purpose
        if (password != null) fields += "password" to password
        if (!email.isNullOrBlank()) fields += "email" to email.trim()
        return KJson.decodeFromString(otpRaw(jsonOf(*fields.toTypedArray())))
    }

    /** Phone + password sign-in (server rate-limited, generic error on failure). */
    suspend fun loginWithPassword(phone: String, password: String): OtpVerifyResponse =
        KJson.decodeFromString(otpRaw(jsonOf("action" to "login", "phone" to phone, "password" to password)))

    // ---------- Google / Apple (Supabase OAuth, PKCE, system browser) ----------

    /** Builds the Supabase authorize URL for [provider] ("google" | "apple") and stores the PKCE verifier. */
    fun oauthAuthorizeUrl(provider: String): String {
        val verifier = Pkce.newVerifier()
        session.oauthVerifier = verifier
        return "$base/auth/v1/authorize?provider=${q(provider)}" +
            "&redirect_to=${q(OAUTH_REDIRECT)}" +
            "&code_challenge=${q(Pkce.challenge(verifier))}&code_challenge_method=s256"
    }

    /** Exchanges the `code` from the kherja://auth-callback deep link for a session. Returns false on failure. */
    suspend fun completeOAuth(authCode: String): TokenResponse? {
        val verifier = session.oauthVerifier ?: return null
        session.oauthVerifier = null // single use
        val res = http.request("$base/auth/v1/token?grant_type=pkce") {
            method = HttpMethod.Post
            header("apikey", anon)
            contentType(ContentType.Application.Json)
            setBody(jsonOf("auth_code" to authCode, "code_verifier" to verifier).toString())
        }
        if (res.status.value !in 200..299) return null
        val t = KJson.decodeFromString<TokenResponse>(res.bodyAsText())
        return if (t.accessToken != null && t.refreshToken != null) t else null
    }

    private suspend fun otp(body: JsonObject): OtpRequestResponse = KJson.decodeFromString(otpRaw(body))

    /** Social accounts, step 1: sends an SMS code to [phone] (needs the signed-in user's token). */
    suspend fun linkRequest(phone: String): OtpRequestResponse {
        val token = validToken() ?: return OtpRequestResponse(ok = false, error = "Session requise")
        return KJson.decodeFromString(otpRaw(jsonOf("action" to "link_request", "phone" to phone), token))
    }

    /** Social accounts, step 2: proves ownership with the code; the server records the verified phone. */
    suspend fun linkVerify(phone: String, code: String): OtpRequestResponse {
        val token = validToken() ?: return OtpRequestResponse(ok = false, error = "Session requise")
        return KJson.decodeFromString(otpRaw(jsonOf("action" to "link_verify", "phone" to phone, "code" to code), token))
    }

    /** Whether the signed-in account has a verified phone (RPC my_phone_verified, migration 0007). */
    suspend fun phoneVerified(): Boolean = rpc("my_phone_verified")

    private suspend fun otpRaw(body: JsonObject, bearer: String = anon): String {
        val res = http.request("$base/functions/v1/auth-otp") {
            method = HttpMethod.Post
            header("apikey", anon)
            header("Authorization", "Bearer $bearer")
            contentType(ContentType.Application.Json)
            setBody(body.toString())
        }
        return res.bodyAsText()
    }

    // ---------- profiles ----------

    suspend fun profile(id: String): Profile? = get<List<Profile>>("/rest/v1/profiles?select=*&id=eq.$id&limit=1").firstOrNull()

    suspend fun updateProfile(id: String, fields: JsonObject) {
        send(HttpMethod.Patch, "/rest/v1/profiles?id=eq.$id", fields.toString(), prefer = "return=minimal")
    }

    // ---------- passenger ----------

    suspend fun quoteFare(pLat: Double, pLng: Double, dLat: Double, dLng: Double, km: Double, vehicle: String, city: String): PassengerQuote =
        rpc("quote_fare", jsonOf(
            "p_pickup_lat" to pLat, "p_pickup_lng" to pLng, "p_dest_lat" to dLat, "p_dest_lng" to dLng,
            "p_distance_km" to km, "p_vehicle" to vehicle, "p_city" to city,
        ))

    suspend fun createRequest(pickup: GeoPlace, dest: GeoPlace, km: Double, vehicle: String, fare: Int, city: String): String =
        rpc("create_request", jsonOf(
            "p_pickup_label" to pickup.label, "p_pickup_lat" to pickup.lat, "p_pickup_lng" to pickup.lng,
            "p_dest_label" to dest.label, "p_dest_lat" to dest.lat, "p_dest_lng" to dest.lng,
            "p_distance_km" to km, "p_vehicle" to vehicle, "p_proposed_fare" to fare, "p_city" to city,
        ))

    suspend fun request(id: String): RideRequest? = get<List<RideRequest>>("/rest/v1/ride_requests?select=*&id=eq.$id&limit=1").firstOrNull()

    suspend fun cancelRequest(id: String) = rpcVoid("cancel_request", jsonOf("p_request_id" to id))

    suspend fun offers(requestId: String): List<Offer> =
        get("/rest/v1/offers?select=*,driver:profiles!offers_driver_id_fkey(*)&request_id=eq.$requestId&order=created_at.desc")

    suspend fun acceptOffer(offerId: String): String = rpc("accept_offer", jsonOf("p_offer_id" to offerId))

    suspend fun messages(requestId: String): List<RideMessage> =
        get("/rest/v1/ride_messages?select=*&request_id=eq.$requestId&order=created_at.asc")

    suspend fun sendMessage(requestId: String, senderId: String, body: String) {
        send(HttpMethod.Post, "/rest/v1/ride_messages",
            jsonOf("request_id" to requestId, "sender_id" to senderId, "body" to body).toString(),
            prefer = "return=minimal")
    }

    suspend fun submitRating(rideId: String, stars: Int, comment: String?) =
        rpcVoid("submit_rating", jsonOf("p_ride_id" to rideId, "p_stars" to stars, "p_comment" to comment))

    // ---------- rides ----------

    suspend fun ride(id: String): Ride? = get<List<Ride>>("/rest/v1/rides?select=*&id=eq.$id&limit=1").firstOrNull()

    suspend fun rideForRequest(requestId: String): Ride? =
        get<List<Ride>>("/rest/v1/rides?select=*&request_id=eq.$requestId&limit=1").firstOrNull()

    suspend fun myRides(userId: String, driver: Boolean): List<Ride> =
        get("/rest/v1/rides?select=*&${if (driver) "driver_id" else "passenger_id"}=eq.$userId&order=created_at.desc&limit=100")

    suspend fun activeDriverRide(userId: String): Ride? =
        get<List<Ride>>("/rest/v1/rides?select=*&driver_id=eq.$userId&status=in.(en_route,arrived,started)&order=created_at.desc&limit=1").firstOrNull()

    suspend fun activePassengerRide(userId: String): Ride? =
        get<List<Ride>>("/rest/v1/rides?select=*&passenger_id=eq.$userId&status=in.(en_route,arrived,started)&order=created_at.desc&limit=1").firstOrNull()

    suspend fun openPassengerRequest(userId: String): RideRequest? =
        get<List<RideRequest>>("/rest/v1/ride_requests?select=*&passenger_id=eq.$userId&status=in.(open,negotiating)&order=created_at.desc&limit=1").firstOrNull()

    suspend fun updateRide(rideId: String, status: String) =
        rpcVoid("update_ride", jsonOf("p_ride_id" to rideId, "p_status" to status))

    suspend fun cancelRide(rideId: String, reason: String?) =
        rpcVoid("cancel_ride", jsonOf("p_ride_id" to rideId, "p_reason" to reason))

    suspend fun transactions(userId: String): List<Transaction> =
        get("/rest/v1/transactions?select=*&user_id=eq.$userId&order=created_at.desc&limit=100")

    // ---------- driver documents ----------
    suspend fun myDriverDocuments(driverId: String): List<DriverDocument> =
        get("/rest/v1/driver_documents?select=*&driver_id=eq.$driverId&order=uploaded_at.desc")

    /** Uploads a private file to the driver's own folder, then registers it for admin review. */
    suspend fun uploadDriverDocument(driverId: String, type: String, bytes: ByteArray, mimeType: String, extension: String) {
        require(type in setOf("id_card", "license", "registration", "insurance", "vehicle_photo"))
        require(bytes.isNotEmpty() && bytes.size <= 10 * 1024 * 1024) { "File must be smaller than 10 MB" }
        require(mimeType in setOf("image/jpeg", "image/png", "image/heic", "application/pdf"))
        val token = validToken() ?: throw ApiException("Session requise", 401)
        val path = "${driverId.lowercase()}/${type}_${System.currentTimeMillis()}.$extension"
        val encodedPath = path.split("/").joinToString("/") { q(it) }
        val response = http.request("$base/storage/v1/object/driver-documents/$encodedPath") {
            method = HttpMethod.Post
            header("apikey", anon)
            header("Authorization", "Bearer $token")
            header("x-upsert", "false")
            contentType(ContentType.parse(mimeType))
            setBody(bytes)
        }
        val body = response.bodyAsText()
        if (response.status.value !in 200..299) throw ApiException(errorMessage(body), response.status.value)
        rpcVoid("submit_driver_document", jsonOf(
            "p_type" to type, "p_path" to path, "p_mime" to mimeType,
        ))
    }

    // ---------- driver ----------

    suspend fun expireStale() = runCatching { rpcVoid("expire_stale_requests") }

    suspend fun openRequests(): List<RideRequest> {
        return get("/rest/v1/ride_requests?select=*,passenger:profiles!ride_requests_passenger_id_fkey(name,rating_avg,trips_count,vehicle_make,vehicle_model,vehicle_plate)&status=in.(open,negotiating)&expires_at=gt.now&order=created_at.desc&limit=30")
    }

    // ---------- parcel delivery ----------
    suspend fun quoteDelivery(pickup: GeoPlace, dest: GeoPlace, km: Double, vehicle: String): DeliveryQuote =
        rpc("quote_delivery", jsonOf(
            "p_pickup_lat" to pickup.lat, "p_pickup_lng" to pickup.lng,
            "p_dest_lat" to dest.lat, "p_dest_lng" to dest.lng,
            "p_distance_km" to km, "p_vehicle" to vehicle,
        ))

    suspend fun createDeliveryOrder(
        pickup: GeoPlace, dest: GeoPlace, km: Double, vehicle: String,
        description: String, recipient: String, phone: String, note: String?, city: String,
    ): String = rpc("create_delivery_order", jsonOf(
        "p_pickup_label" to pickup.label, "p_pickup_lat" to pickup.lat, "p_pickup_lng" to pickup.lng,
        "p_dest_label" to dest.label, "p_dest_lat" to dest.lat, "p_dest_lng" to dest.lng,
        "p_distance_km" to km, "p_vehicle" to vehicle,
        "p_package_description" to description, "p_recipient_name" to recipient,
        "p_recipient_phone" to phone, "p_sender_note" to note, "p_city" to city,
    ))

    suspend fun myDeliveryOrders(): List<DeliveryOrder> {
        rpcVoid("expire_delivery_orders", jsonOf())
        return get("/rest/v1/delivery_orders?select=*&order=created_at.desc&limit=50")
    }

    suspend fun openDeliveryOrders(): List<DeliveryOrder> =
        rpc("open_delivery_feed", jsonOf())

    suspend fun claimDeliveryOrder(id: String) =
        rpcVoid("claim_delivery_order", jsonOf("p_order_id" to id))

    suspend fun updateDeliveryStatus(id: String, status: String) =
        rpcVoid("update_delivery_status", jsonOf("p_order_id" to id, "p_status" to status))

    suspend fun cancelDeliveryOrder(id: String) =
        rpcVoid("cancel_delivery_order", jsonOf("p_order_id" to id))

    suspend fun myDriverOffers(driverId: String): List<Offer> =
        get("/rest/v1/offers?select=*&driver_id=eq.$driverId&status=eq.pending&order=created_at.desc&limit=50")

    suspend fun offerPreview(requestId: String, price: Int): DriverOfferPreview =
        rpc("driver_offer_preview", jsonOf("p_request_id" to requestId, "p_price" to price))

    suspend fun makeOffer(requestId: String, price: Int, kind: String = "initial"): String =
        rpc("make_offer", jsonOf("p_request_id" to requestId, "p_price" to price, "p_kind" to kind))

    suspend fun pingLocation(lat: Double, lng: Double) =
        runCatching { rpcVoid("ping_location", jsonOf("p_lat" to lat, "p_lng" to lng)) }
}
