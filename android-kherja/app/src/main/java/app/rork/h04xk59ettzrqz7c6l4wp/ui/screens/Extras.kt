package app.rork.h04xk59ettzrqz7c6l4wp.ui.screens

import android.content.Intent
import androidx.activity.compose.BackHandler
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
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.DirectionsCar
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.LocationOn
import androidx.compose.material.icons.filled.Notifications
import androidx.compose.material.icons.filled.NotificationsNone
import androidx.compose.material.icons.filled.Receipt
import androidx.compose.material.icons.filled.Share
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.filled.TwoWheeler
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material.icons.filled.Work
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.rork.h04xk59ettzrqz7c6l4wp.AppState
import app.rork.h04xk59ettzrqz7c6l4wp.data.AppNotification
import app.rork.h04xk59ettzrqz7c6l4wp.data.GeoPlace
import app.rork.h04xk59ettzrqz7c6l4wp.data.NotificationPrefs
import app.rork.h04xk59ettzrqz7c6l4wp.data.RideReceipt
import app.rork.h04xk59ettzrqz7c6l4wp.data.SavedPlace
import app.rork.h04xk59ettzrqz7c6l4wp.data.Vehicle
import app.rork.h04xk59ettzrqz7c6l4wp.ui.components.EmptyState
import app.rork.h04xk59ettzrqz7c6l4wp.ui.components.ErrorBanner
import app.rork.h04xk59ettzrqz7c6l4wp.ui.components.IconCircle
import app.rork.h04xk59ettzrqz7c6l4wp.ui.components.KJButton
import app.rork.h04xk59ettzrqz7c6l4wp.ui.components.KJCard
import app.rork.h04xk59ettzrqz7c6l4wp.ui.components.KJOutlineButton
import app.rork.h04xk59ettzrqz7c6l4wp.ui.components.Pill
import app.rork.h04xk59ettzrqz7c6l4wp.ui.components.PulsingDots
import app.rork.h04xk59ettzrqz7c6l4wp.ui.components.SkeletonList
import app.rork.h04xk59ettzrqz7c6l4wp.ui.components.SectionTitle
import app.rork.h04xk59ettzrqz7c6l4wp.ui.components.dzd
import app.rork.h04xk59ettzrqz7c6l4wp.ui.components.formatDate
import app.rork.h04xk59ettzrqz7c6l4wp.ui.theme.KJ
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.util.Locale

// Sub-pages reachable from Settings / Profile and History. Every action goes through SupabaseApi
// (RLS-protected tables and SECURITY DEFINER RPCs from migration 0010).

@Composable
private fun SubHeader(title: String, subtitle: String? = null, onBack: () -> Unit, trailing: (@Composable () -> Unit)? = null) {
    Column(Modifier.fillMaxWidth().statusBarsPadding().padding(horizontal = 20.dp, vertical = 14.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            IconCircle(Icons.AutoMirrored.Filled.ArrowBack, tint = KJ.ink, bg = Color.White, size = 42.dp, onClick = onBack)
            Spacer(Modifier.width(12.dp))
            Text(title, fontSize = 24.sp, fontWeight = FontWeight.ExtraBold, color = KJ.ink, modifier = Modifier.weight(1f))
            trailing?.invoke()
        }
        if (subtitle != null) {
            Spacer(Modifier.height(6.dp))
            Text(subtitle, color = KJ.muted, fontSize = 14.sp)
        }
    }
}

@Composable
private fun FormField(label: String, value: String, keyboard: KeyboardType = KeyboardType.Text, onChange: (String) -> Unit) {
    OutlinedTextField(
        value = value, onValueChange = onChange, label = { Text(label) }, singleLine = true,
        shape = RoundedCornerShape(14.dp), modifier = Modifier.fillMaxWidth(),
        keyboardOptions = KeyboardOptions(keyboardType = keyboard),
        colors = OutlinedTextFieldDefaults.colors(focusedBorderColor = KJ.blue, unfocusedBorderColor = KJ.softBlueMid),
    )
}

