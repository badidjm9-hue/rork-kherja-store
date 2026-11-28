package app.rork.h04xk59ettzrqz7c6l4wp.ui.screens

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.CallMade
import androidx.compose.material.icons.automirrored.filled.CallReceived
import androidx.compose.material.icons.automirrored.filled.Logout
import androidx.compose.material.icons.filled.AccountBalanceWallet
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.DirectionsCar
import androidx.compose.material.icons.filled.History
import androidx.compose.material.icons.filled.Payments
import androidx.compose.material.icons.filled.TwoWheeler
import androidx.compose.material3.Icon
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.TextButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.rork.h04xk59ettzrqz7c6l4wp.AppState
import app.rork.h04xk59ettzrqz7c6l4wp.data.Ride
import app.rork.h04xk59ettzrqz7c6l4wp.data.DriverDocument
import app.rork.h04xk59ettzrqz7c6l4wp.data.Transaction
import app.rork.h04xk59ettzrqz7c6l4wp.data.jsonOf
import app.rork.h04xk59ettzrqz7c6l4wp.ui.components.Avatar
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
import kotlinx.coroutines.launch
import java.util.Locale

@Composable
private fun ScreenHeader(title: String, subtitle: String? = null) {
    Column(Modifier.fillMaxWidth().statusBarsPadding().padding(horizontal = 20.dp, vertical = 14.dp)) {
        Text(title, fontSize = 28.sp, fontWeight = FontWeight.ExtraBold, color = KJ.ink)
        if (subtitle != null) Text(subtitle, color = KJ.muted, fontSize = 14.sp)
    }
}

// ===================== History =====================

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun HistoryScreen(state: AppState, driver: Boolean) {
    val scope = rememberCoroutineScope()
    var rides by remember { mutableStateOf<List<Ride>?>(null) }
    var error by remember { mutableStateOf<String?>(null) }
    var refreshing by remember { mutableStateOf(false) }
    var filter by remember { mutableStateOf("all") }
    var receiptRideId by remember { mutableStateOf<String?>(null) }

    suspend fun load() {
        val uid = state.userId ?: return
        runCatching { state.api.myRides(uid, driver) }
            .onSuccess { rides = it; error = null }
            .onFailure { error = state.serverError(it); if (rides == null) rides = emptyList() }
    }
    LaunchedEffect(driver) { load() }

    receiptRideId?.let { id ->
        ReceiptScreen(state, id) { receiptRideId = null }
        return
    }

    val filtered = rides.orEmpty().filter {
        when (filter) {
            "completed" -> it.status == "completed"
            "in_progress" -> it.isActive
            "cancelled" -> it.status == "cancelled"
            else -> true
        }
    }

    Column(Modifier.fillMaxSize().background(KJ.canvasGradient)) {
        ScreenHeader(state.l("my_trips"), state.l("trips_subtitle"))
        Row(
            Modifier.horizontalScroll(rememberScrollState()).padding(horizontal = 20.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            listOf("all", "completed", "in_progress", "cancelled").forEach { f ->
                val sel = filter == f
                Text(
                    state.l(f), color = if (sel) Color.White else KJ.inkSoft, fontWeight = FontWeight.SemiBold, fontSize = 14.sp,
                    modifier = Modifier.clip(RoundedCornerShape(50)).background(if (sel) KJ.blue else Color.White)
                        .clickable { filter = f }.padding(horizontal = 16.dp, vertical = 9.dp),
                )
            }
        }
        Spacer(Modifier.height(8.dp))
        error?.let { ErrorBanner(it, Modifier.padding(horizontal = 20.dp)) }
        PullToRefreshBox(
            isRefreshing = refreshing,
            onRefresh = { refreshing = true; scope.launch { load(); refreshing = false } },
            modifier = Modifier.weight(1f).fillMaxWidth(),
        ) {
            when {
                rides == null -> SkeletonList(4, Modifier.padding(20.dp))
                filtered.isEmpty() -> LazyColumn(Modifier.fillMaxSize()) {
                    item { Box(Modifier.fillMaxWidth().padding(top = 60.dp), contentAlignment = Alignment.Center) { EmptyState(Icons.Filled.History, state.l("no_trips"), state.l("no_trips_hint")) } }
                }
                else -> LazyColumn(
                    Modifier.fillMaxSize(),
                    contentPadding = PaddingValues(horizontal = 20.dp, vertical = 10.dp),
                    verticalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    items(filtered, key = { it.id }) { RideRow(state, it, driver) { receiptRideId = it.id } }
                }
            }
        }
    }
}

@Composable
private fun RideRow(state: AppState, ride: Ride, driver: Boolean, onReceipt: () -> Unit) {
    val (label, fg, bg) = when {
        ride.status == "completed" -> Triple(state.l("completed"), KJ.success, KJ.successBg)
        ride.status == "cancelled" -> Triple(state.l("cancelled"), KJ.danger, KJ.dangerBg)
        else -> Triple(state.l("in_progress"), KJ.blue, KJ.softBlue)
    }
    KJCard(Modifier.fillMaxWidth().clickable(enabled = ride.status == "completed", onClick = onReceipt), padding = 16.dp) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            IconCircle(if (ride.vehicle == "moto") Icons.Filled.TwoWheeler else Icons.Filled.DirectionsCar, size = 40.dp)
            Spacer(Modifier.width(10.dp))
            Column(Modifier.weight(1f)) {
                Text(formatDate(ride.createdAt, state.language), color = KJ.muted, fontSize = 12.sp)
                Pill(label, fg, bg)
            }
            Column(horizontalAlignment = Alignment.End) {
                Text(dzd(ride.fare), fontWeight = FontWeight.Black, fontSize = 18.sp, color = KJ.ink)
                if (driver && ride.driverNet != null && ride.status == "completed") {
                    Text("${state.l("net_earning")} ${dzd(ride.driverNet)}", color = KJ.success, fontSize = 12.sp, fontWeight = FontWeight.SemiBold)
                }
            }
        }
        Spacer(Modifier.height(12.dp))
        RouteLines(ride.pickupLabel, ride.destLabel)
        ride.distanceKm?.let {
            Spacer(Modifier.height(8.dp))
            Text(String.format(Locale.US, "%.1f %s", it, state.l("km")), color = KJ.muted, fontSize = 12.sp)
        }
        if (ride.status == "completed") {
            Spacer(Modifier.height(8.dp))
            Text(state.l("receipt_view") + " ›", color = KJ.blue, fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
        }
    }
}

