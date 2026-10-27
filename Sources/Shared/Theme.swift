import SwiftUI

#if os(macOS)
import AppKit
typealias PlatformImage = NSImage
extension Image { init(platform: PlatformImage) { self.init(nsImage: platform) } }
#else
import UIKit
typealias PlatformImage = UIImage
extension Image { init(platform: PlatformImage) { self.init(uiImage: platform) } }
#endif

enum Theme {
    static let bg = Color(red: 0.027, green: 0.035, blue: 0.075)
    static let card = Color(red: 0.075, green: 0.09, blue: 0.15)
    static let line = Color.white.opacity(0.08)
    static let lime = Color(red: 0.78, green: 1.0, blue: 0.30)
    static let teal = Color(red: 0.10, green: 0.85, blue: 0.75)
    static let deep = Color(red: 0.04, green: 0.36, blue: 0.50)
    static let ink = Color.white
    static let dim = Color.white.opacity(0.55)
    static let radius: CGFloat = 28

    static let hero = LinearGradient(
        colors: [teal, deep, Color(red: 0.12, green: 0.20, blue: 0.55)],
        startPoint: .topLeading, endPoint: .bottomTrailing)
    static let limeGradient = LinearGradient(colors: [lime, Color(red: 0.55, green: 0.95, blue: 0.35)], startPoint: .leading, endPoint: .trailing)
}

extension Font {
    static func num(_ size: CGFloat) -> Font { .system(size: size, weight: .bold, design: .rounded) }
    static func label(_ size: CGFloat = 12) -> Font { .system(size: size, weight: .semibold, design: .rounded) }
}

struct GlassCard<Content: View>: View {
    var padding: CGFloat = 22
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                    .fill(Theme.card)
                    .overlay(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).fill(.ultraThinMaterial.opacity(0.25)))
                    .overlay(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).stroke(Theme.line, lineWidth: 1))
            )
    }
}

struct HeroCard<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).fill(Theme.hero)
            Circle().fill(Theme.lime.opacity(0.55)).frame(width: 260, height: 260).blur(radius: 70).offset(x: 220, y: -90)
            Circle().stroke(.white.opacity(0.12), lineWidth: 1).frame(width: 300, height: 300).offset(x: 250, y: 20)
            Circle().stroke(.white.opacity(0.10), lineWidth: 1).frame(width: 190, height: 190).offset(x: 305, y: 75)
            RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                .fill(LinearGradient(colors: [.white.opacity(0.28), .clear], startPoint: .top, endPoint: .center))
            content.padding(28).frame(maxWidth: .infinity, alignment: .leading)
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).stroke(.white.opacity(0.25), lineWidth: 1))
        .shadow(color: Theme.teal.opacity(0.35), radius: 30, y: 16)
    }
}

struct PillButtonStyle: ButtonStyle {
    var filled = true
    var tint: Color = Theme.lime
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.label(14))
            .foregroundStyle(filled ? Color.black.opacity(0.85) : Theme.ink)
            .padding(.horizontal, 20).padding(.vertical, 12)
            .background(Capsule().fill(filled ? AnyShapeStyle(tint) : AnyShapeStyle(Color.white.opacity(0.08))))
            .overlay(Capsule().stroke(filled ? .clear : Theme.line, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.75 : 1)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}

struct Chip: View {
    let title: String
    var body: some View {
        Text(title).font(.label(11)).foregroundStyle(Theme.ink.opacity(0.85))
            .padding(.horizontal, 11).padding(.vertical, 6)
            .background(Capsule().fill(.white.opacity(0.14)))
    }
}

struct StatCard: View {
    let title: String
    let value: String
    var accent: Color = Theme.teal
    var body: some View {
        GlassCard(padding: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Circle().fill(accent).frame(width: 8, height: 8)
                Text(value).font(.num(26)).foregroundStyle(Theme.ink).minimumScaleFactor(0.6).lineLimit(1)
                Text(title.uppercased()).font(.label(10)).tracking(1.4).foregroundStyle(Theme.dim)
            }
        }
    }
}

struct CheckDot: View {
    let on: Bool
    var body: some View {
        ZStack {
            Circle().fill(on ? AnyShapeStyle(Theme.lime) : AnyShapeStyle(Color.black.opacity(0.35)))
            Circle().stroke(on ? .clear : .white.opacity(0.7), lineWidth: 1.5)
            if on { Image(systemName: "checkmark").font(.system(size: 10, weight: .heavy)).foregroundStyle(.black) }
        }
        .frame(width: 22, height: 22)
    }
}

struct ActionBar: View {
    let title: String
    let subtitle: String
    let action: String
    var destructive = true
    let run: () -> Void
    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.num(17)).foregroundStyle(Theme.ink)
                Text(subtitle).font(.label(12)).foregroundStyle(Theme.dim)
            }
            Spacer()
            Button(action, action: run).buttonStyle(PillButtonStyle(tint: destructive ? Theme.lime : Theme.teal))
        }
        .padding(.leading, 24).padding(.trailing, 10).padding(.vertical, 10)
        .background(Capsule().fill(.ultraThinMaterial))
        .background(Capsule().fill(Theme.card.opacity(0.85)))
        .overlay(Capsule().stroke(Theme.line, lineWidth: 1))
        .shadow(color: .black.opacity(0.4), radius: 24, y: 10)
    }
}
