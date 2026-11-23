package app.rork.h04xk59ettzrqz7c6l4wp.ui.screens

import android.Manifest
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.animateContentSize
import androidx.compose.foundation.background
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
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Logout
import androidx.compose.material.icons.automirrored.filled.Send
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Block
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.HourglassTop
import androidx.compose.material.icons.filled.Inbox
import androidx.compose.material.icons.filled.Language
import androidx.compose.material.icons.filled.Payments
import androidx.compose.material.icons.filled.PowerSettingsNew
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Remove
import androidx.compose.material.icons.filled.Route
import androidx.compose.material.icons.filled.TwoWheeler
import androidx.compose.material.icons.filled.DirectionsCar
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.rork.h04xk59ettzrqz7c6l4wp.AppState
import app.rork.h04xk59ettzrqz7c6l4wp.data.DriverOfferPreview
import app.rork.h04xk59ettzrqz7c6l4wp.data.Offer
import app.rork.h04xk59ettzrqz7c6l4wp.data.Profile
import app.rork.h04xk59ettzrqz7c6l4wp.data.Ride
import app.rork.h04xk59ettzrqz7c6l4wp.data.RideMessage
import app.rork.h04xk59ettzrqz7c6l4wp.data.RideRequest
import app.rork.h04xk59ettzrqz7c6l4wp.data.jsonOf
import app.rork.h04xk59ettzrqz7c6l4wp.ui.components.Avatar
import app.rork.h04xk59ettzrqz7c6l4wp.ui.components.EmptyState
import app.rork.h04xk59ettzrqz7c6l4wp.ui.components.ErrorBanner
import app.rork.h04xk59ettzrqz7c6l4wp.ui.components.IconCircle
import app.rork.h04xk59ettzrqz7c6l4wp.ui.components.KJButton
import app.rork.h04xk59ettzrqz7c6l4wp.ui.components.KJCard
import app.rork.h04xk59ettzrqz7c6l4wp.ui.components.KJLogo
import app.rork.h04xk59ettzrqz7c6l4wp.ui.components.KJOutlineButton
import app.rork.h04xk59ettzrqz7c6l4wp.ui.components.MapPin
import app.rork.h04xk59ettzrqz7c6l4wp.ui.components.OsmMap
import app.rork.h04xk59ettzrqz7c6l4wp.ui.components.PinKind
import app.rork.h04xk59ettzrqz7c6l4wp.ui.components.Pill
import app.rork.h04xk59ettzrqz7c6l4wp.ui.components.PulsingDots
import app.rork.h04xk59ettzrqz7c6l4wp.ui.components.RatingBadge
import app.rork.h04xk59ettzrqz7c6l4wp.ui.components.SectionTitle
import app.rork.h04xk59ettzrqz7c6l4wp.ui.components.dzd
import app.rork.h04xk59ettzrqz7c6l4wp.ui.components.parseTs
import app.rork.h04xk59ettzrqz7c6l4wp.ui.theme.KJ
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.util.Locale

// ===================== Gate: pending / rejected / suspended =====================

