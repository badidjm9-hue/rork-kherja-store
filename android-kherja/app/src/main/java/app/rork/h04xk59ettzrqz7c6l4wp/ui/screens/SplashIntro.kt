package app.rork.h04xk59ettzrqz7c6l4wp.ui.screens

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.CubicBezierEasing
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.unit.dp
import app.rork.h04xk59ettzrqz7c6l4wp.AppState
import app.rork.h04xk59ettzrqz7c6l4wp.R
import app.rork.h04xk59ettzrqz7c6l4wp.ui.components.KJLogo
import app.rork.h04xk59ettzrqz7c6l4wp.ui.components.rememberReduceMotion
import app.rork.h04xk59ettzrqz7c6l4wp.ui.theme.KJ
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.pow
import kotlin.math.sin
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

private val openingFrames = intArrayOf(
    R.drawable.welcome_drive_0, R.drawable.welcome_drive_1, R.drawable.welcome_drive_2,
    R.drawable.welcome_drive_3, R.drawable.welcome_drive_4, R.drawable.welcome_drive_5,
    R.drawable.welcome_drive_6, R.drawable.welcome_drive_7, R.drawable.welcome_drive_8,
)

/**
 * One-shot launch sequence: white logo hold → original transparent car frames → impact → Welcome.
 * The source artwork is reused as-is; no video card, scenery, or second animation is shown.
 */
@Composable
fun SplashScreen(
    state: AppState,
    onFinished: () -> Unit = {},
    playIntro: Boolean = true,
) {
    val reduce = rememberReduceMotion()
    val haptic = LocalHapticFeedback.current
    var frameIndex by remember { mutableIntStateOf(0) }
    var carVisible by remember { mutableStateOf(false) }
    var didFinish by remember { mutableStateOf(false) }
    val carScale = remember { Animatable(0.62f) }
    val shake = remember { Animatable(0f) }
    val crack = remember { Animatable(0f) }
    val crackAlpha = remember { Animatable(1f) }
    val flash = remember { Animatable(0f) }

    LaunchedEffect(playIntro, reduce) {
        if (!playIntro) return@LaunchedEffect

        // Minimal splash: white background and a small centered logo only, for one second.
        delay(1_000)
        if (reduce) {
            if (!didFinish) {
                didFinish = true
                onFinished()
            }
            return@LaunchedEffect
        }

        carVisible = true
        launch {
            carScale.animateTo(
                1.12f,
                tween(1_620, easing = CubicBezierEasing(0.42f, 0f, 1f, 1f)),
            )
        }

        // The nine original transparent frames are played once, in order.
        openingFrames.forEachIndexed { index, _ ->
            frameIndex = index
            delay(180)
        }

        launch { shake.animateTo(1f, tween(650, easing = LinearEasing)) }
        delay(180)
        haptic.performHapticFeedback(HapticFeedbackType.LongPress)
        launch { crack.animateTo(1f, tween(160)) }
        launch {
            flash.animateTo(0.78f, tween(140))
            delay(100)
            flash.animateTo(0f, tween(220))
        }
        delay(440)
        crackAlpha.animateTo(0f, tween(350))
        if (!didFinish) {
            didFinish = true
            onFinished()
        }
    }

    Box(
        Modifier
            .fillMaxSize()
            .background(Color.White)
            .graphicsLayer {
                val t = shake.value
                val envelope = if (t < 0.30f) 0.25f * (t / 0.30f)
                else (1f - (t - 0.30f) / 0.70f).coerceAtLeast(0f).pow(2)
                translationX = 12.dp.toPx() * envelope * sin(t * PI.toFloat() * 19f)
                translationY = 8.dp.toPx() * envelope * cos(t * PI.toFloat() * 23f)
            },
    ) {
        if (!playIntro) {
            Column(
                Modifier.align(Alignment.Center),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                KJLogo(48.dp)
                CircularProgressIndicator(
                    color = KJ.blue,
                    strokeWidth = 2.dp,
                    modifier = Modifier.padding(top = 18.dp).size(22.dp),
                )
            }
        } else if (!carVisible) {
            KJLogo(48.dp, modifier = Modifier.align(Alignment.Center))
        } else {
            Image(
                painter = painterResource(openingFrames[frameIndex]),
                contentDescription = state.l("welcome_scene"),
                contentScale = ContentScale.Fit,
                modifier = Modifier
                    .align(Alignment.Center)
                    .fillMaxWidth()
                    .padding(horizontal = 8.dp)
                    .aspectRatio(438f / 388f)
                    .graphicsLayer {
                        scaleX = carScale.value
                        scaleY = carScale.value
                    },
            )
        }

        Canvas(Modifier.fillMaxSize()) { drawCracks(crack.value, crackAlpha.value) }
        Box(Modifier.fillMaxSize().graphicsLayer { alpha = flash.value }.background(Color.White))
    }
}

/** Deterministic full-screen glass fracture. */
private fun DrawScope.drawCracks(progress: Float, alpha: Float) {
    if (progress <= 0f || alpha <= 0f) return
    val rnd = kotlin.random.Random(7)
    val center = Offset(size.width / 2f, size.height * 0.42f)
    val reach = hypot(size.width, size.height) * 0.7f * progress
    val path = Path()
    val rays = 16
    for (i in 0 until rays) {
        var angle = i.toFloat() / rays * 2f * PI.toFloat() + (rnd.nextFloat() - 0.5f) * 0.25f
        var x = center.x
        var y = center.y
        path.moveTo(x, y)
        for (step in 1..5) {
            val length = reach / 5f * (0.7f + 0.6f * rnd.nextFloat())
            angle += (rnd.nextFloat() - 0.5f) * 0.5f
            x += cos(angle) * length
            y += sin(angle) * length
            path.lineTo(x, y)
            if (step == 2 || step == 4) {
                val branch = angle + if (rnd.nextFloat() > 0.5f) 0.9f else -0.9f
                path.lineTo(x + cos(branch) * length * 0.8f, y + sin(branch) * length * 0.8f)
                path.moveTo(x, y)
            }
        }
    }
    for (ring in listOf(0.16f, 0.34f)) {
        val radius = reach * ring
        for (k in 0..rays) {
            val angle = k.toFloat() / rays * 2f * PI.toFloat()
            val r = radius * (0.85f + 0.3f * rnd.nextFloat())
            val px = center.x + cos(angle) * r
            val py = center.y + sin(angle) * r
            if (k == 0) path.moveTo(px, py) else path.lineTo(px, py)
        }
    }
    drawPath(path, KJ.ink.copy(alpha = 0.35f * alpha), style = Stroke(3.5.dp.toPx(), cap = StrokeCap.Round, join = StrokeJoin.Round))
    drawPath(path, Color.White.copy(alpha = 0.92f * alpha), style = Stroke(1.5.dp.toPx(), cap = StrokeCap.Round, join = StrokeJoin.Round))
}
