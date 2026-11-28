//
//  AuthViews.swift
//  KHERJA
//
//  Login / register / forgot-password, following the KHERJA login reference:
//  bilingual labels, Connexion | Créer un compte tabs, remember me, Google + Apple.
//  Glass surfaces use real materials over the brand gradient.
//

import AuthenticationServices
import SwiftUI

// MARK: - Rules (client-side mirror of the server; the server re-validates everything)

nonisolated enum AuthRules {
    /// Algerian mobile: 10 digits, 05/06/07 (same rule as the legacy phone screen).
    static func normalizePhone(_ raw: String) -> String? {
        let digits = raw.filter { $0.isNumber }
        guard digits.count == 10, digits.hasPrefix("0") else { return nil }
        guard ["5", "6", "7"].contains(String(digits.dropFirst().prefix(1))) else { return nil }
        return digits
    }

    static func passwordValid(_ pw: String) -> Bool {
        guard (8...72).contains(pw.utf16.count) else { return false }
        let scalars = pw.unicodeScalars
        let hasLetter = scalars.contains {
            ($0.value >= 0x41 && $0.value <= 0x5A) || ($0.value >= 0x61 && $0.value <= 0x7A)
                || ($0.value >= 0x0600 && $0.value <= 0x06FF)
        }
        let hasDigit = scalars.contains { $0.value >= 0x30 && $0.value <= 0x39 }
        return hasLetter && hasDigit
    }

    /// Empty is valid: the contact e-mail is optional.
    static func emailValid(_ email: String) -> Bool {
        let e = email.trimmingCharacters(in: .whitespaces)
        if e.isEmpty { return true }
        return e.count <= 254 && e.range(of: "^[^\\s@]+@[^\\s@]+\\.[^\\s@]+$", options: .regularExpression) != nil
    }

    /// Maps the French messages returned by auth-otp to localized string keys.
    static func errorKey(_ message: String?) -> String {
        let m = (message ?? "").lowercased()
        if m.contains("mot de passe") && m.contains("incorrect") { return "err_login_failed" }
        if m.contains("tentatives") { return "err_too_many" }
        if m.contains("existe déjà") { return "err_account_exists" }
        if m.contains("déjà associé") || m.contains("déjà lié") { return "err_phone_used" }
        if m.contains("session requise") { return "err_session" }
        if m.contains("aucun compte") { return "err_no_account" }
        if m.contains("sms indisponible") { return "err_sms_unavailable" }
        if m.contains("code") { return "wrong_code" }
        return "error_generic"
    }

    /// Maps a thrown transport/service failure (never a business error) to a safe message key.
    static func exceptionKey(_ error: Error) -> String {
        if isCancellation(error) { return "error_generic" }
        if let e = error as? AuthServiceError { return e.messageKey }
        if error is URLError { return "err_network" }
        return "error_generic"
    }

    /// A cancelled task/request (user left the screen, task cancelled): nothing to tell the user.
    static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let u = error as? URLError, u.code == .cancelled { return true }
        return false
    }
}

// MARK: - Glass building blocks

extension View {
    /// Frosted glass: ultra-thin material, white tint, hairline highlight, soft blue shadow.
    func kjGlass(cornerRadius: CGFloat = 22) -> some View {
        background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).fill(Color.white.opacity(0.55)))
                .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).strokeBorder(Color.white.opacity(0.9), lineWidth: 1))
                .shadow(color: KJ.blue.opacity(0.10), radius: 14, x: 0, y: 6)
        )
    }
}

/// (primary, secondary): the app language first, the other language below, as in the reference.
@MainActor
private func biLabels(_ store: AppState, _ key: String) -> (primary: String, secondary: String) {
    let ar = L10n.string(key, .ar)
    let fr = L10n.string(key, .fr)
    return store.language == .ar ? (ar, fr) : (fr, ar)
}

private struct GlassField: View {
    @EnvironmentObject var store: AppState
    let labelKey: String
    let icon: String
    @Binding var text: String
    var keyboard: UIKeyboardType = .default
    var secure = false
    var contentType: UITextContentType?
    var trailing: AnyView?
    @State private var shown = false