@Composable
fun DriverGate(state: AppState, content: @Composable () -> Unit) {
    val p = state.profile
    val blocked = when {
        p == null -> null
        p.accountStatus == "suspended" -> "suspended"
        p.driverStatus == "pending" -> "pending"
        p.driverStatus == "rejected" -> "rejected"
        else -> null
    }
    if (blocked == null) {
        content()
        return
    }
    val scope = rememberCoroutineScope()
    var checking by remember { mutableStateOf(false) }
    // Re-check periodically so approval shows up without manual action.
    LaunchedEffect(blocked) {
        while (true) {
            delay(20_000)
            state.refreshProfile()
        }
    }
    val (icon, tint, bg) = when (blocked) {
        "suspended" -> Triple(Icons.Filled.Block, KJ.danger, KJ.dangerBg)
        "rejected" -> Triple(Icons.Filled.Block, KJ.burgundy, KJ.dangerBg)
        else -> Triple(Icons.Filled.HourglassTop, KJ.warning, KJ.warningBg)
    }
    val title = when (blocked) {
        "suspended" -> state.l("account_suspended_title")
        "rejected" -> state.l("driver_rejected_title")
        else -> state.l("driver_pending_title")
    }
    val body = when (blocked) {
        "suspended" -> state.l("account_suspended_body")
        "rejected" -> state.l("driver_rejected_body")
        else -> state.l("driver_pending_body")
    }
    Box(Modifier.fillMaxSize().background(KJ.canvasGradient)) {
        Column(
            Modifier.fillMaxSize().statusBarsPadding().navigationBarsPadding().verticalScroll(rememberScrollState()).padding(24.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            KJLogo(height = 40.dp)
            Spacer(Modifier.height(48.dp))
            IconCircle(icon, tint = tint, bg = bg, size = 84.dp)
            Spacer(Modifier.height(20.dp))
            Text(title, fontSize = 24.sp, fontWeight = FontWeight.ExtraBold, color = KJ.ink, textAlign = TextAlign.Center)
            Spacer(Modifier.height(8.dp))
            Text(body, color = KJ.muted, textAlign = TextAlign.Center)
            val reason = p?.statusReason
            if (!reason.isNullOrBlank() && blocked != "pending") {
                Spacer(Modifier.height(16.dp))
                KJCard(Modifier.fillMaxWidth()) {
                    Text(state.l("reason"), color = KJ.muted, fontSize = 13.sp)
                    Spacer(Modifier.height(4.dp))
                    Text(reason, color = KJ.ink, fontWeight = FontWeight.SemiBold)
                }
            }
            Spacer(Modifier.height(28.dp))
            KJButton(state.l("check_status"), loading = checking, icon = Icons.Filled.Refresh) {
                checking = true
                scope.launch {
                    state.refreshProfile()
                    delay(400)
                    checking = false
                }
            }
            Spacer(Modifier.height(12.dp))
            KJOutlineButton(
                if (state.language == "ar") "Français" else "العربية",
                icon = Icons.Filled.Language,
            ) { state.setLanguage(if (state.language == "ar") "fr" else "ar") }
            Spacer(Modifier.height(12.dp))
            KJOutlineButton(state.l("logout"), color = KJ.danger, icon = Icons.AutoMirrored.Filled.Logout) { state.signOut() }
        }
    }
}

// ===================== Driver home: online toggle + request feed =====================

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DriverHomeScreen(state: AppState) {
    val rideId = state.activeRideId
    if (rideId != null) {
        DriverActiveRide(state, rideId)
        return
    }
    val scope = rememberCoroutineScope()
    val uid = state.userId
    val profile = state.profile
    val online = profile?.isOnline == true
    var toggling by remember { mutableStateOf(false) }
    var requests by remember { mutableStateOf<List<RideRequest>>(emptyList()) }
    var myOffers by remember { mutableStateOf<List<Offer>>(emptyList()) }
    var feedLoaded by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var selected by remember { mutableStateOf<RideRequest?>(null) }
    val loc by state.location.location.collectAsState()
    var hasPermission by remember { mutableStateOf(state.location.hasPermission()) }

    fun goOnline(value: Boolean) {
        val id = uid ?: return
        toggling = true
        error = null
        scope.launch {
            try {
                val l = state.location.location.value
                val fields = if (value && l != null) {
                    jsonOf("is_online" to true, "current_lat" to l.latitude, "current_lng" to l.longitude)
                } else {
                    jsonOf("is_online" to value)
                }
                state.api.updateProfile(id, fields)
                state.refreshProfile()
                if (value && state.profile?.isOnline != true) error = state.l("err_not_approved")
            } catch (e: Exception) {
                error = state.serverError(e)
            }
            toggling = false
        }
    }

    val permLauncher = rememberLauncherForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) { res ->
        hasPermission = res.values.any { it }
        if (hasPermission) {
            state.location.start()
            goOnline(true)
        } else {
            error = state.l("location_needed")
        }
    }

    LaunchedEffect(Unit) { if (state.location.hasPermission()) state.location.start() }

    // Presence: ping position every 10 s while online.
    LaunchedEffect(online) {
        while (online) {
            state.location.location.value?.let { state.api.pingLocation(it.latitude, it.longitude) }
            delay(10_000)
        }
    }

    // Feed: every 5 s while online. Also catches an accepted offer → active ride.
    LaunchedEffect(online, uid) {
        if (!online || uid == null) {
            requests = emptyList()
            return@LaunchedEffect
        }
        while (true) {
            val active = runCatching { state.api.activeDriverRide(uid) }.getOrNull()
            if (active != null) {
                state.setActiveRide(active.id)
                return@LaunchedEffect
            }
            state.api.expireStale()
            runCatching { state.api.openRequests() }
                .onSuccess { requests = it.filter { r -> r.passengerId != uid }; error = null }
                .onFailure { error = state.serverError(it) }
            runCatching { state.api.myDriverOffers(uid) }.onSuccess { myOffers = it }
            feedLoaded = true
            delay(5000)
        }
    }

    val bg by animateColorAsState(if (online) KJ.success else KJ.muted, label = "onlineColor")

    Column(Modifier.fillMaxSize().background(KJ.canvas)) {
        // Header
        Column(
            Modifier.fillMaxWidth()
                .clip(RoundedCornerShape(bottomStart = 28.dp, bottomEnd = 28.dp))
                .background(if (online) KJ.buttonGradient else KJ.burgundyGradient)
                .statusBarsPadding()
                .padding(horizontal = 20.dp, vertical = 16.dp),
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f)) {
                    Text("${state.l("hello")}, ${profile?.name ?: ""}", color = Color.White, fontWeight = FontWeight.ExtraBold, fontSize = 22.sp)
                    Text(state.l("driver_space"), color = Color.White.copy(alpha = 0.8f), fontSize = 13.sp)
                }
                if (profile != null) {
                    Row(
                        Modifier.clip(RoundedCornerShape(50)).background(Color.White.copy(alpha = 0.18f)).padding(horizontal = 10.dp, vertical = 6.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Text("★ " + String.format(Locale.US, "%.1f", profile.ratingAvg), color = Color.White, fontWeight = FontWeight.Bold, fontSize = 13.sp)
                    }
                }
            }
            Spacer(Modifier.height(14.dp))
            Row(
                Modifier.fillMaxWidth().clip(RoundedCornerShape(20.dp)).background(Color.White).padding(14.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Box(Modifier.size(12.dp).clip(CircleShape).background(bg))
                Spacer(Modifier.width(10.dp))
                Column(Modifier.weight(1f)) {
                    Text(if (online) state.l("online") else state.l("offline"), fontWeight = FontWeight.Bold, color = KJ.ink, fontSize = 16.sp)
                    Text(if (online) state.l("online_subtitle") else state.l("offline_subtitle"), color = KJ.muted, fontSize = 12.sp)
                }
                Switch(
                    checked = online,
                    enabled = !toggling,
                    onCheckedChange = { v ->
                        if (v && !state.location.hasPermission()) {
                            permLauncher.launch(arrayOf(Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION))
                        } else {
                            goOnline(v)
                        }
                    },
                    colors = SwitchDefaults.colors(checkedTrackColor = KJ.success, checkedThumbColor = Color.White),
                )
            }
        }

        error?.let {
            Spacer(Modifier.height(10.dp))
            ErrorBanner(it, Modifier.padding(horizontal = 18.dp))
        }

        if (!online) {
            Box(Modifier.weight(1f).fillMaxWidth(), contentAlignment = Alignment.Center) {
                Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.padding(24.dp)) {
                    IconCircle(Icons.Filled.PowerSettingsNew, tint = KJ.muted, bg = KJ.softBlue, size = 76.dp)
                    Spacer(Modifier.height(14.dp))
                    Text(state.l("go_online_first"), color = KJ.inkSoft, textAlign = TextAlign.Center, fontWeight = FontWeight.SemiBold)
                    if (!hasPermission) {
                        Spacer(Modifier.height(6.dp))
                        Text(state.l("location_needed"), color = KJ.muted, textAlign = TextAlign.Center, fontSize = 13.sp)
                    }
                }
            }
        } else if (!feedLoaded) {
            Box(Modifier.weight(1f).fillMaxWidth(), contentAlignment = Alignment.Center) { PulsingDots() }
        } else if (requests.isEmpty()) {
            Box(Modifier.weight(1f).fillMaxWidth(), contentAlignment = Alignment.Center) {
                EmptyState(Icons.Filled.Inbox, state.l("no_requests"), state.l("no_requests_hint"))
            }
        } else {
            LazyColumn(
                Modifier.weight(1f).fillMaxWidth(),
                contentPadding = androidx.compose.foundation.layout.PaddingValues(horizontal = 18.dp, vertical = 14.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                item {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        SectionTitle(state.l("new_requests"), Modifier.weight(1f))
                        Pill("${requests.size}", KJ.blue, KJ.softBlue)
                    }
                }
                items(requests, key = { it.id }) { req ->
                    RequestCard(state, req, myOffers.firstOrNull { it.requestId == req.id }, loc?.let { it.latitude to it.longitude }) { selected = req }
                }
            }
        }
    }

    selected?.let { req ->
        val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
        ModalBottomSheet(onDismissRequest = { selected = null }, sheetState = sheetState, containerColor = KJ.canvas) {
            OfferSheet(state, req, myOffers.firstOrNull { it.requestId == req.id }) { sent ->
                myOffers = myOffers.filter { it.requestId != req.id } + sent
            }
        }
    }
}

