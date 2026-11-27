package app.rork.h04xk59ettzrqz7c6l4wp.ui.screens

import android.Manifest
import android.content.Intent
import android.net.Uri
import android.provider.Settings
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.animateContentSize
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.LocationOn
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.filled.Work
import androidx.compose.material.icons.filled.Map
import androidx.compose.material.icons.filled.MyLocation
import androidx.compose.material.icons.filled.Payments
import androidx.compose.material.icons.filled.Remove
import androidx.compose.material.icons.filled.Replay
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.TripOrigin
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.rork.h04xk59ettzrqz7c6l4wp.AppState
import app.rork.h04xk59ettzrqz7c6l4wp.R
import app.rork.h04xk59ettzrqz7c6l4wp.data.GeoPlace
import app.rork.h04xk59ettzrqz7c6l4wp.data.PassengerQuote
import app.rork.h04xk59ettzrqz7c6l4wp.data.RouteInfo
import app.rork.h04xk59ettzrqz7c6l4wp.ui.components.ErrorBanner
import app.rork.h04xk59ettzrqz7c6l4wp.ui.components.IconCircle
import app.rork.h04xk59ettzrqz7c6l4wp.ui.components.KJButton
import app.rork.h04xk59ettzrqz7c6l4wp.ui.components.KJCard
import app.rork.h04xk59ettzrqz7c6l4wp.ui.components.KJLogo
import app.rork.h04xk59ettzrqz7c6l4wp.ui.components.MapPin
import app.rork.h04xk59ettzrqz7c6l4wp.ui.components.OsmMap
import app.rork.h04xk59ettzrqz7c6l4wp.ui.components.PinKind
import app.rork.h04xk59ettzrqz7c6l4wp.ui.components.dzd
import app.rork.h04xk59ettzrqz7c6l4wp.ui.theme.KJ
import app.rork.h04xk59ettzrqz7c6l4wp.ui.theme.PriceStyle
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import org.osmdroid.util.GeoPoint

@Composable
fun PassengerHomeScreen(state: AppState) {
    val rideId = state.activeRideId
    val requestId = state.activeRequestId
    when {
        rideId != null -> RideTrackingScreen(state, rideId)
        requestId != null -> RequestScreen(state, requestId)
        else -> BookingScreen(state)
    }
}

private enum class Field { Pickup, Dest }

