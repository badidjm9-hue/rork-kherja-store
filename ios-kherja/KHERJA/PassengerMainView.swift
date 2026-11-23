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
        TabView(selection: $tab) {
            PassengerHomeView()
                .tabItem { Label(store.l("tab_home"), systemImage: "house.fill") }
                .tag(0)
            HistoryView()
                .tabItem { Label(store.l("tab_history"), systemImage: "clock.fill") }
                .tag(1)
            WalletView()
                .tabItem { Label(store.l("tab_wallet"), systemImage: "wallet.bifold.fill") }
                .tag(2)
            SettingsView()
                .tabItem { Label(store.l("tab_settings"), systemImage: "gearshape.fill") }
                .tag(3)
        }
        .tint(KJ.blue)
        .task { await store.refreshProfile() }
    }
}
