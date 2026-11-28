//
//  WelcomeView.swift
//  KHERJA
//
//  Welcome scene: the original car animation with its scenery removed, drawn straight on the screen
//  background (no card). The brand line and the start button settle in once. Reduce Motion shows a
//  single still frame and the final state.
//

import SwiftUI

struct WelcomeView: View {
    @EnvironmentObject var store: AppState
    var onStart: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var frameIndex = 0
    @State private var showText = false
    @State private var showButton = false
    @State private var scene: Task<Void, Never>?

    /// The brand line is shown in Arabic in every language; other languages add a translation below it.
    private let brandLine = "تنقّل بأمان مع خرجة"

    /// Original animation timing: 9 frames, 180 ms each, looping.
    private let frameCount = 9
    private let frameDuration = Duration.milliseconds(180)
    private let frameAspect: CGFloat = 438 / 388
    /// Sharpest view of the whole front with both characters, shown with Reduce Motion.
    private let stillFrame = 2

    var body: some View {
        VStack(spacing: 0) {
            KJLogo(height: 64)
                .padding(.top, 16)

            Image("welcome_drive_\(reduceMotion ? stillFrame : frameIndex)")
                .resizable()
                .interpolation(.high)
                .aspectRatio(frameAspect, contentMode: .fit)
                .frame(maxWidth: 460)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel(Text(store.l("welcome_scene")))

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
        .task(id: reduceMotion) { await animate() }
        .onAppear { play() }
        .onDisappear { scene?.cancel() }
    }

    /// Loops the frames for as long as the screen is visible.
    private func animate() async {
        guard !reduceMotion else { return }
        while !Task.isCancelled {
            for index in 0..<frameCount {
                frameIndex = index
                do { try await Task.sleep(for: frameDuration) } catch { return }
            }
        }
    }

    private func finish() {
        scene?.cancel()
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