@Composable
private fun ChoiceChip(label: String, selected: Boolean, modifier: Modifier = Modifier, onClick: () -> Unit) {
    Box(
        modifier.clip(RoundedCornerShape(14.dp)).background(if (selected) KJ.blue else Color.White)
            .clickable(onClick = onClick).padding(vertical = 12.dp, horizontal = 10.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(label, color = if (selected) Color.White else KJ.ink, fontWeight = FontWeight.Bold, fontSize = 14.sp)
    }
}

/** Row in the Settings "My space" card. */
@Composable
fun SpaceRow(icon: ImageVector, title: String, subtitle: String, badge: String? = null, onClick: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp)).clickable(onClick = onClick).padding(vertical = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        IconCircle(icon, size = 40.dp)
        Spacer(Modifier.width(12.dp))
        Column(Modifier.weight(1f)) {
            Text(title, color = KJ.ink, fontWeight = FontWeight.Bold, fontSize = 15.sp)
            Text(subtitle, color = KJ.muted, fontSize = 12.sp)
        }
        if (badge != null) {
            Pill(badge, Color.White, KJ.burgundy)
            Spacer(Modifier.width(8.dp))
        }
        Text("›", color = KJ.blue, fontSize = 24.sp, fontWeight = FontWeight.Bold)
    }
}

// ===================== Settings host =====================

/** Settings with sub-pages (saved places, notifications, vehicles). */
@Composable
fun SettingsScreen(state: AppState) {
    var page by remember { mutableStateOf<String?>(null) }
    BackHandler(enabled = page != null) { page = null }
    when (page) {
        "places" -> SavedPlacesScreen(state) { page = null }
        "notifications" -> NotificationsScreen(state) { page = null }
        "vehicles" -> VehiclesScreen(state) { page = null }
        "support" -> SupportScreen(state) { page = null }
        else -> SettingsMain(state) { page = it }
    }
}

@Composable
fun MySpaceCard(state: AppState, onOpen: (String) -> Unit) {
    var unread by remember { mutableStateOf(0) }
    LaunchedEffect(Unit) { runCatching { state.api.unreadNotificationCount() }.onSuccess { unread = it } }
    val driver = state.role == "driver"
    KJCard(Modifier.fillMaxWidth()) {
        if (driver) {
            SpaceRow(Icons.Filled.DirectionsCar, state.l("vehicles_title"), state.l("vehicles_subtitle")) { onOpen("vehicles") }
        } else {
            SpaceRow(Icons.Filled.LocationOn, state.l("places_title"), state.l("places_subtitle")) { onOpen("places") }
        }
        Spacer(Modifier.height(12.dp))
        SpaceRow(
            Icons.Filled.Notifications, state.l("notif_title"), state.l("notif_subtitle"),
            badge = if (unread > 0) unread.toString() else null,
        ) { onOpen("notifications") }
        Spacer(Modifier.height(12.dp))
        SpaceRow(Icons.Filled.Warning, state.l("support_title"), state.l("support_subtitle")) { onOpen("support") }
    }
}

// ===================== Saved places =====================

private fun placeIcon(kind: String): ImageVector = when (kind) {
    "home" -> Icons.Filled.Home
    "work" -> Icons.Filled.Work
    else -> Icons.Filled.Star
}

private fun placeKindLabel(state: AppState, kind: String) = when (kind) {
    "home" -> state.l("place_home")
    "work" -> state.l("place_work")
    else -> state.l("place_favorite")
}

