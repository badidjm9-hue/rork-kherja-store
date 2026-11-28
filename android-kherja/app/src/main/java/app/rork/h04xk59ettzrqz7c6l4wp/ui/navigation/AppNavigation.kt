package app.rork.h04xk59ettzrqz7c6l4wp.ui.navigation

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AccountBalanceWallet
import androidx.compose.material.icons.filled.DirectionsCar
import androidx.compose.material.icons.filled.History
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.LocalShipping
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.Icon
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.NavigationBarItemDefaults
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.LayoutDirection
import androidx.lifecycle.viewmodel.compose.viewModel
import app.rork.h04xk59ettzrqz7c6l4wp.AppState
import app.rork.h04xk59ettzrqz7c6l4wp.ui.screens.CompleteProfileScreen
import app.rork.h04xk59ettzrqz7c6l4wp.ui.screens.DriverGate
import app.rork.h04xk59ettzrqz7c6l4wp.ui.screens.DriverHomeScreen
import app.rork.h04xk59ettzrqz7c6l4wp.ui.screens.DeliveryScreen
import app.rork.h04xk59ettzrqz7c6l4wp.ui.screens.HistoryScreen
import app.rork.h04xk59ettzrqz7c6l4wp.ui.screens.LinkPhoneScreen
import app.rork.h04xk59ettzrqz7c6l4wp.ui.screens.OnboardingFlow
import app.rork.h04xk59ettzrqz7c6l4wp.ui.screens.PassengerHomeScreen
import app.rork.h04xk59ettzrqz7c6l4wp.ui.screens.SettingsScreen
import app.rork.h04xk59ettzrqz7c6l4wp.ui.screens.SplashScreen
import app.rork.h04xk59ettzrqz7c6l4wp.ui.screens.WalletScreen
import app.rork.h04xk59ettzrqz7c6l4wp.ui.theme.KJ
import app.rork.h04xk59ettzrqz7c6l4wp.ui.components.KJButton
import app.rork.h04xk59ettzrqz7c6l4wp.ui.components.KJOutlineButton
import androidx.compose.ui.unit.dp

private enum class RootScreen { Splash, Onboarding, Profile, LinkPhone, Driver, Passenger }

@Composable
fun AppNavigation() {
    val state: AppState = viewModel()
    var minSplashDone by rememberSaveable { mutableStateOf(false) }
    LaunchedEffect(Unit) {
        kotlinx.coroutines.delay(1_500)
        minSplashDone = true
    }
    val dir = if (state.isRtl) LayoutDirection.Rtl else LayoutDirection.Ltr
    val root = when {
        !state.bootstrapDone || !minSplashDone -> RootScreen.Splash
        !state.signedIn -> RootScreen.Onboarding
        state.profile == null -> RootScreen.Profile
        // Driver services need a verified phone (also enforced by the database).
        state.role == "driver" && state.phoneVerified == false -> RootScreen.LinkPhone
        state.profile?.name.isNullOrBlank() -> RootScreen.Profile
        state.role == "driver" -> RootScreen.Driver
        else -> RootScreen.Passenger
    }
    CompositionLocalProvider(LocalLayoutDirection provides dir) {
        AnimatedContent(root, transitionSpec = { fadeIn(tween(250)) togetherWith fadeOut(tween(200)) }, label = "root") { r ->
            when (r) {
                RootScreen.Splash -> SplashScreen(state)
                RootScreen.Onboarding -> OnboardingFlow(state)
                RootScreen.Profile -> if (state.profile == null && state.signedIn) ProfileLoading(state) else CompleteProfileScreen(state)
                RootScreen.LinkPhone -> LinkPhoneScreen(state)
                RootScreen.Driver -> DriverGate(state) { DriverTabs(state) }
                RootScreen.Passenger -> DriverGate(state, driverRules = false) { PassengerTabs(state) }
            }
        }
    }
}

