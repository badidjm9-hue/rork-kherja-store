package app.rork.h04xk59ettzrqz7c6l4wp.ui.screens

import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.DirectionsCar
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.Phone
import androidx.compose.material.icons.filled.Sms
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.rork.h04xk59ettzrqz7c6l4wp.AppState
import app.rork.h04xk59ettzrqz7c6l4wp.R
import app.rork.h04xk59ettzrqz7c6l4wp.data.CITIES
import app.rork.h04xk59ettzrqz7c6l4wp.data.jsonOf
import app.rork.h04xk59ettzrqz7c6l4wp.ui.components.ErrorBanner
import app.rork.h04xk59ettzrqz7c6l4wp.ui.components.IconCircle
import app.rork.h04xk59ettzrqz7c6l4wp.ui.components.KJButton
import app.rork.h04xk59ettzrqz7c6l4wp.ui.components.KJLogo
import app.rork.h04xk59ettzrqz7c6l4wp.ui.theme.KJ
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

@Composable
fun SplashScreen(state: AppState) {
    var visible by remember { mutableStateOf(false) }
    val a by animateFloatAsState(if (visible) 1f else 0f, tween(700), label = "splash")
    LaunchedEffect(Unit) { visible = true }
    Box(
        Modifier.fillMaxSize().background(KJ.canvasGradient),
        contentAlignment = Alignment.Center,
    ) {
        Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.alpha(a).scale(0.9f + 0.1f * a)) {
            KJLogo(110.dp)
            Spacer(Modifier.height(18.dp))
            Text(state.l("app_tagline"), color = KJ.inkSoft, fontSize = 16.sp, fontWeight = FontWeight.Medium, textAlign = TextAlign.Center)
            Spacer(Modifier.height(18.dp))
            Image(
                painter = painterResource(R.drawable.car_moto),
                contentDescription = null,
                modifier = Modifier.width(260.dp).height(180.dp),
            )
            Spacer(Modifier.height(18.dp))
            CircularProgressIndicator(color = KJ.blue, strokeWidth = 3.dp, modifier = Modifier.size(28.dp))
            Spacer(Modifier.height(12.dp))
            Text(state.l("loading"), color = KJ.muted, fontSize = 13.sp, fontWeight = FontWeight.Medium)
        }
    }
}

private enum class Step { Language, Auth, Forgot, Role, Phone, Otp }

/** Auth screens follow the app language direction (Arabic = RTL) without touching the legacy screens. */
@Composable
private fun RtlScope(state: AppState, content: @Composable () -> Unit) {
    CompositionLocalProvider(LocalLayoutDirection provides if (state.isRtl) LayoutDirection.Rtl else LayoutDirection.Ltr) { content() }
}

/**
 * Language → Auth (login / register / forgot) → SMS code.
 * The original passwordless flow (role → phone → code) stays reachable through "Se connecter avec un code SMS".
 */
@Composable
fun OnboardingFlow(state: AppState) {
    var step by remember { mutableStateOf(if (state.session.languageChosen) Step.Auth else Step.Language) }
    var phone by remember { mutableStateOf("") }
    var devCode by remember { mutableStateOf<String?>(null) }
    var otpCtx by remember { mutableStateOf(OtpContext()) }
    var otpBack by remember { mutableStateOf(Step.Auth) }

    BackHandler(enabled = step != Step.Language) {
        step = when (step) {
            Step.Otp -> otpBack
            Step.Phone -> Step.Role
            Step.Role, Step.Forgot -> Step.Auth
            else -> Step.Language
        }
    }

    AnimatedContent(step, transitionSpec = { fadeIn(tween(220)) togetherWith fadeOut(tween(160)) }, label = "onb") { s ->
        Box(Modifier.fillMaxSize().background(KJ.canvasGradient)) {
            CornerBlobs()
            Column(Modifier.fillMaxSize().safeDrawingPadding().imePadding()) {
                when (s) {
                    Step.Language -> LanguageStep(state) { step = Step.Auth }
                    Step.Auth -> RtlScope(state) {
                        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState())) {
                            AuthStep(
                                state, startOnRegister = false,
                                onForgot = { step = Step.Forgot },
                                onSmsLogin = { step = Step.Role },
                                onOtp = { p, ctx, dev ->
                                    phone = p; otpCtx = ctx; devCode = dev; otpBack = Step.Auth; step = Step.Otp
                                },
                            )
                        }
                    }
                    Step.Forgot -> RtlScope(state) {
                        BackButton { step = Step.Auth }
                        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState())) {
                            ForgotStep(state) { p, ctx, dev ->
                                phone = p; otpCtx = ctx; devCode = dev; otpBack = Step.Forgot; step = Step.Otp
                            }
                        }
                    }
                    Step.Role -> RoleStep(state, onBack = { step = Step.Auth }) { step = Step.Phone }
                    Step.Phone -> PhoneStep(state, phone, { phone = it }, onBack = { step = Step.Role }) { code ->
                        devCode = code
                        otpCtx = OtpContext()
                        otpBack = Step.Phone
                        step = Step.Otp
                    }
                    Step.Otp -> OtpStep(state, phone, devCode, otpCtx, { devCode = it }, onBack = { step = otpBack })
                }
            }
        }
    }
}

