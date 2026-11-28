package app.rork.h04xk59ettzrqz7c6l4wp.ui.components

import android.animation.ValueAnimator
import android.view.animation.DecelerateInterpolator
import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.drawable.BitmapDrawable
import android.provider.Settings
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

    // Animate the native map overlay without forcing Compose to redraw every frame.
    val routeAnimator = remember { arrayOfNulls<ValueAnimator>(1) }
    val lastRouteKey = remember { arrayOfNulls<String>(1) }
    val driverAnimator = remember { arrayOfNulls<ValueAnimator>(1) }
    val lastDriverPosition = remember { arrayOfNulls<GeoPoint>(1) }
    val driverMarker = remember { arrayOfNulls<Marker>(1) }

    DisposableEffect(Unit) {
        mapView.onResume()
        onDispose {
            routeAnimator[0]?.cancel()
            routeAnimator[0] = null
            lastRouteKey[0] = null
            driverAnimator[0]?.cancel()
            driverAnimator[0] = null
            driverMarker[0] = null
            lastDriverPosition[0] = null
            mapView.onPause()
            mapView.onDetach()
        }
    }

    AndroidView(
        modifier = modifier,
        factory = { mapView },
        update = { map ->
            // Keep the currently rendered GPS position as the next animation's origin.
            val visibleDriverPosition = driverMarker[0]?.position ?: lastDriverPosition[0]
            driverAnimator[0]?.cancel()
            driverAnimator[0] = null
            driverMarker[0] = null
            routeAnimator[0]?.cancel()
            routeAnimator[0] = null
            map.overlays.clear()
            map.overlays.add(MapEventsOverlay(object : MapEventsReceiver {
                override fun singleTapConfirmedHelper(p: GeoPoint): Boolean {
                    val cb = tapHolder[0] ?: return false
                    cb(p.latitude, p.longitude)
                    return true
                }
                override fun longPressHelper(p: GeoPoint): Boolean = false
            }))
            val routeKey = route.joinToString("|") { "${it.first},${it.second}" }
            val animateRoute = route.size >= 2 && routeKey != lastRouteKey[0]
            lastRouteKey[0] = routeKey.takeIf { route.size >= 2 }
            if (route.size >= 2) {
                val line = Polyline(map).apply {
                    setPoints(route.map { GeoPoint(it.first, it.second) })
                    outlinePaint.color = KJ.blue.toArgb()
                    outlinePaint.strokeWidth = 12f
                    outlinePaint.strokeCap = Paint.Cap.ROUND
                    outlinePaint.alpha = if (animateRoute) 0 else 255
                }
                map.overlays.add(line)
                if (animateRoute) {
                    routeAnimator[0] = ValueAnimator.ofInt(0, 255).apply {
                        duration = 850L
                        interpolator = DecelerateInterpolator()
                        addUpdateListener { animation ->
                            line.outlinePaint.alpha = animation.animatedValue as Int
                            map.invalidate()
                        }
                        start()
                    }
                }
            }
            val driverPin = pins.firstOrNull { it.kind == PinKind.Driver }
            pins.filterNot { it.kind == PinKind.Driver }.forEach { pin ->
                val m = Marker(map).apply {
                    position = GeoPoint(pin.lat, pin.lng)
                    setAnchor(Marker.ANCHOR_CENTER, Marker.ANCHOR_CENTER)
                    icon = pinDrawable(context, pin.kind)
                    setInfoWindow(null)
                }
                map.overlays.add(m)
            }

            // Interpolate only between consecutive real driver GPS fixes. Never invent
            // intermediate destinations or run a perpetual animation loop.
            if (driverPin != null) {
                val target = GeoPoint(driverPin.lat, driverPin.lng)
                val startPosition = visibleDriverPosition
                val marker = Marker(map).apply {
                    position = startPosition ?: target
                    setAnchor(Marker.ANCHOR_CENTER, Marker.ANCHOR_CENTER)
                    icon = pinDrawable(context, PinKind.Driver)
                    setInfoWindow(null)
                }
                map.overlays.add(marker)
                driverMarker[0] = marker
                val motionScale = runCatching {
                    Settings.Global.getFloat(context.contentResolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f)
                }.getOrDefault(1f)
                if (startPosition != null && motionScale > 0f &&
                    (startPosition.latitude != target.latitude || startPosition.longitude != target.longitude)
                ) {
                    driverAnimator[0] = ValueAnimator.ofFloat(0f, 1f).apply {
                        duration = (900L * motionScale).toLong().coerceIn(250L, 1400L)
                        interpolator = DecelerateInterpolator()
                        addUpdateListener { animation ->
                            val t = animation.animatedValue as Float
                            marker.position = GeoPoint(
                                startPosition.latitude + (target.latitude - startPosition.latitude) * t,
                                startPosition.longitude + (target.longitude - startPosition.longitude) * t,
                            )
                            map.invalidate()
                        }
                        start()
                    }
                } else {
                    marker.position = target
                }
                lastDriverPosition[0] = target
            } else {
                lastDriverPosition[0] = null
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
