package app.rork.h04xk59ettzrqz7c6l4wp.ui.screens

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.LinearOutSlowInEasing
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
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
import androidx.compose.ui.graphics.Color
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

private const val FRAME_ASPECT = 388f / 438f
private const val STILL_FRAME = R.drawable.welcome_drive_2
private const val BRAND_LINE = "تنقّل بأمان مع خرجة"

/**
 * Stable Welcome screen. The original car animation is played only by SplashScreen;
 * Welcome displays one still frame and never starts, loops, or replays the intro.
 */
@Composable
fun WelcomeScreen(state: AppState, onStart: () -> Unit) {
    val reduce = rememberReduceMotion()
    val haptic = LocalHapticFeedback.current
    val text = remember { Animatable(if (reduce) 1f else 0f) }
    val button = remember { Animatable(if (reduce) 1f else 0f) }
    var skipped by remember { mutableStateOf(false) }

    LaunchedEffect(skipped, reduce) {
        if (reduce || skipped) {
            text.snapTo(1f)
            button.snapTo(1f)
            return@LaunchedEffect
        }
        delay(350)
        launch { text.animateTo(1f, tween(450, easing = LinearOutSlowInEasing)) }
        delay(450)
        haptic.performHapticFeedback(HapticFeedbackType.TextHandleMove)
        button.animateTo(1f, spring(Spring.DampingRatioMediumBouncy, Spring.StiffnessLow))
    }

    Column(
        Modifier.fillMaxSize()
            .clickable(remember { MutableInteractionSource() }, null, enabled = button.value < 1f) { skipped = true }
            .padding(horizontal = 24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Spacer(Modifier.height(20.dp))
        KJLogo(64.dp)
        BoxWithConstraints(Modifier.weight(1f).fillMaxWidth(), contentAlignment = Alignment.Center) {
            val artWidth = min(min(maxWidth, 460.dp), maxHeight / FRAME_ASPECT)
            Image(
                painter = painterResource(STILL_FRAME),
                contentDescription = state.l("welcome_scene"),
                modifier = Modifier.width(artWidth).height(artWidth * FRAME_ASPECT),
            )
        }

        Column(
            Modifier.graphicsLayer { alpha = text.value; translationY = (1f - text.value) * 20.dp.toPx() },
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Text(BRAND_LINE, color = KJ.ink, fontWeight = FontWeight.Black, fontSize = 28.sp, lineHeight = 38.sp, textAlign = TextAlign.Center)
            Spacer(Modifier.height(8.dp))
            Box(Modifier.width(44.dp).height(4.dp).clip(RoundedCornerShape(50)).background(KJ.burgundy))
            val translation = state.l("welcome_translation")
            if (translation.isNotBlank()) {
                Spacer(Modifier.height(8.dp))
                Text(translation, color = KJ.muted, fontSize = 15.sp, textAlign = TextAlign.Center)
            }
        }
        Spacer(Modifier.height(24.dp))
        KJButton(
            state.l("welcome_start"),
            modifier = Modifier.graphicsLayer {
                alpha = button.value.coerceIn(0f, 1f)
                scaleX = 0.9f + 0.1f * button.value
                scaleY = 0.9f + 0.1f * button.value
            },
            enabled = button.value > 0.5f,
            onClick = onStart,
        )
        Spacer(Modifier.height(24.dp))
    }
}
