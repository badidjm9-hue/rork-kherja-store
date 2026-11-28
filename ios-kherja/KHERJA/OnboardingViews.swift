//
//  OnboardingViews.swift
//  KHERJA
//
//  Splash → language → role → phone → OTP verification.
//

import Combine
import SwiftUI

// MARK: - Splash

struct SplashView: View {
    @EnvironmentObject var store: AppState

    var body: some View {
        ZStack {
            KJ.canvasGradient.ignoresSafeArea()
            CornerBlobs()

            VStack(spacing: 28) {
                KJLogo(height: 110)
                    .padding(.top, 60)

                Text(store.l("app_tagline"))
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(KJ.burgundy)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)

                Spacer()

                Image("car_moto")
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)

                VStack(spacing: 16) {
                    ProgressView()
                        .tint(KJ.blue)
                        .scaleEffect(1.2)
                    Text(store.l("loading"))
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(KJ.muted)
                    Capsule()
                        .fill(KJ.blue.opacity(0.2))
                        .frame(height: 6)
                        .overlay(alignment: .leading) {
                            GeometryReader { geo in
                                Capsule()
                                    .fill(KJ.blue)
                                    .frame(width: geo.size.width * 0.7)
                            }
                        }
                        .padding(.horizontal, 60)
                }
                .padding(.bottom, 50)
            }
        }
    }
}

// MARK: - Language select

struct LanguageSelectView: View {
    @EnvironmentObject var store: AppState
    var onContinue: () -> Void = {}

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
            Spacer(minLength: 32)
            KJLogo(height: 84)

            Image("car_moto")
                .resizable()
                .scaledToFit()
                .frame(width: 210, height: 110)
                .padding(.top, 12)

            Text(store.l("choose_language"))
                .font(.system(size: 24, weight: .heavy))
                .foregroundStyle(KJ.ink)
                .padding(.top, 12)

            VStack(spacing: 14) {
                LanguageCard(
                    language: .ar,
                    title: "العربية",
                    subtitle: "Arabic",
                    flag: "flag-dz",
                    selected: store.language == .ar
                ) { store.setLanguage(.ar) }
                LanguageCard(
                    language: .fr,
                    title: "Français",
                    subtitle: "French",
                    flag: "flag-fr",
                    selected: store.language == .fr
                ) { store.setLanguage(.fr) }
            }
            .padding(.top, 20)
            .padding(.horizontal, 28)

            Button { onContinue() } label: {
                Text(store.l("continue"))
            }
            .buttonStyle(KJButtonStyle())
            .padding(.top, 24)
            .padding(.horizontal, 28)

            Spacer(minLength: 24)
        }
            .frame(maxWidth: .infinity)
        }
        .background(KJ.canvasGradient.ignoresSafeArea())
        .overlay(alignment: .top) { CornerBlobs().frame(height: 240) }
        .clipShape(.rect)
    }
}

private struct LanguageCard: View {
    let language: AppLanguage
    let title: String
    let subtitle: String
    let flag: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Circle()
                    .strokeBorder(selected ? KJ.blue : KJ.muted.opacity(0.4), lineWidth: 2)
                    .frame(width: 22, height: 22)
                    .overlay {
                        if selected {
                            Circle().fill(KJ.blue).frame(width: 12, height: 12)
                        }
                    }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(KJ.ink)
                    Text(subtitle)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(KJ.muted)
                }
                Spacer()
                FlagView(code: flag)
            }
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .strokeBorder(selected ? KJ.blue : .clear, lineWidth: 2)
                    )
                    .shadow(color: Color(hex: 0x075BFF).opacity(selected ? 0.18 : 0.08), radius: 16, x: 0, y: 8)
            )
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: selected)
    }
}

struct FlagView: View {
    var code: String

    var body: some View {
        Group {
            if code == "flag-fr" {
                HStack(spacing: 0) {
                    Rectangle().fill(Color(hex: 0x0055A4))
                    Rectangle().fill(.white)
                    Rectangle().fill(Color(hex: 0xEF4135))
                }
            } else {
                ZStack {
                    HStack(spacing: 0) {
                        Rectangle().fill(Color(hex: 0x12824A))
                        Rectangle().fill(.white)
                    }
                    ZStack {
                        Circle().fill(Color(hex: 0xD21034)).frame(width: 22, height: 22)
                        Circle().fill(code == "flag-dz" ? Color(hex: 0x12824A) : .white)
                            .frame(width: 20, height: 20)
                            .offset(x: 4)
                    }
                }
            }
        }
        .frame(width: 52, height: 36)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(.black.opacity(0.06)))
        .shadow(color: .black.opacity(0.1), radius: 3, y: 1)
    }
}

// MARK: - Role select

