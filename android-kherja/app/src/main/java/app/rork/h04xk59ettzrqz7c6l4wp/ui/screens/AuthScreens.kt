package app.rork.h04xk59ettzrqz7c6l4wp.ui.screens

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowForward
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Email
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.Phone
import androidx.compose.material.icons.filled.Visibility
import androidx.compose.material.icons.filled.VisibilityOff
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextDirection
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.rork.h04xk59ettzrqz7c6l4wp.AppState
import app.rork.h04xk59ettzrqz7c6l4wp.R
import app.rork.h04xk59ettzrqz7c6l4wp.i18n.L10n
import app.rork.h04xk59ettzrqz7c6l4wp.ui.components.ErrorBanner
import app.rork.h04xk59ettzrqz7c6l4wp.ui.components.KJLogo
import app.rork.h04xk59ettzrqz7c6l4wp.ui.theme.KJ
import kotlinx.coroutines.launch

/** What the SMS-code step must send along with the code (all null = the original passwordless OTP login). */
data class OtpContext(val purpose: String? = null, val password: String? = null, val email: String? = null)

/** Client-side mirrors of the server rules (the server is authoritative and re-validates everything). */
internal object AuthRules {
    private val letter = Regex("[A-Za-z\\u0600-\\u06FF]")
    private val emailRe = Regex("^[^\\s@]+@[^\\s@]+\\.[^\\s@]+$")

    fun passwordValid(pw: String): Boolean =
        pw.length in 8..72 && letter.containsMatchIn(pw) && pw.any { it in '0'..'9' }

    /** Empty is valid: the contact e-mail is optional. */
    fun emailValid(e: String): Boolean = e.isBlank() || (e.trim().length <= 254 && emailRe.matches(e.trim()))

    /** Maps the French messages returned by auth-otp to localized string keys. */
    fun errorKey(message: String?): String {
        val m = (message ?: "").lowercase()
        return when {
            "mot de passe" in m && "incorrect" in m -> "err_login_failed"
            "tentatives" in m -> "err_too_many"
            "existe déjà" in m -> "err_account_exists"
            "aucun compte" in m -> "err_no_account"
            "sms indisponible" in m -> "err_sms_unavailable"
            "code" in m -> "wrong_code"
            else -> "error_generic"
        }
    }
}

/** (primary, secondary) label pair: the app language first, the other language below, as in the reference design. */
private fun bi(state: AppState, key: String): Pair<String, String> {
    val ar = L10n.string(key, "ar")
    val fr = L10n.string(key, "fr")
    return if (state.language == "ar") ar to fr else fr to ar
}

/** Frosted-glass surface: translucent white, hairline highlight border, soft blue shadow. */
private fun Modifier.glass(shape: Shape = RoundedCornerShape(22.dp)): Modifier =
    this.shadow(10.dp, shape, ambientColor = KJ.blue.copy(alpha = 0.10f), spotColor = KJ.blue.copy(alpha = 0.14f))
        .clip(shape)
        .background(Color.White.copy(alpha = 0.80f))
        .border(1.dp, Color.White.copy(alpha = 0.95f), shape)