@Composable
private fun BookingScreen(state: AppState) {
    val scope = rememberCoroutineScope()
    val context = LocalContext.current
    val myLoc by state.location.location.collectAsState()
    var hasPermission by remember { mutableStateOf(state.location.hasPermission()) }
    val permLauncher = rememberLauncherForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) { res ->
        hasPermission = res.values.any { it }
        if (hasPermission) state.location.start()
    }
    LaunchedEffect(Unit) {
        if (state.location.hasPermission()) state.location.start()
        else permLauncher.launch(arrayOf(Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION))
    }

    var pickup by remember { mutableStateOf<GeoPlace?>(null) }
    var pickupIsMine by remember { mutableStateOf(true) }
    var dest by remember { mutableStateOf<GeoPlace?>(null) }
    var vehicle by remember { mutableStateOf("car") }
    var route by remember { mutableStateOf<RouteInfo?>(null) }
    var routing by remember { mutableStateOf(false) }
    var quote by remember { mutableStateOf<PassengerQuote?>(null) }
    var quoting by remember { mutableStateOf(false) }
    var quoteError by remember { mutableStateOf(false) }
    var fare by remember { mutableIntStateOf(0) }
    var submitting by remember { mutableStateOf(false) }
    var submitError by remember { mutableStateOf<String?>(null) }
    var pickMode by remember { mutableStateOf<Field?>(null) }
    var searchFor by remember { mutableStateOf<Field?>(null) }
    var quoteNonce by remember { mutableIntStateOf(0) }

    // Pickup follows the device location until the passenger chooses another point.
    LaunchedEffect(myLoc, pickupIsMine) {
        val loc = myLoc ?: return@LaunchedEffect
        if (!pickupIsMine) return@LaunchedEffect
        val prev = pickup
        if (prev != null && app.rork.h04xk59ettzrqz7c6l4wp.data.GeoService.haversine(prev.lat, prev.lng, loc.latitude, loc.longitude) < 0.08) return@LaunchedEffect
        pickup = GeoPlace(state.l("my_position"), loc.latitude, loc.longitude)
        val label = state.geo.reverse(loc.latitude, loc.longitude, state.language)
        if (label != null && pickupIsMine) pickup = GeoPlace(label, loc.latitude, loc.longitude)
    }

    LaunchedEffect(pickup?.lat, pickup?.lng, dest?.lat, dest?.lng) {
        val p = pickup
        val d = dest
        route = null
        quote = null
        if (p == null || d == null) return@LaunchedEffect
        routing = true
        route = state.geo.route(p, d)
        routing = false
    }

    LaunchedEffect(route, vehicle, quoteNonce) {
        val p = pickup
        val d = dest
        val r = route
        if (p == null || d == null || r == null) return@LaunchedEffect
        quoting = true
        quoteError = false
        submitError = null
        try {
            val q = state.api.quoteFare(p.lat, p.lng, d.lat, d.lng, r.distanceKm, vehicle, state.profile?.city ?: "Alger")
            quote = q
            fare = q.total
        } catch (e: Exception) {
            quote = null
            quoteError = true
        }
        quoting = false
    }

    val pins = buildList {
        pickup?.let { add(MapPin(it.lat, it.lng, PinKind.Pickup)) }
        dest?.let { add(MapPin(it.lat, it.lng, PinKind.Destination)) }
        if (!pickupIsMine) myLoc?.let { add(MapPin(it.latitude, it.longitude, PinKind.Me)) }
    }

    fun setPoint(field: Field, lat: Double, lng: Double) {
        val placeholder = GeoPlace(String.format(java.util.Locale.US, "%.5f, %.5f", lat, lng), lat, lng)
        if (field == Field.Pickup) { pickup = placeholder; pickupIsMine = false } else dest = placeholder
        scope.launch {
            val label = state.geo.reverse(lat, lng, state.language) ?: return@launch
            if (field == Field.Pickup && pickup?.lat == lat) pickup = GeoPlace(label, lat, lng)
            if (field == Field.Dest && dest?.lat == lat) dest = GeoPlace(label, lat, lng)
        }
    }

    BackHandler(enabled = pickMode != null || searchFor != null) {
        pickMode = null
        searchFor = null
    }

    Box(Modifier.fillMaxSize().background(KJ.canvas)) {
        OsmMap(
            modifier = Modifier.fillMaxWidth().fillMaxHeight(if (pickMode != null) 1f else 0.5f),
            pins = pins,
            route = route?.points ?: emptyList(),
            fitKey = listOf(pickup?.lat, dest?.lat, route?.distanceKm),
            center = myLoc?.let { GeoPoint(it.latitude, it.longitude) },
            onTap = pickMode?.let { f -> { lat: Double, lng: Double -> setPoint(f, lat, lng); pickMode = null } },
        )

        // Header
        Row(
            Modifier.statusBarsPadding().padding(16.dp).fillMaxWidth()
                .shadow(10.dp, RoundedCornerShape(20.dp)).clip(RoundedCornerShape(20.dp)).background(Color.White)
                .padding(horizontal = 16.dp, vertical = 10.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column(Modifier.weight(1f)) {
                Text("${state.l("hello")}, ${state.profile?.name?.split(" ")?.firstOrNull() ?: ""}", fontWeight = FontWeight.ExtraBold, fontSize = 17.sp, color = KJ.ink)
                Text(
                    if (pickMode != null) state.l("point_on_map") else state.l("find_driver"),
                    color = if (pickMode != null) KJ.blue else KJ.muted, fontSize = 13.sp,
                )
            }
            if (pickMode != null) {
                IconCircle(Icons.Filled.Close, size = 36.dp) { pickMode = null }
            } else {
                KJLogo(34.dp)
            }
        }

        if (pickMode == null) {
            Column(
                Modifier.align(Alignment.BottomCenter).fillMaxWidth().heightIn(max = 620.dp).fillMaxHeight(0.58f)
                    .shadow(24.dp, RoundedCornerShape(topStart = 28.dp, topEnd = 28.dp))
                    .clip(RoundedCornerShape(topStart = 28.dp, topEnd = 28.dp))
                    .background(KJ.canvas)
                    .verticalScroll(rememberScrollState())
                    .padding(20.dp)
                    .animateContentSize(),
            ) {
                Text(state.l("where_to"), fontSize = 22.sp, fontWeight = FontWeight.ExtraBold, color = KJ.ink)
                Spacer(Modifier.height(14.dp))

                if (!hasPermission) {
                    KJCard(padding = 12.dp) {
                        Text(
                            if (state.isRtl) "إذن الموقع غير مفعّل. يمكنك اختيار العنوان يدوياً أو تفعيل الموقع من إعدادات الهاتف."
                            else "La localisation est désactivée. Choisissez une adresse manuellement ou autorisez l’accès dans les réglages.",
                            color = KJ.muted, fontSize = 12.sp,
                        )
                        Spacer(Modifier.height(8.dp))
                        Row(horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                            Text(
                                if (state.isRtl) "إعدادات الموقع" else "Réglages",
                                color = KJ.blue, fontWeight = FontWeight.Bold, modifier = Modifier.clickable {
                                    val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:${context.packageName}"))
                                    context.startActivity(intent)
                                },
                            )
                            Text(
                                if (state.isRtl) "إعادة المحاولة" else "Réessayer",
                                color = KJ.blue, fontWeight = FontWeight.Bold, modifier = Modifier.clickable {
                                    permLauncher.launch(arrayOf(Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION))
                                },
                            )
                        }
                    }
                    Spacer(Modifier.height(12.dp))
                }

                KJCard(padding = 6.dp) {
                    PlaceRow(
                        icon = Icons.Filled.TripOrigin, tint = KJ.blue, label = state.l("pickup"),
                        value = pickup?.label ?: if (hasPermission) state.l("loading") else state.l("location_needed"),
                        onClick = { searchFor = Field.Pickup },
                        onMap = { pickMode = Field.Pickup },
                    )
                    Box(Modifier.padding(start = 52.dp, end = 12.dp).fillMaxWidth().height(1.dp).background(KJ.softBlue))
                    PlaceRow(
                        icon = Icons.Filled.LocationOn, tint = KJ.burgundy, label = state.l("destination"),
                        value = dest?.label ?: state.l("where_to"),
                        muted = dest == null,
                        onClick = { searchFor = Field.Dest },
                        onMap = { pickMode = Field.Dest },
                    )
                }
                if (!hasPermission) {
                    Spacer(Modifier.height(10.dp))
                    Text(
                        state.l("allow_location"), color = KJ.blue, fontWeight = FontWeight.Bold,
                        modifier = Modifier.clip(RoundedCornerShape(10.dp)).clickable {
                            permLauncher.launch(arrayOf(Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION))
                        }.padding(6.dp),
                    )
                }
                if (!pickupIsMine && myLoc != null) {
                    Spacer(Modifier.height(8.dp))
                    Row(
                        Modifier.clip(RoundedCornerShape(10.dp)).clickable { pickupIsMine = true; pickup = null }.padding(6.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Icon(Icons.Filled.MyLocation, null, tint = KJ.blue, modifier = Modifier.size(16.dp))
                        Spacer(Modifier.width(6.dp))
                        Text(state.l("my_position"), color = KJ.blue, fontWeight = FontWeight.Bold, fontSize = 14.sp)
                    }
                }

                Spacer(Modifier.height(18.dp))
                Text(state.l("vehicle"), fontWeight = FontWeight.Bold, color = KJ.inkSoft)
                Spacer(Modifier.height(8.dp))
                Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    VehicleCard(Modifier.weight(1f), state.l("car"), R.drawable.car_hero, vehicle == "car") { vehicle = "car" }
                    VehicleCard(Modifier.weight(1f), state.l("moto"), R.drawable.moto_art, vehicle == "moto") { vehicle = "moto" }
                }

                Spacer(Modifier.height(18.dp))
                PriceBlock(
                    state = state, hasDest = dest != null, routing = routing || quoting, quote = quote,
                    quoteError = quoteError, fare = fare, route = route,
                    onFare = { fare = it }, onRetry = { quoteNonce++ },
                )

                submitError?.let {
                    Spacer(Modifier.height(12.dp))
                    ErrorBanner(it)
                }
                Spacer(Modifier.height(16.dp))
                KJButton(
                    state.l("send_request"),
                    enabled = quote != null && pickup != null && dest != null && route != null,
                    loading = submitting,
                ) {
                    val p = pickup ?: return@KJButton
                    val d = dest ?: return@KJButton
                    val r = route ?: return@KJButton
                    submitting = true
                    submitError = null
                    scope.launch {
                        try {
                            val id = state.api.createRequest(p, d, r.distanceKm, vehicle, fare, state.profile?.city ?: "Alger")
                            state.setActiveRequest(id)
                        } catch (e: Exception) {
                            submitError = state.serverError(e)
                            // If the server says a request is already open, resume it.
                            if ((e.message ?: "").contains("active request", true)) {
                                state.userId?.let { uid -> runCatching { state.api.openPassengerRequest(uid) }.getOrNull()?.let { state.setActiveRequest(it.id) } }
                            }
                        }
                        submitting = false
                    }
                }
                Spacer(Modifier.height(8.dp))
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.Center, verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Filled.Payments, null, tint = KJ.success, modifier = Modifier.size(16.dp))
                    Spacer(Modifier.width(6.dp))
                    Text(state.l("cash_note"), color = KJ.muted, fontSize = 13.sp)
                }
            }
        }

        if (searchFor != null) {
            PlaceSearch(
                state = state,
                near = pickup,
                title = if (searchFor == Field.Pickup) state.l("set_pickup") else state.l("set_destination"),
                onClose = { searchFor = null },
                onPickOnMap = { pickMode = searchFor; searchFor = null },
                onMyLocation = if (searchFor == Field.Pickup && myLoc != null) ({ pickupIsMine = true; pickup = null; searchFor = null }) else null,
                onSelect = { place ->
                    if (searchFor == Field.Pickup) { pickup = place; pickupIsMine = false } else dest = place
                    searchFor = null
                },
            )
        }
    }
}

