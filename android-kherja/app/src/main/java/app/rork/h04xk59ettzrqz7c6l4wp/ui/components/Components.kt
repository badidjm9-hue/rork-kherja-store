package app.rork.h04xk59ettzrqz7c6l4wp.ui.components

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.animation.core.animateFloat
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ErrorOutline
import androidx.compose.material.icons.filled.Star
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.rork.h04xk59ettzrqz7c6l4wp.R
import app.rork.h04xk59ettzrqz7c6l4wp.ui.theme.KJ
import java.text.NumberFormat
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone

fun dzd(amount: Int): String {
    val nf = NumberFormat.getIntegerInstance(Locale.FRANCE)
    return nf.format(amount).replace('\u202F', ' ').replace('\u00A0', ' ') + " DA"
}

/** Parses Postgres timestamptz ("2026-11-23T22:18:00.123+00:00") as epoch millis. */
fun parseTs(value: String?): Long? {
    if (value == null || value.length < 19) return null
    return try {
        val fmt = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss", Locale.US)
        fmt.timeZone = TimeZone.getTimeZone("UTC")
        var ms = fmt.parse(value.substring(0, 19))?.time ?: return null
        val tz = Regex("([+-])(\\d{2}):?(\\d{2})$").find(value)
        if (tz != null) {
            val sign = if (tz.groupValues[1] == "+") 1 else -1
            val off = (tz.groupValues[2].toInt() * 60 + tz.groupValues[3].toInt()) * 60_000L
            ms -= sign * off
        }
        ms
    } catch (_: Exception) {
        null
    }
}

fun formatDate(value: String?, lang: String): String {
    val ms = parseTs(value) ?: return ""
    val locale = if (lang == "ar") Locale("ar", "DZ") else Locale.FRANCE
    return SimpleDateFormat("d MMM yyyy · HH:mm", locale).format(Date(ms))
}

@Composable
fun KJLogo(height: Dp, modifier: Modifier = Modifier) {
    Image(
        painter = painterResource(R.drawable.kj_logo),
        contentDescription = "KHERJA",
        modifier = modifier.height(height),
        contentScale = ContentScale.Fit,
    )
}

@Composable
fun KJButton(
    text: String,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    loading: Boolean = false,
    icon: ImageVector? = null,
    brush: Brush = KJ.buttonGradient,
    onClick: () -> Unit,
) {
    val haptic = LocalHapticFeedback.current
    val interaction = remember { MutableInteractionSource() }
    val pressed by interaction.collectIsPressedAsState()
    val scale by animateFloatAsState(if (pressed) 0.97f else 1f, label = "press")
    Box(
        modifier = modifier
            .fillMaxWidth()
            .height(56.dp)
            .scale(scale)
            .alpha(if (enabled) 1f else 0.5f)
            .shadow(if (enabled) 10.dp else 0.dp, RoundedCornerShape(18.dp), ambientColor = KJ.blue, spotColor = KJ.blue)
            .clip(RoundedCornerShape(18.dp))
            .background(brush)
            .clickable(interaction, null, enabled = enabled && !loading) {
                haptic.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                onClick()
            },
        contentAlignment = Alignment.Center,
    ) {
        if (loading) {
            CircularProgressIndicator(color = Color.White, strokeWidth = 2.5.dp, modifier = Modifier.size(24.dp))
        } else {
            Row(verticalAlignment = Alignment.CenterVertically) {
                if (icon != null) {
                    Icon(icon, null, tint = Color.White, modifier = Modifier.size(20.dp))
                    Spacer(Modifier.width(8.dp))
                }
                Text(text, color = Color.White, fontWeight = FontWeight.Bold, fontSize = 17.sp)
            }
        }
    }
}

@Composable
fun KJOutlineButton(text: String, modifier: Modifier = Modifier, color: Color = KJ.blue, icon: ImageVector? = null, enabled: Boolean = true, onClick: () -> Unit) {
    val interaction = remember { MutableInteractionSource() }
    Row(
        modifier = modifier
            .fillMaxWidth()
            .height(52.dp)
            .kjPressable(interaction)
            .alpha(if (enabled) 1f else 0.5f)
            .clip(RoundedCornerShape(16.dp))
            .border(1.5.dp, color.copy(alpha = 0.35f), RoundedCornerShape(16.dp))
            .background(Color.White)
            .clickable(interaction, null, enabled = enabled, onClick = onClick),
        horizontalArrangement = Arrangement.Center,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (icon != null) {
            Icon(icon, null, tint = color, modifier = Modifier.size(19.dp))
            Spacer(Modifier.width(8.dp))
        }
        Text(text, color = color, fontWeight = FontWeight.Bold, fontSize = 16.sp)
    }
}