// ===================== Wallet =====================

private fun txLabel(state: AppState, kind: String): String = when (kind) {
    "earning" -> state.l("earnings")
    "commission" -> state.l("commission")
    "payment" -> state.l("payment")
    "refund" -> state.l("refund")
    "bonus" -> state.l("bonus")
    "adjustment" -> state.l("adjustment")
    "withdrawal" -> state.l("withdrawal")
    "topup" -> state.l("topup")
    else -> kind
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun WalletScreen(state: AppState, driver: Boolean) {
    val scope = rememberCoroutineScope()
    var txs by remember { mutableStateOf<List<Transaction>?>(null) }
    var error by remember { mutableStateOf<String?>(null) }
    var refreshing by remember { mutableStateOf(false) }

    suspend fun load() {
        val uid = state.userId ?: return
        runCatching { state.api.transactions(uid) }
            .onSuccess { txs = it; error = null }
            .onFailure { error = state.serverError(it); if (txs == null) txs = emptyList() }
    }
    LaunchedEffect(driver) { load() }

    val balance = txs.orEmpty().sumOf { it.amount }

    PullToRefreshBox(
        isRefreshing = refreshing,
        onRefresh = { refreshing = true; scope.launch { load(); refreshing = false } },
        modifier = Modifier.fillMaxSize().background(KJ.canvasGradient),
    ) {
        LazyColumn(
            Modifier.fillMaxSize(),
            contentPadding = PaddingValues(bottom = 24.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            item { ScreenHeader(if (driver) state.l("tab_earnings") else state.l("my_wallet"), state.l("wallet_subtitle")) }
            item {
                Column(
                    Modifier.padding(horizontal = 20.dp).fillMaxWidth().clip(RoundedCornerShape(26.dp))
                        .background(if (driver) KJ.buttonGradient else KJ.burgundyGradient).padding(22.dp),
                ) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Icon(Icons.Filled.AccountBalanceWallet, null, tint = Color.White.copy(alpha = 0.85f), modifier = Modifier.size(20.dp))
                        Spacer(Modifier.width(8.dp))
                        Text(if (driver) state.l("total_earnings") else state.l("total_paid"), color = Color.White.copy(alpha = 0.85f), fontWeight = FontWeight.SemiBold)
                    }
                    Spacer(Modifier.height(8.dp))
                    Text(dzd(kotlin.math.abs(balance)), color = Color.White, fontSize = 36.sp, fontWeight = FontWeight.Black)
                    Spacer(Modifier.height(10.dp))
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Icon(Icons.Filled.Payments, null, tint = Color.White, modifier = Modifier.size(16.dp))
                        Spacer(Modifier.width(6.dp))
                        Text(state.l("cash_note"), color = Color.White.copy(alpha = 0.9f), fontSize = 12.sp)
                    }
                }
            }
            item {
                Column(Modifier.padding(horizontal = 20.dp)) {
                    Spacer(Modifier.height(6.dp))
                    SectionTitle(state.l("transactions"))
            error?.let {
                        Spacer(Modifier.height(8.dp))
                        ErrorBanner(it)
                    }
                }
            }
            val list = txs
            when {
                list == null -> item { SkeletonList(3) }
                list.isEmpty() -> item {
                    Box(Modifier.fillMaxWidth().padding(top = 30.dp), contentAlignment = Alignment.Center) {
                        EmptyState(Icons.Filled.AccountBalanceWallet, state.l("no_transactions"))
                    }
                }
                else -> items(list, key = { it.id }) { tx -> TxRow(state, tx) }
            }
        }
    }
}

