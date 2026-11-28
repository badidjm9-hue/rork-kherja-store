package app.rork.h04xk59ettzrqz7c6l4wp.ui.screens

import android.graphics.SurfaceTexture
import android.media.MediaPlayer
import android.os.Build
import android.view.Surface
import android.view.TextureView
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.blur
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
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

/**
 * Opening sequence. The supplied street clip (same two characters, untouched) plays once: the car rushes
 * at the camera. Native effects are layered at the moment of impact: camera shake, motion blur (Android 12+),
 * a glass crack across the whole screen and a flash; then the card dissolves and the KHERJA logo is revealed.
 * With animations disabled the logo is shown straight away. The clip is a plain H.264 file played with
 * MediaPlayer on a TextureView (no third-party player, Lottie or Rive).
 */
@Composable
fun SplashScreen(state: AppState) {
    val reduce = rememberReduceMotion()
    val haptic = LocalHapticFeedback.current
    val shake = remember { Animatable(0f) }
    val flash = remember { Animatable(0f) }
    val crack = remember { Animatable(0f) }
    val crackAlpha = remember { Animatable(1f) }
    val blurRadius = remember { Animatable(0f) }
    val card = remember { Animatable(if (reduce) 0f else 1f) }
    val logo = remember { Animatable(if (reduce) 1f else 0f) }
    var videoFailed by remember { mutableStateOf(false) }

    LaunchedEffect(reduce) {
        if (reduce) return@LaunchedEffect
        // The clip is 2.1 s; the car fills the windscreen around 1.75 s.
        delay(1750)
        launch { shake.animateTo(1f, tween(1150, easing = LinearEasing)) }
        delay(350)
        // Impact.
        haptic.performHapticFeedback(HapticFeedbackType.LongPress)
        launch { crack.animateTo(1f, tween(140, easing = FastOutSlowInEasing)) }
        launch { flash.animateTo(0.9f, tween(140)); flash.animateTo(0f, tween(250)) }
        launch { blurRadius.animateTo(14f, tween(350)) }
        delay(450)
        // Dissolve the scene and reveal the brand.
        launch { crackAlpha.animateTo(0f, tween(500)) }
        launch { card.animateTo(0f, tween(500, easing = FastOutSlowInEasing)) }
        logo.animateTo(1f, spring(Spring.DampingRatioLowBouncy, Spring.StiffnessLow))
    }

    Box(
        Modifier
            .fillMaxSize()
            .background(KJ.canvasGradient)
            .graphicsLayer {
                val t = shake.value
                val envelope = if (t < 0.30f) 0.25f * (t / 0.30f) else (1f - (t - 0.30f) / 0.70f).coerceAtLeast(0f).pow(2)
                translationX = 12.dp.toPx() * envelope * sin(t * PI.toFloat() * 19f)
                translationY = 8.dp.toPx() * envelope * cos(t * PI.toFloat() * 23f)
            },
    ) {
        Column(
            Modifier
                .align(Alignment.Center)
                .graphicsLayer {
                    alpha = logo.value.coerceIn(0f, 1f)
                    val s = 0.82f + 0.18f * logo.value
                    scaleX = s; scaleY = s
                },
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            KJLogo(120.dp)
            Spacer(Modifier.height(20.dp))
            Text(state.l("app_tagline"), color = KJ.burgundy, fontSize = 16.sp, fontWeight = FontWeight.SemiBold, textAlign = TextAlign.Center, modifier = Modifier.padding(horizontal = 40.dp))
            Spacer(Modifier.height(24.dp))
            CircularProgressIndicator(color = KJ.blue, strokeWidth = 3.dp, modifier = Modifier.size(26.dp))
        }

        if (card.value > 0f) {
            Box(
                Modifier
                    .align(Alignment.Center)
                    .padding(horizontal = 16.dp)
                    .fillMaxWidth()
                    .aspectRatio(438f / 388f)
                    .graphicsLayer {
                        alpha = card.value
                        val s = 1f + 0.12f * (1f - card.value)
                        scaleX = s; scaleY = s
                    }
                    .shadow(18.dp, RoundedCornerShape(28.dp), ambientColor = KJ.blue.copy(alpha = 0.3f), spotColor = KJ.blue.copy(alpha = 0.25f))
                    .clip(RoundedCornerShape(28.dp))
                    .then(if (blurRadius.value > 0.5f && Build.VERSION.SDK_INT >= 31) Modifier.blur(blurRadius.value.dp) else Modifier),
            ) {
                if (reduce || videoFailed) {
                    Image(painterResource(R.drawable.kj_splash_a), null, contentScale = ContentScale.Crop, modifier = Modifier.fillMaxSize())
                } else {
                    // Poster = first frame of the clip, so the hand-over to video is seamless.
                    Image(painterResource(R.drawable.kj_splash_a), null, contentScale = ContentScale.Crop, modifier = Modifier.fillMaxSize())
                    SplashVideo(R.raw.kj_splash, Modifier.fillMaxSize()) { videoFailed = true }
                }
            }
        }

        Canvas(Modifier.fillMaxSize()) { drawCracks(crack.value, crackAlpha.value) }
        Box(Modifier.fillMaxSize().graphicsLayer { alpha = flash.value }.background(Color.White))
    }
}