@Composable
private fun CornerBlobs() {
    Box(Modifier.fillMaxWidth().height(220.dp)) {
        Box(Modifier.size(180.dp).padding(start = 0.dp).alpha(0.10f).clip(CircleShape).background(KJ.blue).align(Alignment.TopStart))
        Box(Modifier.size(120.dp).alpha(0.08f).clip(CircleShape).background(KJ.burgundy).align(Alignment.TopEnd))
    }
}

@Composable
private fun BackButton(onClick: () -> Unit) {
    Box(Modifier.padding(16.dp)) {
        IconCircle(Icons.AutoMirrored.Filled.ArrowBack, tint = KJ.ink, bg = Color.White, size = 44.dp, onClick = onClick)
    }
}

@Composable
private fun LanguageStep(state: AppState, onNext: () -> Unit) {
    Column(Modifier.fillMaxSize().padding(horizontal = 28.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        Spacer(Modifier.height(70.dp))
        KJLogo(96.dp)
        Spacer(Modifier.height(28.dp))
        Text(state.l("choose_language"), fontSize = 24.sp, fontWeight = FontWeight.ExtraBold, color = KJ.ink, textAlign = TextAlign.Center)
        Spacer(Modifier.height(28.dp))
        LanguageCard("العربية", "Arabic", "ع", state.language == "ar") { state.setLanguage("ar") }
        Spacer(Modifier.height(14.dp))
        LanguageCard("Français", "French", "Fr", state.language == "fr") { state.setLanguage("fr") }
        Spacer(Modifier.weight(1f))
        KJButton(state.l("continue")) {
            state.setLanguage(state.language)
            onNext()
        }
        Spacer(Modifier.height(28.dp))
    }
}

@Composable
private fun LanguageCard(title: String, sub: String, badge: String, selected: Boolean, onClick: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(20.dp)).background(Color.White)
            .border(2.dp, if (selected) KJ.blue else KJ.softBlueMid, RoundedCornerShape(20.dp))
            .clickable(onClick = onClick).padding(18.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(Modifier.size(46.dp).clip(CircleShape).background(if (selected) KJ.blue else KJ.softBlue), contentAlignment = Alignment.Center) {
            Text(badge, color = if (selected) Color.White else KJ.blue, fontWeight = FontWeight.Black, fontSize = 17.sp)
        }
        Spacer(Modifier.width(14.dp))
        Column(Modifier.weight(1f)) {
            Text(title, fontWeight = FontWeight.Bold, fontSize = 18.sp, color = KJ.ink)
            Text(sub, color = KJ.muted, fontSize = 13.sp)
        }
        if (selected) Icon(Icons.Filled.CheckCircle, null, tint = KJ.blue)
    }
}

