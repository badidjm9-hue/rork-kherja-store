package app.rork.h04xk59ettzrqz7c6l4wp.ui.components

import android.content.Context
import android.provider.Settings
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.composed
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import app.rork.h04xk59ettzrqz7c6l4wp.ui.theme.KJ
import kotlinx.coroutines.delay

/**
 * The single place for UI motion on Android. Screens use these instead of ad-hoc animations.
 * Everything honours the system "Remove animations" / animator-duration-scale = 0 setting.
 * Nothing here loops once its composable leaves the screen (transitions are tied to composition).
 */
object KJMotion {
    const val REVEAL_MS = 380
    const val STAGGER_MS = 45
    const val MAX_STAGGER_STEPS = 8
    fun staggerDelay(index: Int): Int = index.coerceIn(0, MAX_STAGGER_STEPS) * STAGGER_MS
}

/** True when the user disabled animations (Settings > Accessibility > Remove animations, or scale = 0). */
fun animationsDisabled(context: Context): Boolean = try {
    Settings.Global.getFloat(context.contentResolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f) == 0f
} catch (_: Throwable) {
    false
}

@Composable
fun rememberReduceMotion(): Boolean {
    val ctx = LocalContext.current
    return remember(ctx) { animationsDisabled(ctx) }
}

/** Fade + slide-up entrance, staggered by [index]; plays once per composition of the row. */
fun Modifier.kjReveal(index: Int = 0): Modifier = composed {
    val reduce = rememberReduceMotion()
    var shown by rememberSaveable { mutableStateOf(false) }
    val progress = remember { Animatable(if (shown || reduce) 1f else 0f) }
    LaunchedEffect(Unit) {
        if (reduce) {
            progress.snapTo(1f)
        } else if (!shown) {
            delay(KJMotion.staggerDelay(index).toLong())
            progress.animateTo(1f, tween(KJMotion.REVEAL_MS))
        }
        shown = true
    }
    graphicsLayer {
        alpha = progress.value
        translationY = (1f - progress.value) * 14.dp.toPx()
    }
}

/** Shimmering placeholder fill. Skips the sweep when animations are disabled. */
fun Modifier.kjShimmer(): Modifier = composed {
    val reduce = rememberReduceMotion()
    if (reduce) {
        background(KJ.softBlue)
    } else {
        val t = rememberInfiniteTransition(label = "shimmer")
        val x by t.animateFloat(
            0f, 1f,
            infiniteRepeatable(tween(1300, easing = LinearEasing), RepeatMode.Restart),
            label = "shimmerX",
        )
        background(
            Brush.horizontalGradient(
                colors = listOf(KJ.softBlue, Color.White.copy(alpha = 0.85f), KJ.softBlue),
                startX = (x * 2f - 1f) * 600f,
                endX = (x * 2f) * 600f,
            ),
        )
    }
}

@Composable
fun SkeletonBlock(modifier: Modifier = Modifier, height: Dp = 14.dp, width: Dp? = null, radius: Dp = 8.dp) {
    Box(
        modifier
            .then(if (width != null) Modifier.width(width) else Modifier)
            .height(height)
            .clip(RoundedCornerShape(radius))
            .kjShimmer(),
    )
}

/** Card-shaped placeholder rows shown while a list loads. */
@Composable
fun SkeletonList(count: Int = 4, modifier: Modifier = Modifier) {
    Column(modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        repeat(count) {
            KJCard(padding = 14.dp) {
                Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    Box(Modifier.size(40.dp).clip(CircleShape).kjShimmer())
                    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        SkeletonBlock(width = 160.dp)
                        SkeletonBlock(height = 11.dp, width = 100.dp)
                    }
                }
            }
        }
    }
}

/** Horizontal error shake; bump [trigger] to play it. No-op under Reduce Motion. */
fun Modifier.kjShake(trigger: Int): Modifier = composed {
    val reduce = rememberReduceMotion()
    val offset = remember { Animatable(0f) }
    LaunchedEffect(trigger) {
        if (trigger == 0 || reduce) return@LaunchedEffect
        for (v in listOf(-10f, 8f, -6f, 4f, 0f)) offset.animateTo(v, spring(Spring.DampingRatioMediumBouncy, Spring.StiffnessHigh))
    }
    graphicsLayer { translationX = offset.value.dp.toPx() }
}

/** Press feedback (scale) for any tappable surface; pass the same [interaction] given to `clickable`. */
fun Modifier.kjPressable(interaction: androidx.compose.foundation.interaction.InteractionSource, pressedScale: Float = 0.97f): Modifier = composed {
    val pressed by interaction.collectIsPressedAsState()
    val reduce = rememberReduceMotion()
    val scale by animateFloatAsState(
        if (pressed && !reduce) pressedScale else 1f,
        spring(Spring.DampingRatioMediumBouncy, Spring.StiffnessMedium),
        label = "kjPress",
    )
    graphicsLayer { scaleX = scale; scaleY = scale }
}

/** One-shot "pop" used to confirm a state change (accepted, completed). Replays when [key] changes. */
fun Modifier.kjPop(key: Any? = Unit): Modifier = composed {
    val reduce = rememberReduceMotion()
    val progress = remember(key) { Animatable(if (reduce) 1f else 0f) }
    LaunchedEffect(key) {
        if (!reduce) progress.animateTo(1f, spring(Spring.DampingRatioMediumBouncy, Spring.StiffnessMediumLow))
    }
    graphicsLayer {
        val v = progress.value
        scaleX = 0.7f + 0.3f * v
        scaleY = 0.7f + 0.3f * v
        alpha = v.coerceIn(0f, 1f)
    }
}
