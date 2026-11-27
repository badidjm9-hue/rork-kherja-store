package app.rork.h04xk59ettzrqz7c6l4wp

import android.app.Application
import android.util.Log
import com.google.firebase.FirebaseApp
import com.google.firebase.messaging.FirebaseMessaging
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
    // "Remember me" off: the session lasts only until the app is started again.
    val session = SessionStore(app).also { if (!it.rememberMe) { it.clear(); it.rememberMe = true } }
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

    /** Set when a Google/Apple browser sign-in comes back with an error; shown by the login screen. */
    var oauthError by mutableStateOf<String?>(null)
    /** null = unknown (not loaded, or migration 0007 not deployed); the database enforces the rule regardless. */
    var phoneVerified by mutableStateOf<Boolean?>(null)

    var oauthBusy by mutableStateOf(false)
        private set

    /** Name typed on the register form; prefilled in the profile-completion step. */
    var pendingName: String? = null

    val isRtl: Boolean get() = language == "ar"
    val userId: String? get() = session.userId

    init {
        api.onSessionExpired = { signedIn = false; profile = null; phoneVerified = null }
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

    fun onSignedIn(access: String, refresh: String, remember: Boolean = true) {
        session.rememberMe = remember
        session.save(access, refresh)
        signedIn = true
        syncPushToken()
        viewModelScope.launch { bootstrap() }
    }

    /** Register FCM only when this build has a configured Firebase app. */
    fun syncPushToken() {
        val context = getApplication<Application>()
        if (FirebaseApp.getApps(context).isEmpty()) return
        FirebaseMessaging.getInstance().token.addOnSuccessListener { token ->
            if (token.isNullOrBlank()) return@addOnSuccessListener
            session.pushToken = token
            viewModelScope.launch {
                runCatching { api.registerPushDevice(token, "android") }
                    .onFailure { Log.w("KHERJA", "push token registration failed", it) }
            }
        }
    }

    /** Handles the kherja://auth-callback deep link that ends a Google/Apple sign-in. */
    fun handleAuthCallback(uri: android.net.Uri) {
        if (uri.scheme != "kherja" || uri.host != "auth-callback") return
        val code = uri.getQueryParameter("code")
        if (code.isNullOrBlank() || uri.getQueryParameter("error") != null) {
            session.oauthVerifier = null
            oauthError = l("social_failed")
            return
        }
        oauthBusy = true
        viewModelScope.launch {
            val t = runCatching { api.completeOAuth(code) }.getOrNull()
            oauthBusy = false
            if (t?.accessToken != null && t.refreshToken != null) {
                oauthError = null
                onSignedIn(t.accessToken, t.refreshToken)
            } else {
                oauthError = l("social_failed")
            }
        }
    }

    private suspend fun bootstrap() {
        val id = userId
        if (!session.isSignedIn || id == null) {
            signedIn = false
            return
        }
        try {
            val p = api.profile(id)
            if (p?.accountStatus == "deleted") { oauthError = l("account_deleted_notice"); signOut(); return }
            profile = p
            phoneVerified = runCatching { api.phoneVerified() }.getOrNull()
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
        runCatching { api.profile(id) }.getOrNull()?.let {
            if (it.accountStatus == "deleted") { oauthError = l("account_deleted_notice"); signOut(); return }
            profile = it
        }
        phoneVerified = runCatching { api.phoneVerified() }.getOrNull()
    }

    fun signOut() {
        val id = userId
        val wasDriver = role == "driver"
        location.stop()
        viewModelScope.launch {
            session.pushToken?.let { token -> runCatching { api.unregisterPushDevice(token) } }
            if (id != null && wasDriver) {
                runCatching { api.updateProfile(id, jsonOf("is_online" to false)) }
            }
            session.clear()
            profile = null
            phoneVerified = null
            activeRequestId = null
            activeRideId = null
            signedIn = false
        }
    }
}