@Composable
private fun TxRow(state: AppState, tx: Transaction) {
    val credit = tx.amount >= 0
    Row(
        Modifier.padding(horizontal = 20.dp).fillMaxWidth().clip(RoundedCornerShape(18.dp)).background(Color.White).padding(14.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        IconCircle(
            if (credit) Icons.AutoMirrored.Filled.CallReceived else Icons.AutoMirrored.Filled.CallMade,
            tint = if (credit) KJ.success else KJ.danger, bg = if (credit) KJ.successBg else KJ.dangerBg, size = 42.dp,
        )
        Spacer(Modifier.width(12.dp))
        Column(Modifier.weight(1f)) {
            Text(tx.label?.ifBlank { null } ?: txLabel(state, tx.kind), fontWeight = FontWeight.SemiBold, color = KJ.ink, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Text(formatDate(tx.createdAt, state.language), color = KJ.muted, fontSize = 12.sp)
        }
        Text(
            (if (credit) "+ " else "− ") + dzd(kotlin.math.abs(tx.amount)),
            color = if (credit) KJ.success else KJ.danger, fontWeight = FontWeight.Bold,
        )
    }
}

// ===================== Settings / profile =====================

@Composable
internal fun SettingsMain(state: AppState, onOpen: (String) -> Unit) {
    val scope = rememberCoroutineScope()
    val p = state.profile
    val driver = state.role == "driver"
    var name by remember(p?.id) { mutableStateOf(p?.name ?: "") }
    var city by remember(p?.id) { mutableStateOf(p?.city ?: "Alger") }
    var make by remember(p?.id) { mutableStateOf(p?.vehicleMake ?: "") }
    var model by remember(p?.id) { mutableStateOf(p?.vehicleModel ?: "") }
    var plate by remember(p?.id) { mutableStateOf(p?.vehiclePlate ?: "") }
    var color by remember(p?.id) { mutableStateOf(p?.vehicleColor ?: "") }
    var saving by remember { mutableStateOf(false) }
    var saved by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var infoPage by remember { mutableStateOf<String?>(null) }
    var documents by remember { mutableStateOf<List<DriverDocument>>(emptyList()) }
    var documentsLoading by remember { mutableStateOf(false) }
    var uploadingDoc by remember { mutableStateOf<String?>(null) }
    var documentError by remember { mutableStateOf<String?>(null) }
    var pendingDocType by remember { mutableStateOf<String?>(null) }
    var confirmDelete by remember { mutableStateOf(false) }
    var deleting by remember { mutableStateOf(false) }
    val context = LocalContext.current

    suspend fun loadDocuments() {
        val id = state.userId ?: return
        documentsLoading = true
        runCatching { state.api.myDriverDocuments(id) }
            .onSuccess { documents = it; documentError = null }
            .onFailure { documentError = state.serverError(it) }
        documentsLoading = false
    }

    val documentPicker = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        val type = pendingDocType
        pendingDocType = null
        if (uri != null && type != null) {
            val mime = context.contentResolver.getType(uri) ?: ""
            if (mime !in setOf("image/jpeg", "image/png", "image/heic", "application/pdf")) {
                documentError = if (state.isRtl) "نوع الملف غير مدعوم. اختر صورة أو PDF." else "Format non pris en charge. Choisissez une image ou un PDF."
                return@rememberLauncherForActivityResult
            }
            val extension = when (mime) {
                "image/png" -> "png"
                "image/heic" -> "heic"
                "application/pdf" -> "pdf"
                else -> "jpg"
            }
            scope.launch {
                uploadingDoc = type
                documentError = null
                try {
                    val bytes = context.contentResolver.openInputStream(uri)?.use { it.readBytes() } ?: error("Cannot read file")
                    state.api.uploadDriverDocument(state.userId ?: error("Session required"), type, bytes, mime, extension)
                    loadDocuments()
                } catch (e: Exception) { documentError = state.serverError(e) }
                uploadingDoc = null
            }
        }
    }

    LaunchedEffect(Unit) { state.refreshProfile(); if (driver) loadDocuments() }

    val dirty = p != null && (name.trim() != p.name || city != p.city ||
        (driver && (make.trim() != (p.vehicleMake ?: "") || model.trim() != (p.vehicleModel ?: "") ||
            plate.trim() != (p.vehiclePlate ?: "") || color.trim() != (p.vehicleColor ?: ""))))

    Column(
        Modifier.fillMaxSize().background(KJ.canvasGradient).imePadding().verticalScroll(rememberScrollState()),
    ) {
        ScreenHeader(if (driver) state.l("tab_profile") else state.l("settings"))
        Column(Modifier.padding(horizontal = 20.dp)) {
            KJCard(Modifier.fillMaxWidth()) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Avatar(p?.name ?: "K", size = 60.dp)
                    Spacer(Modifier.width(14.dp))
                    Column(Modifier.weight(1f)) {
                        Text(p?.name ?: "", fontSize = 20.sp, fontWeight = FontWeight.ExtraBold, color = KJ.ink)
                        Text(if (driver) state.l("driver") else state.l("passenger"), color = KJ.muted, fontSize = 13.sp)
                        if (driver && p?.driverStatus == "approved") {
                            Spacer(Modifier.height(4.dp))
                            Pill(state.l("secured"), KJ.success, KJ.successBg, icon = Icons.Filled.CheckCircle)
                        }
                    }
                }
                Spacer(Modifier.height(14.dp))
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    StatTile(Modifier.weight(1f), String.format(Locale.US, "%.1f ★", p?.ratingAvg ?: 0.0), state.l("my_rating"))
                    StatTile(Modifier.weight(1f), "${p?.tripsCount ?: 0}", state.l("trips"))
                }
            }

            if (driver) {
                Spacer(Modifier.height(18.dp))
                SectionTitle(if (state.isRtl) "وثائق السائق" else "Documents du chauffeur")
                Spacer(Modifier.height(6.dp))
                Text(if (state.isRtl) "ارفع صوراً واضحة للوثائق المطلوبة. الحد الأقصى 10 ميغابايت للصورة." else "Ajoutez des photos lisibles des pièces requises. 10 Mo maximum par fichier.", color = KJ.muted, fontSize = 12.sp)
                Spacer(Modifier.height(8.dp))
                KJCard(Modifier.fillMaxWidth()) {
                    val requiredDocs = listOf(
                        "id_card" to (if (state.isRtl) "بطاقة التعريف" else "Carte d’identité"),
                        "license" to (if (state.isRtl) "رخصة السياقة" else "Permis de conduire"),
                        "registration" to (if (state.isRtl) "البطاقة الرمادية" else "Carte grise"),
                        "insurance" to (if (state.isRtl) "التأمين" else "Assurance"),
                        "vehicle_photo" to (if (state.isRtl) "صورة المركبة" else "Photo du véhicule"),
                    )
                    requiredDocs.forEachIndexed { index, pair ->
                        val type = pair.first
                        val label = pair.second
                        val doc = documents.firstOrNull { it.docType == type }
                        val status = doc?.status ?: "missing"
                        val statusLabel = when (status) {
                            "approved" -> if (state.isRtl) "مقبولة" else "Approuvée"
                            "rejected" -> if (state.isRtl) "مرفوضة" else "Refusée"
                            "pending" -> if (state.isRtl) "قيد المراجعة" else "En vérification"
                            else -> if (state.isRtl) "لم تُرفع" else "Non envoyée"
                        }
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Column(Modifier.weight(1f)) {
                                Text(label, color = KJ.ink, fontWeight = FontWeight.Bold, fontSize = 14.sp)
                                Text(statusLabel, color = when (status) { "approved" -> KJ.success; "rejected" -> KJ.danger; else -> KJ.muted }, fontSize = 12.sp, fontWeight = FontWeight.SemiBold)
                                if (status == "rejected" && !doc?.reason.isNullOrBlank()) Text(doc?.reason.orEmpty(), color = KJ.danger, fontSize = 11.sp)
                            }
                            if (status != "approved") {
                                KJOutlineButton(if (uploadingDoc == type) (if (state.isRtl) "جارٍ..." else "Envoi…") else if (state.isRtl) "إضافة" else "Ajouter", enabled = uploadingDoc == null) {
                                    pendingDocType = type
                                    documentPicker.launch(arrayOf("image/jpeg", "image/png", "image/heic", "application/pdf"))
                                }
                            } else Pill(statusLabel, KJ.success, KJ.successBg, icon = Icons.Filled.CheckCircle)
                        }
                        if (index != requiredDocs.lastIndex) { Spacer(Modifier.height(12.dp)); androidx.compose.material3.HorizontalDivider(color = KJ.softBlueMid); Spacer(Modifier.height(12.dp)) }
                    }
                    if (documentsLoading) { Spacer(Modifier.height(8.dp)); PulsingDots() }
                    documentError?.let { Spacer(Modifier.height(8.dp)); ErrorBanner(it) }
                    Spacer(Modifier.height(8.dp))
                    Text(if (state.isRtl) "تبقى الموافقة النهائية من الإدارة بعد مراجعة جميع الوثائق." else "L’approbation finale reste soumise à la vérification de tous les documents par l’administration.", color = KJ.muted, fontSize = 11.sp)
                }
            }

            Spacer(Modifier.height(18.dp))
            SectionTitle(state.l("my_space"))
            Spacer(Modifier.height(8.dp))
            MySpaceCard(state, onOpen)

            Spacer(Modifier.height(18.dp))
            SectionTitle(state.l("summary"))
            Spacer(Modifier.height(8.dp))
            KJCard(Modifier.fillMaxWidth()) {
                Field(state.l("name"), name) { name = it.take(60) }
                Spacer(Modifier.height(10.dp))
                Text(state.l("city"), color = KJ.muted, fontSize = 13.sp)
                Spacer(Modifier.height(6.dp))
                CityGrid(selected = city) { city = it }
            }

            if (driver) {
                Spacer(Modifier.height(18.dp))
                SectionTitle(state.l("my_vehicle"))
                Spacer(Modifier.height(8.dp))
                KJCard(Modifier.fillMaxWidth()) {
                    Field(state.l("vehicle"), make) { make = it.take(40) }
                    Spacer(Modifier.height(8.dp))
                    Field(state.l("model"), model) { model = it.take(40) }
                    Spacer(Modifier.height(8.dp))
                    Field(state.l("plate"), plate) { plate = it.take(20) }
                    Spacer(Modifier.height(8.dp))
                    Field(state.l("color"), color) { color = it.take(30) }
                }
            }

            error?.let {
                Spacer(Modifier.height(10.dp))
                ErrorBanner(it)
            }
            if (saved && !dirty) {
                Spacer(Modifier.height(10.dp))
                Pill(state.l("profile_saved"), KJ.success, KJ.successBg, icon = Icons.Filled.CheckCircle)
            }
            Spacer(Modifier.height(14.dp))
            KJButton(state.l("save"), enabled = dirty && name.trim().length >= 2, loading = saving) {
                val id = state.userId ?: return@KJButton
                saving = true
                error = null
                scope.launch {
                    try {
                        val fields = if (driver) {
                            jsonOf(
                                "name" to name.trim(), "city" to city,
                                "vehicle_make" to make.trim().ifEmpty { null }, "vehicle_model" to model.trim().ifEmpty { null },
                                "vehicle_plate" to plate.trim().ifEmpty { null }, "vehicle_color" to color.trim().ifEmpty { null },
                            )
                        } else {
                            jsonOf("name" to name.trim(), "city" to city)
                        }
                        state.api.updateProfile(id, fields)
                        state.refreshProfile()
                        saved = true
                    } catch (e: Exception) {
                        error = state.serverError(e)
                    }
                    saving = false
                }
            }

            Spacer(Modifier.height(22.dp))
            SectionTitle(state.l("language"))
            Spacer(Modifier.height(8.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                LangChip(Modifier.weight(1f), "العربية", state.language == "ar") { state.setLanguage("ar") }
                LangChip(Modifier.weight(1f), "Français", state.language == "fr") { state.setLanguage("fr") }
            }

            Spacer(Modifier.height(22.dp))
            SectionTitle(if (state.isRtl) "المساعدة والمعلومات" else "Aide et informations")
            Spacer(Modifier.height(8.dp))
            KJCard(Modifier.fillMaxWidth()) {
                InfoAction(
                    title = if (state.isRtl) "مركز المساعدة" else "Centre d’aide",
                    subtitle = if (state.isRtl) "الرحلات والتوصيل والحساب" else "Courses, livraison et compte",
                    onClick = { infoPage = "help" },
                )
                Spacer(Modifier.height(12.dp))
                InfoAction(
                    title = if (state.isRtl) "الخصوصية والبيانات" else "Confidentialité et données",
                    subtitle = if (state.isRtl) "معلومات حول استخدام بياناتك" else "Utilisation de vos données",
                    onClick = { infoPage = "privacy" },
                )
                Spacer(Modifier.height(12.dp))
                InfoAction(
                    title = if (state.isRtl) "حول KHERJA" else "À propos de KHERJA",
                    subtitle = if (state.isRtl) "معلومات عن التطبيق" else "Informations sur l’application",
                    onClick = { infoPage = "about" },
                )
            }
            infoPage?.let { page ->
                val title = when (page) {
                    "help" -> if (state.isRtl) "مركز المساعدة" else "Centre d’aide"
                    "privacy" -> if (state.isRtl) "الخصوصية والبيانات" else "Confidentialité et données"
                    else -> if (state.isRtl) "حول KHERJA" else "À propos de KHERJA"
                }
                val body = when (page) {
                    "help" -> if (state.isRtl)
                        "لطلب رحلة: حدد نقطة الانطلاق والوجهة، اختر المركبة، راجع السعر ثم أرسل الطلب. لمتابعة الحالة استخدم أقسام الرحلات والتوصيل. إمكانية الإلغاء تعتمد على حالة الطلب."
                    else
                        "Pour demander une course : choisissez le départ et la destination, sélectionnez un véhicule, vérifiez le tarif puis envoyez la demande. Suivez son état dans les sections Courses et Livraison. L’annulation dépend de l’état de la demande."
                    "privacy" -> if (state.isRtl)
                        "يُستخدم الموقع لتحديد نقطة الانطلاق وعرض معلومات الرحلة عند منح الإذن. تُستخدم بيانات الحساب لتشغيل الخدمات وربط الطلبات بصاحبها. يمكنك إدارة أذونات التطبيق من إعدادات الجهاز. راجع سياسة الخصوصية الرسمية عند نشرها."
                    else
                        "La localisation sert à définir le départ et afficher les informations du trajet lorsque l’autorisation est accordée. Les données du compte servent au fonctionnement du service. Gérez les autorisations dans les réglages de l’appareil. Consultez la politique officielle lorsqu’elle sera publiée."
                    else -> if (state.isRtl)
                        "KHERJA تطبيق للتنقل وطلب توصيل الطرود، بواجهتين منفصلتين للراكب والسائق."
                    else
                        "KHERJA est une application de mobilité et de livraison de colis, avec des espaces distincts pour passagers et chauffeurs."
                }
                AlertDialog(
                    onDismissRequest = { infoPage = null },
                    title = { Text(title, fontWeight = FontWeight.Bold) },
                    text = { Text(body, color = KJ.inkSoft) },
                    confirmButton = {
                        TextButton(onClick = { infoPage = null }) {
                            Text(if (state.isRtl) "تم" else "Terminé", color = KJ.blue)
                        }
                    },
                    containerColor = Color.White,
                )
            }

            Spacer(Modifier.height(22.dp))
            KJOutlineButton(state.l("logout"), color = KJ.danger, icon = Icons.AutoMirrored.Filled.Logout) { state.signOut() }
            Spacer(Modifier.height(6.dp))
            TextButton(onClick = { confirmDelete = true }, enabled = !deleting, modifier = Modifier.fillMaxWidth()) {
                Text(state.l("delete_account"), color = KJ.danger, fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
            }
            if (confirmDelete) {
                AlertDialog(
                    onDismissRequest = { if (!deleting) confirmDelete = false },
                    title = { Text(state.l("delete_account"), fontWeight = FontWeight.Bold) },
                    text = { Text(state.l("delete_account_warning"), color = KJ.inkSoft) },
                    confirmButton = {
                        TextButton(enabled = !deleting, onClick = {
                            deleting = true
                            scope.launch {
                                runCatching { state.api.deleteMyAccount() }
                                    .onSuccess { confirmDelete = false; state.signOut() }
                                    .onFailure { confirmDelete = false; error = state.serverError(it) }
                                deleting = false
                            }
                        }) { Text(state.l("delete_account_confirm"), color = KJ.danger, fontWeight = FontWeight.Bold) }
                    },
                    dismissButton = {
                        TextButton(enabled = !deleting, onClick = { confirmDelete = false }) { Text(state.l("cancel"), color = KJ.blue) }
                    },
                    containerColor = Color.White,
                )
            }
            Spacer(Modifier.height(10.dp))
            Text(
                "KHERJA · ${state.l("map_attribution")}", color = KJ.muted, fontSize = 11.sp,
                modifier = Modifier.fillMaxWidth(), textAlign = androidx.compose.ui.text.style.TextAlign.Center,
            )
            Spacer(Modifier.height(24.dp))
        }
    }
}