private fun haversineKm(a: Pair<Double, Double>, lat: Double, lng: Double): Double {
    val r = 6371.0
    val dLat = Math.toRadians(lat - a.first)
    val dLng = Math.toRadians(lng - a.second)
    val h = Math.sin(dLat / 2) * Math.sin(dLat / 2) +
        Math.cos(Math.toRadians(a.first)) * Math.cos(Math.toRadians(lat)) * Math.sin(dLng / 2) * Math.sin(dLng / 2)
    return 2 * r * Math.asin(Math.sqrt(h))
}

@Composable
private fun RequestCard(state: AppState, req: RideRequest, myOffer: Offer?, me: Pair<Double, Double>?, onClick: () -> Unit) {
    val ok = req.estimatedFare == null || req.proposedFare >= req.estimatedFare
    KJCard(Modifier.fillMaxWidth().clip(RoundedCornerShape(22.dp)).clickable(onClick = onClick), padding = 16.dp) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Avatar(req.passenger?.name ?: "K", size = 40.dp)
            Spacer(Modifier.width(10.dp))
            Column(Modifier.weight(1f)) {
                Text(req.passenger?.name?.ifBlank { null } ?: state.l("passenger_label"), fontWeight = FontWeight.Bold, color = KJ.ink)
                RatingBadge(req.passenger?.ratingAvg ?: 0.0, req.passenger?.tripsCount)
            }
            Column(horizontalAlignment = Alignment.End) {
                Text(dzd(req.proposedFare), fontWeight = FontWeight.Black, fontSize = 20.sp, color = KJ.ink)
                Pill(
                    if (ok) state.l("price_ok") else state.l("price_low"),
                    if (ok) KJ.success else KJ.warning,
                    if (ok) KJ.successBg else KJ.warningBg,
                )
            }
        }
        Spacer(Modifier.height(12.dp))
        RouteLines(req.pickupLabel, req.destLabel)
        Spacer(Modifier.height(10.dp))
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
            Pill(
                String.format(Locale.US, "%.1f %s", req.distanceKm, state.l("km")), KJ.inkSoft, KJ.softBlue,
                icon = Icons.Filled.Route,
            )
            Pill(
                if (req.vehicle == "moto") state.l("moto") else state.l("car"), KJ.inkSoft, KJ.softBlue,
                icon = if (req.vehicle == "moto") Icons.Filled.TwoWheeler else Icons.Filled.DirectionsCar,
            )
            if (me != null) {
                val away = haversineKm(me, req.pickupLat, req.pickupLng)
                Text(String.format(Locale.US, "%.1f %s", away, state.l("km_away")), color = KJ.muted, fontSize = 12.sp)
            }
        }
        if (myOffer != null) {
            Spacer(Modifier.height(10.dp))
            Pill("${state.l("pending_offer")} · ${dzd(myOffer.price)}", KJ.blue, KJ.softBlue, icon = Icons.Filled.HourglassTop)
        }
    }
}