@Composable
private fun GlassField(
    state: AppState,
    labelKey: String,
    icon: ImageVector,
    value: String,
    onValue: (String) -> Unit,
    keyboard: KeyboardType = KeyboardType.Text,
    secret: Boolean = false,
    numeric: Boolean = false,
    trailing: (@Composable () -> Unit)? = null,
) {
    val (primary, secondary) = bi(state, labelKey)
    var shown by remember { mutableStateOf(false) }
    Row(
        Modifier.fillMaxWidth().glass().padding(horizontal = 18.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(icon, null, tint = KJ.ink, modifier = Modifier.size(24.dp))
        Spacer(Modifier.width(14.dp))
        Column(Modifier.weight(1f)) {
            Text(primary, fontWeight = FontWeight.ExtraBold, fontSize = 14.sp, color = KJ.ink)
            Box(Modifier.fillMaxWidth().padding(top = 2.dp)) {
                if (value.isEmpty()) Text(secondary, color = KJ.muted, fontSize = 15.sp)
                BasicTextField(
                    value = value,
                    onValueChange = onValue,
                    singleLine = true,
                    textStyle = TextStyle(
                        fontSize = 16.sp, fontWeight = FontWeight.SemiBold, color = KJ.ink,
                        textDirection = if (numeric || secret) TextDirection.Ltr else TextDirection.Content,
                    ),
                    keyboardOptions = KeyboardOptions(keyboardType = if (secret) KeyboardType.Password else keyboard),
                    visualTransformation = if (secret && !shown) PasswordVisualTransformation() else VisualTransformation.None,
                    cursorBrush = SolidColor(KJ.blue),
                    modifier = Modifier.fillMaxWidth(),
                )
            }
        }
        if (secret) {
            Icon(
                if (shown) Icons.Filled.Visibility else Icons.Filled.VisibilityOff,
                contentDescription = null,
                tint = KJ.ink,
                modifier = Modifier.size(24.dp).clip(CircleShape).clickable { shown = !shown },
            )
        } else if (trailing != null) {
            trailing()
        }
    }
}

@Composable
private fun CountryChip() {
    Row(
        Modifier.clip(RoundedCornerShape(18.dp)).background(KJ.softBlue.copy(alpha = 0.7f)).padding(horizontal = 12.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text("🇩🇿", fontSize = 18.sp)
        Spacer(Modifier.width(6.dp))
        Text("+213", fontWeight = FontWeight.Bold, color = KJ.ink, fontSize = 15.sp)
    }
}

@Composable
private fun BiButton(
    state: AppState,
    labelKey: String,
    loading: Boolean,
    brush: Brush = KJ.buttonGradient,
    onClick: () -> Unit,
) {
    val (primary, secondary) = bi(state, labelKey)
    val shape = RoundedCornerShape(32.dp)
    Row(
        Modifier.fillMaxWidth().height(64.dp)
            .shadow(14.dp, shape, ambientColor = KJ.blue.copy(alpha = 0.25f), spotColor = KJ.blue.copy(alpha = 0.35f))
            .clip(shape).background(brush)
            .alpha(if (loading) 0.85f else 1f)
            .clickable(enabled = !loading, onClick = onClick)
            .padding(horizontal = 24.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Spacer(Modifier.width(24.dp))
        Column(Modifier.weight(1f), horizontalAlignment = Alignment.CenterHorizontally) {
            Text(primary, color = Color.White, fontWeight = FontWeight.ExtraBold, fontSize = 20.sp)
            Text(secondary, color = Color.White.copy(alpha = 0.92f), fontSize = 14.sp, fontWeight = FontWeight.Medium)
        }
        if (loading) {
            CircularProgressIndicator(color = Color.White, strokeWidth = 2.5.dp, modifier = Modifier.size(24.dp))
        } else {
            Icon(Icons.AutoMirrored.Filled.ArrowForward, null, tint = Color.White, modifier = Modifier.size(24.dp))
        }
    }
}

@Composable
private fun AuthTabs(state: AppState, register: Boolean, onSelect: (Boolean) -> Unit) {
    Row(Modifier.fillMaxWidth().glass(RoundedCornerShape(30.dp)).padding(4.dp)) {
        listOf(false to "auth_login_tab", true to "auth_register_tab").forEach { (isRegister, key) ->
            val active = register == isRegister
            val (primary, secondary) = bi(state, key)
            Row(
                Modifier.weight(1f).height(56.dp).clip(RoundedCornerShape(26.dp))
                    .background(if (active) KJ.burgundyGradient else SolidColor(Color.Transparent))
                    .clickable { onSelect(isRegister) },
                horizontalArrangement = Arrangement.Center,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                if (active) {
                    Icon(Icons.Filled.Person, null, tint = Color.White, modifier = Modifier.size(24.dp))
                    Spacer(Modifier.width(10.dp))
                }
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Text(primary, fontWeight = FontWeight.ExtraBold, fontSize = 15.sp, color = if (active) Color.White else KJ.ink)
                    Text(secondary, fontSize = 13.sp, color = if (active) Color.White.copy(alpha = 0.92f) else KJ.inkSoft)
                }
            }
        }
    }
}

@Composable
private fun SocialButton(label: String, icon: Int, modifier: Modifier, onClick: () -> Unit) {
    Row(
        modifier.height(54.dp).glass(RoundedCornerShape(27.dp)).clickable(onClick = onClick).padding(horizontal = 10.dp),
        horizontalArrangement = Arrangement.Center,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Image(painterResource(icon), null, modifier = Modifier.size(24.dp))
        Spacer(Modifier.width(8.dp))
        Text(label, fontWeight = FontWeight.SemiBold, fontSize = 13.sp, color = KJ.ink, maxLines = 1)
    }
}

/** Google and Apple open Supabase OAuth (PKCE) in the system browser; the session comes back via kherja://auth-callback. */
@Composable
private fun SocialRow(state: AppState, onError: (String?) -> Unit) {
    val uriHandler = LocalUriHandler.current
    fun start(provider: String) {
        onError(null)
        state.oauthError = null
        runCatching { uriHandler.openUri(state.api.oauthAuthorizeUrl(provider)) }
            .onFailure { onError(state.l("social_failed")) }
    }
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        SocialButton(bi(state, "auth_google").first, R.drawable.ic_google, Modifier.weight(1f)) { start("google") }
        SocialButton(bi(state, "auth_apple").first, R.drawable.ic_apple, Modifier.weight(1f)) { start("apple") }
    }
}

@Composable
private fun OrDivider(state: AppState) {
    val (primary, secondary) = bi(state, "auth_or")
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.weight(1f).height(1.dp).background(KJ.softBlueMid))
        Column(Modifier.padding(horizontal = 14.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            Text(primary, color = KJ.inkSoft, fontWeight = FontWeight.Bold, fontSize = 14.sp)
            if (secondary != primary) Text(secondary, color = KJ.inkSoft, fontSize = 12.sp)
        }
        Box(Modifier.weight(1f).height(1.dp).background(KJ.softBlueMid))
    }
}