@Composable
private fun PlaceRow(
    icon: androidx.compose.ui.graphics.vector.ImageVector, tint: Color, label: String, value: String,
    muted: Boolean = false, onClick: () -> Unit, onMap: () -> Unit,
) {
    Row(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp)).clickable(onClick = onClick).padding(10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(icon, null, tint = tint, modifier = Modifier.size(22.dp))
        Spacer(Modifier.width(14.dp))
        Column(Modifier.weight(1f)) {
            Text(label, color = KJ.muted, fontSize = 12.sp)
            Text(value, color = if (muted) KJ.muted else KJ.ink, fontWeight = FontWeight.SemiBold, fontSize = 15.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        IconCircle(Icons.Filled.Map, size = 34.dp, onClick = onMap)
    }
}

@Composable
private fun VehicleCard(modifier: Modifier, title: String, image: Int, selected: Boolean, onClick: () -> Unit) {
    Column(
        modifier.clip(RoundedCornerShape(18.dp)).background(if (selected) KJ.softBlue else Color.White)
            .border(2.dp, if (selected) KJ.blue else KJ.softBlueMid, RoundedCornerShape(18.dp))
            .clickable(onClick = onClick).padding(12.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Image(painterResource(image), null, modifier = Modifier.height(48.dp))
        Spacer(Modifier.height(6.dp))
        Text(title, fontWeight = FontWeight.Bold, color = if (selected) KJ.blue else KJ.ink)
    }
}

@Composable
private fun PriceBlock(
    state: AppState, hasDest: Boolean, routing: Boolean, quote: PassengerQuote?, quoteError: Boolean,
    fare: Int, route: RouteInfo?, onFare: (Int) -> Unit, onRetry: () -> Unit,
) {
    KJCard {
        when {
            !hasDest -> Text(state.l("choose_destination_for_price"), color = KJ.muted)
            routing -> Row(verticalAlignment = Alignment.CenterVertically) {
                CircularProgressIndicator(Modifier.size(18.dp), color = KJ.blue, strokeWidth = 2.dp)
                Spacer(Modifier.width(10.dp))
                Text(state.l("computing_price"), color = KJ.muted)
            }
            quoteError || quote == null -> Row(verticalAlignment = Alignment.CenterVertically) {
                Text(state.l("quote_error"), color = KJ.danger, modifier = Modifier.weight(1f))
                Text(state.l("retry"), color = KJ.blue, fontWeight = FontWeight.Bold,
                    modifier = Modifier.clip(RoundedCornerShape(8.dp)).clickable(onClick = onRetry).padding(6.dp))
            }
            else -> {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(state.l("proposed_price"), color = KJ.inkSoft, fontWeight = FontWeight.Bold, modifier = Modifier.weight(1f))
                    if (route != null) {
                        Text(
                            "${route.distanceKm} ${state.l("km")}" + (route.durationMin?.let { " · $it ${state.l("min")}" } ?: ""),
                            color = KJ.muted, fontSize = 13.sp,
                        )
                    }
                }
                Spacer(Modifier.height(10.dp))
                Row(verticalAlignment = Alignment.CenterVertically) {
                    IconCircle(Icons.Filled.Remove, size = 46.dp, onClick = if (fare > quote.minProposal) ({ onFare((fare - 50).coerceAtLeast(quote.minProposal)) }) else null)
                    Column(Modifier.weight(1f), horizontalAlignment = Alignment.CenterHorizontally) {
                        Text(dzd(fare), style = PriceStyle)
                    }
                    IconCircle(Icons.Filled.Add, size = 46.dp, onClick = if (fare < quote.maxProposal) ({ onFare((fare + 50).coerceAtMost(quote.maxProposal)) }) else null)
                }
                Spacer(Modifier.height(12.dp))
                Box(Modifier.fillMaxWidth().height(1.dp).background(KJ.softBlue))
                Spacer(Modifier.height(10.dp))
                SummaryLine(state.l("estimate"), dzd(quote.estimatedTotal), strike = quote.discount > 0)
                if (quote.discount > 0) SummaryLine(state.l("discount"), "− " + dzd(quote.discount), color = KJ.success)
                SummaryLine(state.l("total"), dzd(quote.total), bold = true)
                if (fare != quote.total) {
                    Spacer(Modifier.height(6.dp))
                    Row(
                        Modifier.clip(RoundedCornerShape(10.dp)).clickable { onFare(quote.total) }.padding(6.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Icon(Icons.Filled.Replay, null, tint = KJ.blue, modifier = Modifier.size(16.dp))
                        Spacer(Modifier.width(6.dp))
                        Text(state.l("use_suggested"), color = KJ.blue, fontWeight = FontWeight.Bold, fontSize = 14.sp)
                    }
                }
                Spacer(Modifier.height(4.dp))
                Text(state.l("price_hint"), color = KJ.muted, fontSize = 12.sp)
            }
        }
    }
}

@Composable
fun SummaryLine(label: String, value: String, strike: Boolean = false, bold: Boolean = false, color: Color = KJ.ink) {
    Row(Modifier.fillMaxWidth().padding(vertical = 3.dp)) {
        Text(label, color = KJ.muted, modifier = Modifier.weight(1f), fontSize = 14.sp)
        Text(
            value, color = if (strike) KJ.muted else color,
            fontWeight = if (bold) FontWeight.ExtraBold else FontWeight.SemiBold,
            fontSize = if (bold) 16.sp else 14.sp,
            textDecoration = if (strike) TextDecoration.LineThrough else null,
        )
    }
}

@Composable
private fun PlaceSearch(
    state: AppState, near: GeoPlace?, title: String,
    onClose: () -> Unit, onPickOnMap: () -> Unit, onMyLocation: (() -> Unit)?, onSelect: (GeoPlace) -> Unit,
) {
    var query by remember { mutableStateOf("") }
    var results by remember { mutableStateOf<List<GeoPlace>>(emptyList()) }
    var searching by remember { mutableStateOf(false) }
    var saved by remember { mutableStateOf<List<app.rork.h04xk59ettzrqz7c6l4wp.data.SavedPlace>>(emptyList()) }
    LaunchedEffect(Unit) { saved = runCatching { state.api.savedPlaces() }.getOrDefault(emptyList()) }
    LaunchedEffect(query) {
        val q = query.trim()
        if (q.length < 3) { results = emptyList(); return@LaunchedEffect }
        delay(450) // debounce; Nominatim allows ~1 req/s
        searching = true
        results = state.geo.search(q, state.language, near)
        searching = false
    }
    Column(Modifier.fillMaxSize().background(KJ.canvas).statusBarsPadding().imePadding().padding(16.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            IconCircle(Icons.AutoMirrored.Filled.ArrowBack, tint = KJ.ink, bg = Color.White, size = 42.dp, onClick = onClose)
            Spacer(Modifier.width(12.dp))
            Text(title, fontSize = 20.sp, fontWeight = FontWeight.ExtraBold, color = KJ.ink)
        }
        Spacer(Modifier.height(14.dp))
        OutlinedTextField(
            value = query, onValueChange = { query = it },
            placeholder = { Text(state.l("search_place")) },
            leadingIcon = { Icon(Icons.Filled.Search, null, tint = KJ.blue) },
            trailingIcon = { if (searching) CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp) },
            singleLine = true,
            shape = RoundedCornerShape(16.dp),
            keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search),
            keyboardActions = KeyboardActions(),
            colors = OutlinedTextFieldDefaults.colors(unfocusedContainerColor = Color.White, focusedContainerColor = Color.White, unfocusedBorderColor = KJ.softBlueMid),
            modifier = Modifier.fillMaxWidth(),
        )
        Spacer(Modifier.height(10.dp))
        if (onMyLocation != null) SearchAction(Icons.Filled.MyLocation, state.l("my_position"), onMyLocation)
        SearchAction(Icons.Filled.Map, state.l("choose_on_map"), onPickOnMap)
        Spacer(Modifier.height(6.dp))
        LazyColumn(Modifier.weight(1f)) {
            if (query.trim().length < 3) {
                items(saved) { p ->
                    Row(
                        Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp)).clickable { onSelect(GeoPlace(p.address, p.lat, p.lng)) }.padding(vertical = 10.dp, horizontal = 8.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        IconCircle(
                            when (p.kind) { "home" -> Icons.Filled.Home; "work" -> Icons.Filled.Work; else -> Icons.Filled.Star },
                            size = 36.dp,
                        )
                        Spacer(Modifier.width(12.dp))
                        Column(Modifier.weight(1f)) {
                            Text(p.label, color = KJ.ink, fontWeight = FontWeight.Bold, fontSize = 15.sp)
                            Text(p.address, color = KJ.muted, fontSize = 12.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        }
                    }
                }
            }
            items(results) { place ->
                Row(
                    Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp)).clickable { onSelect(place) }.padding(vertical = 12.dp, horizontal = 8.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    IconCircle(Icons.Filled.LocationOn, tint = KJ.burgundy, bg = KJ.dangerBg, size = 36.dp)
                    Spacer(Modifier.width(12.dp))
                    Text(place.label, color = KJ.ink, fontSize = 15.sp, maxLines = 2, overflow = TextOverflow.Ellipsis)
                }
            }
            if (!searching && query.trim().length >= 3 && results.isEmpty()) {
                item { Text(state.l("no_results"), color = KJ.muted, modifier = Modifier.padding(12.dp)) }
            }
        }
        Text(state.l("map_attribution"), color = KJ.muted, fontSize = 11.sp)
    }
}

@Composable
private fun SearchAction(icon: androidx.compose.ui.graphics.vector.ImageVector, label: String, onClick: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp)).clickable(onClick = onClick).padding(vertical = 10.dp, horizontal = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(Modifier.size(36.dp).clip(CircleShape).background(KJ.softBlue), contentAlignment = Alignment.Center) {
            Icon(icon, null, tint = KJ.blue, modifier = Modifier.size(18.dp))
        }
        Spacer(Modifier.width(12.dp))
        Text(label, color = KJ.blue, fontWeight = FontWeight.Bold)
    }
}
