package app.rork.h04xk59ettzrqz7c6l4wp.ui.screens

import androidx.compose.animation.animateContentSize
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Send
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.DirectionsCar
import androidx.compose.material.icons.filled.Flag
import androidx.compose.material.icons.filled.LocationOn
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.Payments
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.filled.StarBorder
import androidx.compose.material.icons.filled.Timer
import androidx.compose.material.icons.filled.TripOrigin
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
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
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.rork.h04xk59ettzrqz7c6l4wp.AppState
import app.rork.h04xk59ettzrqz7c6l4wp.data.Offer
import app.rork.h04xk59ettzrqz7c6l4wp.data.Profile
import app.rork.h04xk59ettzrqz7c6l4wp.data.Ride
import app.rork.h04xk59ettzrqz7c6l4wp.data.RideMessage
import app.rork.h04xk59ettzrqz7c6l4wp.data.RideRequest
import app.rork.h04xk59ettzrqz7c6l4wp.ui.components.Avatar
import app.rork.h04xk59ettzrqz7c6l4wp.ui.components.ErrorBanner
import app.rork.h04xk59ettzrqz7c6l4wp.ui.components.IconCircle
import app.rork.h04xk59ettzrqz7c6l4wp.ui.components.KJButton
import app.rork.h04xk59ettzrqz7c6l4wp.ui.components.KJCard
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

// ===================== Request: waiting for offers + negotiation =====================