@Composable
private fun CheckBox(checked: Boolean, onToggle: () -> Unit) {
    Box(
        Modifier.size(30.dp).clip(RoundedCornerShape(9.dp))
            .background(if (checked) KJ.blue else Color.White)
            .border(2.dp, KJ.blue, RoundedCornerShape(9.dp))
            .clickable(onClick = onToggle),
        contentAlignment = Alignment.Center,
    ) {
        if (checked) Icon(Icons.Filled.Check, null, tint = Color.White, modifier = Modifier.size(20.dp))
    }
}

@Composable
private fun RoleChoice(state: AppState, labelKey: String, image: Int, selected: Boolean, modifier: Modifier, onClick: () -> Unit) {
    val (primary, secondary) = bi(state, labelKey)
    val shape = RoundedCornerShape(22.dp)
    Row(
        modifier.height(76.dp).glass(shape)
            .border(if (selected) 2.dp else 0.dp, if (selected) KJ.blue else Color.Transparent, shape)
            .clickable(onClick = onClick).padding(horizontal = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(
            Modifier.size(22.dp).clip(CircleShape).border(2.dp, if (selected) KJ.blue else KJ.muted, CircleShape),
            contentAlignment = Alignment.Center,
        ) { if (selected) Box(Modifier.size(11.dp).clip(CircleShape).background(KJ.blue)) }
        Spacer(Modifier.width(8.dp))
        Column(Modifier.weight(1f)) {
            Text(primary, fontWeight = FontWeight.ExtraBold, fontSize = 15.sp, color = KJ.ink, maxLines = 1)
            Text(secondary, fontSize = 13.sp, color = KJ.inkSoft, maxLines = 1)
        }
        Image(painterResource(image), null, modifier = Modifier.width(54.dp).height(40.dp))
    }
}

/** Connexion / Créer un compte. */
@Composable
fun AuthStep(
    state: AppState,
    startOnRegister: Boolean,
    onForgot: () -> Unit,
    onSmsLogin: () -> Unit,
    onOtp: (phone: String, ctx: OtpContext, devCode: String?) -> Unit,
) {
    val scope = rememberCoroutineScope()
    var register by remember { mutableStateOf(startOnRegister) }
    var loading by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }

    var phone by remember { mutableStateOf("") }
    var password by remember { mutableStateOf("") }
    var rememberMe by remember { mutableStateOf(state.session.rememberMe) }

    var name by remember { mutableStateOf("") }
    var email by remember { mutableStateOf("") }
    var confirm by remember { mutableStateOf("") }
    var terms by remember { mutableStateOf(false) }
    var role by remember { mutableStateOf(state.role) }

    val shownError = error ?: state.oauthError

    fun login() {
        val p = normalizePhone(phone) ?: run { error = state.l("invalid_phone"); return }
        if (password.isEmpty()) { error = state.l("err_enter_password"); return }
        loading = true
        error = null
        scope.launch {
            try {
                val res = state.api.loginWithPassword(p, password)
                if (res.ok && res.accessToken != null && res.refreshToken != null) {
                    state.onSignedIn(res.accessToken, res.refreshToken, rememberMe)
                } else {
                    error = state.l(AuthRules.errorKey(res.error))
                }
            } catch (e: Exception) {
                error = state.l("error_generic")
            }
            loading = false
        }
    }

    fun signUp() {
        if (name.trim().length < 2) { error = state.l("err_name"); return }
        val p = normalizePhone(phone) ?: run { error = state.l("invalid_phone"); return }
        if (!AuthRules.emailValid(email)) { error = state.l("err_email"); return }
        if (!AuthRules.passwordValid(password)) { error = state.l("err_password_rules"); return }
        if (password != confirm) { error = state.l("err_password_mismatch"); return }
        if (!terms) { error = state.l("err_terms"); return }
        loading = true
        error = null
        scope.launch {
            try {
                val res = state.api.requestOtp(p)
                if (res.ok) {
                    state.pendingName = name.trim()
                    state.setRole(role)
                    onOtp(p, OtpContext("register", password, email.trim()), res.devCode)
                } else {
                    error = state.l(AuthRules.errorKey(res.error))
                }
            } catch (e: Exception) {
                error = state.l("error_generic")
            }
            loading = false
        }
    }

    Column(
        Modifier.fillMaxWidth().padding(horizontal = 22.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Spacer(Modifier.height(24.dp))
        KJLogo(if (register) 72.dp else 88.dp)
        if (register) {
            val (t1, t2) = bi(state, "auth_register_title")
            Spacer(Modifier.height(10.dp))
            Text(t1, fontSize = 26.sp, fontWeight = FontWeight.ExtraBold, color = KJ.ink, textAlign = TextAlign.Center)
            Text(t2, fontSize = 18.sp, color = KJ.inkSoft, textAlign = TextAlign.Center)
            Spacer(Modifier.height(4.dp))
            Text(bi(state, "auth_join").first, fontSize = 14.sp, color = KJ.muted, textAlign = TextAlign.Center)
        } else {
            Spacer(Modifier.height(6.dp))
            Text(L10n.string("app_tagline_ar", "ar"), fontSize = 17.sp, fontWeight = FontWeight.ExtraBold, color = KJ.ink, textAlign = TextAlign.Center)
            Text(L10n.string("app_tagline", "fr"), fontSize = 14.sp, color = KJ.inkSoft, textAlign = TextAlign.Center)
            Image(
                painterResource(R.drawable.car_moto), null,
                modifier = Modifier.fillMaxWidth().height(150.dp).padding(top = 6.dp),
            )
        }
        Spacer(Modifier.height(14.dp))
        AuthTabs(state, register) { register = it; error = null; state.oauthError = null }
        Spacer(Modifier.height(16.dp))

        if (register) {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                RoleChoice(state, "passenger", R.drawable.car_hero, role == "passenger", Modifier.weight(1f)) { role = "passenger" }
                RoleChoice(state, "driver", R.drawable.moto_art, role == "driver", Modifier.weight(1f)) { role = "driver" }
            }
            Spacer(Modifier.height(12.dp))
            GlassField(state, "auth_name", Icons.Filled.Person, name, { name = it.take(60); error = null })
            Spacer(Modifier.height(12.dp))
        }

        GlassField(
            state, "auth_phone", Icons.Filled.Phone, phone,
            { v -> phone = v.filter { it.isDigit() || it == ' ' }.take(14); error = null },
            keyboard = KeyboardType.Phone, numeric = true, trailing = { CountryChip() },
        )
        Spacer(Modifier.height(12.dp))

        if (register) {
            GlassField(state, "auth_email", Icons.Filled.Email, email, { email = it.take(254); error = null }, keyboard = KeyboardType.Email, numeric = true)
            Spacer(Modifier.height(12.dp))
        }

        GlassField(state, "auth_password", Icons.Filled.Lock, password, { password = it.take(72); error = null }, secret = true)

        if (register) {
            Spacer(Modifier.height(12.dp))
            GlassField(state, "auth_confirm", Icons.Filled.Lock, confirm, { confirm = it.take(72); error = null }, secret = true)
            Spacer(Modifier.height(14.dp))
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                CheckBox(terms) { terms = !terms; error = null }
                Spacer(Modifier.width(12.dp))
                Column(Modifier.weight(1f)) {
                    val (a, b) = bi(state, "auth_terms")
                    Text(a, fontSize = 13.sp, fontWeight = FontWeight.Bold, color = KJ.ink)
                    Text(b, fontSize = 11.sp, color = KJ.inkSoft)
                }
            }
        } else {
            Spacer(Modifier.height(14.dp))
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                CheckBox(rememberMe) { rememberMe = !rememberMe }
                Spacer(Modifier.width(10.dp))
                Column {
                    val (a, b) = bi(state, "auth_remember")
                    Text(a, fontSize = 14.sp, fontWeight = FontWeight.Bold, color = KJ.ink)
                    Text(b, fontSize = 12.sp, color = KJ.inkSoft)
                }
                Spacer(Modifier.weight(1f))
                Column(Modifier.clip(RoundedCornerShape(8.dp)).clickable(onClick = onForgot).padding(4.dp)) {
                    val (a, b) = bi(state, "auth_forgot")
                    Text(a, fontSize = 14.sp, fontWeight = FontWeight.Bold, color = KJ.blue)
                    Text(b, fontSize = 12.sp, color = KJ.blue)
                }
            }
        }

        if (shownError != null) {
            Spacer(Modifier.height(12.dp))
            ErrorBanner(shownError)
        }
        Spacer(Modifier.height(16.dp))
        BiButton(state, if (register) "auth_register_btn" else "auth_signin", loading || state.oauthBusy) {
            if (register) signUp() else login()
        }

        if (!register) {
            Spacer(Modifier.height(16.dp))
            OrDivider(state)
            Spacer(Modifier.height(12.dp))
            SocialRow(state) { error = it }
            Spacer(Modifier.height(10.dp))
            Text(
                bi(state, "auth_sms_login").first, color = KJ.blue, fontWeight = FontWeight.SemiBold, fontSize = 14.sp,
                modifier = Modifier.clip(RoundedCornerShape(10.dp)).clickable(onClick = onSmsLogin).padding(8.dp),
            )
        }

        Spacer(Modifier.height(10.dp))
        val (q1, _) = bi(state, if (register) "auth_have_account" else "auth_no_account")
        val (l1, _) = bi(state, if (register) "auth_signin_link" else "auth_create_link")
        Text(q1, color = KJ.inkSoft, fontSize = 14.sp)
        Text(
            l1, color = KJ.burgundy, fontWeight = FontWeight.ExtraBold, fontSize = 16.sp,
            modifier = Modifier.clip(RoundedCornerShape(10.dp)).clickable { register = !register; error = null; state.oauthError = null }.padding(8.dp),
        )
        Spacer(Modifier.height(28.dp))
    }
}

