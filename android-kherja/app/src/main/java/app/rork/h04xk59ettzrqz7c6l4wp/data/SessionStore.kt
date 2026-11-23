package app.rork.h04xk59ettzrqz7c6l4wp.data

import android.content.Context
import android.util.Base64
import org.json.JSONObject

/** Persists tokens and lightweight app preferences. */
class SessionStore(context: Context) {
    private val prefs = context.getSharedPreferences("kherja", Context.MODE_PRIVATE)

    var accessToken: String?
        get() = prefs.getString("access", null)
        private set(v) { prefs.edit().putString("access", v).apply() }

    var refreshToken: String?
        get() = prefs.getString("refresh", null)
        private set(v) { prefs.edit().putString("refresh", v).apply() }

    var language: String
        get() = prefs.getString("lang", "fr") ?: "fr"
        set(v) { prefs.edit().putString("lang", v).apply() }

    var languageChosen: Boolean
        get() = prefs.getBoolean("lang_chosen", false)
        set(v) { prefs.edit().putBoolean("lang_chosen", v).apply() }

    var role: String
        get() = prefs.getString("role", "passenger") ?: "passenger"
        set(v) { prefs.edit().putString("role", v).apply() }

    var activeRequestId: String?
        get() = prefs.getString("active_request", null)
        set(v) { prefs.edit().putString("active_request", v).apply() }

    var activeRideId: String?
        get() = prefs.getString("active_ride", null)
        set(v) { prefs.edit().putString("active_ride", v).apply() }

    val isSignedIn: Boolean get() = refreshToken != null && userId != null

    val userId: String? get() = accessToken?.let { claim(it, "sub") as? String }

    fun save(access: String, refresh: String) {
        accessToken = access
        refreshToken = refresh
    }

    fun clear() {
        prefs.edit()
            .remove("access").remove("refresh")
            .remove("active_request").remove("active_ride")
            .apply()
    }

    /** Seconds since epoch at which the access token expires, or null. */
    fun accessExpiry(): Long? {
        val token = accessToken ?: return null
        return (claim(token, "exp") as? Number)?.toLong()
    }

    private fun claim(token: String, key: String): Any? = try {
        val part = token.split(".").getOrNull(1) ?: return null
        val decoded = String(Base64.decode(part, Base64.URL_SAFE or Base64.NO_PADDING or Base64.NO_WRAP))
        val obj = JSONObject(decoded)
        if (obj.has(key)) obj.get(key) else null
    } catch (_: Exception) {
        null
    }
}
