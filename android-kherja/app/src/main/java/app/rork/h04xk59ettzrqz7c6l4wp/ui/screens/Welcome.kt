package app.rork.h04xk59ettzrqz7c6l4wp.ui.screens

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.CubicBezierEasing
import androidx.compose.animation.core.LinearOutSlowInEasing
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.min
import androidx.compose.ui.unit.sp
import app.rork.h04xk59ettzrqz7c6l4wp.AppState
import app.rork.h04xk59ettzrqz7c6l4wp.R
import app.rork.h04xk59ettzrqz7c6l4wp.ui.components.KJButton
import app.rork.h04xk59ettzrqz7c6l4wp.ui.components.KJLogo
import app.rork.h04xk59ettzrqz7c6l4wp.ui.components.rememberReduceMotion
import app.rork.h04xk59ettzrqz7c6l4wp.ui.theme.KJ
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

private const val DRIVE_MS = 1500
private const val CAR_ASPECT = 304f / 420f

/** The brand line is shown in Arabic in every language; other languages add a translation below it. */
private const val BRAND_LINE = "تنقّل بأمان مع خرجة"

/**
 * Opening scene: the KHERJA car speeds in from the horizon, brakes just short of the "camera",
 * bounces, flashes its headlights and honks; then the brand line and the start button appear.
 * Everything is one-shot (no endless loops). With animations disabled the final frame is shown.
 */
