//
//  KHERJAApp.swift
//  KHERJA
//

import SwiftUI
import UIKit
import UserNotifications

@main
struct KHERJAApp: App {
    @UIApplicationDelegateAdaptor(KHERJAPushDelegate.self) private var pushDelegate
    @StateObject private var store = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .tint(KJ.blue)
        }
    }
}


@MainActor
final class KHERJAPushDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        UserDefaults.standard.set(token, forKey: KHERJAPushRegistration.tokenKey)
        Task { try? await SupabaseService.shared.registerPushDevice(token: token) }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .badge])
    }
}

@MainActor
enum KHERJAPushRegistration {
    static let tokenKey = "kherja.apns.device_token"
    static var cachedToken: String? { UserDefaults.standard.string(forKey: tokenKey) }

    static func requestIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        var allowed = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
        if settings.authorizationStatus == .notDetermined {
            allowed = (try? await center.requestAuthorization(options: [.alert, .badge, .sound])) ?? false
        }
        guard allowed else { return }
        UIApplication.shared.registerForRemoteNotifications()
        if let token = cachedToken {
            try? await SupabaseService.shared.registerPushDevice(token: token)
        }
    }
}