@Composable
fun RequestScreen(state: AppState, requestId: String) {
    val scope = rememberCoroutineScope()
    var request by remember { mutableStateOf<RideRequest?>(null) }
    var offers by remember { mutableStateOf<List<Offer>>(emptyList()) }
    var messages by remember { mutableStateOf<List<RideMessage>>(emptyList()) }
    var draft by remember { mutableStateOf("") }
    var accepting by remember { mutableStateOf<String?>(null) }
    var error by remember { mutableStateOf<String?>(null) }
    var now by remember { mutableLongStateOf(System.currentTimeMillis()) }
    var confirmCancel by remember { mutableStateOf(false) }

    suspend fun poll() {
        val req = runCatching { state.api.request(requestId) }.getOrNull()
        if (req != null) {
            request = req
            when (req.status) {
                "accepted" -> {
                    val ride = runCatching { state.api.rideForRequest(requestId) }.getOrNull()
                    if (ride != null) {
                        state.setActiveRide(ride.id)
                        state.setActiveRequest(null)
                    }
                    return
                }
                "cancelled", "expired" -> {
                    state.setActiveRequest(null)
                    return
                }
            }
        }
        runCatching { state.api.offers(requestId) }.onSuccess { list -> offers = list.filter { it.status == "pending" } }
        runCatching { state.api.messages(requestId) }.onSuccess { messages = it }
    }

    LaunchedEffect(requestId) {
        while (true) {
            poll()
            delay(3500)
        }
    }
    LaunchedEffect(Unit) {
        while (true) {
            now = System.currentTimeMillis()
            delay(1000)
        }
    }

    fun send(body: String) {
        val text = body.trim()
        val uid = state.userId ?: return
        if (text.isEmpty()) return
        draft = ""
        scope.launch {
            runCatching { state.api.sendMessage(requestId, uid, text.take(500)) }
                .onFailure { error = state.serverError(it) }
            runCatching { state.api.messages(requestId) }.onSuccess { messages = it }
        }
    }

    val req = request
    val expiresMs = parseTs(req?.expiresAt)
    val remaining = expiresMs?.let { ((it - now) / 1000).coerceAtLeast(0) }
    val best = offers.minByOrNull { it.price }

    Column(Modifier.fillMaxSize().background(KJ.canvas)) {
        Box(Modifier.fillMaxWidth().fillMaxHeight(0.30f)) {
            if (req != null) {
                OsmMap(
                    modifier = Modifier.fillMaxSize(),
                    pins = listOf(MapPin(req.pickupLat, req.pickupLng, PinKind.Pickup), MapPin(req.destLat, req.destLng, PinKind.Destination)),
                    fitKey = req.id,
                )
            }
            Row(
                Modifier.statusBarsPadding().padding(14.dp).shadow(8.dp, RoundedCornerShape(50)).clip(RoundedCornerShape(50))
                    .background(Color.White).padding(horizontal = 14.dp, vertical = 8.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    if (offers.isEmpty()) state.l("waiting_offers") else state.l("negotiation_open"),
                    fontWeight = FontWeight.Bold, color = KJ.ink, fontSize = 14.sp,
                )
                if (remaining != null) {
                    Spacer(Modifier.width(10.dp))
                    Icon(Icons.Filled.Timer, null, tint = KJ.burgundy, modifier = Modifier.size(15.dp))
                    Spacer(Modifier.width(3.dp))
                    Text(String.format(java.util.Locale.US, "%d:%02d", remaining / 60, remaining % 60), color = KJ.burgundy, fontWeight = FontWeight.Bold, fontSize = 14.sp)
                }
            }
        }

        Column(
            Modifier.weight(1f).fillMaxWidth().verticalScroll(rememberScrollState()).padding(horizontal = 18.dp, vertical = 14.dp),
        ) {
            if (req != null) {
                KJCard {
                    RouteLines(req.pickupLabel, req.destLabel)
                    Spacer(Modifier.height(12.dp))
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(state.l("proposed_price"), color = KJ.muted, modifier = Modifier.weight(1f))
                        Text(dzd(req.proposedFare), fontWeight = FontWeight.Black, fontSize = 20.sp, color = KJ.ink)
                    }
                }
            }
            Spacer(Modifier.height(16.dp))
            Row(verticalAlignment = Alignment.CenterVertically) {
                SectionTitle(state.l("offers"), Modifier.weight(1f))
                if (offers.isNotEmpty()) Pill("${offers.size} ${state.l("offers_received")}", KJ.blue, KJ.softBlue)
            }
            Spacer(Modifier.height(10.dp))
            if (offers.isEmpty()) {
                KJCard {
                    Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally) {
                        PulsingDots()
                        Spacer(Modifier.height(10.dp))
                        Text(state.l("no_offers_yet"), color = KJ.muted, textAlign = TextAlign.Center)
                    }
                }
            } else {
                Column(verticalArrangement = Arrangement.spacedBy(10.dp), modifier = Modifier.animateContentSize()) {
                    offers.forEach { offer ->
                        OfferCard(state, offer, isBest = offer.id == best?.id && offers.size > 1, accepting = accepting == offer.id) {
                            accepting = offer.id
                            error = null
                            scope.launch {
                                try {
                                    val rideId = state.api.acceptOffer(offer.id)
                                    state.setActiveRide(rideId)
                                    state.setActiveRequest(null)
                                } catch (e: Exception) {
                                    error = state.serverError(e)
                                }
                                accepting = null
                            }
                        }
                    }
                }
            }
            error?.let {
                Spacer(Modifier.height(10.dp))
                ErrorBanner(it)
            }

            if (offers.isNotEmpty() || messages.isNotEmpty()) {
                Spacer(Modifier.height(18.dp))
                SectionTitle(state.l("negotiation"))
                Spacer(Modifier.height(4.dp))
                Text(state.l("negotiation_hint"), color = KJ.muted, fontSize = 13.sp)
                Spacer(Modifier.height(10.dp))
                messages.forEach { m -> ChatBubble(m.body, mine = m.senderId == state.userId) }
                Spacer(Modifier.height(8.dp))
                Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    QuickReply(state.l("can_you_lower")) { send(state.l("can_you_lower")) }
                    val base = best?.price ?: req?.proposedFare
                    if (base != null) {
                        val counter = (base - 50).coerceAtLeast(50)
                        QuickReply("${state.l("propose")} ${dzd(counter)}") { send("${state.l("propose")} ${dzd(counter)}") }
                    }
                }
            }
            Spacer(Modifier.height(18.dp))
            KJOutlineButton(state.l("cancel_request"), color = KJ.danger) { confirmCancel = true }
            Spacer(Modifier.height(12.dp))
        }

        if (offers.isNotEmpty() || messages.isNotEmpty()) {
            Row(
                Modifier.fillMaxWidth().background(Color.White).imePadding().padding(horizontal = 14.dp, vertical = 10.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                OutlinedTextField(
                    value = draft, onValueChange = { draft = it.take(500) },
                    placeholder = { Text(state.l("write_message")) },
                    singleLine = true,
                    shape = RoundedCornerShape(24.dp),
                    colors = OutlinedTextFieldDefaults.colors(unfocusedContainerColor = KJ.canvas, focusedContainerColor = KJ.canvas, unfocusedBorderColor = Color.Transparent),
                    modifier = Modifier.weight(1f),
                )
                Spacer(Modifier.width(8.dp))
                IconCircle(Icons.AutoMirrored.Filled.Send, tint = Color.White, bg = if (draft.isBlank()) KJ.muted else KJ.blue, size = 48.dp,
                    onClick = if (draft.isBlank()) null else ({ send(draft) }))
            }
        }
    }

    if (confirmCancel) {
        AlertDialog(
            onDismissRequest = { confirmCancel = false },
            title = { Text(state.l("cancel_request")) },
            text = { Text(state.l("cancel_confirm")) },
            confirmButton = {
                TextButton(onClick = {
                    confirmCancel = false
                    scope.launch {
                        try {
                            state.api.cancelRequest(requestId)
                            state.setActiveRequest(null)
                        } catch (e: Exception) {
                            error = state.serverError(e)
                        }
                    }
                }) { Text(state.l("yes"), color = KJ.danger) }
            },
            dismissButton = { TextButton(onClick = { confirmCancel = false }) { Text(state.l("no")) } },
        )
    }
}

