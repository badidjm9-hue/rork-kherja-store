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
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
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
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.TransformOrigin
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.rork.h04xk59ettzrqz7c6l4wp.AppState
import app.rork.h04xk59ettzrqz7c6l4wp.R
import app.rork.h04xk59ettzrqz7c6l4wp.ui.components.KJButton
import app.rork.h04xk59ettzrqz7c6l4wp.ui.components.KJLogo
import app.rork.h04xk59ettzrqz7c6l4wp.ui.components.rememberReduceMotion
import app.rork.h04xk59ettzrqz7c6l4wp.ui.theme.KJ
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/** The brand line is shown in Arabic in every language; other languages add a translation below it. */
private const val BRAND_LINE = "تنقّل بأمان مع خرجة"

/**
 * Calm welcome scene. Same two characters as the splash (the supplied street scene), no vector stand-ins:
 * the street slowly pushes in once, then the brand line and the start button settle in.
 * Everything is one-shot (no endless loops). With animations disabled the final state is shown.
 */
@Composable
fun WelcomeScreen(state: AppState, onStart: () -> Unit) {
    val reduce = rememberReduceMotion()
    val haptic = LocalHapticFeedback.current
    val push = remember { Animatable(if (reduce) 1f else 0f) }
    val text = remember { Animatable(if (reduce) 1f else 0f) }
    val button = remember { Animatable(if (reduce) 1f else 0f) }
    var skipped by remember { mutableStateOf(false) }

    LaunchedEffect(skipped) {
        if (reduce || skipped) {
            push.snapTo(1f); text.snapTo(1f); button.snapTo(1f)
            return@LaunchedEffect
        }
        launch { push.animateTo(1f, tween(6000, easing = LinearOutSlowInEasing)) }
        delay(350)
        launch { text.animateTo(1f, tween(450, easing = LinearOutSlowInEasing)) }
        delay(450)
        haptic.performHapticFeedback(HapticFeedbackType.TextHandleMove)
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
        Spacer(Modifier.weight(1f))

        Box(
            Modifier
                .fillMaxWidth()
                .aspectRatio(438f / 388f)
                .shadow(20.dp, RoundedCornerShape(28.dp), ambientColor = KJ.blue.copy(alpha = 0.25f), spotColor = KJ.blue.copy(alpha = 0.2f))
                .clip(RoundedCornerShape(28.dp)),
        ) {
            Image(
                painterResource(R.drawable.kj_splash_a),
                contentDescription = state.l("welcome_scene"),
                contentScale = ContentScale.Crop,
                modifier = Modifier.fillMaxSize().graphicsLayer {
                    val s = 1f + 0.08f * push.value
                    scaleX = s; scaleY = s
                    transformOrigin = TransformOrigin(0.5f, 0.6f)
                    translationY = -6.dp.toPx() * push.value
                },
            )
            // Brand wash: royal blue from below, a touch of burgundy at the horizon.
            Box(Modifier.fillMaxSize().background(Brush.verticalGradient(listOf(Color.Transparent, KJ.blue.copy(alpha = 0.22f)))))
            Box(Modifier.fillMaxSize().background(Brush.linearGradient(listOf(KJ.burgundy.copy(alpha = 0.10f), Color.Transparent), end = androidx.compose.ui.geometry.Offset(400f, 400f))))
        }

        Spacer(Modifier.weight(1f))

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
