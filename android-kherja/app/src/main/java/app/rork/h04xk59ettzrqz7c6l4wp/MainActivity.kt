package app.rork.h04xk59ettzrqz7c6l4wp

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.result.contract.ActivityResultContracts
import androidx.activity.SystemBarStyle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.runtime.LaunchedEffect
import androidx.lifecycle.ViewModelProvider
import app.rork.h04xk59ettzrqz7c6l4wp.ui.navigation.AppNavigation
import app.rork.h04xk59ettzrqz7c6l4wp.ui.theme.AppTheme

class MainActivity : ComponentActivity() {
    private val notificationPermission = registerForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        if (granted) appState.syncPushToken()
    }
    // Same instance the Compose tree gets from viewModel() (activity scope).
    private val appState by lazy { ViewModelProvider(this)[AppState::class.java] }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        intent.data?.let { appState.handleAuthCallback(it) }
    }

    override fun onResume() {
        super.onResume()
        if (appState.signedIn) appState.syncPushToken()
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge(
            statusBarStyle = SystemBarStyle.light(android.graphics.Color.TRANSPARENT, android.graphics.Color.TRANSPARENT),
            navigationBarStyle = SystemBarStyle.light(android.graphics.Color.WHITE, android.graphics.Color.WHITE),
        )
        if (savedInstanceState == null) intent?.data?.let { appState.handleAuthCallback(it) }
        setContent {
            AppTheme {
                LaunchedEffect(appState.signedIn) {
                    if (appState.signedIn) {
                        if (Build.VERSION.SDK_INT >= 33 && checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                            notificationPermission.launch(Manifest.permission.POST_NOTIFICATIONS)
                        } else {
                            appState.syncPushToken()
                        }
                    }
                }
                AppNavigation()
            }
        }
    }
}