@Composable
fun SavedPlacesScreen(state: AppState, onBack: () -> Unit) {
    val scope = rememberCoroutineScope()
    var places by remember { mutableStateOf<List<SavedPlace>?>(null) }
    var error by remember { mutableStateOf<String?>(null) }
    var adding by remember { mutableStateOf(false) }
    var toDelete by remember { mutableStateOf<SavedPlace?>(null) }

    suspend fun load() {
        runCatching { state.api.savedPlaces() }
            .onSuccess { places = it; error = null }
            .onFailure { error = state.serverError(it); if (places == null) places = emptyList() }
    }
    LaunchedEffect(Unit) { load() }
    BackHandler(enabled = adding) { adding = false }

    if (adding) {
        AddPlaceScreen(state, places.orEmpty(), onBack = { adding = false }) { adding = false; scope.launch { load() } }
        return
    }

    Column(Modifier.fillMaxSize().background(KJ.canvasGradient)) {
        SubHeader(state.l("places_title"), state.l("places_subtitle"), onBack)
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = 20.dp)) {
            error?.let { ErrorBanner(it); Spacer(Modifier.height(10.dp)) }
            when {
                places == null -> Box(Modifier.fillMaxWidth().padding(top = 40.dp), contentAlignment = Alignment.Center) { PulsingDots() }
                places.orEmpty().isEmpty() -> EmptyState(Icons.Filled.LocationOn, state.l("place_none"), state.l("place_none_hint"))
                else -> Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    places.orEmpty().forEach { p ->
                        KJCard(Modifier.fillMaxWidth(), padding = 14.dp) {
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                IconCircle(placeIcon(p.kind), size = 42.dp)
                                Spacer(Modifier.width(12.dp))
                                Column(Modifier.weight(1f)) {
                                    Text(p.label, fontWeight = FontWeight.Bold, color = KJ.ink, fontSize = 16.sp)
                                    Text(p.address, color = KJ.muted, fontSize = 12.sp, maxLines = 2, overflow = TextOverflow.Ellipsis)
                                }
                                IconCircle(Icons.Filled.Delete, tint = KJ.danger, bg = KJ.dangerBg, size = 38.dp) { toDelete = p }
                            }
                        }
                    }
                }
            }
            Spacer(Modifier.height(24.dp))
        }
        Column(Modifier.padding(horizontal = 20.dp, vertical = 12.dp)) {
            KJButton(state.l("place_add"), icon = Icons.Filled.Add) { adding = true }
        }
    }

    toDelete?.let { p ->
        AlertDialog(
            onDismissRequest = { toDelete = null },
            title = { Text(p.label, fontWeight = FontWeight.Bold) },
            text = { Text(p.address, color = KJ.inkSoft) },
            confirmButton = {
                TextButton(onClick = {
                    toDelete = null
                    scope.launch {
                        runCatching { state.api.deleteSavedPlace(p.id) }.onFailure { error = state.serverError(it) }
                        load()
                    }
                }) { Text(state.l("delete_action"), color = KJ.danger) }
            },
            dismissButton = { TextButton(onClick = { toDelete = null }) { Text(state.l("cancel"), color = KJ.blue) } },
            containerColor = Color.White,
        )
    }
}

