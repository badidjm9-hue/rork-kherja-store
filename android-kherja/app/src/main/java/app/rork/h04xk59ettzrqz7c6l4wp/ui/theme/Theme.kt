package app.rork.h04xk59ettzrqz7c6l4wp.ui.theme

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Typography
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp

object KJ {
    val blue = Color(0xFF075BFF)
    val blueDeep = Color(0xFF0043C7)
    val blueLight = Color(0xFF1668FF)
    val burgundy = Color(0xFF85003F)
    val burgundyBright = Color(0xFFC4145A)
    val ink = Color(0xFF0D1B4C)
    val inkSoft = Color(0xFF3D4A73)
    val muted = Color(0xFF7A8199)
    val canvas = Color(0xFFF7F8FC)
    val softBlue = Color(0xFFE9EEFB)
    val softBlueMid = Color(0xFFDCE4F8)
    val success = Color(0xFF12A150)
    val successBg = Color(0xFFE3F6EB)
    val danger = Color(0xFFE5484D)
    val dangerBg = Color(0xFFFCE9EA)
    val warning = Color(0xFFF0A52D)
    val warningBg = Color(0xFFFFF4E0)

    val buttonGradient = Brush.horizontalGradient(listOf(blueLight, blue))
    val burgundyGradient = Brush.linearGradient(listOf(burgundyBright, burgundy))
    val canvasGradient = Brush.verticalGradient(0f to Color(0xFFE8EDFA), 0.35f to canvas, 1f to canvas)
}

private val colors = lightColorScheme(
    primary = KJ.blue,
    onPrimary = Color.White,
    secondary = KJ.burgundy,
    onSecondary = Color.White,
    background = KJ.canvas,
    onBackground = KJ.ink,
    surface = Color.White,
    onSurface = KJ.ink,
    surfaceVariant = KJ.softBlue,
    onSurfaceVariant = KJ.inkSoft,
    surfaceContainer = Color.White,
    surfaceContainerHigh = Color.White,
    surfaceContainerLow = KJ.canvas,
    outline = KJ.softBlueMid,
    error = KJ.danger,
)

private val base = Typography()
private val typography = Typography(
    headlineLarge = base.headlineLarge.copy(fontWeight = FontWeight.ExtraBold, color = KJ.ink),
    headlineMedium = base.headlineMedium.copy(fontWeight = FontWeight.ExtraBold, fontSize = 26.sp),
    headlineSmall = base.headlineSmall.copy(fontWeight = FontWeight.Bold),
    titleLarge = base.titleLarge.copy(fontWeight = FontWeight.Bold),
    titleMedium = base.titleMedium.copy(fontWeight = FontWeight.Bold),
    bodyLarge = base.bodyLarge,
    bodyMedium = base.bodyMedium,
    labelLarge = base.labelLarge.copy(fontWeight = FontWeight.Bold),
)

val PriceStyle = TextStyle(fontSize = 34.sp, fontWeight = FontWeight.Black, color = KJ.ink)

@Composable
fun AppTheme(content: @Composable () -> Unit) {
    MaterialTheme(colorScheme = colors, typography = typography, content = content)
}