/** Password reset: phone + new password, confirmed with an SMS code (purpose = "reset"). */
@Composable
fun ForgotStep(state: AppState, onOtp: (phone: String, ctx: OtpContext, devCode: String?) -> Unit) {
    val scope = rememberCoroutineScope()
    var phone by remember { mutableStateOf("") }
    var password by remember { mutableStateOf("") }
    var confirm by remember { mutableStateOf("") }
    var loading by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }

    fun submit() {
        val p = normalizePhone(phone) ?: run { error = state.l("invalid_phone"); return }
        if (!AuthRules.passwordValid(password)) { error = state.l("err_password_rules"); return }
        if (password != confirm) { error = state.l("err_password_mismatch"); return }
        loading = true
        error = null
        scope.launch {
            try {
                val res = state.api.requestOtp(p)
                if (res.ok) onOtp(p, OtpContext("reset", password, null), res.devCode)
                else error = state.l(AuthRules.errorKey(res.error))
            } catch (e: Exception) {
                error = state.l("error_generic")
            }
            loading = false
        }
    }

    Column(Modifier.fillMaxWidth().padding(horizontal = 22.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        Spacer(Modifier.height(8.dp))
        KJLogo(72.dp)
        Spacer(Modifier.height(14.dp))
        val (t1, t2) = bi(state, "auth_forgot_title")
        Text(t1, fontSize = 26.sp, fontWeight = FontWeight.ExtraBold, color = KJ.ink, textAlign = TextAlign.Center)
        Text(t2, fontSize = 16.sp, color = KJ.inkSoft, textAlign = TextAlign.Center)
        Spacer(Modifier.height(8.dp))
        Text(bi(state, "auth_forgot_hint").first, fontSize = 14.sp, color = KJ.muted, textAlign = TextAlign.Center)
        Spacer(Modifier.height(20.dp))
        GlassField(
            state, "auth_phone", Icons.Filled.Phone, phone,
            { v -> phone = v.filter { it.isDigit() || it == ' ' }.take(14); error = null },
            keyboard = KeyboardType.Phone, numeric = true, trailing = { CountryChip() },
        )
        Spacer(Modifier.height(12.dp))
        GlassField(state, "auth_new_password", Icons.Filled.Lock, password, { password = it.take(72); error = null }, secret = true)
        Spacer(Modifier.height(12.dp))
        GlassField(state, "auth_confirm", Icons.Filled.Lock, confirm, { confirm = it.take(72); error = null }, secret = true)
        if (error != null) {
            Spacer(Modifier.height(12.dp))
            ErrorBanner(error!!)
        }
        Spacer(Modifier.height(20.dp))
        BiButton(state, "auth_reset_btn", loading) { submit() }
        Spacer(Modifier.height(28.dp))
    }
}
