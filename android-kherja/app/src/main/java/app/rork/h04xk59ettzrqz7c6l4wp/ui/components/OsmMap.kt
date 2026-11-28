package app.rork.h04xk59ettzrqz7c6l4wp.ui.components

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.drawable.BitmapDrawable
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.tween
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.viewinterop.AndroidView
import app.rork.h04xk59ettzrqz7c6l4wp.ui.theme.KJ
import org.osmdroid.config.Configuration
import org.osmdroid.events.MapEventsReceiver
import org.osmdroid.tileprovider.tilesource.TileSourceFactory
import org.osmdroid.util.BoundingBox
import org.osmdroid.util.GeoPoint
import org.osmdroid.views.CustomZoomButtonsController
import org.osmdroid.views.MapView
import org.osmdroid.views.overlay.MapEventsOverlay
import org.osmdroid.views.overlay.Marker
import org.osmdroid.views.overlay.Polyline

data class MapPin(val lat: Double, val lng: Double, val kind: PinKind)

enum class PinKind { Pickup, Destination, Driver, Me }

/** Default view: Algiers. */
val ALGIERS = GeoPoint(36.7538, 3.0588)

/**
 * OpenStreetMap view (osmdroid). Pins and route are redrawn when they change;
 * the camera fits pins on change of [fitKey].
 */
@Composable
fun OsmMap(
    modifier: Modifier = Modifier,
    pins: List<MapPin>,
    route: List<Pair<Double, Double>> = emptyList(),
    fitKey: Any? = null,
    center: GeoPoint? = null,
    onTap: ((Double, Double) -> Unit)? = null,
) {
    val context = LocalContext.current
    val mapView = remember {
        Configuration.getInstance().userAgentValue = context.packageName
        Configuration.getInstance().osmdroidBasePath = context.cacheDir
        Configuration.getInstance().osmdroidTileCache = context.cacheDir.resolve("tiles")
        MapView(context).apply {
            setTileSource(TileSourceFactory.MAPNIK)
            setMultiTouchControls(true)
            zoomController.setVisibility(CustomZoomButtonsController.Visibility.NEVER)
            isTilesScaledToDpi = true
            minZoomLevel = 5.0
            maxZoomLevel = 19.0
            controller.setZoom(13.0)
            controller.setCenter(ALGIERS)
        }
    }
    val tapHolder = remember { arrayOfNulls<((Double, Double) -> Unit)?>(1) }
    tapHolder[0] = onTap

    // Reveal a new route progressively instead of flashing the complete line.
    val routeProgress = remember { Animatable(0f) }
    LaunchedEffect(route) {
        routeProgress.snapTo(0f)
        if (route.size >= 2) {
            routeProgress.animateTo(1f, animationSpec = tween(durationMillis = 900))
        }
    }
    val visibleRoute = revealRoute(route, routeProgress.value)

    DisposableEffect(Unit) {
        mapView.onResume()
        onDispose {
            mapView.onPause()
            mapView.onDetach()
        }
    }

    AndroidView(
        modifier = modifier,
        factory = { mapView },
        update = { map ->
            map.overlays.clear()
            map.overlays.add(MapEventsOverlay(object : MapEventsReceiver {
                override fun singleTapConfirmedHelper(p: GeoPoint): Boolean {
                    val cb = tapHolder[0] ?: return false
                    cb(p.latitude, p.longitude)
                    return true
                }
                override fun longPressHelper(p: GeoPoint): Boolean = false
            }))
            if (route.size >= 2) {
                val line = Polyline(map).apply {
                    setPoints(route.map { GeoPoint(it.first, it.second) })
                    outlinePaint.color = KJ.blue.toArgb()
                    outlinePaint.strokeWidth = 12f
                    outlinePaint.strokeCap = Paint.Cap.ROUND
                }
                map.overlays.add(line)
            }
            pins.forEach { pin ->
                val m = Marker(map).apply {
                    position = GeoPoint(pin.lat, pin.lng)
                    setAnchor(Marker.ANCHOR_CENTER, Marker.ANCHOR_CENTER)
                    icon = pinDrawable(context, pin.kind)
                    setInfoWindow(null)
                }
                map.overlays.add(m)
            }
            map.invalidate()
        },
    )

    LaunchedEffect(fitKey) {
        val points = pins.map { GeoPoint(it.lat, it.lng) } + route.map { GeoPoint(it.first, it.second) }
        when {
            points.size >= 2 -> mapView.post {
                runCatching {
                    val box = BoundingBox.fromGeoPoints(points)
                    mapView.zoomToBoundingBox(box.increaseByScale(1.5f), true, 80)
                }
            }
            points.size == 1 -> {
                mapView.controller.setZoom(15.0)
                mapView.controller.animateTo(points.first())
            }
            center != null -> mapView.controller.animateTo(center)
        }
    }
}


private fun revealRoute(
    points: List<Pair<Double, Double>>,
    progress: Float,
): List<Pair<Double, Double>> {
    if (points.size < 2) return points
    val position = progress.coerceIn(0f, 1f) * (points.size - 1)
    val completed = position.toInt()
    val fraction = position - completed
    val result = points.take(completed + 1).toMutableList()
    if (completed < points.lastIndex) {
        val start = points[completed]
        val end = points[completed + 1]
        result += Pair(
            start.first + (end.first - start.first) * fraction,
            start.second + (end.second - start.second) * fraction,
        )
    }
    return result
}

private fun pinDrawable(context: Context, kind: PinKind): BitmapDrawable {
    val d = context.resources.displayMetrics.density
    val size = (if (kind == PinKind.Me) 22 else 30) * d
    val bmp = Bitmap.createBitmap(size.toInt(), size.toInt(), Bitmap.Config.ARGB_8888)
    val c = Canvas(bmp)
    val p = Paint(Paint.ANTI_ALIAS_FLAG)
    val r = size / 2
    val fill = when (kind) {
        PinKind.Pickup -> KJ.blue
        PinKind.Destination -> KJ.burgundy
        PinKind.Driver -> KJ.ink
        PinKind.Me -> KJ.blue
    }
    p.color = Color.White.toArgb()
    c.drawCircle(r, r, r, p)
    p.color = fill.toArgb()
    c.drawCircle(r, r, r - 3.5f * d, p)
    p.color = Color.White.toArgb()
    c.drawCircle(r, r, if (kind == PinKind.Me) 3f * d else 5f * d, p)
    return BitmapDrawable(context.resources, bmp)
}