@Composable
fun RouteLines(from: String, to: String) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Icon(Icons.Filled.TripOrigin, null, tint = KJ.blue, modifier = Modifier.size(18.dp))
        Spacer(Modifier.width(10.dp))
        Text(from, color = KJ.ink, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
    Box(Modifier.padding(start = 8.dp).width(2.dp).height(14.dp).background(KJ.softBlueMid))
    Row(verticalAlignment = Alignment.CenterVertically) {
        Icon(Icons.Filled.LocationOn, null, tint = KJ.burgundy, modifier = Modifier.size(18.dp))
        Spacer(Modifier.width(10.dp))
        Text(to, color = KJ.ink, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
}

@Composable
private fun OfferCard(state: AppState, offer: Offer, isBest: Boolean, accepting: Boolean, onAccept: () -> Unit) {
    val d = offer.driver
    KJCard(Modifier.fillMaxWidth().then(if (isBest) Modifier.border(2.dp, KJ.success, RoundedCornerShape(22.dp)) else Modifier), padding = 14.dp) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Avatar(d?.name ?: "K")
            Spacer(Modifier.width(12.dp))
            Column(Modifier.weight(1f)) {
                Text(d?.name ?: state.l("driver_label"), fontWeight = FontWeight.Bold, color = KJ.ink)
                RatingBadge(d?.ratingAvg ?: 0.0, d?.tripsCount)
                val vehicle = listOfNotNull(d?.vehicleMake, d?.vehicleModel).joinToString(" ")
                if (vehicle.isNotBlank()) Text(vehicle + (d?.vehicleColor?.let { " · $it" } ?: ""), color = KJ.muted, fontSize = 12.sp)
            }
            Column(horizontalAlignment = Alignment.End) {
                Text(dzd(offer.price), fontWeight = FontWeight.Black, fontSize = 20.sp, color = KJ.ink)
                if (offer.kind == "counter") Text(state.l("counter_offer"), color = KJ.burgundy, fontSize = 11.sp, fontWeight = FontWeight.Bold)
            }
        }
        Spacer(Modifier.height(10.dp))
        KJButton(state.l("accept_offer"), loading = accepting, icon = Icons.Filled.CheckCircle, onClick = onAccept)
    }
}

@Composable
fun ChatBubble(text: String, mine: Boolean) {
    Row(Modifier.fillMaxWidth().padding(vertical = 3.dp), horizontalArrangement = if (mine) Arrangement.End else Arrangement.Start) {
        Text(
            text,
            color = if (mine) Color.White else KJ.ink,
            modifier = Modifier.widthIn(max = 280.dp)
                .clip(RoundedCornerShape(18.dp))
                .background(if (mine) KJ.blue else Color.White)
                .padding(horizontal = 14.dp, vertical = 9.dp),
        )
    }
}

