//
//  Motion.swift
//  KHERJA
//
//  The single place for UI motion. Screens use these building blocks instead of ad-hoc animations:
//    - KJMotion          : shared animation curves and the stagger rule
//    - .kjReveal(index:) : fade + slide-up entrance, staggered, played once per view identity
//    - SkeletonBlock / SkeletonList : shimmering placeholders while data loads
//    - .kjShake(_:)      : error shake driven by a counter
//    - KJHaptics         : success / error / selection feedback
//    - KJPressableStyle  : press feedback for tappable cards
//  Everything honours Reduce Motion (accessibilityReduceMotion): entrances become a short fade,
//  shimmer and shake are skipped. No animation here runs forever once its view is off screen.
//

import SwiftUI
import UIKit

enum KJMotion {
    /// Press feedback on buttons and cards.
    static let press = Animation.spring(response: 0.3, dampingFraction: 0.7)
    /// Entrance of cards and rows.
    static let reveal = Animation.spring(response: 0.45, dampingFraction: 0.86)
    /// Colour / selection / small state changes.
    static let state = Animation.easeInOut(duration: 0.22)

    /// Rows enter one after another; capped so long lists never feel slow.
    static func staggerDelay(_ index: Int) -> Double { Double(min(max(index, 0), 8)) * 0.045 }
}

// MARK: - Reveal

struct KJReveal: ViewModifier {
    let index: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 14)
            .onAppear {
                guard !shown else { return }   // a refresh must not replay the entrance
                if reduceMotion {
                    withAnimation(.easeIn(duration: 0.15)) { shown = true }
                } else {
                    withAnimation(KJMotion.reveal.delay(KJMotion.staggerDelay(index))) { shown = true }
                }
            }
    }
}

extension View {
    /// Staggered fade + slide-up entrance (played once). `index` is the row position in its list.
    func kjReveal(index: Int = 0) -> some View { modifier(KJReveal(index: index)) }
}

// MARK: - Skeleton

struct KJShimmer: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .overlay {
                if !reduceMotion {
                    GeometryReader { geo in
                        LinearGradient(
                            colors: [.clear, .white.opacity(0.6), .clear],
                            startPoint: .leading, endPoint: .trailing
                        )
                        .frame(width: geo.size.width * 0.6)
                        .offset(x: (phase * 1.6 - 0.6) * geo.size.width)
                    }
                    .allowsHitTesting(false)
                }
            }
            .clipped()
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 1.3).repeatForever(autoreverses: false)) { phase = 1 }
            }
    }
}

extension View {
    func kjShimmer() -> some View { modifier(KJShimmer()) }
}

/// A rounded placeholder block.
struct SkeletonBlock: View {
    var height: CGFloat = 14
    var width: CGFloat? = nil
    var radius: CGFloat = 8

    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(KJ.softBlue)
            .frame(width: width, height: height)
            .kjShimmer()
            .accessibilityHidden(true)
    }
}

/// Card-shaped placeholder rows shown while a list loads.
struct SkeletonList: View {
    var count: Int = 4

    var body: some View {
        VStack(spacing: 12) {
            ForEach(0..<count, id: \.self) { _ in
                HStack(spacing: 12) {
                    SkeletonBlock(height: 40, width: 40, radius: 20)
                    VStack(alignment: .leading, spacing: 8) {
                        SkeletonBlock(height: 14, width: 160)
                        SkeletonBlock(height: 11, width: 100)
                    }
                    Spacer()
                    SkeletonBlock(height: 14, width: 52)
                }
                .kjCard(padding: 14)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("…"))
    }
}

// MARK: - Error shake + haptics

struct KJShake: GeometryEffect {
    var travel: CGFloat = 8
    var shakes: CGFloat = 3
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: travel * sin(animatableData * .pi * shakes * 2), y: 0))
    }
}

extension View {
    /// Shakes horizontally each time `trigger` increases (use `withAnimation(.linear(duration: 0.4))`).
    func kjShake(_ trigger: Int) -> some View { modifier(KJShake(animatableData: CGFloat(trigger))) }
}

enum KJHaptics {
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func error() { UINotificationFeedbackGenerator().notificationOccurred(.error) }
    static func selection() { UISelectionFeedbackGenerator().selectionChanged() }
    static func impact() { UIImpactFeedbackGenerator(style: .heavy).impactOccurred() }
}

// MARK: - Pressable cards

/// Press feedback for a tappable card: slight scale + dim, no layout change.
struct KJPressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.92 : 1)
            .animation(KJMotion.press, value: configuration.isPressed)
    }
}

// MARK: - Success check

/// Check mark that pops in and draws itself once, with a success haptic. Static under Reduce Motion.
struct KJSuccessCheck: View {
    var size: CGFloat = 60
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var popped = false
    @State private var drawn = false

    var body: some View {
        ZStack {
            Circle().fill(KJ.success).scaleEffect(popped ? 1 : 0.5)
            KJCheckShape()
                .trim(from: 0, to: drawn ? 1 : 0)
                .stroke(.white, style: StrokeStyle(lineWidth: size * 0.09, lineCap: .round, lineJoin: .round))
                .padding(size * 0.27)
        }
        .frame(width: size, height: size)
        .onAppear {
            if reduceMotion { popped = true; drawn = true; return }
            withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) { popped = true }
            withAnimation(.easeOut(duration: 0.35).delay(0.15)) { drawn = true }
            KJHaptics.success()
        }
        .accessibilityHidden(true)
    }
}

struct KJCheckShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX + rect.width * 0.05, y: rect.minY + rect.height * 0.52))
        p.addLine(to: CGPoint(x: rect.minX + rect.width * 0.38, y: rect.minY + rect.height * 0.82))
        p.addLine(to: CGPoint(x: rect.minX + rect.width * 0.95, y: rect.minY + rect.height * 0.18))
        return p
    }
}