    var body: some View {
        let labels = biLabels(store, labelKey)
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(KJ.ink)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(labels.primary)
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(KJ.ink)
                Group {
                    if secure && !shown {
                        SecureField(labels.secondary, text: $text)
                    } else {
                        TextField(labels.secondary, text: $text)
                            .keyboardType(keyboard)
                    }
                }
                .textContentType(contentType)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(KJ.ink)
            }
            if secure {
                Button { shown.toggle() } label: {
                    Image(systemName: shown ? "eye" : "eye.slash")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(KJ.ink)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(shown ? "Hide password" : "Show password")
            } else if let trailing {
                trailing
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .kjGlass()
    }
}

private struct CountryChip: View {
    var body: some View {
        HStack(spacing: 6) {
            Text("🇩🇿").font(.system(size: 18))
            Text("+213").font(.system(size: 15, weight: .bold)).foregroundStyle(KJ.ink)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Capsule().fill(KJ.softBlue.opacity(0.7)))
    }
}

private struct BiButton: View {
    @EnvironmentObject var store: AppState
    let labelKey: String
    var loading = false
    let action: () -> Void

    var body: some View {
        let labels = biLabels(store, labelKey)
        Button(action: action) {
            ZStack {
                VStack(spacing: 0) {
                    Text(labels.primary).font(.system(size: 20, weight: .heavy))
                    Text(labels.secondary).font(.system(size: 14, weight: .medium)).opacity(0.92)
                }
                .opacity(loading ? 0 : 1)
                HStack {
                    Spacer()
                    if loading {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "arrow.forward").font(.system(size: 20, weight: .semibold))
                    }
                }
                .padding(.horizontal, 26)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 64)
            .background(Capsule().fill(KJ.buttonGradient))
            .shadow(color: KJ.blue.opacity(0.35), radius: 14, x: 0, y: 8)
        }
        .buttonStyle(.plain)
        .disabled(loading)
    }
}

private struct AuthTabs: View {
    @EnvironmentObject var store: AppState
    @Binding var register: Bool

    var body: some View {
        HStack(spacing: 0) {
            tab(register: false, key: "auth_login_tab")
            tab(register: true, key: "auth_register_tab")
        }
        .padding(4)
        .kjGlass(cornerRadius: 32)
    }

    private func tab(register isRegister: Bool, key: String) -> some View {
        let active = register == isRegister
        let labels = biLabels(store, key)
        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { register = isRegister }
        } label: {
            HStack(spacing: 10) {
                if active { Image(systemName: "person.fill").font(.system(size: 20, weight: .semibold)) }
                VStack(spacing: 0) {
                    Text(labels.primary).font(.system(size: 15, weight: .heavy))
                    Text(labels.secondary).font(.system(size: 13, weight: .medium)).opacity(0.9)
                }
            }
            .foregroundStyle(active ? Color.white : KJ.ink)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(Capsule().fill(active ? AnyShapeStyle(KJ.burgundyGradient) : AnyShapeStyle(Color.clear)))
        }
        .buttonStyle(.plain)
    }
}

private struct CheckBox: View {
    let checked: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(checked ? KJ.blue : Color.white)
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(KJ.blue, lineWidth: 2))
                .overlay(Image(systemName: "checkmark").font(.system(size: 14, weight: .heavy)).foregroundStyle(.white).opacity(checked ? 1 : 0))
                .frame(width: 30, height: 30)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(checked ? .isSelected : [])
    }
}

private struct RoleChoice: View {
    @EnvironmentObject var store: AppState
    let labelKey: String
    let art: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        let labels = biLabels(store, labelKey)
        Button(action: action) {
            HStack(spacing: 8) {
                ZStack {
                    Circle().strokeBorder(selected ? KJ.blue : KJ.muted.opacity(0.5), lineWidth: 2).frame(width: 22, height: 22)
                    if selected { Circle().fill(KJ.blue).frame(width: 11, height: 11) }
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text(labels.primary).font(.system(size: 15, weight: .heavy)).foregroundStyle(KJ.ink)
                    Text(labels.secondary).font(.system(size: 13, weight: .medium)).foregroundStyle(KJ.inkSoft)
                }
                Spacer(minLength: 0)
                Image(art).resizable().scaledToFit().frame(width: 54, height: 40)
            }
            .padding(.horizontal, 10)
            .frame(height: 76)
            .kjGlass()
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(selected ? KJ.blue : .clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
    }
}

private struct SocialButton: View {
    let title: String
    let icon: AnyView
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                icon
                Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(KJ.ink).lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .kjGlass(cornerRadius: 27)
        }
        .buttonStyle(.plain)
    }
}

