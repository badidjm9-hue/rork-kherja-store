//
//  RootView.swift
//  KHERJA
//
//  Top-level routing: splash → onboarding → main app per role.
//

import SwiftUI

enum OnboardingStep: Hashable {
    case language, auth, forgot, role, phone, otp
}

struct RootView: View {
    @EnvironmentObject var store: AppState
    @State private var minSplash = true
    @State private var path: [OnboardingStep] = []
    /// The welcome scene plays once each time the signed-out flow is entered.
    @State private var welcomed = false

    var body: some View {
        Group {
            if minSplash {
                SplashView { withAnimation(.easeInOut(duration: 0.45)) { minSplash = false } }
            } else if !store.bootstrapDone || (!store.session.isSignedIn && !welcomed) {
                // One Welcome branch: it is shown right after the intro while the session bootstrap
                // finishes, and stays the same view afterwards. Two separate branches made SwiftUI
                // rebuild Welcome when bootstrap completed, replaying its reveal (visible flicker).
                WelcomeView { withAnimation(.easeInOut(duration: 0.3)) { welcomed = true } }
                    .transition(.opacity)
            } else if !store.session.isSignedIn {
                NavigationStack(path: $path) {
                    LanguageSelectView(
                        onContinue: { path.append(.auth) }
                    )
                    .navigationDestination(for: OnboardingStep.self) { step in
                        switch step {
                        case .language: LanguageSelectView(onContinue: { path.append(.auth) })
                        case .auth:
                            AuthView(
                                onForgot: { path.append(.forgot) },
                                onSms: { PhoneFlowManager.shared.clearCredentials(); path.append(.role) },
                                onCodeSent: { path.append(.otp) }
                            )
                        case .forgot: ForgotPasswordView(onCodeSent: { path.append(.otp) })
                        case .role: RoleSelectView(onContinue: { path.append(.phone) })
                        case .phone: PhoneEntryView(onCodeSent: { PhoneFlowManager.shared.clearCredentials(); path.append(.otp) })
                        case .otp: OtpVerifyView()
                        }
                    }
                }
                .environmentObject(PhoneFlowManager.shared)
            } else if store.bootstrapFailed {
                VStack(spacing: 18) {
                    KJLogo(height: 72)
                    Text(store.l("error_generic"))
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(KJ.ink)
                        .multilineTextAlignment(.center)
                    Button {
                        Task { await store.bootstrap() }
                    } label: {
                        Text(store.l("retry"))
                    }
                    .buttonStyle(KJButtonStyle())
                    Button(store.l("logout")) { store.signOut() }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(KJ.muted)
                }
                .padding(28)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(KJ.canvasGradient.ignoresSafeArea())
            } else if store.profile == nil {
                CompleteProfileView()
            } else if store.role == "driver" && store.phoneVerified == false {
                // Driver services need a verified phone (also enforced by the database).
                LinkPhoneView()
            } else if (store.profile?.name ?? "").isEmpty {
                CompleteProfileView()
            } else if store.role == "driver" {
                DriverMainView()
            } else {
                PassengerMainView()
            }
        }
        .alert(store.l("delete_account"), isPresented: Binding(
            get: { store.accountNotice != nil },
            set: { if !$0 { store.accountNotice = nil } }
        )) {
            Button(store.l("ok"), role: .cancel) {}
        } message: {
            Text(store.accountNotice ?? "")
        }
        .animation(.easeInOut(duration: 0.25), value: store.bootstrapDone)
        .animation(.easeInOut(duration: 0.25), value: store.session.isSignedIn)
        .task {
            // Bootstrap and the one-shot intro run in parallel. Routing waits for both.
            async let boot: Void = store.bootstrap()
            await boot
            if store.session.isSignedIn { await KHERJAPushRegistration.requestIfNeeded() }
        }
        .onChange(of: store.session.isSignedIn) { _, signedIn in
            if !signedIn { welcomed = false }   // play it again after a sign-out
            if signedIn { Task { await KHERJAPushRegistration.requestIfNeeded() } }
        }
        .environment(\.layoutDirection, store.language.isRTL ? .rightToLeft : .leftToRight)
    }
}

// MARK: - Profile completion (name) after first sign-in

struct CompleteProfileView: View {
    @EnvironmentObject var store: AppState
    @State private var name = ""
    @State private var city = "Alger"
    @State private var saving = false
    @State private var errorMessage: String?

    private let cities = ["Alger", "Oran", "Constantine", "Annaba", "Blida", "Batna", "Sétif", "Tlemcen", "Béjaïa", "Ouargla"]

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 30)
            KJLogo(height: 72)

            Text(store.l("name"))
                .font(.system(size: 26, weight: .heavy))
                .foregroundStyle(KJ.ink)
                .padding(.top, 26)

            TextField(store.l("your_name"), text: $name)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(KJ.ink)
                .padding(18)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(.white)
                        .shadow(color: Color(hex: 0x075BFF).opacity(0.10), radius: 14, x: 0, y: 6)
                )
                .padding(.top, 26)
                .padding(.horizontal, 30)

            Picker(store.l("city"), selection: $city) {
                ForEach(cities, id: \.self) { Text($0).tag($0) }
            }
            .pickerStyle(.menu)
            .tint(KJ.blue)
            .padding(.top, 10)

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(KJ.danger)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
            }

            Button {
                save()
            } label: {
                if saving { ProgressView().tint(.white) } else { Text(store.l("continue")) }
            }
            .buttonStyle(KJButtonStyle())
            .disabled(name.trimmingCharacters(in: .whitespaces).count < 2 || saving)
            .padding(.top, 22)
            .padding(.horizontal, 28)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(KJ.canvasGradient.ignoresSafeArea())
        .overlay(alignment: .top) { CornerBlobs().frame(height: 220) }
        .onAppear {
            if name.isEmpty {
                let existing = store.profile?.name ?? ""
                name = existing.isEmpty ? (PhoneFlowManager.shared.pendingName ?? "") : existing
            }
        }
    }

    private func save() {
        saving = true
        errorMessage = nil
        Task {
            guard let id = store.session.userId else {
                errorMessage = store.l("error_generic")
                saving = false
                return
            }
            let update = ProfileUpdate(name: name.trimmingCharacters(in: .whitespaces), city: city, language: store.language.rawValue, role: store.role)
            do {
                try await SupabaseService.shared.updateProfile(id: id, update: update)
                await store.refreshProfile()
                if (store.profile?.name ?? "").isEmpty {
                    errorMessage = store.l("error_generic")
                }
            } catch {
                errorMessage = store.serverErrorMessage(error)
            }
            saving = false
        }
    }
}
