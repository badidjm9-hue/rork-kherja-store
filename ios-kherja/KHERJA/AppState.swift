//
//  AppState.swift
//  KHERJA
//
//  Global app state: language, role, session, profile, active flow ids.
//

import Combine
import Foundation
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    let session = SessionManager.shared
    let supabase = SupabaseService.shared

    @Published private(set) var language: AppLanguage
    @Published private(set) var role: String   // "passenger" | "driver"
    @Published var profile: Profile?
    /// nil = unknown (not loaded, or migration 0007 not deployed); the database enforces the rule regardless.
    @Published var phoneVerified: Bool?
    @Published var activeRequestId: UUID?
    @Published var activeRideId: UUID?
    @Published var bootstrapDone = false

    private let defaults = UserDefaults.standard
    private static let langKey = "kherja.language"
    private static let roleKey = "kherja.role"
    private static let reqKey = "kherja.active_request"
    private static let rideKey = "kherja.active_ride"

    init() {
        let savedLang = UserDefaults.standard.string(forKey: Self.langKey)
        language = AppLanguage(rawValue: savedLang ?? "") ?? .fr
        let savedRole = UserDefaults.standard.string(forKey: Self.roleKey)
        role = savedRole ?? "passenger"
        if let req = UserDefaults.standard.string(forKey: Self.reqKey) {
            activeRequestId = UUID(uuidString: req)
        }
        if let ride = UserDefaults.standard.string(forKey: Self.rideKey) {
            activeRideId = UUID(uuidString: ride)
        }
    }

    // MARK: Localized strings

    func l(_ key: String) -> String {
        L10n.string(key, language)
    }

    /// Localized text for an error raised by a server RPC.
    func serverErrorMessage(_ error: Error) -> String {
        l(L10n.serverErrorKey("\(error)" + " " + error.localizedDescription))
    }

    // MARK: Setters (explicit, persisted)

    func setLanguage(_ newLanguage: AppLanguage) {
        language = newLanguage
        defaults.set(newLanguage.rawValue, forKey: Self.langKey)
        if var p = profile {
            p.language = newLanguage.rawValue
            profile = p
        }
        if let id = session.userId {
            Task { [supabase] in
                try? await supabase.updateProfile(id: id, update: ProfileUpdate(language: newLanguage.rawValue))
            }
        }
    }

    func setRole(_ newRole: String) {
        role = newRole
        defaults.set(newRole, forKey: Self.roleKey)
    }

    func setActiveRequest(_ id: UUID?) {
        activeRequestId = id
        defaults.set(id?.uuidString, forKey: Self.reqKey)
    }

    func setActiveRide(_ id: UUID?) {
        activeRideId = id
        defaults.set(id?.uuidString, forKey: Self.rideKey)
    }

    // MARK: Bootstrap

    func bootstrap() async {
        guard session.isSignedIn else {
            bootstrapDone = true
            return
        }
        guard let id = session.userId else {
            bootstrapDone = true
            return
        }
        do {
            profile = try await supabase.profile(id: id)
            phoneVerified = try? await supabase.phoneVerified()
            if let p = profile {
                role = p.role
                if let lang = AppLanguage(rawValue: p.language) {
                    language = lang
                }
            }
            await resumeActiveFlow()
        } catch {
            print("KHERJA bootstrap error: \(error)")
        }
        bootstrapDone = true
    }

    /// Restore in-flight request/ride after relaunch.
    func resumeActiveFlow() async {
        if let rideId = activeRideId {
            if let ride = try? await supabase.ride(id: rideId), ride.status != "completed", ride.status != "cancelled" {
                return // keep
            }
            setActiveRide(nil)
        }
        if let reqId = activeRequestId {
            let requests = (try? await supabase.myRequests(passengerId: session.userId ?? UUID())) ?? []
            if let req = requests.first(where: { $0.id == reqId }), req.status == "open" || req.status == "negotiating" {
                return // keep
            }
            setActiveRequest(nil)
        }
    }

    func refreshProfile() async {
        guard let id = session.userId else { return }
        if let p = try? await supabase.profile(id: id) {
            profile = p
        }
        phoneVerified = try? await supabase.phoneVerified()
    }

    func signOut() {
        session.signOut()
        profile = nil
        phoneVerified = nil
        setActiveRequest(nil)
        setActiveRide(nil)
    }
}