@Composable
fun WelcomeScreen(state: AppState, onStart: () -> Unit) {
    val reduce = rememberReduceMotion()
    val haptic = LocalHapticFeedback.current
    val drive = remember { Animatable(if (reduce) 1f else 0f) }
    val squash = remember { Animatable(0f) }
    val flash = remember { Animatable(0f) }
    val dust = remember { Animatable(0f) }
    val honk = remember { Animatable(0f) }
    val text = remember { Animatable(if (reduce) 1f else 0f) }
    val button = remember { Animatable(if (reduce) 1f else 0f) }
    var skipped by remember { mutableStateOf(false) }

    LaunchedEffect(skipped) {
        if (reduce || skipped) {
            drive.snapTo(1f); squash.snapTo(0f); flash.snapTo(0f); dust.snapTo(0f); honk.snapTo(0f)
            text.snapTo(1f); button.snapTo(1f)
            return@LaunchedEffect
        }
        delay(250)
        // Slow start, hard acceleration, short brake.
        drive.animateTo(1f, tween(DRIVE_MS, easing = CubicBezierEasing(0.6f, 0f, 0.35f, 1f)))
        haptic.performHapticFeedback(HapticFeedbackType.LongPress)
        launch {
            squash.animateTo(1f, tween(110))
            squash.animateTo(0f, spring(Spring.DampingRatioMediumBouncy, Spring.StiffnessMediumLow))
        }
        launch { dust.animateTo(1f, tween(650, easing = LinearOutSlowInEasing)) }
        launch {
            repeat(2) { flash.animateTo(1f, tween(90)); flash.animateTo(0f, tween(150)) }
        }
        launch {
            honk.animateTo(1f, spring(Spring.DampingRatioMediumBouncy, Spring.StiffnessMedium))
            delay(800)
            honk.animateTo(0f, tween(220))
        }
        delay(180)
        launch { text.animateTo(1f, tween(500, easing = LinearOutSlowInEasing)) }
        delay(350)
        button.animateTo(1f, spring(Spring.DampingRatioMediumBouncy, Spring.StiffnessLow))
    }

    Column(
        Modifier.fillMaxSize()
            // Tap anywhere to jump to the end of the scene.
            .clickable(remember { MutableInteractionSource() }, null, enabled = button.value < 1f) { skipped = true }
            .padding(horizontal = 24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Spacer(Modifier.height(20.dp))
        KJLogo(64.dp)

        BoxWithConstraints(Modifier.weight(1f).fillMaxWidth(), contentAlignment = Alignment.Center) {
            val carWidth = min(min(maxWidth, 420.dp), maxHeight / (CAR_ASPECT * 1.25f))
            val carHeight = carWidth * CAR_ASPECT

            Canvas(Modifier.fillMaxSize()) {
                val p = drive.value
                val horizon = size.height * 0.28f
                val bottom = size.height * 0.5f + carHeight.toPx() * 0.52f
                val road = Path().apply {
                    moveTo(size.width * 0.47f, horizon)
                    lineTo(size.width * 0.53f, horizon)
                    lineTo(size.width * 0.98f, bottom)
                    lineTo(size.width * 0.02f, bottom)
                    close()
                }
                drawPath(road, KJ.softBlueMid.copy(alpha = 0.55f))
                // Centre line scrolls towards the viewer while the car is moving.
                val span = bottom - horizon
                for (i in 0 until 5) {
                    val t = ((i / 5f) + p * 1.6f) % 1f
                    val y = horizon + span * t * t
                    drawLine(Color.White, Offset(size.width / 2, y), Offset(size.width / 2, y + span * 0.09f * t), (2f + 10f * t).dp.toPx() / 2, StrokeCap.Round)
                }
                // Speed lines, strongest mid-run.
                val speed = (4f * p * (1f - p)).coerceIn(0f, 1f)
                if (speed > 0.05f) {
                    for (side in listOf(-1f, 1f)) for (k in 0 until 3) {
                        val y = size.height * (0.36f + 0.1f * k)
                        val x = size.width / 2 + side * size.width * (0.24f + 0.08f * k + 0.14f * p)
                        drawLine(KJ.blue.copy(alpha = 0.35f * speed), Offset(x, y), Offset(x + side * 52.dp.toPx() * speed, y - 6.dp.toPx()), 3.dp.toPx(), StrokeCap.Round)
                    }
                }
                // Braking dust puffs.
                val d = dust.value
                if (d > 0f && d < 1f) {
                    val baseY = size.height * 0.5f + carHeight.toPx() * 0.46f
                    for (side in listOf(-1f, 1f)) for (k in 0 until 3) {
                        val x = size.width / 2 + side * (carWidth.toPx() * 0.38f + (18 + 22 * k).dp.toPx() * d)
                        drawCircle(KJ.muted.copy(alpha = 0.28f * (1f - d)), (7 + 5 * k).dp.toPx() * (0.5f + d), Offset(x, baseY - (6 * k).dp.toPx() * d))
                    }
                }
            }

            Box(
                Modifier.width(carWidth).height(carHeight).graphicsLayer {
                    val p = drive.value
                    val s = 0.07f + 0.93f * p
                    scaleX = s * (1f + 0.07f * squash.value)
                    scaleY = s * (1f - 0.08f * squash.value)
                    translationY = -(1f - p) * this@BoxWithConstraints.maxHeight.toPx() * 0.2f + squash.value * 10.dp.toPx()
                    // Playful sway that dies out as the car stops.
                    rotationZ = kotlin.math.sin(p * 18f) * 2.2f * (1f - p)
                },
            ) {
                Image(painterResource(R.drawable.kj_front), contentDescription = state.l("welcome_scene"), modifier = Modifier.fillMaxSize())
                Canvas(Modifier.fillMaxSize()) {
                    val a = flash.value
                    if (a > 0f) {
                        for (x in listOf(96f, 324f)) {
                            val c = Offset(size.width * x / 420f, size.height * 204f / 304f)
                            drawCircle(Color.White.copy(alpha = 0.35f * a), size.width * 0.13f, c)
                            drawCircle(Color.White.copy(alpha = 0.9f * a), size.width * 0.05f, c)
                        }
                    }
                }
            }

            if (honk.value > 0.01f) {
                Text(
                    state.l("welcome_beep"),
                    color = Color.White, fontWeight = FontWeight.Black, fontSize = 18.sp,
                    modifier = Modifier.align(Alignment.Center)
                        .offset(x = carWidth * 0.28f, y = -carHeight * 0.62f)
                        .graphicsLayer {
                            scaleX = honk.value; scaleY = honk.value
                            alpha = honk.value.coerceIn(0f, 1f)
                            rotationZ = 8f
                        }
                        .shadow(8.dp, RoundedCornerShape(50))
                        .clip(RoundedCornerShape(50))
                        .background(KJ.burgundy)
                        .padding(horizontal = 14.dp, vertical = 7.dp),
                )
            }
        }

        Column(
            Modifier.graphicsLayer { alpha = text.value; translationY = (1f - text.value) * 24.dp.toPx() },
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Text(BRAND_LINE, color = KJ.ink, fontWeight = FontWeight.Black, fontSize = 28.sp, lineHeight = 38.sp, textAlign = TextAlign.Center)
            val translation = state.l("welcome_translation")
            if (translation.isNotBlank()) {
                Spacer(Modifier.height(6.dp))
                Text(translation, color = KJ.muted, fontSize = 15.sp, textAlign = TextAlign.Center)
            }
        }
        Spacer(Modifier.height(24.dp))
        KJButton(
            state.l("welcome_start"),
            modifier = Modifier.graphicsLayer {
                alpha = button.value.coerceIn(0f, 1f)
                scaleX = 0.8f + 0.2f * button.value
                scaleY = 0.8f + 0.2f * button.value
            },
            enabled = button.value > 0.5f,
            onClick = onStart,
        )
        Spacer(Modifier.height(24.dp))
    }
}
