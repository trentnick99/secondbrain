import SwiftUI
import UIKit
import SecondBrainCore

/// Visual language: charcoal surfaces, one restrained accent, clear quadrant colors.
/// Deliberately neutral — no retailer branding.
enum Theme {
    static func dynamic(light: UIColor, dark: UIColor) -> Color {
        Color(uiColor: UIColor { traits in traits.userInterfaceStyle == .dark ? dark : light })
    }

    static func rgb(_ r: Int, _ g: Int, _ b: Int, _ a: CGFloat = 1) -> UIColor {
        UIColor(red: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: a)
    }

    /// Calm teal accent.
    static let accent = dynamic(light: rgb(14, 140, 126), dark: rgb(56, 201, 180))

    static let background = dynamic(light: rgb(242, 242, 245), dark: rgb(17, 18, 20))
    static let surface = dynamic(light: .white, dark: rgb(28, 29, 32))
    static let surfaceRaised = dynamic(light: rgb(248, 248, 250), dark: rgb(38, 39, 43))
    static let stroke = dynamic(light: rgb(0, 0, 0, 0.06), dark: rgb(255, 255, 255, 0.07))
    static let secondaryText = Color.secondary

    static let danger = dynamic(light: rgb(209, 52, 56), dark: rgb(255, 99, 99))
    static let warning = dynamic(light: rgb(199, 125, 0), dark: rgb(255, 184, 77))
    static let success = dynamic(light: rgb(36, 145, 84), dark: rgb(84, 214, 138))

    static func color(for quadrant: Quadrant) -> Color {
        switch quadrant {
        case .doFirst: return dynamic(light: rgb(214, 57, 61), dark: rgb(255, 102, 102))
        case .schedule: return dynamic(light: rgb(38, 110, 214), dark: rgb(102, 163, 255))
        case .delegate: return dynamic(light: rgb(196, 124, 0), dark: rgb(255, 189, 89))
        case .eliminate: return dynamic(light: rgb(120, 124, 132), dark: rgb(150, 154, 163))
        }
    }

    static func color(for priority: TaskPriority) -> Color {
        switch priority {
        case .critical: return danger
        case .high: return warning
        case .normal: return .secondary
        case .low: return Color.secondary.opacity(0.6)
        }
    }

    static let cornerRadius: CGFloat = 16
}

/// Card container used across the dashboard and planners.
struct CardBackground: ViewModifier {
    var padding: CGFloat = 14

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                    .strokeBorder(Theme.stroke, lineWidth: 1)
            )
    }
}

extension View {
    func card(padding: CGFloat = 14) -> some View { modifier(CardBackground(padding: padding)) }
}
