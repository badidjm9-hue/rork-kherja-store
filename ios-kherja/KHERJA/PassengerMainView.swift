//
//  PassengerMainView.swift
//  KHERJA
//
//  Passenger tabs: Accueil / Historique / Portefeuille / Paramètres.
//

import SwiftUI

struct PassengerMainView: View {
    @EnvironmentObject var store: AppState
    @State private var tab = 0

    var body: some View {
        if store.profile?.accountStatus == "suspended" {
            // Suspended accounts see their status instead of tabs whose actions would all fail.
            DriverStatusView(kind: .suspended, reason: store.profile?.statusReason, showSignOut: true)
                .task { await store.refreshProfile() }
        } else {
            tabs
        }
    }

    private var tabs: some View {
        TabView(selection: $tab) {
            PassengerHomeView()
                .tabItem { Label(store.l("tab_home"), systemImage: "house.fill") }
                .tag(0)
            DeliveryView()
                .tabItem { Label(store.l("tab_delivery"), systemImage: "shippingbox.fill") }
                .tag(1)
            HistoryView()
                .tabItem { Label(store.l("tab_history"), systemImage: "clock.fill") }
                .tag(2)
            WalletView()
                .tabItem { Label(store.l("tab_wallet"), systemImage: "wallet.bifold.fill") }
                .tag(3)
            SettingsView()
                .tabItem { Label(store.l("tab_settings"), systemImage: "gearshape.fill") }
                .tag(4)
        }
        .tint(KJ.blue)
        .task { await store.refreshProfile() }
    }
}