@Composable
fun QuickReply(label: String, onClick: () -> Unit) {
    Text(
        label, color = KJ.blue, fontWeight = FontWeight.SemiBold, fontSize = 13.sp,
        modifier = Modifier.clip(RoundedCornerShape(50)).background(KJ.softBlue).clickable(onClick = onClick).padding(horizontal = 14.dp, vertical = 8.dp),
    )
}

// ===================== Ride tracking (passenger) =====================

@Composable
fun RideTrackingScreen(state: AppState, rideId: String) {
    val scope = rememberCoroutineScope()
    var ride by remember { mutableStateOf<Ride?>(null) }
    var driver by remember { mutableStateOf<Profile?>(null) }
    var loaded by remember { mutableStateOf(false) }
    var confirmCancel by remember { mutableStateOf(false) }
    var cancelling by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }

    LaunchedEffect(rideId) {
        while (true) {
            val r = runCatching { state.api.ride(rideId) }.getOrNull()
            if (r != null) {
                ride = r
                runCatching { state.api.profile(r.driverId) }.getOrNull()?.let { driver = it }
            } else if (!loaded) {
                // Unknown ride (deleted or not visible): leave the screen.
                state.setActiveRide(null)
            }
            loaded = true
            if (r != null && (r.status == "completed" || r.status == "cancelled")) break
            delay(5000)
        }
    }

    val r = ride
    if (r == null) {
        Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { PulsingDots() }
        return
    }
    if (r.status == "completed") {
        RatingScreen(state, r, driver)
        return
    }

    Column(Modifier.fillMaxSize().background(KJ.canvas)) {
        Box(Modifier.fillMaxWidth().weight(1f)) {
            val pins = buildList {
                add(MapPin(r.pickupLat, r.pickupLng, PinKind.Pickup))
                add(MapPin(r.destLat, r.destLng, PinKind.Destination))
                val d = driver
                if (d?.currentLat != null && d.currentLng != null && r.status != "cancelled") add(MapPin(d.currentLat, d.currentLng, PinKind.Driver))
            }
            OsmMap(Modifier.fillMaxSize(), pins = pins, fitKey = r.id)
            Row(
                Modifier.statusBarsPadding().padding(14.dp).shadow(8.dp, RoundedCornerShape(50)).clip(RoundedCornerShape(50))
                    .background(Color.White).padding(horizontal = 14.dp, vertical = 8.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Icon(Icons.Filled.Lock, null, tint = KJ.success, modifier = Modifier.size(15.dp))
                Spacer(Modifier.width(6.dp))
                Text(state.l("offer_accepted"), fontWeight = FontWeight.Bold, color = KJ.ink, fontSize = 13.sp)
            }
        }
        Column(
            Modifier.fillMaxWidth().shadow(20.dp, RoundedCornerShape(topStart = 28.dp, topEnd = 28.dp))
                .clip(RoundedCornerShape(topStart = 28.dp, topEnd = 28.dp)).background(KJ.canvas)
                .verticalScroll(rememberScrollState()).padding(20.dp),
        ) {
            if (r.status == "cancelled") {
                Text(state.l("ride_cancelled"), fontSize = 22.sp, fontWeight = FontWeight.ExtraBold, color = KJ.danger)
                Spacer(Modifier.height(16.dp))
                KJButton(state.l("back_home")) { state.setActiveRide(null) }
                return@Column
            }
            Text(
                when (r.status) {
                    "arrived" -> state.l("status_arrived")
                    "started" -> state.l("status_started")
                    else -> state.l("driver_on_way")
                },
                fontSize = 22.sp, fontWeight = FontWeight.ExtraBold, color = KJ.ink,
            )
            Spacer(Modifier.height(12.dp))
            StatusSteps(state, r.status)
            Spacer(Modifier.height(16.dp))
            KJCard(padding = 14.dp) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Avatar(driver?.name ?: "K", size = 52.dp)
                    Spacer(Modifier.width(12.dp))
                    Column(Modifier.weight(1f)) {
                        Text(driver?.name ?: state.l("driver_label"), fontWeight = FontWeight.Bold, color = KJ.ink, fontSize = 16.sp)
                        RatingBadge(driver?.ratingAvg ?: 0.0, driver?.tripsCount)
                    }
                    val plate = driver?.vehiclePlate
                    if (!plate.isNullOrBlank()) Pill(plate, KJ.ink, KJ.softBlue)
                }
                val vehicle = listOfNotNull(driver?.vehicleMake, driver?.vehicleModel, driver?.vehicleColor).joinToString(" · ")
                if (vehicle.isNotBlank()) {
                    Spacer(Modifier.height(8.dp))
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Icon(Icons.Filled.DirectionsCar, null, tint = KJ.muted, modifier = Modifier.size(16.dp))
                        Spacer(Modifier.width(6.dp))
                        Text(vehicle, color = KJ.inkSoft, fontSize = 14.sp)
                    }
                }
            }
            Spacer(Modifier.height(12.dp))
            KJCard {
                RouteLines(r.pickupLabel, r.destLabel)
                Spacer(Modifier.height(12.dp))
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f)) {
                        Text(state.l("agreed_price"), color = KJ.muted, fontSize = 13.sp)
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Icon(Icons.Filled.Payments, null, tint = KJ.success, modifier = Modifier.size(15.dp))
                            Spacer(Modifier.width(4.dp))
                            Text(state.l("cash_on_delivery"), color = KJ.success, fontSize = 12.sp, fontWeight = FontWeight.SemiBold)
                        }
                    }
                    Text(dzd(r.fare), fontWeight = FontWeight.Black, fontSize = 24.sp, color = KJ.ink)
                }
            }
            error?.let {
                Spacer(Modifier.height(10.dp))
                ErrorBanner(it)
            }
            if (r.status == "en_route" || r.status == "arrived") {
                Spacer(Modifier.height(14.dp))
                KJOutlineButton(state.l("cancel_ride"), color = KJ.danger, enabled = !cancelling) { confirmCancel = true }
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
                    cancelling = true
                    scope.launch {
                        try {
                            state.api.cancelRide(rideId, "passenger_cancelled")
                            ride = state.api.ride(rideId)
                        } catch (e: Exception) {
                            error = state.serverError(e)
                        }
                        cancelling = false
                    }
                }) { Text(state.l("yes"), color = KJ.danger) }
            },
            dismissButton = { TextButton(onClick = { confirmCancel = false }) { Text(state.l("no")) } },
        )
    }
}