@Composable
private fun AddPlaceScreen(state: AppState, existing: List<SavedPlace>, onBack: () -> Unit, onSaved: () -> Unit) {
    val scope = rememberCoroutineScope()
    var query by remember { mutableStateOf("") }
    var results by remember { mutableStateOf<List<GeoPlace>>(emptyList()) }
    var searching by remember { mutableStateOf(false) }
    var chosen by remember { mutableStateOf<GeoPlace?>(null) }
    var kind by remember { mutableStateOf("favorite") }
    var label by remember { mutableStateOf("") }
    var saving by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    val hasHome = existing.any { it.kind == "home" }
    val hasWork = existing.any { it.kind == "work" }

    LaunchedEffect(query) {
        val q = query.trim()
        if (q.length < 3 || chosen != null) { results = emptyList(); return@LaunchedEffect }
        delay(450)
        searching = true
        results = state.geo.search(q, state.language, null)
        searching = false
    }

    Column(Modifier.fillMaxSize().background(KJ.canvasGradient).imePadding()) {
        SubHeader(state.l("place_add"), null, onBack)
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = 20.dp)) {
            if (chosen == null) {
                FormField(state.l("search_place"), query) { query = it }
                Spacer(Modifier.height(10.dp))
                results.forEach { place ->
                    Row(
                        Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp)).clickable { chosen = place; label = ""; results = emptyList() }.padding(vertical = 12.dp, horizontal = 8.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        IconCircle(Icons.Filled.LocationOn, tint = KJ.burgundy, bg = KJ.dangerBg, size = 36.dp)
                        Spacer(Modifier.width(12.dp))
                        Text(place.label, color = KJ.ink, fontSize = 15.sp, maxLines = 2, overflow = TextOverflow.Ellipsis)
                    }
                }
                if (!searching && query.trim().length >= 3 && results.isEmpty()) {
                    Text(state.l("no_results"), color = KJ.muted, modifier = Modifier.padding(12.dp))
                }
                Text(state.l("map_attribution"), color = KJ.muted, fontSize = 11.sp, modifier = Modifier.padding(top = 12.dp))
            } else {
                val place = chosen!!
                KJCard(Modifier.fillMaxWidth(), padding = 14.dp) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        IconCircle(Icons.Filled.LocationOn, tint = KJ.burgundy, bg = KJ.dangerBg, size = 40.dp)
                        Spacer(Modifier.width(12.dp))
                        Text(place.label, color = KJ.ink, fontSize = 15.sp, maxLines = 3, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
                    }
                    Spacer(Modifier.height(8.dp))
                    TextButton(onClick = { chosen = null }) { Text(state.l("place_pick_address"), color = KJ.blue) }
                }
                Spacer(Modifier.height(16.dp))
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    listOf("home", "work", "favorite").forEach { k ->
                        val disabled = (k == "home" && hasHome) || (k == "work" && hasWork)
                        ChoiceChip(
                            placeKindLabel(state, k), kind == k,
                            Modifier.weight(1f).alpha(if (disabled) 0.4f else 1f),
                        ) { if (!disabled) kind = k }
                    }
                }
                Spacer(Modifier.height(12.dp))
                FormField(state.l("place_label"), label) { label = it.take(60) }
                error?.let { Spacer(Modifier.height(10.dp)); ErrorBanner(it) }
            }
        }
        if (chosen != null) {
            val finalLabel = label.trim().ifEmpty { if (kind == "favorite") "" else placeKindLabel(state, kind) }
            Column(Modifier.padding(horizontal = 20.dp, vertical = 12.dp)) {
                KJButton(state.l("save"), enabled = finalLabel.isNotEmpty(), loading = saving) {
                    val uid = state.userId ?: return@KJButton
                    val place = chosen ?: return@KJButton
                    saving = true
                    error = null
                    scope.launch {
                        try {
                            state.api.addSavedPlace(uid, kind, finalLabel, place.label, place.lat, place.lng)
                            onSaved()
                        } catch (e: Exception) { error = state.serverError(e) }
                        saving = false
                    }
                }
            }
        }
    }
}

// ===================== Notifications =====================