@Composable
private fun ProfileLoading(state: AppState) {
    // Profile row is created by a trigger at sign-up; retry fetching briefly.
    var attempt by rememberSaveable { mutableIntStateOf(0) }
    var failed by androidx.compose.runtime.remember { androidx.compose.runtime.mutableStateOf(false) }
    androidx.compose.runtime.LaunchedEffect(attempt) {
        failed = false
        repeat(5) {
            state.refreshProfile()
            if (state.profile != null) return@LaunchedEffect
            kotlinx.coroutines.delay(1500)
        }
        failed = true
    }
    if (!failed) {
        SplashScreen(state)
        return
    }
    androidx.compose.foundation.layout.Column(
        Modifier.fillMaxSize().padding(24.dp),
        verticalArrangement = androidx.compose.foundation.layout.Arrangement.Center,
        horizontalAlignment = androidx.compose.ui.Alignment.CenterHorizontally,
    ) {
        Text(state.l("error_generic"), color = KJ.ink, fontWeight = FontWeight.Bold)
        androidx.compose.foundation.layout.Spacer(Modifier.padding(8.dp))
        KJButton(state.l("retry")) { attempt++ }
        androidx.compose.foundation.layout.Spacer(Modifier.padding(6.dp))
        KJOutlineButton(state.l("logout"), color = KJ.danger) { state.signOut() }
    }
}

private data class Tab(val label: String, val icon: ImageVector)

@Composable
private fun TabScaffold(tabs: List<Tab>, selected: Int, onSelect: (Int) -> Unit, content: @Composable (Int) -> Unit) {
    Scaffold(
        containerColor = KJ.canvas,
        bottomBar = {
            NavigationBar(containerColor = Color.White) {
                tabs.forEachIndexed { i, t ->
                    NavigationBarItem(
                        selected = selected == i,
                        onClick = { onSelect(i) },
                        icon = { Icon(t.icon, null) },
                        label = { Text(t.label, fontWeight = if (selected == i) FontWeight.Bold else FontWeight.Normal) },
                        colors = NavigationBarItemDefaults.colors(
                            selectedIconColor = KJ.blue, selectedTextColor = KJ.blue,
                            indicatorColor = KJ.softBlue, unselectedIconColor = KJ.muted, unselectedTextColor = KJ.muted,
                        ),
                    )
                }
            }
        },
    ) { padding ->
        Box(Modifier.fillMaxSize().padding(bottom = padding.calculateBottomPadding())) {
            AnimatedContent(
                targetState = selected,
                transitionSpec = {
                    (fadeIn(tween(190)) + slideInVertically(
                        animationSpec = tween(230),
                        initialOffsetY = { fullHeight -> fullHeight / 18 },
                    )) togetherWith
                        (fadeOut(tween(130)) + slideOutVertically(
                            animationSpec = tween(180),
                            targetOffsetY = { fullHeight -> -fullHeight / 28 },
                        ))
                },
                label = "tab-transition",
            ) { targetTab ->
                content(targetTab)
            }
        }
    }
}

@Composable
private fun PassengerTabs(state: AppState) {
    var tab by rememberSaveable { mutableIntStateOf(0) }
    val tabs = listOf(
        Tab(state.l("tab_home"), Icons.Filled.Home),
        Tab(state.l("tab_delivery"), Icons.Filled.LocalShipping),
        Tab(state.l("tab_history"), Icons.Filled.History),
        Tab(state.l("tab_wallet"), Icons.Filled.AccountBalanceWallet),
        Tab(state.l("tab_settings"), Icons.Filled.Settings),
    )
    TabScaffold(tabs, tab, { tab = it }) { i ->
        when (i) {
            0 -> PassengerHomeScreen(state)
            1 -> DeliveryScreen(state, driver = false)
            2 -> HistoryScreen(state, driver = false)
            3 -> WalletScreen(state, driver = false)
            else -> SettingsScreen(state)
        }
    }
}

@Composable
private fun DriverTabs(state: AppState) {
    var tab by rememberSaveable { mutableIntStateOf(0) }
    val tabs = listOf(
        Tab(state.l("tab_jobs"), Icons.Filled.DirectionsCar),
        Tab(state.l("tab_delivery"), Icons.Filled.LocalShipping),
        Tab(state.l("tab_history"), Icons.Filled.History),
        Tab(state.l("tab_earnings"), Icons.Filled.AccountBalanceWallet),
        Tab(state.l("tab_profile"), Icons.Filled.Person),
    )
    TabScaffold(tabs, tab, { tab = it }) { i ->
        when (i) {
            0 -> DriverHomeScreen(state)
            1 -> DeliveryScreen(state, driver = true)
            2 -> HistoryScreen(state, driver = true)
            3 -> WalletScreen(state, driver = true)
            else -> SettingsScreen(state)
        }
    }
}