@Composable
private fun RoleStep(state: AppState, onBack: () -> Unit, onNext: () -> Unit) {
    BackButton(onBack)
    Column(Modifier.fillMaxSize().padding(horizontal = 28.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        KJLogo(72.dp)
        Spacer(Modifier.height(18.dp))
        Text(state.l("join_community"), fontSize = 24.sp, fontWeight = FontWeight.ExtraBold, color = KJ.ink, textAlign = TextAlign.Center)
        Spacer(Modifier.height(6.dp))
        Text(state.l("what_role"), color = KJ.muted, fontSize = 15.sp)
        Spacer(Modifier.height(26.dp))
        Row(horizontalArrangement = Arrangement.spacedBy(14.dp)) {
            RoleCard(Modifier.weight(1f), state.l("passenger"), Icons.Filled.Person, R.drawable.car_moto, state.role == "passenger") { state.setRole("passenger") }
            RoleCard(Modifier.weight(1f), state.l("driver"), Icons.Filled.DirectionsCar, R.drawable.car_hero, state.role == "driver") { state.setRole("driver") }
        }
        Spacer(Modifier.weight(1f))
        KJButton(state.l("continue"), onClick = onNext)
        Spacer(Modifier.height(28.dp))
    }
}

@Composable
private fun RoleCard(modifier: Modifier, title: String, icon: ImageVector, image: Int, selected: Boolean, onClick: () -> Unit) {
    val scale by animateFloatAsState(if (selected) 1f else 0.96f, label = "role")
    Column(
        modifier.scale(scale).clip(RoundedCornerShape(24.dp))
            .background(if (selected) Brush.verticalGradient(listOf(KJ.blueLight, KJ.blueDeep)) else Brush.verticalGradient(listOf(Color.White, Color.White)))
            .border(2.dp, if (selected) KJ.blue else KJ.softBlueMid, RoundedCornerShape(24.dp))
            .clickable(onClick = onClick).padding(16.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Icon(icon, null, tint = if (selected) Color.White else KJ.blue, modifier = Modifier.size(30.dp))
        Spacer(Modifier.height(10.dp))
        Image(painterResource(image), null, modifier = Modifier.fillMaxWidth().height(70.dp))
        Spacer(Modifier.height(10.dp))
        Text(title, fontWeight = FontWeight.ExtraBold, fontSize = 17.sp, color = if (selected) Color.White else KJ.ink)
    }
}

internal fun normalizePhone(raw: String): String? {
    val digits = raw.filter { it.isDigit() }
    if (digits.length != 10 || !digits.startsWith("0")) return null
    if (digits[1] !in listOf('5', '6', '7')) return null
    return digits
}

@Composable
private fun PhoneStep(state: AppState, phone: String, onPhone: (String) -> Unit, onBack: () -> Unit, onSent: (String?) -> Unit) {
    val scope = rememberCoroutineScope()
    var loading by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    val normalized = normalizePhone(phone)
    BackButton(onBack)
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 28.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        KJLogo(72.dp)
        Spacer(Modifier.height(20.dp))
        Text(state.l("your_number"), fontSize = 26.sp, fontWeight = FontWeight.ExtraBold, color = KJ.ink)
        Spacer(Modifier.height(6.dp))
        Text(state.l("sms_hint"), color = KJ.muted, fontSize = 15.sp, textAlign = TextAlign.Center)
        Spacer(Modifier.height(28.dp))
        Row(
            Modifier.fillMaxWidth().clip(RoundedCornerShape(18.dp)).background(Color.White)
                .border(1.5.dp, KJ.softBlueMid, RoundedCornerShape(18.dp)).padding(horizontal = 16.dp, vertical = 6.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text("🇩🇿 +213", fontWeight = FontWeight.Bold, color = KJ.ink)
            Spacer(Modifier.width(10.dp))
            Box(Modifier.width(1.dp).height(28.dp).background(KJ.softBlueMid))
            Spacer(Modifier.width(10.dp))
            OutlinedTextField(
                value = phone,
                onValueChange = { v -> onPhone(v.filter { it.isDigit() || it == ' ' }.take(14)); error = null },
                placeholder = { Text(state.l("phone_placeholder"), color = KJ.muted) },
                singleLine = true,
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Phone),
                colors = OutlinedTextFieldDefaults.colors(
                    focusedBorderColor = Color.Transparent, unfocusedBorderColor = Color.Transparent,
                ),
                textStyle = androidx.compose.ui.text.TextStyle(fontSize = 19.sp, fontWeight = FontWeight.Bold, color = KJ.ink),
                leadingIcon = { Icon(Icons.Filled.Phone, null, tint = KJ.blue) },
                modifier = Modifier.weight(1f),
            )
        }
        if (error != null) {
            Spacer(Modifier.height(12.dp))
            ErrorBanner(error!!)
        }
        Spacer(Modifier.height(28.dp))
        KJButton(state.l("send_code"), enabled = normalized != null, loading = loading, icon = Icons.Filled.Sms) {
            val p = normalized ?: run { error = state.l("invalid_phone"); return@KJButton }
            loading = true
            error = null
            scope.launch {
                try {
                    val res = state.api.requestOtp(p)
                    if (res.ok) onSent(res.devCode) else error = res.error ?: state.l("error_generic")
                } catch (e: Exception) {
                    error = state.l(AuthRules.exceptionKey(e))
                }
                loading = false
            }
        }
        Spacer(Modifier.height(28.dp))
    }
}

@Composable
private fun OtpStep(state: AppState, phone: String, devCode: String?, ctx: OtpContext, onDevCode: (String?) -> Unit, onBack: () -> Unit) {
    val scope = rememberCoroutineScope()
    val normalized = normalizePhone(phone) ?: phone
    var code by remember { mutableStateOf("") }
    var loading by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var countdown by remember { mutableIntStateOf(45) }
    val focus = remember { FocusRequester() }

    LaunchedEffect(countdown) {
        if (countdown > 0) {
            delay(1000)
            countdown -= 1
        }
    }
    LaunchedEffect(Unit) { runCatching { focus.requestFocus() } }

    fun verify() {
        if (code.length != 6 || loading) return
        loading = true
        error = null
        scope.launch {
            try {
                val res = state.api.verifyOtp(normalized, code, ctx.purpose, ctx.password, ctx.email)
                if (res.ok && res.accessToken != null && res.refreshToken != null) {
                    state.onSignedIn(res.accessToken, res.refreshToken)
                } else {
                    // Legacy passwordless flow keeps its original message; new flows show the specific reason.
                    error = state.l(if (ctx.purpose == null) "wrong_code" else AuthRules.errorKey(res.error))
                    code = ""
                }
            } catch (e: Exception) {
                error = state.l(AuthRules.exceptionKey(e))
            }
            loading = false
        }
    }

    BackButton(onBack)
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 28.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        IconCircle(Icons.Filled.Sms, size = 72.dp)
        Spacer(Modifier.height(18.dp))
        Text(state.l("verify_title"), fontSize = 26.sp, fontWeight = FontWeight.ExtraBold, color = KJ.ink)
        Spacer(Modifier.height(6.dp))
        Text("${state.l("verify_hint")} $normalized", color = KJ.muted, fontSize = 15.sp, textAlign = TextAlign.Center)

        if (devCode != null) {
            Spacer(Modifier.height(16.dp))
            Column(
                Modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp)).background(KJ.warningBg).padding(14.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                Text(state.l("dev_code_banner"), color = KJ.inkSoft, fontSize = 13.sp, textAlign = TextAlign.Center)
                Spacer(Modifier.height(4.dp))
                Text(devCode, fontWeight = FontWeight.Black, fontSize = 24.sp, color = KJ.ink, letterSpacing = 6.sp)
            }
        }

        Spacer(Modifier.height(24.dp))
        Box {
            BasicTextField(
                value = code,
                onValueChange = { v ->
                    code = v.filter { it.isDigit() }.take(6)
                    error = null
                    if (code.length == 6) verify()
                },
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.NumberPassword),
                modifier = Modifier.focusRequester(focus).alpha(0.01f).fillMaxWidth().height(60.dp),
            )
            Row(Modifier.fillMaxWidth().clickable { runCatching { focus.requestFocus() } }, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                repeat(6) { i ->
                    val ch = code.getOrNull(i)?.toString() ?: ""
                    val active = i == code.length
                    Box(
                        Modifier.weight(1f).height(60.dp).clip(RoundedCornerShape(14.dp)).background(Color.White)
                            .border(2.dp, if (active) KJ.blue else KJ.softBlueMid, RoundedCornerShape(14.dp)),
                        contentAlignment = Alignment.Center,
                    ) {
                        Text(ch, fontSize = 24.sp, fontWeight = FontWeight.Black, color = KJ.ink)
                    }
                }
            }
        }
        if (error != null) {
            Spacer(Modifier.height(12.dp))
            ErrorBanner(error!!)
        }
        Spacer(Modifier.height(24.dp))
        KJButton(state.l("verify_title"), enabled = code.length == 6, loading = loading) { verify() }
        Spacer(Modifier.height(16.dp))
        Text(
            if (countdown > 0) "${state.l("resend_in")} ${countdown}s" else state.l("resend"),
            color = if (countdown > 0) KJ.muted else KJ.blue,
            fontWeight = FontWeight.Bold,
            modifier = Modifier.clip(RoundedCornerShape(10.dp)).clickable(enabled = countdown == 0) {
                countdown = 45
                scope.launch {
                    runCatching { state.api.requestOtp(normalized) }.onSuccess { onDevCode(it.devCode) }
                }
            }.padding(8.dp),
        )
        Text(
            state.l("change_number"), color = KJ.inkSoft, fontSize = 14.sp,
            modifier = Modifier.clip(RoundedCornerShape(10.dp)).clickable(onClick = onBack).padding(8.dp),
        )
        Spacer(Modifier.height(28.dp))
    }
}