/** Glass crack radiating from just above the screen centre. Deterministic (fixed seed). */
private fun DrawScope.drawCracks(progress: Float, alpha: Float) {
    if (progress <= 0f || alpha <= 0f) return
    val rnd = kotlin.random.Random(7)
    val c = Offset(size.width / 2f, size.height * 0.42f)
    val reach = hypot(size.width, size.height) * 0.7f * progress
    val path = Path()
    val rays = 16
    for (i in 0 until rays) {
        var angle = i.toFloat() / rays * 2f * PI.toFloat() + (rnd.nextFloat() - 0.5f) * 0.25f
        var x = c.x; var y = c.y
        path.moveTo(x, y)
        for (step in 1..5) {
            val len = reach / 5f * (0.7f + 0.6f * rnd.nextFloat())
            angle += (rnd.nextFloat() - 0.5f) * 0.5f
            x += cos(angle) * len; y += sin(angle) * len
            path.lineTo(x, y)
            if (step == 2 || step == 4) {
                val b = angle + if (rnd.nextFloat() > 0.5f) 0.9f else -0.9f
                path.lineTo(x + cos(b) * len * 0.8f, y + sin(b) * len * 0.8f)
                path.moveTo(x, y)
            }
        }
    }
    for (ring in listOf(0.16f, 0.34f)) {
        val radius = reach * ring
        for (k in 0..rays) {
            val a = k.toFloat() / rays * 2f * PI.toFloat()
            val r = radius * (0.85f + 0.3f * rnd.nextFloat())
            val px = c.x + cos(a) * r; val py = c.y + sin(a) * r
            if (k == 0) path.moveTo(px, py) else path.lineTo(px, py)
        }
    }
    drawPath(path, KJ.ink.copy(alpha = 0.35f * alpha), style = Stroke(3.5.dp.toPx(), cap = StrokeCap.Round, join = StrokeJoin.Round))
    drawPath(path, Color.White.copy(alpha = 0.92f * alpha), style = Stroke(1.5.dp.toPx(), cap = StrokeCap.Round, join = StrokeJoin.Round))
}

/** Muted, play-once clip on a TextureView (so Compose transforms apply). Releases the player on leave. */
@Composable
private fun SplashVideo(rawRes: Int, modifier: Modifier = Modifier, onFailed: () -> Unit) {
    val ctx = LocalContext.current
    AndroidView(
        modifier = modifier,
        factory = {
            TextureView(ctx).apply {
                surfaceTextureListener = object : TextureView.SurfaceTextureListener {
                    private var player: MediaPlayer? = null
                    private var surface: Surface? = null

                    override fun onSurfaceTextureAvailable(st: SurfaceTexture, width: Int, height: Int) {
                        try {
                            val afd = ctx.resources.openRawResourceFd(rawRes)
                            val s = Surface(st)
                            surface = s
                            player = MediaPlayer().apply {
                                setDataSource(afd.fileDescriptor, afd.startOffset, afd.length)
                                afd.close()
                                setSurface(s)
                                isLooping = false
                                setVolume(0f, 0f)
                                setOnPreparedListener { it.start() }
                                setOnErrorListener { _, _, _ -> onFailed(); true }
                                prepareAsync()
                            }
                        } catch (_: Throwable) {
                            onFailed()
                        }
                    }

                    override fun onSurfaceTextureSizeChanged(st: SurfaceTexture, width: Int, height: Int) {}
                    override fun onSurfaceTextureUpdated(st: SurfaceTexture) {}
                    override fun onSurfaceTextureDestroyed(st: SurfaceTexture): Boolean {
                        try { player?.release() } catch (_: Throwable) {}
                        player = null
                        surface?.release()
                        surface = null
                        return true
                    }
                }
            }
        },
    )
}