@Composable
private fun OfferSheet(state: AppState, req: RideRequest, existing: Offer?, onSent: (Offer) -> Unit) {
    val scope = rememberCoroutineScope()
    val haptic = LocalHapticFeedback.current
    var price by remember { mutableIntStateOf(existing?.price ?: req.proposedFare) }
    var preview by remember { mutableStateOf<DriverOfferPreview?>(null) }
    var sending by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var sent by remember { mutableStateOf(existing) }
    var messages by remember { mutableStateOf<List<RideMessage>>(emptyList()) }
    var draft by remember { mutableStateOf("") }
    var now by remember { mutableLongStateOf(System.currentTimeMillis()) }

    // Server preview: suggested price, allowed range and net gain for the chosen price.
    LaunchedEffect(price) {
        delay(250)
        runCatching { state.api.offerPreview(req.id, price) }
            .onSuccess {
                preview = it
                val clamped = price.coerceIn(it.minPrice, it.maxPrice)
                if (clamped != price) price = clamped
            }
            .onFailure { error = state.serverError(it) }
    }
    // Passenger messages are visible once an offer exists.
    LaunchedEffect(sent?.id) {
        if (sent == null) return@LaunchedEffect
        while (true) {
            runCatching { state.api.messages(req.id) }.onSuccess { messages = it }
            delay(3500)
        }
    }
    LaunchedEffect(Unit) {
        while (true) {
            now = System.currentTimeMillis()
            delay(1000)
        }
    }

    val p = preview
    val remaining = parseTs(req.expiresAt)?.let { ((it - now) / 1000).coerceAtLeast(0) }

    Column(
        Modifier.fillMaxWidth().imePadding().verticalScroll(rememberScrollState()).padding(horizontal = 20.dp).padding(bottom = 24.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(state.l("new_ride_request"), fontSize = 20.sp, fontWeight = FontWeight.ExtraBold, color = KJ.ink, modifier = Modifier.weight(1f))
            if (remaining != null) {
                Pill(
                    "${state.l("expires_in")} " + String.format(Locale.US, "%d:%02d", remaining / 60, remaining % 60),
                    KJ.burgundy, KJ.dangerBg, icon = Icons.Filled.HourglassTop,
                )
            }
        }
        Spacer(Modifier.height(12.dp))
        Box(Modifier.fillMaxWidth().height(170.dp).clip(RoundedCornerShape(20.dp))) {
            OsmMap(
                Modifier.fillMaxSize(),
                pins = listOf(MapPin(req.pickupLat, req.pickupLng, PinKind.Pickup), MapPin(req.destLat, req.destLng, PinKind.Destination)),
                fitKey = req.id,
            )
        }
        Spacer(Modifier.height(12.dp))
        KJCard {
            RouteLines(req.pickupLabel, req.destLabel)
            Spacer(Modifier.height(10.dp))
            SummaryLine(state.l("distance"), String.format(Locale.US, "%.1f %s", req.distanceKm, state.l("km")))
            SummaryLine(state.l("proposed_price"), dzd(req.proposedFare), bold = true)
        }
        Spacer(Modifier.height(16.dp))
        SectionTitle(state.l("your_price"))
        Spacer(Modifier.height(10.dp))
        KJCard {
            Row(verticalAlignment = Alignment.CenterVertically) {
                IconCircle(Icons.Filled.Remove, size = 48.dp, onClick = {
                    haptic.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                    price = (price - 50).coerceAtLeast(p?.minPrice ?: 50)
                })
                Text(
                    dzd(price), fontSize = 30.sp, fontWeight = FontWeight.Black, color = KJ.ink,
                    textAlign = TextAlign.Center, modifier = Modifier.weight(1f).animateContentSize(),
                )
                IconCircle(Icons.Filled.Add, size = 48.dp, onClick = {
                    haptic.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                    price = if (p != null) (price + 50).coerceAtMost(p.maxPrice) else price + 50
                })
            }
            if (p != null) {
                Spacer(Modifier.height(12.dp))
                Row(
                    Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp)).background(KJ.successBg).padding(12.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Icon(Icons.Filled.Payments, null, tint = KJ.success, modifier = Modifier.size(18.dp))
                    Spacer(Modifier.width(8.dp))
                    Text(state.l("net_gain"), color = KJ.success, fontWeight = FontWeight.SemiBold, modifier = Modifier.weight(1f))
                    Text(dzd(p.net), color = KJ.success, fontWeight = FontWeight.Black, fontSize = 18.sp)
                }
                if (price != p.suggested) {
                    Spacer(Modifier.height(8.dp))
                    Text(
                        "${state.l("use_suggested")} · ${dzd(p.suggested)}",
                        color = KJ.blue, fontWeight = FontWeight.SemiBold, fontSize = 14.sp,
                        modifier = Modifier.clip(RoundedCornerShape(10.dp)).clickable { price = p.suggested }.padding(6.dp),
                    )
                }
            }
        }
        error?.let {
            Spacer(Modifier.height(10.dp))
            ErrorBanner(it)
        }
        Spacer(Modifier.height(14.dp))
        val already = sent
        if (already != null) {
            Pill("${state.l("your_offer_sent")} · ${dzd(already.price)}", KJ.success, KJ.successBg, icon = Icons.Filled.CheckCircle)
            Spacer(Modifier.height(6.dp))
            Text(state.l("waiting_accept"), color = KJ.muted, fontSize = 13.sp)
            Spacer(Modifier.height(10.dp))
        }
        KJButton(
            if (already == null) state.l("make_offer") else state.l("counter_offer"),
            loading = sending,
            enabled = p != null && (already == null || already.price != price),
            icon = Icons.AutoMirrored.Filled.Send,
        ) {
            sending = true
            error = null
            scope.launch {
                try {
                    val kind = if (already == null) "initial" else "counter"
                    val id = state.api.makeOffer(req.id, price, kind)
                    val o = Offer(id = id, requestId = req.id, driverId = state.userId ?: "", price = price, kind = kind)
                    sent = o
                    onSent(o)
                } catch (e: Exception) {
                    error = state.serverError(e)
                }
                sending = false
            }
        }

        if (already != null) {
            Spacer(Modifier.height(18.dp))
            SectionTitle(state.l("passenger_messages"))
            Spacer(Modifier.height(8.dp))
            if (messages.isEmpty()) {
                Text(state.l("message_empty"), color = KJ.muted, fontSize = 13.sp)
            } else {
                messages.forEach { m -> ChatBubble(m.body, mine = m.senderId == state.userId) }
            }
            Spacer(Modifier.height(10.dp))
            Row(verticalAlignment = Alignment.CenterVertically) {
                OutlinedTextField(
                    value = draft, onValueChange = { draft = it.take(500) },
                    placeholder = { Text(state.l("write_message")) },
                    singleLine = true,
                    shape = RoundedCornerShape(24.dp),
                    colors = OutlinedTextFieldDefaults.colors(unfocusedContainerColor = Color.White, focusedContainerColor = Color.White, unfocusedBorderColor = Color.Transparent),
                    modifier = Modifier.weight(1f),
                )
                Spacer(Modifier.width(8.dp))
                IconCircle(
                    Icons.AutoMirrored.Filled.Send, tint = Color.White, bg = if (draft.isBlank()) KJ.muted else KJ.blue, size = 48.dp,
                    onClick = if (draft.isBlank()) null else ({
                        val text = draft.trim()
                        val uid = state.userId
                        draft = ""
                        if (uid != null && text.isNotEmpty()) scope.launch {
                            runCatching { state.api.sendMessage(req.id, uid, text) }.onFailure { error = state.serverError(it) }
                            runCatching { state.api.messages(req.id) }.onSuccess { messages = it }
                        }
                    }),
                )
            }
        }
    }
}