@Composable
fun CompleteProfileScreen(state: AppState) {
    val scope = rememberCoroutineScope()
    var name by remember { mutableStateOf(state.profile?.name?.takeIf { it.isNotBlank() } ?: state.pendingName ?: "") }
    var city by remember { mutableStateOf(state.profile?.city?.takeIf { it in CITIES } ?: "Alger") }
    var saving by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }

    Box(Modifier.fillMaxSize().background(KJ.canvasGradient)) {
        Column(
            Modifier.fillMaxSize().safeDrawingPadding().imePadding().verticalScroll(rememberScrollState()).padding(horizontal = 28.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Spacer(Modifier.height(40.dp))
            KJLogo(72.dp)
            Spacer(Modifier.height(18.dp))
            Text(state.l("join_community"), fontSize = 24.sp, fontWeight = FontWeight.ExtraBold, color = KJ.ink, textAlign = TextAlign.Center)
            Spacer(Modifier.height(28.dp))
            Text(state.l("name"), modifier = Modifier.fillMaxWidth(), fontWeight = FontWeight.Bold, color = KJ.inkSoft)
            Spacer(Modifier.height(6.dp))
            OutlinedTextField(
                value = name, onValueChange = { name = it.take(60) },
                placeholder = { Text(state.l("your_name")) },
                singleLine = true,
                shape = RoundedCornerShape(16.dp),
                colors = OutlinedTextFieldDefaults.colors(unfocusedContainerColor = Color.White, focusedContainerColor = Color.White, unfocusedBorderColor = KJ.softBlueMid),
                modifier = Modifier.fillMaxWidth(),
            )
            Spacer(Modifier.height(20.dp))
            Text(state.l("city"), modifier = Modifier.fillMaxWidth(), fontWeight = FontWeight.Bold, color = KJ.inkSoft)
            Spacer(Modifier.height(8.dp))
            CityGrid(city) { city = it }
            if (error != null) {
                Spacer(Modifier.height(12.dp))
                ErrorBanner(error!!)
            }
            Spacer(Modifier.height(28.dp))
            KJButton(state.l("continue"), enabled = name.trim().length >= 2, loading = saving) {
                val id = state.userId ?: return@KJButton
                saving = true
                error = null
                scope.launch {
                    try {
                        state.api.updateProfile(id, jsonOf(
                            "name" to name.trim(), "city" to city, "language" to state.language, "role" to state.role,
                        ))
                        state.refreshProfile()
                    } catch (e: Exception) {
                        error = state.serverError(e)
                    }
                    saving = false
                }
            }
            Spacer(Modifier.height(16.dp))
            Text(state.l("logout"), color = KJ.muted, modifier = Modifier.clip(RoundedCornerShape(10.dp)).clickable { state.signOut() }.padding(8.dp))
            Spacer(Modifier.height(28.dp))
        }
    }
}

@Composable
fun CityGrid(selected: String, onSelect: (String) -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        CITIES.chunked(2).forEach { row ->
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                row.forEach { c ->
                    val sel = c == selected
                    Box(
                        Modifier.weight(1f).height(46.dp).clip(RoundedCornerShape(14.dp))
                            .background(if (sel) KJ.blue else Color.White)
                            .border(1.5.dp, if (sel) KJ.blue else KJ.softBlueMid, RoundedCornerShape(14.dp))
                            .clickable { onSelect(c) },
                        contentAlignment = Alignment.Center,
                    ) {
                        Text(c, color = if (sel) Color.White else KJ.ink, fontWeight = FontWeight.SemiBold)
                    }
                }
                if (row.size == 1) Spacer(Modifier.weight(1f))
            }
        }
    }
}
