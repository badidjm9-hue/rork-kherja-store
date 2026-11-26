package app.rork.h04xk59ettzrqz7c6l4wp.data

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlin.math.roundToInt

@Serializable
data class Profile(
    val id: String,
    val role: String = "passenger",
    val name: String = "",
    val city: String = "Alger",
    val language: String = "fr",
    @SerialName("vehicle_make") val vehicleMake: String? = null,
    @SerialName("vehicle_model") val vehicleModel: String? = null,
    @SerialName("vehicle_plate") val vehiclePlate: String? = null,
    @SerialName("vehicle_color") val vehicleColor: String? = null,
    @SerialName("is_online") val isOnline: Boolean = false,
    @SerialName("current_lat") val currentLat: Double? = null,
    @SerialName("current_lng") val currentLng: Double? = null,
    @SerialName("rating_avg") val ratingAvg: Double = 0.0,
    @SerialName("rating_count") val ratingCount: Int = 0,
    @SerialName("trips_count") val tripsCount: Int = 0,
    @SerialName("created_at") val createdAt: String? = null,
    @SerialName("driver_status") val driverStatus: String? = null,
    @SerialName("account_status") val accountStatus: String? = null,
    @SerialName("status_reason") val statusReason: String? = null,
)

@Serializable
data class ProfileStub(
    val name: String = "",
    @SerialName("rating_avg") val ratingAvg: Double = 0.0,
    @SerialName("trips_count") val tripsCount: Int = 0,
    @SerialName("vehicle_make") val vehicleMake: String? = null,
    @SerialName("vehicle_model") val vehicleModel: String? = null,
    @SerialName("vehicle_plate") val vehiclePlate: String? = null,
)

@Serializable
data class RideRequest(
    val id: String,
    @SerialName("passenger_id") val passengerId: String,
    @SerialName("pickup_label") val pickupLabel: String,
    @SerialName("pickup_lat") val pickupLat: Double,
    @SerialName("pickup_lng") val pickupLng: Double,
    @SerialName("dest_label") val destLabel: String,
    @SerialName("dest_lat") val destLat: Double,
    @SerialName("dest_lng") val destLng: Double,
    val city: String = "Alger",
    @SerialName("distance_km") val distanceKm: Double = 0.0,
    val vehicle: String = "car",
    @SerialName("proposed_fare") val proposedFare: Int = 0,
    @SerialName("estimated_fare") val estimatedFare: Int? = null,
    val discount: Int = 0,
    val status: String = "open",
    @SerialName("created_at") val createdAt: String? = null,
    @SerialName("expires_at") val expiresAt: String? = null,
    val passenger: ProfileStub? = null,
)

@Serializable
data class DeliveryOrder(
    val id: String,
    @SerialName("passenger_id") val passengerId: String,
    @SerialName("driver_id") val driverId: String? = null,
    @SerialName("pickup_label") val pickupLabel: String,
    @SerialName("pickup_lat") val pickupLat: Double,
    @SerialName("pickup_lng") val pickupLng: Double,
    @SerialName("dest_label") val destLabel: String,
    @SerialName("dest_lat") val destLat: Double,
    @SerialName("dest_lng") val destLng: Double,
    val city: String = "Alger",
    @SerialName("distance_km") val distanceKm: Double = 0.0,
    val vehicle: String = "moto",
    @SerialName("package_description") val packageDescription: String,
    @SerialName("recipient_name") val recipientName: String = "",
    @SerialName("recipient_phone") val recipientPhone: String = "",
    @SerialName("sender_note") val senderNote: String? = null,
    @SerialName("delivery_fee") val deliveryFee: Int = 0,
    @SerialName("payment_method") val paymentMethod: String = "cash",
    val status: String = "open",
    @SerialName("created_at") val createdAt: String? = null,
    @SerialName("expires_at") val expiresAt: String? = null,
    @SerialName("accepted_at") val acceptedAt: String? = null,
    @SerialName("picked_up_at") val pickedUpAt: String? = null,
    @SerialName("delivered_at") val deliveredAt: String? = null,
)

@Serializable
data class DeliveryQuote(
    @SerialName("distance_km") val distanceKm: Double,
    val vehicle: String,
    @SerialName("rate_per_km") val ratePerKm: Int,
    @SerialName("minimum_fee") val minimumFee: Int,
    @SerialName("delivery_fee") val deliveryFee: Int,
    val currency: String = "DZD",
    @SerialName("payment_method") val paymentMethod: String = "cash",
)

@Serializable
data class Offer(
    val id: String,
    @SerialName("request_id") val requestId: String,
    @SerialName("driver_id") val driverId: String,
    val price: Int,
    val kind: String = "initial",
    val status: String = "pending",
    @SerialName("created_at") val createdAt: String? = null,
    val driver: Profile? = null,
)

@Serializable
data class Ride(
    val id: String,
    @SerialName("request_id") val requestId: String,
    @SerialName("passenger_id") val passengerId: String,
    @SerialName("driver_id") val driverId: String,
    val vehicle: String = "car",
    val fare: Int = 0,
    val status: String = "en_route",
    @SerialName("pickup_label") val pickupLabel: String = "",
    @SerialName("pickup_lat") val pickupLat: Double = 0.0,
    @SerialName("pickup_lng") val pickupLng: Double = 0.0,
    @SerialName("dest_label") val destLabel: String = "",
    @SerialName("dest_lat") val destLat: Double = 0.0,
    @SerialName("dest_lng") val destLng: Double = 0.0,
    @SerialName("distance_km") val distanceKm: Double? = null,
    @SerialName("driver_net") val driverNet: Int? = null,
    @SerialName("started_at") val startedAt: String? = null,
    @SerialName("completed_at") val completedAt: String? = null,
    @SerialName("created_at") val createdAt: String? = null,
) {
    val isActive: Boolean get() = status == "en_route" || status == "arrived" || status == "started"
}

