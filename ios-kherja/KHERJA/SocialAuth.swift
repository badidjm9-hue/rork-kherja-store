//
//  SocialAuth.swift
//  KHERJA
//
//  Real Google and Apple sign-in on top of Supabase Auth. No third-party SDK:
//   - Apple: native Sign in with Apple (ASAuthorizationController) → Supabase `id_token` grant.
//   - Google: Supabase OAuth with PKCE in ASWebAuthenticationSession → `pkce` token exchange.
//  Both need dashboard configuration first (see docs/AUTH_SETUP.md); without it the calls fail
//  and the UI shows an error. Nothing here pretends to succeed.
//

import AuthenticationServices
import Combine
import CryptoKit
import Foundation
import UIKit

nonisolated enum SocialError: Error {
    case failed
}

nonisolated enum SocialCrypto {
    static let redirectURL = "kherja://auth-callback"

    /// URL-safe random string (PKCE verifier, Apple nonce).
    static func randomString(byteCount: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        let status = SecRandomCopyBytes(kSecRandomDefault, byteCount, &bytes)
        precondition(status == errSecSuccess, "secure random unavailable")
        return base64URL(Data(bytes))
    }

    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// PKCE S256 challenge for a verifier.
    static func pkceChallenge(_ verifier: String) -> String {
        base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    /// Apple expects the SHA-256 hex of the nonce in the request; Supabase gets the raw nonce.
    static func sha256Hex(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

@MainActor
final class SocialAuthCoordinator: NSObject, ObservableObject,
    ASAuthorizationControllerDelegate,
    ASAuthorizationControllerPresentationContextProviding,
    ASWebAuthenticationPresentationContextProviding
{
    // No @Published properties are needed here; provide the publisher explicitly
    // so ObservableObject conformance remains valid without changing auth behavior.
    let objectWillChange = ObservableObjectPublisher()

    private var appleContinuation: CheckedContinuation<ASAuthorization, Error>?
    private var appleController: ASAuthorizationController?
    private var webSession: ASWebAuthenticationSession?

    private static func anchor() -> ASPresentationAnchor {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        return scene?.keyWindow ?? scene?.windows.first ?? ASPresentationAnchor()
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor { Self.anchor() }
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor { Self.anchor() }

    // MARK: Apple

    /// Returns the display name Apple shared (only provided on the very first authorization), if any.
    func signInWithApple() async throws -> String? {
        let rawNonce = SocialCrypto.randomString(byteCount: 32)
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = SocialCrypto.sha256Hex(rawNonce)

        let authorization: ASAuthorization = try await withCheckedThrowingContinuation { continuation in
            appleContinuation = continuation
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            appleController = controller
            controller.performRequests()
        }
        appleController = nil

        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let tokenData = credential.identityToken,
              let idToken = String(data: tokenData, encoding: .utf8) else { throw SocialError.failed }

        guard try await SupabaseService.shared.signInWithApple(idToken: idToken, nonce: rawNonce) else {
            throw SocialError.failed
        }
        guard let name = credential.fullName else { return nil }
        let full = PersonNameComponentsFormatter().string(from: name).trimmingCharacters(in: .whitespaces)
        return full.isEmpty ? nil : full
    }

    nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        Task { @MainActor in
            appleContinuation?.resume(returning: authorization)
            appleContinuation = nil
        }
    }

    nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        Task { @MainActor in
            appleContinuation?.resume(throwing: error)
            appleContinuation = nil
        }
    }

    // MARK: Google

    func signInWithGoogle() async throws {
        let verifier = SocialCrypto.randomString(byteCount: 48)
        var components = URLComponents(string: "\(Config.EXPO_PUBLIC_SUPABASE_URL)/auth/v1/authorize")!
        components.queryItems = [
            URLQueryItem(name: "provider", value: "google"),
            URLQueryItem(name: "redirect_to", value: SocialCrypto.redirectURL),
            URLQueryItem(name: "code_challenge", value: SocialCrypto.pkceChallenge(verifier)),
            URLQueryItem(name: "code_challenge_method", value: "s256"),
        ]
        guard let authorizeURL = components.url else { throw SocialError.failed }

        let callback: URL = try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: authorizeURL, callbackURLScheme: "kherja") { url, error in
                if let url {
                    continuation.resume(returning: url)
                } else {
                    continuation.resume(throwing: error ?? SocialError.failed)
                }
            }
            session.presentationContextProvider = self
            webSession = session
            session.start()
        }
        webSession = nil

        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        guard items.first(where: { $0.name == "error" }) == nil,
              let code = items.first(where: { $0.name == "code" })?.value, !code.isEmpty else { throw SocialError.failed }
        guard try await SupabaseService.shared.completeOAuth(authCode: code, verifier: verifier) else {
            throw SocialError.failed
        }
    }

    /// True when the user dismissed the system sheet (not an error worth showing).
    static func isCancellation(_ error: Error) -> Bool {
        if let e = error as? ASAuthorizationError, e.code == .canceled { return true }
        if let e = error as? ASWebAuthenticationSessionError, e.code == .canceledLogin { return true }
        return false
    }
}