@Composable
private fun StatTile(modifier: Modifier, value: String, label: String) {
    Column(modifier.clip(RoundedCornerShape(16.dp)).background(KJ.softBlue).padding(12.dp)) {
        Text(value, fontWeight = FontWeight.Black, fontSize = 20.sp, color = KJ.ink)
        Text(label, color = KJ.muted, fontSize = 12.sp)
    }
}

@Composable
private fun Field(label: String, value: String, onChange: (String) -> Unit) {
    OutlinedTextField(
        value = value, onValueChange = onChange, label = { Text(label) }, singleLine = true,
        shape = RoundedCornerShape(14.dp), modifier = Modifier.fillMaxWidth(),
        colors = OutlinedTextFieldDefaults.colors(focusedBorderColor = KJ.blue, unfocusedBorderColor = KJ.softBlueMid),
    )
}

@Composable
private fun LangChip(modifier: Modifier, label: String, selected: Boolean, onClick: () -> Unit) {
    Box(
        modifier.clip(RoundedCornerShape(16.dp)).background(if (selected) KJ.blue else Color.White).clickable(onClick = onClick).padding(vertical = 14.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(label, color = if (selected) Color.White else KJ.ink, fontWeight = FontWeight.Bold)
    }
}

@Composable
private fun InfoAction(title: String, subtitle: String, onClick: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp)).clickable(onClick = onClick).padding(vertical = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(Modifier.weight(1f)) {
            Text(title, color = KJ.ink, fontWeight = FontWeight.Bold, fontSize = 15.sp)
            Text(subtitle, color = KJ.muted, fontSize = 12.sp)
        }
        Text("›", color = KJ.blue, fontSize = 24.sp, fontWeight = FontWeight.Bold)
    }
}