/// Official four-colour Google "G" (vector asset google_g).
private struct GoogleGlyph: View {
    var body: some View {
        Image("google_g").resizable().scaledToFit().frame(width: 22, height: 22).accessibilityHidden(true)
    }
}

// MARK: - Login / register

struct AuthView: View {
    @EnvironmentObject var store: AppState
    var onForgot: () -> Void = {}
    var onSms: () -> Void = {}
    var onCodeSent: () -> Void = {}

    @State private var register = false
    @State private var loading = false
    @State private var errorMessage: String?
    @State private var errorTick = 0
    @State private var phone = ""
    @State private var password = ""
    @State private var confirm = ""
    @State private var name = ""
    @State private var email = ""
    @State private var remember = true
    @State private var terms = false
    @State private var role = "passenger"
    @StateObject private var social = SocialAuthCoordinator()

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private func bumpError() {
        KJHaptics.error()
        if reduceMotion { return }
        withAnimation(.linear(duration: 0.4)) { errorTick += 1 }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                header
                AuthTabs(register: $register).padding(.top, 14)

                VStack(spacing: 12) {
                    if register {
                        HStack(spacing: 12) {
                            RoleChoice(labelKey: "passenger", art: "kj_car", selected: role == "passenger") { role = "passenger" }
                            RoleChoice(labelKey: "driver", art: "kj_moto", selected: role == "driver") { role = "driver" }
                        }
                        GlassField(labelKey: "auth_name", icon: "person.fill", text: $name, contentType: .name)
                    }
                    GlassField(labelKey: "auth_phone", icon: "phone.fill", text: $phone, keyboard: .phonePad,
                               contentType: .telephoneNumber, trailing: AnyView(CountryChip()))
                    if register {
                        GlassField(labelKey: "auth_email", icon: "envelope.fill", text: $email, keyboard: .emailAddress, contentType: .emailAddress)
                    }
                    GlassField(labelKey: "auth_password", icon: "lock.fill", text: $password, secure: true,
                               contentType: register ? .newPassword : .password)
                    if register {
                        GlassField(labelKey: "auth_confirm", icon: "lock.fill", text: $confirm, secure: true, contentType: .newPassword)
                    }
                }
                .padding(.top, 16)

                if register { termsRow } else { rememberRow }

                if let message = errorMessage {
                    Text(message)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(KJ.danger)
                        .multilineTextAlignment(.center)
                        .padding(.top, 12)
                        .kjShake(errorTick)
                        .onAppear { bumpError() }
                        .onChange(of: errorMessage) { _, new in if new != nil { bumpError() } }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                BiButton(labelKey: register ? "auth_register_btn" : "auth_signin", loading: loading) {
                    register ? signUp() : login()
                }
                .padding(.top, 16)

                if !register { socialSection }
                switchRow
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 28)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(KJ.canvasGradient.ignoresSafeArea())
        .overlay(alignment: .top) { CornerBlobs().frame(height: 220) }
        .navigationBarBackButtonHidden(true)
        .toolbar { ToolbarItem(placement: .navigationBarLeading) { BackCircleButton() } }
        .onAppear { role = store.role }
    }

    private var header: some View {
        VStack(spacing: 4) {
            KJLogo(height: register ? 72 : 88).padding(.top, 8)
            if register {
                let t = biLabels(store, "auth_register_title")
                Text(t.primary).font(.system(size: 26, weight: .heavy)).foregroundStyle(KJ.ink).padding(.top, 8)
                Text(t.secondary).font(.system(size: 18, weight: .medium)).foregroundStyle(KJ.inkSoft)
                Text(biLabels(store, "auth_join").primary).font(.system(size: 14)).foregroundStyle(KJ.muted)
            } else {
                Text(L10n.string("app_tagline_ar", .ar)).font(.system(size: 17, weight: .heavy)).foregroundStyle(KJ.ink).padding(.top, 4)
                Text(L10n.string("app_tagline", .fr)).font(.system(size: 14)).foregroundStyle(KJ.inkSoft)
                Image("kj_duo").resizable().scaledToFit().frame(height: 140).padding(.top, 4)
            }
        }
        .multilineTextAlignment(.center)
    }

