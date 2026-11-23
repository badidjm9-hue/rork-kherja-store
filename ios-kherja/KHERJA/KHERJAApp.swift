//
//  KHERJAApp.swift
//  KHERJA
//

import SwiftUI

@main
struct KHERJAApp: App {
    @StateObject private var store = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .tint(KJ.blue)
        }
    }
}