@Composable
fun NotificationsScreen(state: AppState, onBack: () -> Unit) {
    val scope = rememberCoroutineScope()
    var items by remember { mutableStateOf<List<AppNotification>?>(null) }
    var prefs by remember { mutableStateOf(NotificationPrefs()) }
    var error by remember { mutableStateOf<String?>(null) }

    suspend fun load() {
        runCatching { state.api.notifications() }
            .onSuccess { items = it; error = null }
            .onFailure { error = state.serverError(it); if (items == null) items = emptyList() }
    }
    LaunchedEffect(Unit) {
        load()
        val uid = state.userId ?: return@LaunchedEffect
        runCatching { state.api.notificationPrefs(uid) }.onSuccess { prefs = it }
    }

    fun savePrefs(next: NotificationPrefs) {
        val old = prefs
        prefs = next
        val uid = state.userId ?: return
        scope.launch {
            runCatching { state.api.saveNotificationPrefs(uid, next) }.onFailure { prefs = old; error = state.serverError(it) }
        }
    }

    val unread = items.orEmpty().count { it.isUnread }
    Column(Modifier.fillMaxSize().background(KJ.canvasGradient)) {
        SubHeader(state.l("notif_title"), state.l("notif_subtitle"), onBack)
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = 20.dp)) {
            error?.let { ErrorBanner(it); Spacer(Modifier.height(10.dp)) }
            SectionTitle(state.l("notif_prefs"))
            Spacer(Modifier.height(8.dp))
            KJCard(Modifier.fillMaxWidth()) {
                PrefRow(state.l("notif_pref_rides"), state.l("notif_pref_rides_hint"), prefs.rides) { savePrefs(prefs.copy(rides = it)) }
                Spacer(Modifier.height(12.dp))
                PrefRow(state.l("notif_pref_promos"), state.l("notif_pref_promos_hint"), prefs.promotions) { savePrefs(prefs.copy(promotions = it)) }
            }
            Spacer(Modifier.height(18.dp))
            Row(verticalAlignment = Alignment.CenterVertically) {
                SectionTitle(state.l("notif_title"), Modifier.weight(1f))
                if (unread > 0) {
                    TextButton(onClick = {
                        scope.launch {
                            runCatching { state.api.markAllNotificationsRead() }.onFailure { error = state.serverError(it) }
                            load()
                        }
                    }) { Text(state.l("notif_mark_all"), color = KJ.blue, fontWeight = FontWeight.SemiBold) }
                }
            }
            Spacer(Modifier.height(8.dp))
            when {
                items == null -> SkeletonList(4)
                items.orEmpty().isEmpty() -> EmptyState(Icons.Filled.NotificationsNone, state.l("notif_none"), state.l("notif_none_hint"))
                else -> Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    items.orEmpty().forEach { n ->
                        KJCard(
                            Modifier.fillMaxWidth().clickable(enabled = n.isUnread) {
                                scope.launch { runCatching { state.api.markNotificationRead(n.id) }; load() }
                            },
                            padding = 14.dp,
                        ) {
                            Row(verticalAlignment = Alignment.Top) {
                                IconCircle(
                                    if (n.isUnread) Icons.Filled.Notifications else Icons.Filled.NotificationsNone,
                                    tint = if (n.isUnread) KJ.burgundy else KJ.muted,
                                    bg = if (n.isUnread) KJ.dangerBg else KJ.softBlue, size = 40.dp,
                                )
                                Spacer(Modifier.width(12.dp))
                                Column(Modifier.weight(1f)) {
                                    Text(n.title, fontWeight = if (n.isUnread) FontWeight.ExtraBold else FontWeight.SemiBold, color = KJ.ink, fontSize = 15.sp)
                                    if (n.body.isNotBlank()) Text(n.body, color = KJ.inkSoft, fontSize = 13.sp)
                                    Text(formatDate(n.createdAt, state.language), color = KJ.muted, fontSize = 11.sp)
                                }
                                IconCircle(Icons.Filled.Delete, tint = KJ.muted, bg = Color.Transparent, size = 36.dp) {
                                    scope.launch { runCatching { state.api.deleteNotification(n.id) }; load() }
                                }
                            }
                        }
                    }
                }
            }
            Spacer(Modifier.height(24.dp))
        }
    }
}

@Composable
private fun PrefRow(title: String, hint: String, checked: Boolean, onChange: (Boolean) -> Unit) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f)) {
            Text(title, color = KJ.ink, fontWeight = FontWeight.Bold, fontSize = 15.sp)
            Text(hint, color = KJ.muted, fontSize = 12.sp)
        }
        Switch(
            checked = checked, onCheckedChange = onChange,
            colors = SwitchDefaults.colors(checkedTrackColor = KJ.blue, checkedThumbColor = Color.White),
        )
    }
}

// ===================== Vehicles (driver) =====================

