package app.rork.h04xk59ettzrqz7c6l4wp.data

import io.ktor.client.HttpClient
import io.ktor.client.request.get
import io.ktor.client.request.header
import io.ktor.client.statement.bodyAsText
import io.ktor.http.encodeURLQueryComponent
import kotlinx.serialization.json.double
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.roundToInt
import kotlin.math.sin
import kotlin.math.sqrt

/**
 * Address search (Nominatim / OpenStreetMap) and road distance (OSRM).
 * No API key needed. The server bounds the distance anyway (trusted_distance).
 */
class GeoService(private val http: HttpClient) {
    private val ua = "KHERJA-Android/1.0 (app.rork.kherja)"

    suspend fun search(query: String, lang: String, near: GeoPlace?): List<GeoPlace> =
        runCatching { searchOrThrow(query, lang, near) }.getOrDefault(emptyList())

    /** Strict variant for UI that must distinguish an empty result from a network/provider error. */
    suspend fun searchOrThrow(query: String, lang: String, near: GeoPlace?): List<GeoPlace> {
        val viewbox = near?.let { "&viewbox=${it.lng - 0.6},${it.lat + 0.6},${it.lng + 0.6},${it.lat - 0.6}" } ?: ""
        val url = "https://nominatim.openstreetmap.org/search?format=jsonv2&limit=8&countrycodes=dz" +
            "&accept-language=$lang$viewbox&q=${query.encodeURLQueryComponent()}"
        val response = http.get(url) { header("User-Agent", ua) }
        if (response.status.value !in 200..299) throw IllegalStateException("Address search unavailable (${response.status.value})")
        val text = response.bodyAsText()
        return KJson.parseToJsonElement(text).jsonArray.mapNotNull { el ->
            val o = el.jsonObject
            val lat = o["lat"]?.jsonPrimitive?.content?.toDoubleOrNull() ?: return@mapNotNull null
            val lng = o["lon"]?.jsonPrimitive?.content?.toDoubleOrNull() ?: return@mapNotNull null
            val display = o["display_name"]?.jsonPrimitive?.content ?: return@mapNotNull null
            GeoPlace(shorten(display), lat, lng)
        }
    }

    suspend fun reverse(lat: Double, lng: Double, lang: String): String? = runCatching {
        val url = "https://nominatim.openstreetmap.org/reverse?format=jsonv2&zoom=17&accept-language=$lang&lat=$lat&lon=$lng"
        val text = http.get(url) { header("User-Agent", ua) }.bodyAsText()
        KJson.parseToJsonElement(text).jsonObject["display_name"]?.jsonPrimitive?.content?.let { shorten(it) }
    }.getOrNull()

    suspend fun route(from: GeoPlace, to: GeoPlace): RouteInfo {
        val result = runCatching {
            val url = "https://router.project-osrm.org/route/v1/driving/${from.lng},${from.lat};${to.lng},${to.lat}?overview=full&geometries=geojson"
            val text = http.get(url) { header("User-Agent", ua) }.bodyAsText()
            val route = KJson.parseToJsonElement(text).jsonObject["routes"]!!.jsonArray[0].jsonObject
            val meters = route["distance"]!!.jsonPrimitive.double
            val seconds = route["duration"]?.jsonPrimitive?.doubleOrNull
            val coords = route["geometry"]!!.jsonObject["coordinates"]!!.jsonArray.map {
                val pair = it.jsonArray
                pair[1].jsonPrimitive.double to pair[0].jsonPrimitive.double
            }
            RouteInfo(round2(meters / 1000.0), seconds?.let { (it / 60).roundToInt().coerceAtLeast(1) }, coords)
        }.getOrNull()
        if (result != null && result.distanceKm > 0) return result
        val km = haversine(from.lat, from.lng, to.lat, to.lng) * 1.3
        return RouteInfo(round2(km), null, listOf(from.lat to from.lng, to.lat to to.lng))
    }

    private fun shorten(display: String): String =
        display.split(",").map { it.trim() }.filter { it.isNotEmpty() }.take(3).joinToString(", ")

    companion object {
        fun round2(v: Double) = (v * 100).roundToInt() / 100.0

        fun haversine(lat1: Double, lng1: Double, lat2: Double, lng2: Double): Double {
            val r = 6371.0
            val dLat = Math.toRadians(lat2 - lat1)
            val dLng = Math.toRadians(lng2 - lng1)
            val a = sin(dLat / 2) * sin(dLat / 2) +
                cos(Math.toRadians(lat1)) * cos(Math.toRadians(lat2)) * sin(dLng / 2) * sin(dLng / 2)
            return r * 2 * atan2(sqrt(a), sqrt(1 - a))
        }
    }
}
