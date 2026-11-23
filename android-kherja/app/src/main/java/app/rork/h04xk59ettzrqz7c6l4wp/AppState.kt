package app.rork.h04xk59ettzrqz7c6l4wp

import android.app.Application
import android.util.Log
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import app.rork.h04xk59ettzrqz7c6l4wp.data.GeoService
import app.rork.h04xk59ettzrqz7c6l4wp.data.LocationTracker
import app.rork.h04xk59ettzrqz7c6l4wp.data.Profile
import app.rork.h04xk59ettzrqz7c6l4wp.data.SessionStore
import app.rork.h04xk59ettzrqz7c6l4wp.data.SupabaseApi
import app.rork.h04xk59ettzrqz7c6l4wp.data.jsonOf
import app.rork.h04xk59ettzrqz7c6l4wp.i18n.L10n
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/** Global app state: language, role, session, profile, active flow ids. */
class AppState(app: Application) : AndroidViewModel(app) {
    val session = SessionStore(app)
    val api = SupabaseApi(session)
    val geo = GeoService(api.http)
    val location = LocationTracker(app)

    @set:JvmName("assignLanguage")
    var language by mutableStateOf(session.language)
        private set
    @set:JvmName("assignRole")
    var role by mutableStateOf(session.role)
        private set
    var profile by mutableStateOf<Profile?>(null)
    var signedIn by mutableStateOf(session.isSignedIn)
        private set
    var bootstrapDone by mutableStateOf(false)
        private set
    var activeRequestId by mutableStateOf(session.activeRequestId)
        private set
    var activeRideId by mutableStateOf(session.activeRideId)
        private set

    val isRtl: Boolean get() = language == "ar"
    val userId: String? get() = session.userId

    init {
        api.onSessionExpired = { signedIn = false; profile = null }
        viewModelScope.launch {
            val started = System.currentTimeMillis()
            bootstrap()
            val elapsed = System.currentTimeMillis() - started
            if (elapsed < 1200) delay(1200 - elapsed)
            bootstrapDone = true
        }
    }

    fun l(key: String): String = L10n.string(key, language)

    fun serverError(e: Throwable): String {
        Log.w("KHERJA", "server error", e)
        return l(L10n.serverErrorKey(e.message))
    }

    fun setLanguage(lang: String) {
        language = lang
        session.language = lang
        session.languageChosen = true
        val id = userId ?: return
        profile = profile?.copy(language = lang)
        viewModelScope.launch { runCatching { api.updateProfile(id, jsonOf("language" to lang)) } }
    }

    fun setRole(r: String) {
        role = r
        session.role = r
    }

    fun setActiveRequest(id: String?) {
        activeRequestId = id
        session.activeRequestId = id
    }

    fun setActiveRide(id: String?) {
        activeRideId = id
        session.activeRideId = id
    }

    fun onSignedIn(access: String, refresh: String) {
        session.save(access, refresh)
        signedIn = true
        viewModelScope.launch { bootstrap() }
    }

    private suspend fun bootstrap() {
        val id = userId
        if (!session.isSignedIn || id == null) {
            signedIn = false
            return
        }
        try {
            val p = api.profile(id)
            profile = p
            if (p != null) {
                // Keep the role chosen during onboarding until the profile is completed.
                if (p.name.isNotBlank()) setRole(p.role)
                if (p.language == "ar" || p.language == "fr") {
                    language = p.language
                    session.language = p.language
                }
            }
            resumeActiveFlow(id)
        } catch (e: Exception) {
            Log.w("KHERJA", "bootstrap failed", e)
        }
    }

    /** Restores an in-flight request or ride after relaunch, from the server. */
    private suspend fun resumeActiveFlow(id: String) {
        if (role == "driver") {
            val ride = runCatching { api.activeDriverRide(id) }.getOrNull()
            setActiveRide(ride?.id)
            return
        }
        val ride = runCatching { api.activePassengerRide(id) }.getOrNull()
        if (ride != null) {
            setActiveRide(ride.id)
            setActiveRequest(null)
            return
        }
        setActiveRide(null)
        val req = runCatching { api.openPassengerRequest(id) }.getOrNull()
        setActiveRequest(req?.id)
    }

    suspend fun refreshProfile() {
        val id = userId ?: return
        runCatching { api.profile(id) }.getOrNull()?.let { profile = it }
    }

    fun signOut() {
        val id = userId
        val wasDriver = role == "driver"
        location.stop()
        viewModelScope.launch {
            if (id != null && wasDriver) {
                runCatching { api.updateProfile(id, jsonOf("is_online" to false)) }
            }
            session.clear()
            profile = null
            activeRequestId = null
            activeRideId = null
            signedIn = false
        }
    }
}