@Composable
fun VehiclesScreen(state: AppState, onBack: () -> Unit) {
    val scope = rememberCoroutineScope()
    var vehicles by remember { mutableStateOf<List<Vehicle>?>(null) }
    var error by remember { mutableStateOf<String?>(null) }
    var editing by remember { mutableStateOf<Vehicle?>(null) }
    var creating by remember { mutableStateOf(false) }
    var toDelete by remember { mutableStateOf<Vehicle?>(null) }

    suspend fun load() {
        val uid = state.userId ?: return
        runCatching { state.api.myVehicles(uid) }
            .onSuccess { vehicles = it; error = null }
            .onFailure { error = state.serverError(it); if (vehicles == null) vehicles = emptyList() }
        state.refreshProfile()
    }
    LaunchedEffect(Unit) { load() }
    BackHandler(enabled = creating || editing != null) { creating = false; editing = null }

    if (creating || editing != null) {
        VehicleForm(state, editing, onBack = { creating = false; editing = null }) {
            creating = false; editing = null
            scope.launch { load() }
        }
        return
    }

    Column(Modifier.fillMaxSize().background(KJ.canvasGradient)) {
        SubHeader(state.l("vehicles_title"), state.l("vehicles_subtitle"), onBack)
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = 20.dp)) {
            error?.let { ErrorBanner(it); Spacer(Modifier.height(10.dp)) }
            when {
                vehicles == null -> Box(Modifier.fillMaxWidth().padding(top = 40.dp), contentAlignment = Alignment.Center) { PulsingDots() }
                vehicles.orEmpty().isEmpty() -> EmptyState(Icons.Filled.DirectionsCar, state.l("veh_none"), state.l("veh_none_hint"))
                else -> Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    vehicles.orEmpty().forEach { v ->
                        KJCard(Modifier.fillMaxWidth(), padding = 16.dp) {
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                IconCircle(if (v.category == "moto") Icons.Filled.TwoWheeler else Icons.Filled.DirectionsCar, size = 44.dp)
                                Spacer(Modifier.width(12.dp))
                                Column(Modifier.weight(1f)) {
                                    Text("${v.make} ${v.model}", fontWeight = FontWeight.ExtraBold, color = KJ.ink, fontSize = 16.sp)
                                    Text(
                                        listOfNotNull(v.plate, v.year?.toString(), v.color.ifBlank { null }).joinToString(" · "),
                                        color = KJ.muted, fontSize = 13.sp,
                                    )
                                }
                            }
                            Spacer(Modifier.height(10.dp))
                            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                                Pill(if (v.category == "moto") state.l("moto") else state.l("car"), KJ.inkSoft, KJ.softBlue)
                                if (v.isPrimary) Pill(state.l("veh_primary"), KJ.success, KJ.successBg, icon = Icons.Filled.CheckCircle)
                                if (v.status == "suspended") Pill(state.l("veh_suspended"), KJ.danger, KJ.dangerBg)
                            }
                            if (v.status == "suspended" && !v.suspendedReason.isNullOrBlank()) {
                                Spacer(Modifier.height(6.dp))
                                Text(v.suspendedReason, color = KJ.danger, fontSize = 12.sp)
                            }
                            Spacer(Modifier.height(12.dp))
                            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                if (!v.isPrimary && v.status == "active") {
                                    KJOutlineButton(state.l("veh_make_primary"), Modifier.weight(1f)) {
                                        scope.launch {
                                            runCatching { state.api.setPrimaryVehicle(v.id) }.onFailure { error = state.serverError(it) }
                                            load()
                                        }
                                    }
                                }
                                KJOutlineButton(state.l("veh_edit"), Modifier.weight(1f)) { editing = v }
                                IconCircle(Icons.Filled.Delete, tint = KJ.danger, bg = KJ.dangerBg, size = 44.dp) { toDelete = v }
                            }
                        }
                    }
                }
            }
            Spacer(Modifier.height(24.dp))
        }
        Column(Modifier.padding(horizontal = 20.dp, vertical = 12.dp)) {
            KJButton(state.l("veh_add"), icon = Icons.Filled.Add) { creating = true }
        }
    }

    toDelete?.let { v ->
        AlertDialog(
            onDismissRequest = { toDelete = null },
            title = { Text(state.l("veh_delete_confirm"), fontWeight = FontWeight.Bold) },
            text = { Text("${v.make} ${v.model} · ${v.plate}", color = KJ.inkSoft) },
            confirmButton = {
                TextButton(onClick = {
                    toDelete = null
                    scope.launch {
                        runCatching { state.api.deleteVehicle(v.id) }.onFailure { error = state.serverError(it) }
                        load()
                    }
                }) { Text(state.l("delete_action"), color = KJ.danger) }
            },
            dismissButton = { TextButton(onClick = { toDelete = null }) { Text(state.l("cancel"), color = KJ.blue) } },
            containerColor = Color.White,
        )
    }
}