struct RoleSelectView: View {
    @EnvironmentObject var store: AppState
    var onContinue: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 20)
            KJLogo(height: 84)

            Text(store.l("join_community"))
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(KJ.inkSoft)
                .padding(.top, 14)

            VStack(spacing: 16) {
                RoleCard(
                    titleAr: "سائق",
                    title: store.l("driver"),
                    subtitleKey: "driver",
                    art: "moto_art",
                    selected: store.role == "driver"
                ) { store.setRole("driver") }

                RoleCard(
                    titleAr: "راكب",
                    title: store.l("passenger"),
                    subtitleKey: "passenger",
                    art: "car_moto",
                    selected: store.role == "passenger"
                ) { store.setRole("passenger") }
            }
            .padding(.top, 30)

            Spacer(minLength: 0)

            Button {
                onContinue()
            } label: {
                HStack {
                    Text(store.l("continue"))
                    Image(systemName: "arrow.right")
                }
            }
            .buttonStyle(KJButtonStyle())
            .padding(.horizontal, 28)
            .padding(.bottom, 30)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(KJ.canvasGradient.ignoresSafeArea())
        .overlay(alignment: .top) { CornerBlobs().frame(height: 220) }
    }
}

private struct RoleCard: View {
    let titleAr: String
    let title: String
    let subtitleKey: String
    let art: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(art)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 76, height: 58)
                VStack(alignment: .leading, spacing: 2) {
                    Text(titleAr)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(KJ.ink)
                    Text(title)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(KJ.muted)
                }
                Spacer()
                ZStack {
                    Circle()
                        .strokeBorder(selected ? KJ.blue : KJ.muted.opacity(0.4), lineWidth: 2)
                        .frame(width: 24, height: 24)
                    if selected {
                        Circle().fill(KJ.blue).frame(width: 13, height: 13)
                    }
                }
            }
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .strokeBorder(selected ? KJ.blue : .clear, lineWidth: 2)
                    )
                    .shadow(color: Color(hex: 0x075BFF).opacity(selected ? 0.18 : 0.08), radius: 16, x: 0, y: 8)
            )
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: selected)
    }
}

// MARK: - Phone entry

struct PhoneEntryView: View {
    @EnvironmentObject var store: AppState
    var onCodeSent: () -> Void = {}
    @State private var phone = ""
    @State private var loading = false
    @State private var errorMessage: String?
    @FocusState private var focused: Bool

    var normalizedPhone: String? {
        let digits = phone.replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
        guard digits.count == 10, digits.hasPrefix("0") else { return nil }
        guard ["5", "6", "7"].contains(String(digits.dropFirst().prefix(1))) else { return nil }
        return digits
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 30)
            KJLogo(height: 84)

            Text(store.l("your_number"))
                .font(.system(size: 26, weight: .heavy))
                .foregroundStyle(KJ.ink)
                .padding(.top, 26)

            Text(store.l("sms_hint"))
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(KJ.muted)
                .padding(.top, 6)

            HStack(spacing: 12) {
                Image(systemName: "phone.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(KJ.blue)
                TextField(store.l("phone_placeholder"), text: $phone)
                    .keyboardType(.phonePad)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(KJ.ink)
                    .focused($focused)
                    .disabled(loading)
            }
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.white)
                    .shadow(color: Color(hex: 0x075BFF).opacity(0.10), radius: 14, x: 0, y: 6)
            )
            .padding(.top, 30)
            .padding(.horizontal, 30)

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(KJ.danger)
                    .padding(.top, 12)
            }

            Button {
                submit()
            } label: {
                HStack {
                    if loading { ProgressView().tint(.white) }
                    else {
                        Text(store.l("send_code"))
                        Image(systemName: "arrow.right")
                    }
                }
            }
            .buttonStyle(KJButtonStyle())
            .disabled(normalizedPhone == nil || loading)
            .opacity(normalizedPhone == nil && !phone.isEmpty ? 0.6 : 1)
            .padding(.top, 28)
            .padding(.horizontal, 28)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(KJ.canvasGradient.ignoresSafeArea())
        .overlay(alignment: .top) { CornerBlobs().frame(height: 220) }
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                BackCircleButton()
            }
        }
    }

    private func submit() {
        guard let normalized = normalizedPhone else {
            errorMessage = store.l("invalid_phone")
            return
        }
        loading = true
        errorMessage = nil
        Task {
            do {
                let res = try await SupabaseService.shared.requestOtp(phone: normalized)
                if res.ok {
                    PhoneFlowManager.shared.phoneNumber = normalized
                    PhoneFlowManager.shared.devCode = res.devCode
                    onCodeSent()
                } else {
                    errorMessage = res.error ?? store.l("error_generic")
                }
            } catch {
                if !AuthRules.isCancellation(error) { errorMessage = store.l(AuthRules.exceptionKey(error)) }
            }
            loading = false
        }
    }
}

// MARK: - OTP verify

