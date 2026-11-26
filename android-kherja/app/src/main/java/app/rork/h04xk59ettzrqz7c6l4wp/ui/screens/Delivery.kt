package app.rork.h04xk59ettzrqz7c6l4wp.ui.screens

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.rork.h04xk59ettzrqz7c6l4wp.AppState
import app.rork.h04xk59ettzrqz7c6l4wp.data.DeliveryOrder
import app.rork.h04xk59ettzrqz7c6l4wp.data.GeoPlace
import app.rork.h04xk59ettzrqz7c6l4wp.ui.components.ErrorBanner
import app.rork.h04xk59ettzrqz7c6l4wp.ui.components.KJButton
import app.rork.h04xk59ettzrqz7c6l4wp.ui.components.KJCard
import app.rork.h04xk59ettzrqz7c6l4wp.ui.components.OsmMap
import app.rork.h04xk59ettzrqz7c6l4wp.ui.components.MapPin
import app.rork.h04xk59ettzrqz7c6l4wp.ui.components.PinKind
import app.rork.h04xk59ettzrqz7c6l4wp.ui.theme.KJ
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

@Composable
fun DeliveryScreen(state: AppState, driver: Boolean) {
    val scope = rememberCoroutineScope()
    val location by state.location.location.collectAsState()
    var pickup by remember { mutableStateOf<GeoPlace?>(null) }
    var destinationQuery by remember { mutableStateOf("") }
    var destination by remember { mutableStateOf<GeoPlace?>(null) }
    var suggestions by remember { mutableStateOf<List<GeoPlace>>(emptyList()) }
    var routeKm by remember { mutableStateOf<Double?>(null) }
    var vehicle by remember { mutableStateOf("moto") }
    var description by remember { mutableStateOf("") }
    var recipient by remember { mutableStateOf("") }
    var phone by remember { mutableStateOf("") }
    var note by remember { mutableStateOf("") }
    var fee by remember { mutableStateOf<Int?>(null) }
    var orders by remember { mutableStateOf<List<DeliveryOrder>>(emptyList()) }
    var openOrders by remember { mutableStateOf<List<DeliveryOrder>>(emptyList()) }
    var busy by remember { mutableStateOf(false) }
    var loading by remember { mutableStateOf(true) }
    var error by remember { mutableStateOf<String?>(null) }
    var info by remember { mutableStateOf<String?>(null) }

    val permission = rememberLauncherForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) { result ->
        if (result.values.any { it }) state.location.start()
        else error = state.l("location_needed")
    }

    LaunchedEffect(Unit) {
        if (!state.location.hasPermission()) permission.launch(arrayOf(android.Manifest.permission.ACCESS_FINE_LOCATION, android.Manifest.permission.ACCESS_COARSE_LOCATION))
        else state.location.start()
    }
    LaunchedEffect(location) {
        val loc = location ?: return@LaunchedEffect
        if (pickup == null) {
            val label = state.geo.reverse(loc.latitude, loc.longitude, state.language) ?: state.l("my_position")
            pickup = GeoPlace(label, loc.latitude, loc.longitude)
        }
    }
    LaunchedEffect(destination, pickup, driver) {
        val p = pickup
        val d = destination
        if (!driver && p != null && d != null) {
            val route = runCatching { state.geo.route(p, d) }.getOrNull()
            routeKm = route?.distanceKm
            fee = if (route != null) runCatching { state.api.quoteDelivery(p, d, route.distanceKm, vehicle).deliveryFee }.getOrNull() else null
        }
    }
    LaunchedEffect(vehicle, routeKm) {
        val p = pickup
        val d = destination
        val km = routeKm
        if (!driver && p != null && d != null && km != null) {
            fee = runCatching { state.api.quoteDelivery(p, d, km, vehicle).deliveryFee }.getOrNull()
        }
    }
    LaunchedEffect(driver, state.userId) {
        while (true) {
            if (driver) {
                orders = runCatching { state.api.myDeliveryOrders() }.getOrDefault(emptyList())
                openOrders = if (state.profile?.isOnline == true) runCatching { state.api.openDeliveryOrders() }.getOrDefault(emptyList()) else emptyList()
            } else {
                orders = runCatching { state.api.myDeliveryOrders() }.getOrDefault(emptyList())
            }
            loading = false
            delay(6000)
        }
    }

    val active = orders.firstOrNull { it.status in if (driver) listOf("accepted", "picked_up") else listOf("open", "accepted", "picked_up") }

    LazyColumn(
        modifier = Modifier.fillMaxSize().background(KJ.canvas).padding(horizontal = 16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        item {
            Spacer(Modifier.height(12.dp))
            Text(state.l("delivery_title"), fontSize = 25.sp, fontWeight = FontWeight.ExtraBold, color = KJ.ink)
            Text(state.l(if (driver) "delivery_driver_hint" else "delivery_passenger_hint"), fontSize = 13.sp, color = KJ.muted)
            Spacer(Modifier.height(8.dp))
            error?.let { ErrorBanner(it) }
            info?.let { Text(it, color = KJ.success, fontWeight = FontWeight.SemiBold) }
        }

        if (!driver && active == null) {
            item {
                KJCard {
                    Text(state.l("delivery_pickup"), fontWeight = FontWeight.Bold, color = KJ.ink)
                    Text(pickup?.label ?: state.l("delivery_wait_location"), color = KJ.muted, fontSize = 13.sp)
                    OutlinedTextField(
                        value = destinationQuery, onValueChange = { destinationQuery = it; destination = null; fee = null },
                        modifier = Modifier.fillMaxWidth(), label = { Text(state.l("delivery_destination")) },
                        singleLine = true,
                    )
                    Button(onClick = {
                        if (destinationQuery.trim().length >= 3) scope.launch {
                            busy = true
                            suggestions = state.geo.search(destinationQuery, state.language, pickup)
                            busy = false
                        }
                    }, enabled = !busy && destinationQuery.trim().length >= 3) { Text(state.l("delivery_search")) }
                    if (busy) CircularProgressIndicator()
                    suggestions.forEach { place ->
                        Text(
                            place.label, modifier = Modifier.fillMaxWidth().padding(vertical = 6.dp)
                                .background(Color.White, RoundedCornerShape(10.dp)).padding(10.dp)
                                .then(Modifier),
                            color = KJ.ink,
                        )
                        Button(onClick = { destination = place; destinationQuery = place.label; suggestions = emptyList() }) {
                            Text(state.l("delivery_select"))
                        }
                    }
                    destination?.let { d ->
                        Text("${state.l("delivery_destination")}: ${d.label}", color = KJ.ink, fontWeight = FontWeight.SemiBold)
                        pickup?.let { p ->
                            OsmMap(
                                modifier = Modifier.fillMaxWidth().height(180.dp),
                                pins = listOf(MapPin(p.lat, p.lng, PinKind.Pickup), MapPin(d.lat, d.lng, PinKind.Destination)),
                            )
                        }
                    }
                }
            }
            item {
                KJCard {
                    Text(state.l("delivery_package"), fontWeight = FontWeight.Bold, color = KJ.ink)
                    OutlinedTextField(description, { description = it.take(300) }, modifier = Modifier.fillMaxWidth(), label = { Text(state.l("delivery_package_hint")) })
                    OutlinedTextField(recipient, { recipient = it.take(100) }, modifier = Modifier.fillMaxWidth(), label = { Text(state.l("delivery_recipient")) }, singleLine = true)
                    OutlinedTextField(phone, { phone = it.take(20) }, modifier = Modifier.fillMaxWidth(), label = { Text(state.l("delivery_phone")) }, singleLine = true)
                    OutlinedTextField(note, { note = it.take(300) }, modifier = Modifier.fillMaxWidth(), label = { Text(state.l("delivery_note")) })
                }
            }
            item {
                KJCard {
                    Text(state.l("delivery_vehicle"), fontWeight = FontWeight.Bold, color = KJ.ink)
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Button(onClick = { vehicle = "moto" }) { Text(if (vehicle == "moto") "✓ Moto" else "Moto") }
                        Button(onClick = { vehicle = "car" }) { Text(if (vehicle == "car") "✓ Car" else "Car") }
                    }
                    Text(state.l("delivery_cash_only"), color = KJ.muted, fontSize = 13.sp)
                    fee?.let { Text("${state.l("delivery_fee")}: $it DZD", fontSize = 20.sp, fontWeight = FontWeight.ExtraBold, color = KJ.blue) }
                    KJButton(
                        text = state.l("delivery_create"), enabled = !busy && pickup != null && destination != null &&
                            description.trim().length >= 2 && recipient.trim().length >= 2 && phone.filter { it.isDigit() }.length >= 8 && fee != null,
                        loading = busy,
                    ) {
                        scope.launch {
                            busy = true; error = null; info = null
                            try {
                                val p = pickup!!; val d = destination!!; val km = routeKm ?: state.geo.route(p, d).distanceKm
                                state.api.createDeliveryOrder(p, d, km, vehicle, description.trim(), recipient.trim(), phone.trim(), note.trim().ifBlank { null }, state.profile?.city ?: "Alger")
                                info = state.l("delivery_created")
                                destination = null; destinationQuery = ""; suggestions = emptyList()
                                orders = state.api.myDeliveryOrders()
                            } catch (e: Exception) { error = state.serverError(e) }
                            busy = false
                        }
                    }
                }
            }
        }

        if (driver && !loading && active == null && openOrders.isEmpty()) {
            item { KJCard { Text(state.l(if (state.profile?.isOnline == true) "delivery_no_orders" else "go_online_first"), color = KJ.muted) } }
        }

        if (driver && active == null) {
            items(openOrders, key = { it.id }) { order ->
                KJCard {
                    Text("${order.pickupLabel} → ${order.destLabel}", fontWeight = FontWeight.Bold, color = KJ.ink)
                    Text(order.packageDescription, color = KJ.muted)
                    Text("${order.distanceKm} km · ${order.deliveryFee} DZD · ${order.vehicle}", color = KJ.blue, fontWeight = FontWeight.Bold)
                    KJButton(state.l("delivery_accept"), enabled = !busy, loading = busy) {
                        scope.launch {
                            busy = true; error = null
                            try { state.api.claimDeliveryOrder(order.id); orders = state.api.myDeliveryOrders(); openOrders = state.api.openDeliveryOrders() }
                            catch (e: Exception) { error = state.serverError(e) }
                            busy = false
                        }
                    }
                }
            }
        }

        active?.let { order ->
            item {
                KJCard {
                    Text(state.l("delivery_active"), fontWeight = FontWeight.Bold, color = KJ.ink)
                    Text("${order.pickupLabel} → ${order.destLabel}", color = KJ.ink)
                    Text(order.packageDescription, color = KJ.muted)
                    Text("${order.recipientName} · ${order.recipientPhone}", color = KJ.ink, fontWeight = FontWeight.SemiBold)
                    Text("${order.deliveryFee} DZD · ${state.l("delivery_cash_only")}", color = KJ.blue, fontWeight = FontWeight.Bold)
                    if (driver && order.status == "accepted") {
                        KJButton(state.l("delivery_picked_up"), enabled = !busy, loading = busy) {
                            scope.launch { busy = true; runCatching { state.api.updateDeliveryStatus(order.id, "picked_up") }.onFailure { error = state.serverError(it) }; orders = state.api.myDeliveryOrders(); busy = false }
                        }
                    } else if (driver && order.status == "picked_up") {
                        KJButton(state.l("delivery_delivered"), enabled = !busy, loading = busy) {
                            scope.launch { busy = true; runCatching { state.api.updateDeliveryStatus(order.id, "delivered") }.onFailure { error = state.serverError(it) }; orders = state.api.myDeliveryOrders(); busy = false }
                        }
                    } else if (!driver && order.status == "open") {
                        KJButton(state.l("delivery_cancel"), enabled = !busy, loading = busy, brush = androidx.compose.ui.graphics.SolidColor(KJ.burgundy)) {
                            scope.launch { busy = true; runCatching { state.api.cancelDeliveryOrder(order.id) }.onFailure { error = state.serverError(it) }; orders = state.api.myDeliveryOrders(); busy = false }
                        }
                    }
                    Text(state.l("delivery_status_${order.status}"), color = KJ.muted, fontSize = 13.sp)
                }
            }
        }

        if (!loading && orders.isEmpty() && !driver) {
            item { KJCard { Text(state.l("delivery_empty"), color = KJ.muted) } }
        }
        if (loading) item { CircularProgressIndicator() }
        item { Spacer(Modifier.height(20.dp)) }
    }
}