    private var rememberRow: some View {
        let remembered = biLabels(store, "auth_remember")
        let forgot = biLabels(store, "auth_forgot")
        return HStack(alignment: .center, spacing: 10) {
            CheckBox(checked: remember) { remember.toggle() }
            VStack(alignment: .leading, spacing: 0) {
                Text(remembered.primary).font(.system(size: 14, weight: .bold)).foregroundStyle(KJ.ink)
                Text(remembered.secondary).font(.system(size: 12)).foregroundStyle(KJ.inkSoft)
            }
            Spacer()
            Button(action: onForgot) {
                VStack(alignment: .trailing, spacing: 0) {
                    Text(forgot.primary).font(.system(size: 14, weight: .bold))
                    Text(forgot.secondary).font(.system(size: 12))
                }
                .foregroundStyle(KJ.blue)
            }
        }
        .padding(.top, 14)
    }

    private var termsRow: some View {
        let t = biLabels(store, "auth_terms")
        return HStack(spacing: 12) {
            CheckBox(checked: terms) { terms.toggle(); errorMessage = nil }
            VStack(alignment: .leading, spacing: 0) {
                Text(t.primary).font(.system(size: 13, weight: .bold)).foregroundStyle(KJ.ink)
                Text(t.secondary).font(.system(size: 11)).foregroundStyle(KJ.inkSoft)
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 14)
    }

    private var socialSection: some View {
        VStack(spacing: 12) {
            let or = biLabels(store, "auth_or")
            HStack {
                Rectangle().fill(KJ.softBlueMid).frame(height: 1)
                VStack(spacing: 0) {
                    Text(or.primary).font(.system(size: 14, weight: .bold))
                    if or.secondary != or.primary { Text(or.secondary).font(.system(size: 12)) }
                }
                .foregroundStyle(KJ.inkSoft)
                Rectangle().fill(KJ.softBlueMid).frame(height: 1)
            }
            HStack(spacing: 12) {
                SocialButton(title: biLabels(store, "auth_google").primary, icon: AnyView(GoogleGlyph())) { googleSignIn() }
                SocialButton(title: biLabels(store, "auth_apple").primary,
                             icon: AnyView(Image(systemName: "apple.logo").font(.system(size: 22)).foregroundStyle(.black))) { appleSignIn() }
            }
            Button(biLabels(store, "auth_sms_login").primary, action: onSms)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(KJ.blue)
        }
        .padding(.top, 16)
    }

    private var switchRow: some View {
        let q = biLabels(store, register ? "auth_have_account" : "auth_no_account")
        let l = biLabels(store, register ? "auth_signin_link" : "auth_create_link")
        return VStack(spacing: 4) {
            Text(q.primary).font(.system(size: 14)).foregroundStyle(KJ.inkSoft)
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { register.toggle() }
                errorMessage = nil
            } label: {
                HStack(spacing: 6) {
                    Text(l.primary).font(.system(size: 16, weight: .heavy))
                    Image(systemName: "arrow.forward").font(.system(size: 14, weight: .bold))
                }
                .foregroundStyle(KJ.burgundy)
            }
        }
        .padding(.top, 14)
    }

    // MARK: Actions

    private func login() {
        guard let p = AuthRules.normalizePhone(phone) else { errorMessage = store.l("invalid_phone"); return }
        guard !password.isEmpty else { errorMessage = store.l("err_enter_password"); return }
        loading = true
        errorMessage = nil
        Task {
            do {
                let res = try await SupabaseService.shared.loginWithPassword(phone: p, password: password, remember: remember)
                if res.ok, res.accessToken != nil {
                    await store.bootstrap()
                } else {
                    errorMessage = store.l(AuthRules.errorKey(res.error))
                }
            } catch {
                if !AuthRules.isCancellation(error) { errorMessage = store.l(AuthRules.exceptionKey(error)) }
            }
            loading = false
        }
    }