@Composable
private fun VehicleForm(state: AppState, vehicle: Vehicle?, onBack: () -> Unit, onSaved: () -> Unit) {
    val scope = rememberCoroutineScope()
    var category by remember { mutableStateOf(vehicle?.category ?: "car") }
    var make by remember { mutableStateOf(vehicle?.make ?: "") }
    var model by remember { mutableStateOf(vehicle?.model ?: "") }
    var year by remember { mutableStateOf(vehicle?.year?.toString() ?: "") }
    var plate by remember { mutableStateOf(vehicle?.plate ?: "") }
    var color by remember { mutableStateOf(vehicle?.color ?: "") }
    var seats by remember { mutableStateOf((vehicle?.seats ?: 4).toString()) }
    var saving by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }

    val yearVal = year.trim().toIntOrNull()
    val seatsVal = seats.trim().toIntOrNull()
    val yearOk = year.isBlank() || (yearVal != null && yearVal in 1990..2100)
    val valid = make.trim().length in 1..40 && model.trim().length in 1..40 && plate.trim().length in 3..20 &&
        yearOk && seatsVal != null && seatsVal in 1..8

    Column(Modifier.fillMaxSize().background(KJ.canvasGradient).imePadding()) {
        SubHeader(if (vehicle == null) state.l("veh_add") else state.l("veh_edit"), null, onBack)
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = 20.dp)) {
            Text(state.l("veh_category"), color = KJ.muted, fontSize = 13.sp)
            Spacer(Modifier.height(6.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                ChoiceChip(state.l("car"), category == "car", Modifier.weight(1f)) { category = "car"; if (seats == "1") seats = "4" }
                ChoiceChip(state.l("moto"), category == "moto", Modifier.weight(1f)) { category = "moto"; seats = "1" }
            }
            Spacer(Modifier.height(12.dp))
            FormField(state.l("vehicle"), make) { make = it.take(40) }
            Spacer(Modifier.height(8.dp))
            FormField(state.l("model"), model) { model = it.take(40) }
            Spacer(Modifier.height(8.dp))
            FormField(state.l("plate"), plate) { plate = it.take(20) }
            Spacer(Modifier.height(8.dp))
            FormField(state.l("color"), color) { color = it.take(30) }
            Spacer(Modifier.height(8.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Box(Modifier.weight(1f)) { FormField(state.l("veh_year"), year, KeyboardType.Number) { year = it.filter(Char::isDigit).take(4) } }
                Box(Modifier.weight(1f)) { FormField(state.l("veh_seats"), seats, KeyboardType.Number) { seats = it.filter(Char::isDigit).take(1) } }
            }
            error?.let { Spacer(Modifier.height(10.dp)); ErrorBanner(it) }
            Spacer(Modifier.height(16.dp))
        }
        Column(Modifier.padding(horizontal = 20.dp, vertical = 12.dp)) {
            KJButton(state.l("save"), enabled = valid, loading = saving) {
                val uid = state.userId ?: return@KJButton
                saving = true
                error = null
                scope.launch {
                    try {
                        if (vehicle == null) {
                            state.api.addVehicle(uid, category, make.trim(), model.trim(), yearVal, plate.trim(), color.trim(), seatsVal ?: 4)
                        } else {
                            state.api.updateVehicle(vehicle.id, category, make.trim(), model.trim(), yearVal, plate.trim(), color.trim(), seatsVal ?: 4)
                        }
                        onSaved()
                    } catch (e: Exception) { error = state.serverError(e) }
                    saving = false
                }
            }
        }
    }
}

// ===================== Receipt =====================

