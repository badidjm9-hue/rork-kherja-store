//
//  KherjaApp.swift
//  Kherja
//

import SwiftUI

@main
struct KherjaApp: App {
    @StateObject private var store = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .tint(KJ.blue)
        }
    }
}