@Composable
fun StatusSteps(state: AppState, status: String) {
    val steps = listOf("en_route", "arrived", "started", "completed")
    val idx = steps.indexOf(status).coerceAtLeast(0)
    val labels = listOf(state.l("status_en_route"), state.l("status_arrived"), state.l("status_started"), state.l("status_completed"))
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.Top) {
        steps.forEachIndexed { i, _ ->
            Column(Modifier.weight(1f), horizontalAlignment = Alignment.CenterHorizontally) {
                val reached = i <= idx
                val active = i == idx
                val stepColor by animateColorAsState(
                    if (reached) KJ.blue else KJ.softBlueMid,
                    animationSpec = tween(320),
                    label = "ride-step-color-$i",
                )
                val dotSize by animateDpAsState(
                    if (active) 22.dp else 16.dp,
                    animationSpec = tween(320),
                    label = "ride-step-size-$i",
                )
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Box(Modifier.weight(1f).height(3.dp).background(if (i == 0) Color.Transparent else if (i <= idx) KJ.blue else KJ.softBlueMid))
                    Box(
                        Modifier.size(dotSize).clip(CircleShape).background(stepColor),
                        contentAlignment = Alignment.Center,
                    ) {
                        if (i < idx) Icon(Icons.Filled.CheckCircle, null, tint = Color.White, modifier = Modifier.size(12.dp))
                        if (i == steps.lastIndex && i > idx) Icon(Icons.Filled.Flag, null, tint = Color.White, modifier = Modifier.size(10.dp))
                    }
                    Box(Modifier.weight(1f).height(3.dp).background(if (i == steps.lastIndex) Color.Transparent else if (i < idx) KJ.blue else KJ.softBlueMid))
                }
                Spacer(Modifier.height(6.dp))
                Text(labels[i], fontSize = 11.sp, color = if (reached) KJ.ink else KJ.muted, textAlign = TextAlign.Center,
                    fontWeight = if (active) FontWeight.Bold else FontWeight.Normal, maxLines = 2)
            }
        }
    }
}