struct OtpVerifyView: View {
    @EnvironmentObject var store: AppState
    @State private var code = ""
    @State private var loading = false
    @State private var errorMessage: String?
    @State private var countdown = 45
    @State private var timer: Timer?

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 30)
            KJLogo(height: 76)

            Text(store.l("verify_title"))
                .font(.system(size: 26, weight: .heavy))
                .foregroundStyle(KJ.ink)
                .padding(.top, 24)

            Text("\(store.l("verify_hint")) \(PhoneFlowManager.shared.displayPhone)")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(KJ.muted)
                .multilineTextAlignment(.center)
                .padding(.top, 6)
                .padding(.horizontal, 30)

            if let devCode = PhoneFlowManager.shared.devCode {
                VStack(spacing: 6) {
                    Text(store.l("dev_code_banner"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(KJ.burgundy)
                    Text(devCode)
                        .font(.system(size: 26, weight: .heavy, design: .monospaced))
                        .foregroundStyle(KJ.burgundy)
                }
                .padding(14)
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: 16).fill(KJ.burgundy.opacity(0.07)))
                .padding(.top, 18)
                .padding(.horizontal, 30)
            }

            TextField("••••••", text: $code)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .font(.system(size: 30, weight: .heavy, design: .monospaced))
                .foregroundStyle(KJ.ink)
                .frame(height: 66)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(.white)
                        .shadow(color: Color(hex: 0x075BFF).opacity(0.10), radius: 14, x: 0, y: 6)
                )
                .padding(.top, 24)
                .padding(.horizontal, 40)

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(KJ.danger)
                    .padding(.top, 12)
            }

            Button {
                verify()
            } label: {
                if loading { ProgressView().tint(.white) } else { Text(store.l("verify_title")) }
            }
            .buttonStyle(KJButtonStyle())
            .disabled(code.count < 6 || loading)
            .padding(.top, 24)
            .padding(.horizontal, 28)

            Button {
                resend()
            } label: {
                Text(countdown > 0
                    ? "\(store.l("resend_in")) \(countdown)s"
                    : store.l("resend"))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(countdown > 0 ? KJ.muted : KJ.blue)
            }
            .disabled(countdown > 0)
            .padding(.top, 16)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(KJ.canvasGradient.ignoresSafeArea())
        .overlay(alignment: .top) { CornerBlobs().frame(height: 200) }
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) { BackCircleButton() }
        }
        .onAppear { startCountdown() }
        .onDisappear { timer?.invalidate() }
    }

    private func startCountdown() {
        countdown = 45
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { t in
            Task { @MainActor in
                if countdown > 0 { countdown -= 1 } else { t.invalidate() }
            }
        }
    }

    private func resend() {
        Task {
            do {
                let res = try await SupabaseService.shared.requestOtp(phone: PhoneFlowManager.shared.phoneNumber)
                PhoneFlowManager.shared.devCode = res.devCode
                startCountdown()
            } catch {
                if !AuthRules.isCancellation(error) { errorMessage = store.l(AuthRules.exceptionKey(error)) }
            }
        }
    }

    private func verify() {
        loading = true
        errorMessage = nil
        Task {
            do {
                let flow = PhoneFlowManager.shared
                let res = try await SupabaseService.shared.verifyOtp(
                    phone: flow.phoneNumber,
                    code: code,
                    purpose: flow.purpose,
                    password: flow.password,
                    email: flow.email
                )
                if res.ok, let userIdString = res.userId, let userId = UUID(uuidString: userIdString) {
                    SessionManager.shared.userId = userId
                    flow.clearCredentials()
                    await store.bootstrap()
                    flow.stage = .done
                } else if flow.purpose == nil {
                    // Legacy passwordless flow keeps its original behaviour.
                    errorMessage = res.error ?? store.l("wrong_code")
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

// MARK: - Shared flow manager + back button

@MainActor
final class PhoneFlowManager: ObservableObject {
    static let shared = PhoneFlowManager()

    enum Stage: Equatable {
        case phone, otp, done
    }

    @Published var stage: Stage = .phone
    @Published var phoneNumber = ""
    @Published var devCode: String?

    // Context for the SMS-code step. All nil/empty = the original passwordless OTP login.
    // Kept in memory only (never persisted or logged) and wiped by `reset()` / after success.
    var purpose: String?          // "register" | "reset" | nil
    var password: String?
    var email: String?
    var pendingName: String?      // prefilled in the profile step

    var displayPhone: String {
        let digits = phoneNumber
        guard digits.count == 10 else { return phoneNumber }
        let idx = digits.startIndex
        let a = digits[idx...].prefix(4)
        let b = digits.index(idx, offsetBy: 4)...digits.index(idx, offsetBy: 5)
        let c = digits.index(idx, offsetBy: 6)...digits.index(idx, offsetBy: 7)
        let d = digits.index(idx, offsetBy: 8)...digits.index(idx, offsetBy: 9)
        return [String(a), String(digits[b]), String(digits[c]), String(digits[d])].joined(separator: " ")
    }

    func reset() {
        stage = .phone
        phoneNumber = ""
        devCode = nil
        clearCredentials()
    }

    func clearCredentials() {
        purpose = nil
        password = nil
        email = nil
    }
}

struct BackCircleButton: View {
    @Environment(\.dismiss) private var dismiss
    var action: (() -> Void)?

    var body: some View {
        Button {
            if let action { action() } else { dismiss() }
        } label: {
            Image(systemName: "chevron.left")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(KJ.ink)
                .frame(width: 44, height: 44)
                .background(Circle().fill(.white).shadow(color: .black.opacity(0.08), radius: 8, y: 3))
        }
    }
}
