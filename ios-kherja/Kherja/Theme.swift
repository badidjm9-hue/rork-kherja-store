//
//  Theme.swift
//  Kherja
//
//  KJ design language — Blue #075BFF, Burgundy #85003F, light lavender canvas.
//

import SwiftUI

enum KJ {
    static let blue = Color(hex: 0x075BFF)
    static let blueDeep = Color(hex: 0x0043C7)
    static let burgundy = Color(hex: 0x85003F)
    static let burgundyBright = Color(hex: 0xC4145A)
    static let ink = Color(hex: 0x0D1B4C)
    static let inkSoft = Color(hex: 0x3D4A73)
    static let muted = Color(hex: 0x7A8199)
    static let canvas = Color(hex: 0xF7F8FC)
    static let softBlue = Color(hex: 0xE9EEFB)
    static let softBlueMid = Color(hex: 0xDCE4F8)
    static let success = Color(hex: 0x12A150)
    static let successBg = Color(hex: 0xE3F6EB)
    static let danger = Color(hex: 0xE5484D)
    static let dangerBg = Color(hex: 0xFCE9EA)
    static let warning = Color(hex: 0xF0A52D)
    static let white = Color.white

    static let buttonGradient = LinearGradient(
        colors: [Color(hex: 0x1668FF), blue],
        startPoint: .top, endPoint: .bottom
    )
    static let burgundyGradient = LinearGradient(
        colors: [burgundyBright, burgundy],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    static let canvasGradient = LinearGradient(
        colors: [Color(hex: 0xE8EDFA), canvas, canvas],
        startPoint: .top, endPoint: .bottom
    )
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}

// MARK: - Logo

struct KJLogo: View {
    var height: CGFloat = 88

    var body: some View {
        Image("kj_logo")
            .resizable()
            .scaledToFit()
            .frame(height: height)
            .accessibilityLabel("KHERJA")
    }
}

// MARK: - Corner blobs (the KJ header decoration)

struct CornerBlobs: View {
    var showBurgundy = true

    var body: some View {
        ZStack(alignment: .top) {
            GeometryReader { geo in
                Circle()
                    .fill(KJ.buttonGradient)
                    .frame(width: geo.size.width * 0.62, height: geo.size.width * 0.62)
                    .offset(x: -geo.size.width * 0.30, y: -geo.size.width * 0.34)
                if showBurgundy {
                    Circle()
                        .fill(KJ.burgundyGradient)
                        .frame(width: geo.size.width * 0.34, height: geo.size.width * 0.34)
                        .offset(x: geo.size.width * 0.78, y: -geo.size.width * 0.16)
                }
                Circle()
                    .fill(KJ.softBlueMid.opacity(0.7))
                    .frame(width: geo.size.width * 0.22, height: geo.size.width * 0.22)
                    .offset(x: geo.size.width * 0.62, y: -geo.size.width * 0.02)
            }
        }
        .allowsHitTesting(false)
        .ignoresSafeArea(edges: .top)
    }
}

// MARK: - Card + button styles

struct KJCard: ViewModifier {
    var padding: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(.white)
                    .shadow(color: Color(hex: 0x075BFF).opacity(0.10), radius: 18, x: 0, y: 8)
                    .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 2)
            )
    }
}

extension View {
    func kjCard(padding: CGFloat = 16) -> some View {
        modifier(KJCard(padding: padding))
    }
}

struct KJButtonStyle: ButtonStyle {
    var gradient: LinearGradient = KJ.buttonGradient
    var pressedScale: CGFloat = 0.97
    var shadowColor: Color = KJ.blue

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .bold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(Capsule().fill(gradient))
            .shadow(color: shadowColor.opacity(0.35), radius: 14, x: 0, y: 8)
            .scaleEffect(configuration.isPressed ? pressedScale : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

struct GhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(KJ.blue)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(
                Capsule()
                    .fill(.white)
                    .overlay(Capsule().strokeBorder(KJ.blue.opacity(0.35), lineWidth: 1.5))
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Formatting

enum KJFormat {
    static func dzd(_ amount: Int) -> String {
        return "\(group(amount)) DA"
    }

    static func group(_ n: Int) -> String {
        let s = String(abs(n))
        var out = ""
        for (i, ch) in s.enumerated() {
            if i > 0 && (s.count - i) % 3 == 0 { out += " " }
            out.append(ch)
        }
        return n < 0 ? "-" + out : out
    }
}
