package app.rork.h04xk59ettzrqz7c6l4wp

import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.SystemBarStyle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.lifecycle.ViewModelProvider
import app.rork.h04xk59ettzrqz7c6l4wp.ui.navigation.AppNavigation
import app.rork.h04xk59ettzrqz7c6l4wp.ui.theme.AppTheme

class MainActivity : ComponentActivity() {
    // Same instance the Compose tree gets from viewModel() (activity scope).
    private val appState by lazy { ViewModelProvider(this)[AppState::class.java] }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        intent.data?.let { appState.handleAuthCallback(it) }
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
                AppNavigation()
            }
        }
    }
}