@Composable
fun ReceiptScreen(state: AppState, rideId: String, onBack: () -> Unit) {
    var receipt by remember { mutableStateOf<RideReceipt?>(null) }
    var error by remember { mutableStateOf<String?>(null) }
    var loading by remember { mutableStateOf(true) }
    val context = LocalContext.current
    LaunchedEffect(rideId) {
        loading = true
        runCatching { state.api.rideReceipt(rideId) }
            .onSuccess { receipt = it; error = null }
            .onFailure { error = state.serverError(it) }
        loading = false
    }
    BackHandler { onBack() }

    Column(Modifier.fillMaxSize().background(KJ.canvasGradient)) {
        SubHeader(state.l("receipt_title"), null, onBack)
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = 20.dp)) {
            when {
                loading -> Box(Modifier.fillMaxWidth().padding(top = 40.dp), contentAlignment = Alignment.Center) { PulsingDots() }
                receipt == null -> {
                    error?.let { ErrorBanner(it) }
                    EmptyState(Icons.Filled.Receipt, state.l("receipt_title"), state.l("receipt_unavailable"))
                }
                else -> {
                    val r = receipt!!
                    KJCard(Modifier.fillMaxWidth()) {
                        Text(state.l("receipt_total"), color = KJ.muted, fontSize = 13.sp)
                        Text(dzd(r.fare), fontSize = 34.sp, fontWeight = FontWeight.Black, color = KJ.ink)
                        Spacer(Modifier.height(4.dp))
                        Pill(state.l("completed"), KJ.success, KJ.successBg, icon = Icons.Filled.CheckCircle)
                        Spacer(Modifier.height(16.dp))
                        RouteLines(r.pickupLabel, r.destLabel)
                    }
                    Spacer(Modifier.height(14.dp))
                    KJCard(Modifier.fillMaxWidth()) {
                        ReceiptLine(state.l("receipt_ref"), r.reference)
                        ReceiptLine(state.l("receipt_date"), formatDate(r.completedAt ?: r.createdAt, state.language))
                        r.distanceKm?.let { ReceiptLine(state.l("distance"), String.format(Locale.US, "%.1f %s", it, state.l("km"))) }
                        r.driverName?.takeIf { it.isNotBlank() }?.let { ReceiptLine(state.l("driver"), it) }
                        val car = listOfNotNull(r.vehicleMake, r.vehicleModel).joinToString(" ")
                        if (car.isNotBlank() || !r.vehiclePlate.isNullOrBlank()) {
                            ReceiptLine(state.l("vehicle"), listOf(car, r.vehiclePlate.orEmpty()).filter { it.isNotBlank() }.joinToString(" · "))
                        }
                        ReceiptLine(state.l("receipt_payment"), if (r.payment == "cash") state.l("payment_cash") else r.payment)
                    }
                }
            }
            Spacer(Modifier.height(24.dp))
        }
        receipt?.let { r ->
            Column(Modifier.padding(horizontal = 20.dp, vertical = 12.dp)) {
                KJButton(state.l("receipt_share"), icon = Icons.Filled.Share) {
                    val text = buildString {
                        append("KHERJA · ${state.l("receipt_title")} ${r.reference}\n")
                        append("${r.pickupLabel} → ${r.destLabel}\n")
                        append("${state.l("receipt_total")}: ${dzd(r.fare)}\n")
                        append(formatDate(r.completedAt ?: r.createdAt, state.language))
                    }
                    val send = Intent(Intent.ACTION_SEND).apply { type = "text/plain"; putExtra(Intent.EXTRA_TEXT, text) }
                    context.startActivity(Intent.createChooser(send, state.l("receipt_share")))
                }
            }
        }
    }
}

@Composable
private fun ReceiptLine(label: String, value: String) {
    Row(Modifier.fillMaxWidth().padding(vertical = 6.dp), verticalAlignment = Alignment.Top) {
        Text(label, color = KJ.muted, fontSize = 14.sp, modifier = Modifier.weight(0.4f))
        Text(value, color = KJ.ink, fontSize = 14.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.weight(0.6f))
    }
}