// ===================== Active ride (driver) =====================

@Composable
private fun DriverActiveRide(state: AppState, rideId: String) {
    val scope = rememberCoroutineScope()
    var ride by remember { mutableStateOf<Ride?>(null) }
    var passenger by remember { mutableStateOf<Profile?>(null) }
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var confirmCancel by remember { mutableStateOf(false) }
    var loaded by remember { mutableStateOf(false) }
    val loc by state.location.location.collectAsState()

    LaunchedEffect(Unit) { if (state.location.hasPermission()) state.location.start() }

    LaunchedEffect(rideId) {
        while (true) {
            val r = runCatching { state.api.ride(rideId) }.getOrNull()
            if (r != null) {
                ride = r
                if (passenger == null) passenger = runCatching { state.api.profile(r.passengerId) }.getOrNull()
            } else if (!loaded) {
                state.setActiveRide(null)
            }
            loaded = true
            if (r != null && !r.isActive) break
            state.location.location.value?.let { state.api.pingLocation(it.latitude, it.longitude) }
            delay(5000)
        }
    }

    fun advance(status: String) {
        busy = true
        error = null
        scope.launch {
            try {
                state.api.updateRide(rideId, status)
                ride = state.api.ride(rideId)
                if (status == "completed" || status == "cancelled") state.refreshProfile()
            } catch (e: Exception) {
                error = state.serverError(e)
            }
            busy = false
        }
    }

    val r = ride
    if (r == null) {
        Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { PulsingDots() }
        return
    }

    if (r.status == "completed" || r.status == "cancelled") {
        val done = r.status == "completed"
        Box(Modifier.fillMaxSize().background(KJ.canvasGradient)) {
            Column(
                Modifier.fillMaxSize().statusBarsPadding().verticalScroll(rememberScrollState()).padding(24.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                Spacer(Modifier.height(30.dp))
                IconCircle(
                    if (done) Icons.Filled.CheckCircle else Icons.Filled.Block,
                    tint = if (done) KJ.success else KJ.danger, bg = if (done) KJ.successBg else KJ.dangerBg, size = 84.dp,
                )
                Spacer(Modifier.height(16.dp))
                Text(
                    if (done) state.l("ride_done") else state.l("ride_cancelled"),
                    fontSize = 24.sp, fontWeight = FontWeight.ExtraBold, color = KJ.ink, textAlign = TextAlign.Center,
                )
                if (done) {
                    Spacer(Modifier.height(20.dp))
                    KJCard(Modifier.fillMaxWidth()) {
                        RouteLines(r.pickupLabel, r.destLabel)
                        Spacer(Modifier.height(12.dp))
                        SummaryLine(state.l("ride_fare"), dzd(r.fare), bold = true)
                        r.driverNet?.let { SummaryLine(state.l("net_earning"), dzd(it), color = KJ.success, bold = true) }
                        SummaryLine(state.l("payment"), state.l("cash_on_delivery"))
                    }
                }
                Spacer(Modifier.height(24.dp))
                KJButton(state.l("back_home")) { state.setActiveRide(null) }
            }
        }
        return
    }

    Column(Modifier.fillMaxSize().background(KJ.canvas)) {
        Box(Modifier.fillMaxWidth().weight(1f)) {
            val pins = buildList {
                add(MapPin(r.pickupLat, r.pickupLng, PinKind.Pickup))
                add(MapPin(r.destLat, r.destLng, PinKind.Destination))
                loc?.let { add(MapPin(it.latitude, it.longitude, PinKind.Me)) }
            }
            OsmMap(Modifier.fillMaxSize(), pins = pins, fitKey = r.id + r.status)
            Row(
                Modifier.statusBarsPadding().padding(14.dp).shadow(8.dp, RoundedCornerShape(50)).clip(RoundedCornerShape(50))
                    .background(Color.White).padding(horizontal = 14.dp, vertical = 8.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(state.l("active_ride"), fontWeight = FontWeight.Bold, color = KJ.ink, fontSize = 13.sp)
            }
        }
        Column(
            Modifier.fillMaxWidth().shadow(20.dp, RoundedCornerShape(topStart = 28.dp, topEnd = 28.dp))
                .clip(RoundedCornerShape(topStart = 28.dp, topEnd = 28.dp)).background(KJ.canvas)
                .verticalScroll(rememberScrollState()).padding(20.dp),
        ) {
            StatusSteps(state, r.status)
            Spacer(Modifier.height(14.dp))
            KJCard(padding = 14.dp) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Avatar(passenger?.name ?: "K", size = 48.dp)
                    Spacer(Modifier.width(12.dp))
                    Column(Modifier.weight(1f)) {
                        Text(passenger?.name?.ifBlank { null } ?: state.l("passenger_label"), fontWeight = FontWeight.Bold, color = KJ.ink, fontSize = 16.sp)
                        passenger?.let { RatingBadge(it.ratingAvg, it.tripsCount) }
                    }
                    Column(horizontalAlignment = Alignment.End) {
                        Text(dzd(r.fare), fontWeight = FontWeight.Black, fontSize = 22.sp, color = KJ.ink)
                        Text(state.l("cash_on_delivery"), color = KJ.success, fontSize = 11.sp, fontWeight = FontWeight.SemiBold)
                    }
                }
                Spacer(Modifier.height(12.dp))
                RouteLines(r.pickupLabel, r.destLabel)
            }
            error?.let {
                Spacer(Modifier.height(10.dp))
                ErrorBanner(it)
            }
            Spacer(Modifier.height(14.dp))
            when (r.status) {
                "en_route" -> KJButton(state.l("mark_arrived"), loading = busy) { advance("arrived") }
                "arrived" -> KJButton(state.l("start_ride"), loading = busy) { advance("started") }
                "started" -> KJButton(state.l("finish_ride"), loading = busy, brush = KJ.burgundyGradient) { advance("completed") }
            }
            if (r.status == "en_route" || r.status == "arrived") {
                Spacer(Modifier.height(10.dp))
                KJOutlineButton(state.l("cancel_ride"), color = KJ.danger, enabled = !busy) { confirmCancel = true }
            }
        }
    }

    if (confirmCancel) {
        AlertDialog(
            onDismissRequest = { confirmCancel = false },
            title = { Text(state.l("cancel_ride")) },
            text = { Text(state.l("cancel_confirm")) },
            confirmButton = {
                TextButton(onClick = {
                    confirmCancel = false
                    advance("cancelled")
                }) { Text(state.l("yes"), color = KJ.danger) }
            },
            dismissButton = { TextButton(onClick = { confirmCancel = false }) { Text(state.l("no")) } },
        )
    }
}