@Serializable
data class RideMessage(
    val id: String,
    @SerialName("request_id") val requestId: String,
    @SerialName("sender_id") val senderId: String,
    val body: String,
    @SerialName("created_at") val createdAt: String? = null,
)

@Serializable
data class Transaction(
    val id: String,
    @SerialName("user_id") val userId: String,
    @SerialName("ride_id") val rideId: String? = null,
    val kind: String,
    val amount: Int,
    val method: String = "cash",
    val label: String? = null,
    @SerialName("created_at") val createdAt: String? = null,
)

/** Server quote from quote_fare. Numerics may arrive as 290 or 290.0. */
@Serializable
data class PassengerQuote(
    @SerialName("estimated_total") val estimatedTotalRaw: Double,
    @SerialName("discount") val discountRaw: Double = 0.0,
    @SerialName("total") val totalRaw: Double,
    @SerialName("min_proposal") val minRaw: Double,
    @SerialName("max_proposal") val maxRaw: Double,
) {
    val estimatedTotal get() = estimatedTotalRaw.roundToInt()
    val discount get() = discountRaw.roundToInt()
    val total get() = totalRaw.roundToInt()
    val minProposal get() = minRaw.roundToInt()
    val maxProposal get() = maxRaw.roundToInt()
}

/** Driver preview from driver_offer_preview: suggested price, net gain, range. */
@Serializable
data class DriverOfferPreview(
    @SerialName("suggested") val suggestedRaw: Double,
    @SerialName("net") val netRaw: Double,
    @SerialName("min_price") val minRaw: Double,
    @SerialName("max_price") val maxRaw: Double,
) {
    val suggested get() = suggestedRaw.roundToInt()
    val net get() = netRaw.roundToInt()
    val minPrice get() = minRaw.roundToInt()
    val maxPrice get() = maxRaw.roundToInt()
}

@Serializable
data class OtpRequestResponse(
    val ok: Boolean = false,
    val phone: String? = null,
    @SerialName("dev_code") val devCode: String? = null,
    val dev: Boolean? = null,
    val error: String? = null,
)

@Serializable
data class OtpVerifyResponse(
    val ok: Boolean = false,
    @SerialName("access_token") val accessToken: String? = null,
    @SerialName("refresh_token") val refreshToken: String? = null,
    @SerialName("expires_in") val expiresIn: Int? = null,
    @SerialName("user_id") val userId: String? = null,
    @SerialName("is_new") val isNew: Boolean? = null,
    val error: String? = null,
)

@Serializable
data class TokenResponse(
    @SerialName("access_token") val accessToken: String? = null,
    @SerialName("refresh_token") val refreshToken: String? = null,
)

data class GeoPlace(val label: String, val lat: Double, val lng: Double)

data class RouteInfo(val distanceKm: Double, val durationMin: Int?, val points: List<Pair<Double, Double>>)

val CITIES = listOf("Alger", "Oran", "Constantine", "Annaba", "Blida", "Batna", "Sétif", "Tlemcen", "Béjaïa", "Ouargla")


@Serializable
data class DriverDocument(
    val id: String,
    @SerialName("driver_id") val driverId: String,
    @SerialName("doc_type") val docType: String,
    @SerialName("storage_path") val storagePath: String,
    @SerialName("mime_type") val mimeType: String = "image/jpeg",
    val status: String = "pending",
    val reason: String? = null,
    @SerialName("uploaded_at") val uploadedAt: String? = null,
    @SerialName("reviewed_at") val reviewedAt: String? = null,
)


@Serializable
data class SavedPlace(
    val id: String,
    val kind: String = "favorite",
    val label: String,
    val address: String,
    val lat: Double,
    val lng: Double,
)

@Serializable
data class AppNotification(
    val id: String,
    val kind: String = "system",
    val title: String,
    val body: String = "",
    @SerialName("read_at") val readAt: String? = null,
    @SerialName("created_at") val createdAt: String? = null,
) {
    val isUnread: Boolean get() = readAt == null
}

@Serializable
data class NotificationPrefs(
    val rides: Boolean = true,
    val promotions: Boolean = true,
)

@Serializable
data class Vehicle(
    val id: String,
    val category: String = "car",
    val make: String,
    val model: String,
    val year: Int? = null,
    val plate: String,
    val color: String = "",
    val seats: Int = 4,
    @SerialName("is_primary") val isPrimary: Boolean = false,
    val status: String = "active",
    @SerialName("suspended_reason") val suspendedReason: String? = null,
)

@Serializable
data class RideReceipt(
    @SerialName("ride_id") val rideId: String,
    val reference: String,
    val vehicle: String = "car",
    val fare: Int = 0,
    @SerialName("distance_km") val distanceKm: Double? = null,
    @SerialName("pickup_label") val pickupLabel: String = "",
    @SerialName("dest_label") val destLabel: String = "",
    @SerialName("created_at") val createdAt: String? = null,
    @SerialName("started_at") val startedAt: String? = null,
    @SerialName("completed_at") val completedAt: String? = null,
    @SerialName("driver_name") val driverName: String? = null,
    @SerialName("vehicle_make") val vehicleMake: String? = null,
    @SerialName("vehicle_model") val vehicleModel: String? = null,
    @SerialName("vehicle_plate") val vehiclePlate: String? = null,
    val payment: String = "cash",
)

@Serializable
data class SupportContact(
    val phone: String = "",
    val email: String = "",
)