@Composable
fun KJCard(modifier: Modifier = Modifier, padding: Dp = 18.dp, content: @Composable ColumnScope.() -> Unit) {
    Column(
        modifier = modifier
            .shadow(14.dp, RoundedCornerShape(22.dp), ambientColor = KJ.blue.copy(alpha = 0.25f), spotColor = KJ.blue.copy(alpha = 0.18f))
            .clip(RoundedCornerShape(22.dp))
            .background(Color.White)
            .padding(padding),
        content = content,
    )
}

@Composable
fun Pill(text: String, fg: Color, bg: Color, modifier: Modifier = Modifier, icon: ImageVector? = null) {
    Row(
        modifier = modifier.clip(RoundedCornerShape(50)).background(bg).padding(horizontal = 10.dp, vertical = 5.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (icon != null) {
            Icon(icon, null, tint = fg, modifier = Modifier.size(14.dp))
            Spacer(Modifier.width(4.dp))
        }
        Text(text, color = fg, fontSize = 12.sp, fontWeight = FontWeight.Bold)
    }
}

@Composable
fun RatingBadge(rating: Double, trips: Int? = null) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Icon(Icons.Filled.Star, null, tint = KJ.warning, modifier = Modifier.size(15.dp))
        Spacer(Modifier.width(3.dp))
        Text(if (rating > 0) String.format(Locale.US, "%.1f", rating) else "—", fontWeight = FontWeight.Bold, fontSize = 13.sp, color = KJ.ink)
        if (trips != null) {
            Text("  ·  $trips", fontSize = 13.sp, color = KJ.muted)
        }
    }
}

@Composable
fun Avatar(name: String, size: Dp = 46.dp, brush: Brush = KJ.buttonGradient) {
    Box(
        Modifier.size(size).clip(CircleShape).background(brush),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            name.trim().take(1).uppercase().ifEmpty { "K" },
            color = Color.White,
            fontWeight = FontWeight.Black,
            fontSize = (size.value * 0.42f).sp,
        )
    }
}

@Composable
fun ErrorBanner(text: String, modifier: Modifier = Modifier) {
    Row(
        modifier = modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp)).background(KJ.dangerBg).padding(12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(Icons.Filled.ErrorOutline, null, tint = KJ.danger, modifier = Modifier.size(18.dp))
        Spacer(Modifier.width(8.dp))
        Text(text, color = KJ.danger, fontSize = 14.sp, fontWeight = FontWeight.SemiBold)
    }
}

@Composable
fun PulsingDots() {
    val t = rememberInfiniteTransition(label = "dots")
    Row(horizontalArrangement = Arrangement.spacedBy(7.dp)) {
        repeat(3) { i ->
            val s by t.animateFloat(
                0.55f, 1f,
                infiniteRepeatable(tween(600, delayMillis = i * 180), RepeatMode.Reverse),
                label = "dot$i",
            )
            Box(Modifier.size(9.dp).scale(s).alpha(s).clip(CircleShape).background(KJ.blue))
        }
    }
}

@Composable
fun IconCircle(icon: ImageVector, tint: Color = KJ.blue, bg: Color = KJ.softBlue, size: Dp = 40.dp, onClick: (() -> Unit)? = null) {
    Box(
        Modifier.size(size).clip(CircleShape).background(bg)
            .then(if (onClick != null) Modifier.clickable(onClick = onClick) else Modifier),
        contentAlignment = Alignment.Center,
    ) {
        Icon(icon, null, tint = tint, modifier = Modifier.size(size * 0.5f))
    }
}

@Composable
fun SectionTitle(text: String, modifier: Modifier = Modifier) {
    Text(text, modifier = modifier, fontSize = 18.sp, fontWeight = FontWeight.ExtraBold, color = KJ.ink)
}

@Composable
fun EmptyState(icon: ImageVector, title: String, subtitle: String? = null) {
    Column(
        Modifier.fillMaxWidth().padding(vertical = 48.dp, horizontal = 24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        IconCircle(icon, size = 64.dp)
        Spacer(Modifier.height(14.dp))
        Text(title, fontWeight = FontWeight.Bold, fontSize = 17.sp, color = KJ.ink)
        if (subtitle != null) {
            Spacer(Modifier.height(4.dp))
            Text(subtitle, color = KJ.muted, fontSize = 14.sp)
        }
    }
}

val ScreenPadding = PaddingValues(horizontal = 20.dp)
