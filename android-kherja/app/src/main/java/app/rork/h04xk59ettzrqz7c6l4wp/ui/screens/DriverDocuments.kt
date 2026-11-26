package app.rork.h04xk59ettzrqz7c6l4wp.ui.screens

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.rork.h04xk59ettzrqz7c6l4wp.AppState
import app.rork.h04xk59ettzrqz7c6l4wp.data.DriverDocument
import app.rork.h04xk59ettzrqz7c6l4wp.ui.components.ErrorBanner
import app.rork.h04xk59ettzrqz7c6l4wp.ui.components.KJCard
import app.rork.h04xk59ettzrqz7c6l4wp.ui.components.KJOutlineButton
import app.rork.h04xk59ettzrqz7c6l4wp.ui.components.Pill
import app.rork.h04xk59ettzrqz7c6l4wp.ui.components.SectionTitle
import app.rork.h04xk59ettzrqz7c6l4wp.ui.theme.KJ
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

private val DOC_TYPES = listOf("id_card", "license", "registration", "insurance", "vehicle_photo")
private val ALLOWED_MIME = arrayOf("image/jpeg", "image/png", "image/heic", "application/pdf")
private const val MAX_DOC_BYTES = 10 * 1024 * 1024 // matches the bucket limit

/** Driver document upload: one card per required document, each with its review status. */
@Composable
fun DriverDocumentsSection(state: AppState) {
    val scope = rememberCoroutineScope()
    val context = LocalContext.current
    var docs by remember { mutableStateOf<List<DriverDocument>?>(null) }
    var busyType by remember { mutableStateOf<String?>(null) }
    var pendingType by remember { mutableStateOf<String?>(null) }
    var error by remember { mutableStateOf<String?>(null) }

    LaunchedEffect(state.userId) {
        val uid = state.userId ?: return@LaunchedEffect
        try {
            docs = state.api.driverDocuments(uid)
        } catch (e: Exception) {
            docs = emptyList()
            error = state.l("doc_load_failed")
        }
    }

    val picker = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        val type = pendingType
        pendingType = null
        val uid = state.userId
        if (uri == null || type == null || uid == null) return@rememberLauncherForActivityResult
        val mime = context.contentResolver.getType(uri)
        if (mime == null || mime !in ALLOWED_MIME) {
            error = state.l("doc_bad_type")
            return@rememberLauncherForActivityResult
        }
        busyType = type
        error = null
        scope.launch {
            try {
                val bytes = withContext(Dispatchers.IO) {
                    context.contentResolver.openInputStream(uri)?.use { it.readBytes() }
                }
                when {
                    bytes == null -> error = state.l("doc_read_failed")
                    bytes.size > MAX_DOC_BYTES -> error = state.l("doc_too_large")
                    else -> {
                        state.api.uploadDriverDocument(uid, type, bytes, mime)
                        docs = state.api.driverDocuments(uid)
                    }
                }
            } catch (e: Exception) {
                error = state.serverError(e)
            }
            busyType = null
        }
    }

    Column(Modifier.fillMaxWidth()) {
        SectionTitle(state.l("docs_title"))
        Spacer(Modifier.height(6.dp))
        Text(state.l("docs_hint"), color = KJ.muted, fontSize = 13.sp)
        Spacer(Modifier.height(10.dp))
        if (docs == null) {
            CircularProgressIndicator(color = KJ.blue, modifier = Modifier.align(Alignment.CenterHorizontally))
        } else {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                DOC_TYPES.forEach { type ->
                    val doc = docs?.firstOrNull { it.docType == type }
                    val approved = doc?.status == "approved"
                    KJCard(Modifier.fillMaxWidth(), padding = 14.dp) {
                        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.SpaceBetween) {
                            Text(state.l("doc_$type"), fontWeight = FontWeight.Bold, color = KJ.ink, modifier = Modifier.weight(1f))
                            when (doc?.status) {
                                "approved" -> Pill(state.l("doc_approved"), KJ.success, KJ.successBg)
                                "rejected" -> Pill(state.l("doc_rejected"), KJ.danger, KJ.dangerBg)
                                "pending" -> Pill(state.l("doc_pending"), KJ.warning, KJ.warningBg)
                                else -> Pill(state.l("doc_not_sent"), KJ.muted, KJ.softBlue)
                            }
                        }
                        if (doc?.status == "rejected" && !doc.reason.isNullOrBlank()) {
                            Spacer(Modifier.height(6.dp))
                            Text(doc.reason, color = KJ.danger, fontSize = 13.sp)
                        }
                        if (!approved) {
                            Spacer(Modifier.height(10.dp))
                            KJOutlineButton(
                                text = state.l(if (doc == null) "doc_upload" else "doc_replace"),
                                enabled = busyType == null,
                            ) {
                                pendingType = type
                                picker.launch(ALLOWED_MIME)
                            }
                            if (busyType == type) {
                                Spacer(Modifier.height(8.dp))
                                CircularProgressIndicator(color = KJ.blue, modifier = Modifier.align(Alignment.CenterHorizontally))
                            }
                        }
                    }
                }
            }
        }
        error?.let {
            Spacer(Modifier.height(10.dp))
            ErrorBanner(it)
        }
    }
}
