import SwiftUI
import UIKit
import SecondBrainCore

/// Visual language: "calm and roomy" — soft surfaces, generous spacing and rounded cards under a deep
/// teal header, with color kept for meaning (badges, quadrants, safety). Deliberately neutral — no
/// retailer branding.
enum Theme {
    static func dynamic(light: UIColor, dark: UIColor) -> Color {
        Color(uiColor: UIColor { traits in traits.userInterfaceStyle == .dark ? dark : light })
    }

    static func rgb(_ r: Int, _ g: Int, _ b: Int, _ a: CGFloat = 1) -> UIColor {
        UIColor(red: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: a)
    }

    /// Calm teal accent.
    static let accent = dynamic(light: rgb(14, 140, 126), dark: rgb(56, 201, 180))

    static let background = dynamic(light: rgb(244, 245, 243), dark: rgb(17, 18, 20))
    static let surface = dynamic(light: .white, dark: rgb(28, 29, 32))
    static let surfaceRaised = dynamic(light: rgb(248, 248, 250), dark: rgb(38, 39, 43))
    static let stroke = dynamic(light: rgb(0, 0, 0, 0.06), dark: rgb(255, 255, 255, 0.07))
    static let secondaryText = Color.secondary

    static let danger = dynamic(light: rgb(209, 52, 56), dark: rgb(255, 99, 99))
    static let warning = dynamic(light: rgb(199, 125, 0), dark: rgb(255, 184, 77))
    static let success = dynamic(light: rgb(36, 145, 84), dark: rgb(84, 214, 138))
    static let purple = dynamic(light: rgb(83, 74, 183), dark: rgb(175, 169, 236))
    static let pink = dynamic(light: rgb(193, 64, 110), dark: rgb(237, 147, 177))
    static let brown = dynamic(light: rgb(140, 94, 60), dark: rgb(214, 170, 130))

    // Header ("hero") card: deep teal with mint text, the same in light and dark.
    static let heroFill = Color(uiColor: rgb(15, 110, 86))
    static let heroText = Color(uiColor: rgb(225, 245, 238))
    static let heroSecondary = Color(uiColor: rgb(159, 225, 203))
    static let heroTrack = Color(uiColor: rgb(8, 80, 65))
    static let heroProgress = Color(uiColor: rgb(93, 202, 165))

    /// Background for a colored tile or badge.
    static func tint(_ color: Color, _ strength: Double = 0.16) -> Color { color.opacity(strength) }

    static func color(for quadrant: Quadrant) -> Color {
        switch quadrant {
        case .doFirst: return dynamic(light: rgb(214, 57, 61), dark: rgb(255, 102, 102))
        case .schedule: return dynamic(light: rgb(38, 110, 214), dark: rgb(102, 163, 255))
        case .delegate: return dynamic(light: rgb(196, 124, 0), dark: rgb(255, 189, 89))
        case .eliminate: return dynamic(light: rgb(120, 124, 132), dark: rgb(150, 154, 163))
        }
    }

    static func color(for kind: RetailMoment.Kind) -> Color {
        switch kind {
        case .holiday: return purple
        case .salesEvent: return pink
        case .seasonal: return success
        case .operations: return color(for: .schedule)
        case .safety: return warning
        case .fiscal: return accent
        case .store: return brown
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

    static let cornerRadius: CGFloat = 20
}

/// Card container used across the dashboard and planners.
struct CardBackground: ViewModifier {
    var padding: CGFloat = 16
    /// Optional color wash for cards that carry a meaning (Inbox, Coming up).
    var tint: Color? = nil

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                ZStack {
                    shape.fill(Theme.surface)
                    if let tint { shape.fill(tint.opacity(0.12)) }
                }
            }
            .overlay(shape.strokeBorder(tint.map { $0.opacity(0.35) } ?? Theme.stroke, lineWidth: 1))
    }
}

extension View {
    func card(padding: CGFloat = 16, tint: Color? = nil) -> some View {
        modifier(CardBackground(padding: padding, tint: tint))
    }
}
