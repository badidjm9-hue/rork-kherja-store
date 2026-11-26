package app.rork.h04xk59ettzrqz7c6l4wp.ui.screens

import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.OutlinedTextField
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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.rork.h04xk59ettzrqz7c6l4wp.AppState
import app.rork.h04xk59ettzrqz7c6l4wp.data.SupportContact
import app.rork.h04xk59ettzrqz7c6l4wp.ui.components.ErrorBanner
import app.rork.h04xk59ettzrqz7c6l4wp.ui.components.IconCircle
import app.rork.h04xk59ettzrqz7c6l4wp.ui.components.KJButton
import app.rork.h04xk59ettzrqz7c6l4wp.ui.components.KJCard
import app.rork.h04xk59ettzrqz7c6l4wp.ui.components.KJOutlineButton
import app.rork.h04xk59ettzrqz7c6l4wp.ui.components.SectionTitle
import app.rork.h04xk59ettzrqz7c6l4wp.ui.theme.KJ
import kotlinx.coroutines.launch

/** Support contact (entered by admins), ticket form and SOS alert. Backend: migration 0011. */
@Composable
fun SupportScreen(state: AppState, onBack: () -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var contact by remember { mutableStateOf<SupportContact?>(null) }
    var category by remember { mutableStateOf("ride") }
    var message by remember { mutableStateOf("") }
    var info by remember { mutableStateOf<String?>(null) }
    var error by remember { mutableStateOf<String?>(null) }
    var confirmSos by remember { mutableStateOf(false) }
    var busy by remember { mutableStateOf(false) }

    LaunchedEffect(Unit) { contact = runCatching { state.api.supportContact() }.getOrNull() }

    Column(Modifier.fillMaxSize().background(KJ.canvasGradient)) {
        Column(Modifier.fillMaxWidth().statusBarsPadding().padding(horizontal = 20.dp, vertical = 14.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                IconCircle(Icons.AutoMirrored.Filled.ArrowBack, tint = KJ.ink, bg = Color.White, size = 42.dp, onClick = onBack)
                Spacer(Modifier.width(12.dp))
                Text(state.l("support_title"), fontSize = 24.sp, fontWeight = FontWeight.ExtraBold, color = KJ.ink)
            }
            Spacer(Modifier.height(6.dp))
            Text(state.l("support_subtitle"), color = KJ.muted, fontSize = 14.sp)
        }
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = 20.dp)) {
            error?.let { ErrorBanner(it); Spacer(Modifier.height(10.dp)) }
            info?.let { Text(it, color = KJ.success, fontWeight = FontWeight.Bold, fontSize = 14.sp); Spacer(Modifier.height(10.dp)) }

            KJCard(Modifier.fillMaxWidth()) {
                Text(state.l("sos_title"), color = KJ.danger, fontWeight = FontWeight.ExtraBold, fontSize = 17.sp)
                Spacer(Modifier.height(6.dp))
                Text(state.l("sos_hint"), color = KJ.inkSoft, fontSize = 13.sp)
                Spacer(Modifier.height(12.dp))
                KJOutlineButton(state.l("sos_button"), color = KJ.danger, icon = Icons.Filled.Warning, enabled = !busy) { confirmSos = true }
            }

            Spacer(Modifier.height(18.dp))
            SectionTitle(state.l("support_contact"))
            Spacer(Modifier.height(8.dp))
            KJCard(Modifier.fillMaxWidth()) {
                val c = contact
                if (c == null || (c.phone.isBlank() && c.email.isBlank())) {
                    Text(state.l("support_contact_none"), color = KJ.muted, fontSize = 13.sp)
                } else {
                    if (c.phone.isNotBlank()) {
                        KJOutlineButton("${state.l("support_call")} ${c.phone}") {
                            val number = c.phone.filter { it.isDigit() || it == '+' }
                            runCatching { context.startActivity(Intent(Intent.ACTION_DIAL, Uri.parse("tel:$number"))) }
                        }
                    }
                    if (c.phone.isNotBlank() && c.email.isNotBlank()) Spacer(Modifier.height(10.dp))
                    if (c.email.isNotBlank()) {
                        KJOutlineButton(c.email) {
                            runCatching { context.startActivity(Intent(Intent.ACTION_SENDTO, Uri.parse("mailto:${c.email}"))) }
                        }
                    }
                }
            }

            Spacer(Modifier.height(18.dp))
            SectionTitle(state.l("ticket_new"))
            Spacer(Modifier.height(8.dp))
            KJCard(Modifier.fillMaxWidth()) {
                Text(state.l("ticket_category"), color = KJ.muted, fontSize = 12.sp)
                Spacer(Modifier.height(6.dp))
                Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    listOf("ride", "payment", "account", "safety", "other").chunked(3).forEach { rowItems ->
                        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                            rowItems.forEach { c ->
                                val sel = category == c
                                Text(
                                    state.l("cat_$c"),
                                    color = if (sel) Color.White else KJ.ink,
                                    fontWeight = FontWeight.Bold, fontSize = 13.sp,
                                    modifier = Modifier
                                        .clickable { category = c }
                                        .background(if (sel) KJ.blue else KJ.softBlue, RoundedCornerShape(50))
                                        .padding(horizontal = 14.dp, vertical = 8.dp),
                                )
                            }
                        }
                    }
                }
                Spacer(Modifier.height(12.dp))
                OutlinedTextField(
                    value = message, onValueChange = { message = it.take(1000) },
                    label = { Text(state.l("ticket_message")) },
                    modifier = Modifier.fillMaxWidth().height(140.dp),
                )
                Spacer(Modifier.height(12.dp))
                KJButton(state.l("ticket_send"), enabled = !busy, loading = busy) {
                    val uid = state.userId ?: return@KJButton
                    val text = message.trim()
                    if (text.length < 5) { error = state.l("ticket_too_short"); info = null; return@KJButton }
                    busy = true
                    scope.launch {
                        runCatching { state.api.createTicket(uid, category, text, state.activeRideId) }
                            .onSuccess { message = ""; error = null; info = state.l("ticket_sent") }
                            .onFailure { error = state.serverError(it); info = null }
                        busy = false
                    }
                }
            }
            Spacer(Modifier.height(24.dp))
        }
    }

    if (confirmSos) {
        AlertDialog(
            onDismissRequest = { confirmSos = false },
            title = { Text(state.l("sos_confirm")) },
            confirmButton = {
                TextButton(onClick = {
                    confirmSos = false
                    busy = true
                    val loc = state.location.location.value
                    scope.launch {
                        runCatching { state.api.raiseSos(state.activeRideId, loc?.latitude, loc?.longitude) }
                            .onSuccess { error = null; info = state.l("sos_sent") + if (loc == null) " " + state.l("sos_no_location") else "" }
                            .onFailure { error = state.serverError(it); info = null }
                        busy = false
                    }
                }) { Text(state.l("sos_button"), color = KJ.danger, fontWeight = FontWeight.Bold) }
            },
            dismissButton = { TextButton(onClick = { confirmSos = false }) { Text(state.l("cancel_action")) } },
        )
    }
}
