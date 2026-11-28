//
//  SplashIntro.swift
//  KHERJA
//
//  One-shot launch sequence: white logo hold → original transparent car frames → impact → Welcome.
//  The original car and both characters are reused without redrawing or changing their appearance.
//

import SwiftUI
import UIKit

struct SplashView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let onFinished: () -> Void

    @State private var frameIndex = 0
    @State private var carVisible = false
    @State private var carScale: CGFloat = 0.62
    @State private var shake: CGFloat = 0
    @State private var crack: CGFloat = 0
    @State private var crackOpacity = 1.0
    @State private var flash = 0.0
    @State private var didFinish = false

    private let frameCount = 9
    private let frameDelay = Duration.milliseconds(180)

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()

            if carVisible {
                Image("welcome_drive_\(frameIndex)")
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(maxWidth: 460)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .scaleEffect(carScale)
                    .accessibilityHidden(true)
            } else {
                KJLogo(height: 48)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityLabel("KHERJA")
            }

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
        .task { await runOpeningSequence() }
    }

    @MainActor
    private func runOpeningSequence() async {
        do {
            // Minimal splash: the logo is the only visible element for exactly one second.
            try await Task.sleep(for: .seconds(1))

            if reduceMotion {
                finishOnce()
                return
            }

            carVisible = true
            withAnimation(.timingCurve(0.42, 0, 1, 1, duration: 1.62)) {
                carScale = 1.12
            }

            // Play the original transparent frames once, in order. Never loop or replay on Welcome.
            for index in 0..<frameCount {
                frameIndex = index
                try await Task.sleep(for: frameDelay)
            }

            withAnimation(.linear(duration: 0.65)) { shake = 1 }
            try await Task.sleep(for: .milliseconds(180))

            KJHaptics.impact()
            withAnimation(.easeOut(duration: 0.16)) {
                crack = 1
                flash = 0.78
            }
            try await Task.sleep(for: .milliseconds(120))
            withAnimation(.easeOut(duration: 0.24)) { flash = 0 }
            try await Task.sleep(for: .milliseconds(320))
            withAnimation(.easeInOut(duration: 0.35)) { crackOpacity = 0 }
            finishOnce()
        } catch {
            // Cancellation means the launch view is leaving; do not restart the sequence.
        }
    }

    @MainActor
    private func finishOnce() {
        guard !didFinish else { return }
        didFinish = true
        onFinished()
    }
}

/// Camera shake is limited to the impact and decays smoothly.
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

/// Deterministic glass fracture, drawn over the entire screen.
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
