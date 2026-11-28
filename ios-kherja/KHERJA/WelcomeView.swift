//
//  WelcomeView.swift
//  KHERJA
//
//  Opening scene: the KHERJA car speeds in from the horizon, brakes just short of the "camera",
//  bounces, flashes its headlights and honks; then the brand line and the start button appear.
//  Everything is one-shot (no endless loops). Reduce Motion shows the final frame.
//

import SwiftUI

struct WelcomeView: View {
    @EnvironmentObject var store: AppState
    var onStart: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var drive: CGFloat = 0
    @State private var squash: CGFloat = 0
    @State private var flash: Double = 0
    @State private var dust: CGFloat = 0
    @State private var honk = false
    @State private var showText = false
    @State private var showButton = false
    @State private var impact = 0
    @State private var scene: Task<Void, Never>?

    /// The brand line is shown in Arabic in every language; other languages add a translation below it.
    private let brandLine = "تنقّل بأمان مع خرجة"
    private let carAspect: CGFloat = 304 / 420

    var body: some View {
        VStack(spacing: 0) {
            KJLogo(height: 64)
                .padding(.top, 16)

            GeometryReader { geo in
                let carWidth = max(0, min(min(geo.size.width, 420), geo.size.height / (carAspect * 1.25)))
                let carHeight = carWidth * carAspect

                ZStack {
                    WelcomeRoad(progress: drive, carHeight: carHeight)
                    BrakeDust(progress: dust, carWidth: carWidth, carHeight: carHeight)

                    Image("kj_front")
                        .resizable()
                        .scaledToFit()
                        .frame(width: carWidth, height: carHeight)
                        .overlay { headlights(width: carWidth, height: carHeight) }
                        .scaleEffect(x: 1 + 0.07 * squash, y: 1 - 0.08 * squash, anchor: .bottom)
                        .modifier(ApproachEffect(progress: drive, travel: geo.size.height * 0.2))
                        .offset(y: squash * 10)
                        .accessibilityLabel(Text(store.l("welcome_scene")))

                    if honk {
                        Text(store.l("welcome_beep"))
                            .font(.system(size: 18, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(Capsule().fill(KJ.burgundy))
                            .shadow(color: KJ.burgundy.opacity(0.35), radius: 8, y: 4)
                            .rotationEffect(.degrees(8))
                            .offset(x: carWidth * 0.28, y: -carHeight * 0.62)
                            .transition(.scale(scale: 0.2).combined(with: .opacity))
                            .accessibilityHidden(true)
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
            // The scene is a picture: keep it left-to-right even in Arabic.
            .environment(\.layoutDirection, .leftToRight)

            VStack(spacing: 6) {
                Text(brandLine)
                    .font(.system(size: 28, weight: .heavy, design: .rounded))
                    .foregroundStyle(KJ.ink)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.7)
                if !store.l("welcome_translation").isEmpty {
                    Text(store.l("welcome_translation"))
                        .font(.subheadline)
                        .foregroundStyle(KJ.muted)
                        .multilineTextAlignment(.center)
                }
            }
            .opacity(showText ? 1 : 0)
            .offset(y: showText || reduceMotion ? 0 : 24)

            Button {
                scene?.cancel()
                onStart()
            } label: {
                Text(store.l("welcome_start"))
            }
            .buttonStyle(KJButtonStyle())
            .opacity(showButton ? 1 : 0)
            .scaleEffect(showButton || reduceMotion ? 1 : 0.8)
            .disabled(!showButton)
            .padding(.top, 24)
            .padding(.bottom, 24)
        }
        .padding(.horizontal, 24)
        .background(KJ.canvasGradient.ignoresSafeArea())
        .contentShape(Rectangle())
        // Tap anywhere to jump to the end of the scene.
        .onTapGesture { if !showButton { finish() } }
        .sensoryFeedback(.impact(weight: .medium), trigger: impact)
        .onAppear { play() }
        .onDisappear { scene?.cancel() }
    }

    private func headlights(width: CGFloat, height: CGFloat) -> some View {
        ZStack {
            ForEach([96.0, 324.0], id: \.self) { x in
                Circle()
                    .fill(RadialGradient(colors: [.white, .white.opacity(0)], center: .center, startRadius: 2, endRadius: width * 0.13))
                    .frame(width: width * 0.26, height: width * 0.26)
                    .position(x: width * CGFloat(x) / 420, y: height * 204 / 304)
            }
        }
        .opacity(flash)
        .allowsHitTesting(false)
    }

    private func finish() {
        scene?.cancel()
        var transaction = SwiftUI.Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            drive = 1; squash = 0; flash = 0; dust = 0; honk = false
        }
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
                try await Task.sleep(for: .milliseconds(250))
                // Slow start, hard acceleration, short brake.
                withAnimation(.timingCurve(0.6, 0, 0.35, 1, duration: 1.5)) { drive = 1 }
                try await Task.sleep(for: .milliseconds(1500))
                impact += 1
                withAnimation(.easeOut(duration: 0.11)) { squash = 1; flash = 1 }
                withAnimation(.easeOut(duration: 0.65)) { dust = 1 }
                try await Task.sleep(for: .milliseconds(110))
                withAnimation(.spring(response: 0.4, dampingFraction: 0.4)) { squash = 0; honk = true }
                withAnimation(.easeIn(duration: 0.12)) { flash = 0 }
                try await Task.sleep(for: .milliseconds(130))
                withAnimation(.easeOut(duration: 0.09)) { flash = 1 }
                withAnimation(.easeOut(duration: 0.5)) { showText = true }
                try await Task.sleep(for: .milliseconds(100))
                withAnimation(.easeIn(duration: 0.18)) { flash = 0 }
                try await Task.sleep(for: .milliseconds(250))
                withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) { showButton = true }
                try await Task.sleep(for: .milliseconds(600))
                withAnimation(.easeOut(duration: 0.22)) { honk = false }
            } catch {
                // Cancelled: the view left the screen or the scene was skipped.
            }
        }
    }
}