// ===================== Rating =====================

@Composable
private fun RatingScreen(state: AppState, ride: Ride, driver: Profile?) {
    val scope = rememberCoroutineScope()
    var stars by remember { mutableIntStateOf(5) }
    var comment by remember { mutableStateOf("") }
    var sending by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }

    Box(Modifier.fillMaxSize().background(KJ.canvasGradient)) {
        Column(
            Modifier.fillMaxSize().statusBarsPadding().imePadding().verticalScroll(rememberScrollState()).padding(24.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Spacer(Modifier.height(20.dp))
            IconCircle(Icons.Filled.CheckCircle, tint = KJ.success, bg = KJ.successBg, size = 80.dp)
            Spacer(Modifier.height(16.dp))
            Text(state.l("arrived_destination"), fontSize = 24.sp, fontWeight = FontWeight.ExtraBold, color = KJ.ink, textAlign = TextAlign.Center)
            Text(state.l("thanks_kherja"), color = KJ.muted)
            Spacer(Modifier.height(20.dp))
            KJCard(Modifier.fillMaxWidth()) {
                RouteLines(ride.pickupLabel, ride.destLabel)
                Spacer(Modifier.height(12.dp))
                SummaryLine(state.l("agreed_price"), dzd(ride.fare), bold = true)
                SummaryLine(state.l("cash_on_delivery"), state.l("paid"), color = KJ.success)
            }
            Spacer(Modifier.height(20.dp))
            KJCard(Modifier.fillMaxWidth()) {
                Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally) {
                    Avatar(driver?.name ?: "K", size = 56.dp)
                    Spacer(Modifier.height(8.dp))
                    Text(state.l("rate_ride"), fontWeight = FontWeight.ExtraBold, fontSize = 18.sp, color = KJ.ink)
                    Text(state.l("rate_hint"), color = KJ.muted, fontSize = 13.sp, textAlign = TextAlign.Center)
                    Spacer(Modifier.height(12.dp))
                    Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        (1..5).forEach { i ->
                            Icon(
                                if (i <= stars) Icons.Filled.Star else Icons.Filled.StarBorder, null,
                                tint = if (i <= stars) KJ.warning else KJ.softBlueMid,
                                modifier = Modifier.size(42.dp).clip(CircleShape).clickable { stars = i },
                            )
                        }
                    }
                    Spacer(Modifier.height(12.dp))
                    OutlinedTextField(
                        value = comment, onValueChange = { comment = it.take(300) },
                        placeholder = { Text(state.l("add_comment")) },
                        shape = RoundedCornerShape(16.dp),
                        modifier = Modifier.fillMaxWidth().height(100.dp),
                        colors = OutlinedTextFieldDefaults.colors(unfocusedBorderColor = KJ.softBlueMid),
                    )
                }
            }
            error?.let {
                Spacer(Modifier.height(10.dp))
                ErrorBanner(it)
            }
            Spacer(Modifier.height(20.dp))
            KJButton(state.l("submit_rating"), loading = sending) {
                sending = true
                error = null
                scope.launch {
                    try {
                        state.api.submitRating(ride.id, stars, comment.trim().ifEmpty { null })
                        state.setActiveRide(null)
                    } catch (e: Exception) {
                        // Already rated → just go home.
                        if ((e.message ?: "").contains("already", true)) state.setActiveRide(null) else error = state.serverError(e)
                    }
                    sending = false
                }
            }
            Spacer(Modifier.height(10.dp))
            Text(
                state.l("back_home"), color = KJ.muted, fontWeight = FontWeight.SemiBold,
                modifier = Modifier.clip(RoundedCornerShape(10.dp)).clickable { state.setActiveRide(null) }.padding(8.dp),
            )
        }
    }
}
