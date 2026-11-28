//
//  WelcomeView.swift
//  KHERJA
//
//  Calm welcome scene. Same two characters as the splash (the supplied street scene), no vector
//  stand-ins: the street slowly pushes in once, then the brand line and the start button settle in.
//  Everything is one-shot (no endless loops). Reduce Motion shows the final state immediately.
//

import SwiftUI

struct WelcomeView: View {
    @EnvironmentObject var store: AppState
    var onStart: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var push: CGFloat = 0          // 0 → 1 slow camera push-in
    @State private var showText = false
    @State private var showButton = false
    @State private var scene: Task<Void, Never>?

    /// The brand line is shown in Arabic in every language; other languages add a translation below it.
    private let brandLine = "تنقّل بأمان مع خرجة"

    var body: some View {
        VStack(spacing: 0) {
            KJLogo(height: 64)
                .padding(.top, 16)

            Spacer(minLength: 12)

            street
                .aspectRatio(438.0 / 388.0, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                .shadow(color: KJ.blue.opacity(0.25), radius: 20, y: 12)
                .accessibilityLabel(Text(store.l("welcome_scene")))
                // The scene is a picture: keep it left-to-right even in Arabic.
                .environment(\.layoutDirection, .leftToRight)

            Spacer(minLength: 12)

            VStack(spacing: 8) {
                Text(brandLine)
                    .font(.system(size: 28, weight: .heavy, design: .rounded))
                    .foregroundStyle(KJ.ink)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.7)
                Capsule().fill(KJ.burgundy).frame(width: 44, height: 4)
                if !store.l("welcome_translation").isEmpty {
                    Text(store.l("welcome_translation"))
                        .font(.subheadline)
                        .foregroundStyle(KJ.muted)
                        .multilineTextAlignment(.center)
                }
            }
            .opacity(showText ? 1 : 0)
            .offset(y: showText || reduceMotion ? 0 : 20)

            Button {
                scene?.cancel()
                onStart()
            } label: {
                Text(store.l("welcome_start"))
            }
            .buttonStyle(KJButtonStyle())
            .opacity(showButton ? 1 : 0)
            .scaleEffect(showButton || reduceMotion ? 1 : 0.9)
            .disabled(!showButton)
            .padding(.top, 24)
            .padding(.bottom, 24)
        }
        .padding(.horizontal, 24)
        .background(KJ.canvasGradient.ignoresSafeArea())
        .contentShape(Rectangle())
        // Tap anywhere to jump to the end of the scene.
        .onTapGesture { if !showButton { finish() } }
        .onAppear { play() }
        .onDisappear { scene?.cancel() }
    }

    private var street: some View {
        ZStack {
            Image("kj_splash_a")
                .resizable()
                .scaledToFill()
                .scaleEffect(1 + 0.08 * push, anchor: UnitPoint(x: 0.5, y: 0.6))
                .offset(y: -6 * push)
            // Brand wash: royal blue from below, a touch of burgundy at the horizon.
            LinearGradient(colors: [.clear, KJ.blue.opacity(0.22)], startPoint: .top, endPoint: .bottom)
            LinearGradient(colors: [KJ.burgundy.opacity(0.10), .clear], startPoint: .topLeading, endPoint: .center)
        }
    }

    private func finish() {
        scene?.cancel()
        var transaction = SwiftUI.Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { push = 1 }
        withAnimation(.easeIn(duration: 0.15)) {
            showText = true
            showButton = true
        }
    }

    private func play() {
        guard !showButton else { return }
        if reduceMotion { finish(); return }
        scene = Task { @MainActor in
            do {
                withAnimation(.easeOut(duration: 6)) { push = 1 }
                try await Task.sleep(for: .milliseconds(350))
                withAnimation(KJMotion.reveal) { showText = true }
                try await Task.sleep(for: .milliseconds(450))
                withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) { showButton = true }
                KJHaptics.selection()
            } catch {
                // Cancelled: the view left the screen or the scene was skipped.
            }
        }
    }
}
