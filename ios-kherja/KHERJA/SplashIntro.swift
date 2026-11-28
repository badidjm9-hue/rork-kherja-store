//
//  SplashIntro.swift
//  KHERJA
//
//  Opening sequence. The supplied street clip (same two characters, untouched) plays once: the car
//  rushes at the camera. Native effects are layered on top at the moment of impact: camera shake,
//  motion blur, a glass crack across the whole screen and a flash, then the card dissolves and the
//  KHERJA logo is revealed. Reduce Motion skips straight to the logo.
//
//  The clip is a plain H.264 file played with AVPlayer (no third-party player or Lottie/Rive).
//

import AVFoundation
import SwiftUI
import UIKit

struct SplashView: View {
    @EnvironmentObject var store: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var playVideo = false
    @State private var shake: CGFloat = 0
    @State private var flash = 0.0
    @State private var crack: CGFloat = 0
    @State private var crackOpacity = 1.0
    @State private var blur: CGFloat = 0
    @State private var cardOpacity = 1.0
    @State private var cardScale: CGFloat = 1
    @State private var logoShown = false

    var body: some View {
        ZStack {
            KJ.canvasGradient.ignoresSafeArea()
            CornerBlobs().opacity(logoShown ? 1 : 0)

            VStack(spacing: 20) {
                KJLogo(height: 120)
                Text(store.l("app_tagline"))
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(KJ.burgundy)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                ProgressView()
                    .tint(KJ.blue)
                    .padding(.top, 12)
            }
            .scaleEffect(logoShown ? 1 : 0.82)
            .opacity(logoShown ? 1 : 0)

            card
                .padding(.horizontal, 16)
                .scaleEffect(cardScale)
                .blur(radius: blur)
                .opacity(cardOpacity)

            CrackShape(progress: crack)
                .stroke(KJ.ink.opacity(0.35), style: StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round))
                .opacity(crackOpacity)
                .ignoresSafeArea()
                .allowsHitTesting(false)
            CrackShape(progress: crack)
                .stroke(.white.opacity(0.92), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                .opacity(crackOpacity)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            Color.white.opacity(flash).ignoresSafeArea().allowsHitTesting(false)
        }
        .modifier(KJCameraShake(t: shake))
        .task { await run() }
    }

    private var card: some View {
        ZStack {
            if playVideo, let url = Bundle.main.url(forResource: "kj_splash", withExtension: "mp4") {
                SplashVideo(url: url)
            } else {
                // First frame of the clip, so the hand-over to video is seamless.
                Image("kj_splash_a").resizable().scaledToFill()
            }
        }
        .aspectRatio(438.0 / 388.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: KJ.blue.opacity(0.28), radius: 18, y: 10)
        .accessibilityHidden(true)
    }

    @MainActor
    private func run() async {
        if reduceMotion {
            cardOpacity = 0
            logoShown = true
            return
        }
        do {
            playVideo = true
            // The clip is 2.1 s; the car fills the windscreen around 1.75 s.
            try await Task.sleep(for: .milliseconds(1750))
            withAnimation(.linear(duration: 1.15)) { shake = 1 }
            try await Task.sleep(for: .milliseconds(350))
            // Impact.
            KJHaptics.impact()
            withAnimation(.easeOut(duration: 0.14)) { crack = 1; flash = 0.9 }
            withAnimation(.easeOut(duration: 0.35)) { blur = 14 }
            try await Task.sleep(for: .milliseconds(150))
            withAnimation(.easeIn(duration: 0.25)) { flash = 0 }
            try await Task.sleep(for: .milliseconds(300))
            // Dissolve the scene and reveal the brand.
            withAnimation(.easeInOut(duration: 0.5)) { cardOpacity = 0; cardScale = 1.12; crackOpacity = 0 }
            withAnimation(.spring(response: 0.55, dampingFraction: 0.78).delay(0.2)) { logoShown = true }
        } catch {
            // Cancelled: the splash left the screen.
        }
    }
}

// MARK: - Effects

/// Camera shake: builds up as the car arrives, jolts at the impact (t ≈ 0.30), then dies out.
struct KJCameraShake: GeometryEffect {
    var t: CGFloat
    var animatableData: CGFloat {
        get { t }
        set { t = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        let envelope: CGFloat = t < 0.30 ? 0.25 * (t / 0.30) : pow(max(0, 1 - (t - 0.30) / 0.70), 2)
        let x = 12 * envelope * sin(t * .pi * 19)
        let y = 8 * envelope * cos(t * .pi * 23)
        return ProjectionTransform(CGAffineTransform(translationX: x, y: y))
    }
}

/// Glass crack radiating from just above the screen centre. Deterministic (no randomness between runs).
struct CrackShape: Shape {
    var progress: CGFloat
    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard progress > 0 else { return path }
        let center = CGPoint(x: rect.midX, y: rect.height * 0.42)
        var seed: UInt64 = 0x9E37_79B9_7F4A_7C15
        func rnd() -> CGFloat {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return CGFloat((seed >> 33) & 0xFFFF) / 65535
        }
        let reach = hypot(rect.width, rect.height) * 0.7 * progress
        let rays = 16
        for i in 0..<rays {
            var angle = CGFloat(i) / CGFloat(rays) * 2 * .pi + (rnd() - 0.5) * 0.25
            var point = center
            path.move(to: point)
            for step in 1...5 {
                let length = reach / 5 * (0.7 + 0.6 * rnd())
                angle += (rnd() - 0.5) * 0.5
                point = CGPoint(x: point.x + cos(angle) * length, y: point.y + sin(angle) * length)
                path.addLine(to: point)
                if step == 2 || step == 4 {
                    let branch = angle + (rnd() > 0.5 ? 0.9 : -0.9)
                    path.addLine(to: CGPoint(x: point.x + cos(branch) * length * 0.8, y: point.y + sin(branch) * length * 0.8))
                    path.move(to: point)
                }
            }
        }
        // Two irregular rings connect the rays, like real laminated glass.
        for ring in [0.16, 0.34] as [CGFloat] {
            let radius = reach * ring
            for k in 0...rays {
                let a = CGFloat(k) / CGFloat(rays) * 2 * .pi
                let r = radius * (0.85 + 0.3 * rnd())
                let p = CGPoint(x: center.x + cos(a) * r, y: center.y + sin(a) * r)
                if k == 0 { path.move(to: p) } else { path.addLine(to: p) }
            }
        }
        return path
    }
}

// MARK: - Video

private final class SplashPlayerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}

/// Muted, play-once clip. Needs no audio session and releases the player when it leaves the screen.
private struct SplashVideo: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> SplashPlayerView {
        let view = SplashPlayerView()
        view.backgroundColor = .clear
        let player = AVPlayer(url: url)
        player.isMuted = true
        player.actionAtItemEnd = .pause
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspectFill
        player.play()
        return view
    }

    func updateUIView(_ uiView: SplashPlayerView, context: Context) {}

    static func dismantleUIView(_ uiView: SplashPlayerView, coordinator: ()) {
        uiView.playerLayer.player?.pause()
        uiView.playerLayer.player = nil
    }
}