    private func signUp() {
        guard name.trimmingCharacters(in: .whitespaces).count >= 2 else { errorMessage = store.l("err_name"); return }
        guard let p = AuthRules.normalizePhone(phone) else { errorMessage = store.l("invalid_phone"); return }
        guard AuthRules.emailValid(email) else { errorMessage = store.l("err_email"); return }
        guard AuthRules.passwordValid(password) else { errorMessage = store.l("err_password_rules"); return }
        guard password == confirm else { errorMessage = store.l("err_password_mismatch"); return }
        guard terms else { errorMessage = store.l("err_terms"); return }
        loading = true
        errorMessage = nil
        Task {
            do {
                let res = try await SupabaseService.shared.requestOtp(phone: p)
                if res.ok {
                    let flow = PhoneFlowManager.shared
                    flow.phoneNumber = p
                    flow.devCode = res.devCode
                    flow.purpose = "register"
                    flow.password = password
                    flow.email = email.trimmingCharacters(in: .whitespaces)
                    flow.pendingName = name.trimmingCharacters(in: .whitespaces)
                    store.setRole(role)
                    onCodeSent()
                } else {
                    errorMessage = store.l(AuthRules.errorKey(res.error))
                }
            } catch {
                if !AuthRules.isCancellation(error) { errorMessage = store.l(AuthRules.exceptionKey(error)) }
            }
            loading = false
        }
    }

    private func appleSignIn() {
        loading = true
        errorMessage = nil
        Task {
            do {
                if let appleName = try await social.signInWithApple() {
                    PhoneFlowManager.shared.pendingName = appleName
                }
                await store.bootstrap()
            } catch {
                if !SocialAuthCoordinator.isCancellation(error) { errorMessage = store.l("social_failed") }
            }
            loading = false
        }
    }

    private func googleSignIn() {
        loading = true
        errorMessage = nil
        Task {
            do {
                try await social.signInWithGoogle()
                await store.bootstrap()
            } catch {
                if !SocialAuthCoordinator.isCancellation(error) { errorMessage = store.l("social_failed") }
            }
            loading = false
        }
    }
}

// MARK: - Forgot password

struct ForgotPasswordView: View {
    @EnvironmentObject var store: AppState
    var onCodeSent: () -> Void = {}

    @State private var phone = ""
    @State private var password = ""
    @State private var confirm = ""
    @State private var loading = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                KJLogo(height: 72).padding(.top, 8)
                let t = biLabels(store, "auth_forgot_title")
                Text(t.primary).font(.system(size: 26, weight: .heavy)).foregroundStyle(KJ.ink).padding(.top, 14)
                Text(t.secondary).font(.system(size: 16)).foregroundStyle(KJ.inkSoft)
                Text(biLabels(store, "auth_forgot_hint").primary)
                    .font(.system(size: 14)).foregroundStyle(KJ.muted)
                    .multilineTextAlignment(.center).padding(.top, 8)

                VStack(spacing: 12) {
                    GlassField(labelKey: "auth_phone", icon: "phone.fill", text: $phone, keyboard: .phonePad,
                               contentType: .telephoneNumber, trailing: AnyView(CountryChip()))
                    GlassField(labelKey: "auth_new_password", icon: "lock.fill", text: $password, secure: true, contentType: .newPassword)
                    GlassField(labelKey: "auth_confirm", icon: "lock.fill", text: $confirm, secure: true, contentType: .newPassword)
                }
                .padding(.top, 20)