/// Grows the car from the horizon, with a playful sway that dies out as it stops.
private struct ApproachEffect: ViewModifier, Animatable {
    var progress: CGFloat
    let travel: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(Double(sin(progress * 18) * 2.2 * (1 - progress))))
            .scaleEffect(0.07 + 0.93 * progress)
            .offset(y: -(1 - progress) * travel)
    }
}

/// Perspective road, centre dashes and speed lines.
private struct WelcomeRoad: View, Animatable {
    var progress: CGFloat
    let carHeight: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        Canvas { context, size in
            let horizon = size.height * 0.28
            let bottom = size.height * 0.5 + carHeight * 0.52
            var road = Path()
            road.move(to: CGPoint(x: size.width * 0.47, y: horizon))
            road.addLine(to: CGPoint(x: size.width * 0.53, y: horizon))
            road.addLine(to: CGPoint(x: size.width * 0.98, y: bottom))
            road.addLine(to: CGPoint(x: size.width * 0.02, y: bottom))
            road.closeSubpath()
            context.fill(road, with: .color(KJ.softBlueMid.opacity(0.55)))

            let span = bottom - horizon
            for i in 0..<5 {
                let t = (CGFloat(i) / 5 + progress * 1.6).truncatingRemainder(dividingBy: 1)
                let y = horizon + span * t * t
                var dash = Path()
                dash.move(to: CGPoint(x: size.width / 2, y: y))
                dash.addLine(to: CGPoint(x: size.width / 2, y: y + span * 0.09 * t))
                context.stroke(dash, with: .color(.white), style: StrokeStyle(lineWidth: 1 + 5 * t, lineCap: .round))
            }

            let speed = min(max(4 * progress * (1 - progress), 0), 1)
            guard speed > 0.05 else { return }
            for side in [CGFloat(-1), 1] {
                for k in 0..<3 {
                    let y = size.height * (0.36 + 0.1 * CGFloat(k))
                    let x = size.width / 2 + side * size.width * (0.24 + 0.08 * CGFloat(k) + 0.14 * progress)
                    var line = Path()
                    line.move(to: CGPoint(x: x, y: y))
                    line.addLine(to: CGPoint(x: x + side * 52 * speed, y: y - 6))
                    context.stroke(line, with: .color(KJ.blue.opacity(0.35 * Double(speed))), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// Dust puffs kicked up when the car brakes.
private struct BrakeDust: View, Animatable {
    var progress: CGFloat
    let carWidth: CGFloat
    let carHeight: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        Canvas { context, size in
            guard progress > 0, progress < 1 else { return }
            let baseY = size.height * 0.5 + carHeight * 0.46
            for side in [CGFloat(-1), 1] {
                for k in 0..<3 {
                    let step = CGFloat(k)
                    let x = size.width / 2 + side * (carWidth * 0.38 + (18 + 22 * step) * progress)
                    let r = (7 + 5 * step) * (0.5 + progress)
                    let rect = CGRect(x: x - r, y: baseY - 6 * step * progress - r, width: r * 2, height: r * 2)
                    context.fill(Path(ellipseIn: rect), with: .color(KJ.muted.opacity(0.28 * Double(1 - progress))))
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