                if let message = errorMessage {
                    Text(message).font(.system(size: 14, weight: .semibold)).foregroundStyle(KJ.danger).padding(.top, 12)
                }
                BiButton(labelKey: "auth_reset_btn", loading: loading) { submit() }.padding(.top, 20)
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 28)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(KJ.canvasGradient.ignoresSafeArea())
        .overlay(alignment: .top) { CornerBlobs().frame(height: 200) }
        .navigationBarBackButtonHidden(true)
        .toolbar { ToolbarItem(placement: .navigationBarLeading) { BackCircleButton() } }
    }

    private func submit() {
        guard let p = AuthRules.normalizePhone(phone) else { errorMessage = store.l("invalid_phone"); return }
        guard AuthRules.passwordValid(password) else { errorMessage = store.l("err_password_rules"); return }
        guard password == confirm else { errorMessage = store.l("err_password_mismatch"); return }
        loading = true
        errorMessage = nil
        Task {
            do {
                let res = try await SupabaseService.shared.requestOtp(phone: p)
                if res.ok {
                    let flow = PhoneFlowManager.shared
                    flow.phoneNumber = p
                    flow.devCode = res.devCode
                    flow.purpose = "reset"
                    flow.password = password
                    flow.email = ""
                    onCodeSent()
                } else {
                    errorMessage = store.l(AuthRules.errorKey(res.error))
                }
            } catch {
                if !AuthRules.isCancellation(error) { errorMessage = store.l(AuthRules.exceptionKey(error)) }
            }
            loading = false
        }
    }
}

// MARK: - Link a verified phone (social accounts)

/// Shown to a driver account (for example created with Google/Apple) that has no verified phone yet.
struct LinkPhoneView: View {
    @EnvironmentObject var store: AppState
    @State private var phone = ""
    @State private var code = ""
    @State private var sentTo: String?
    @State private var devCode: String?
    @State private var loading = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                KJLogo(height: 72).padding(.top, 32)
                let t = biLabels(store, "link_title")
                Text(t.primary).font(.system(size: 26, weight: .heavy)).foregroundStyle(KJ.ink).padding(.top, 14)
                Text(t.secondary).font(.system(size: 16)).foregroundStyle(KJ.inkSoft)
                Text(biLabels(store, "link_hint").primary)
                    .font(.system(size: 14)).foregroundStyle(KJ.muted)
                    .multilineTextAlignment(.center).padding(.top, 8)

                Group {
                    if sentTo == nil {
                        GlassField(labelKey: "auth_phone", icon: "phone.fill", text: $phone, keyboard: .phonePad,
                                   contentType: .telephoneNumber, trailing: AnyView(CountryChip()))
                    } else {
                        GlassField(labelKey: "link_code", icon: "lock.fill", text: $code, keyboard: .numberPad, contentType: .oneTimeCode)
                        if let devCode { Text("DEV: \(devCode)").font(.system(size: 12)).foregroundStyle(KJ.muted) }
                    }
                }
                .padding(.top, 20)

                if let message = errorMessage {
                    Text(message).font(.system(size: 14, weight: .semibold)).foregroundStyle(KJ.danger).padding(.top, 12)
                }
                BiButton(labelKey: sentTo == nil ? "link_send" : "link_confirm", loading: loading) {
                    sentTo == nil ? send() : confirm()
                }
                .padding(.top, 20)

                Button(biLabels(store, "link_continue_passenger").primary) { store.setRole("passenger") }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(KJ.blue)
                    .padding(.top, 14)
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 28)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(KJ.canvasGradient.ignoresSafeArea())
    }

    private func send() {
        guard let p = AuthRules.normalizePhone(phone) else { errorMessage = store.l("invalid_phone"); return }
        loading = true
        errorMessage = nil
        Task {
            do {
                let res = try await SupabaseService.shared.linkRequest(phone: p)
                if res.ok { sentTo = p; devCode = res.devCode } else { errorMessage = store.l(AuthRules.errorKey(res.error)) }
            } catch {
                if !AuthRules.isCancellation(error) { errorMessage = store.l(AuthRules.exceptionKey(error)) }
            }
            loading = false
        }
    }

    private func confirm() {
        guard let p = sentTo else { return }
        guard code.count == 6 else { errorMessage = store.l("wrong_code"); return }
        loading = true
        errorMessage = nil
        Task {
            do {
                let res = try await SupabaseService.shared.linkVerify(phone: p, code: code)
                if res.ok { await store.refreshProfile() } else { errorMessage = store.l(AuthRules.errorKey(res.error)) }
            } catch {
                if !AuthRules.isCancellation(error) { errorMessage = store.l(AuthRules.exceptionKey(error)) }
            }
            loading = false
        }
    }
}
