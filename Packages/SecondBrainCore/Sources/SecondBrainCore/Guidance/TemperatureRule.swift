import Foundation

/// The limits written in a temperature standard, read from plain words: "41°F or colder",
/// "-10 F or below", "135°F or hotter", "between 33 and 41°F", "33–38°F". When the words can't be
/// read, there's no rule and the person says whether a reading meets the standard themselves.
public struct TemperatureRule: Equatable, Sendable {
    public var minimum: Double?
    public var maximum: Double?

    public init(minimum: Double? = nil, maximum: Double? = nil) {
        self.minimum = minimum
        self.maximum = maximum
    }

    public func allows(_ reading: Double) -> Bool {
        if let minimum, reading < minimum { return false }
        if let maximum, reading > maximum { return false }
        return true
    }

    /// "41°F or colder" style text for a reading outside the rule.
    public var summary: String {
        switch (minimum, maximum) {
        case let (low?, high?): return "\(Self.format(low))–\(Self.format(high))°F"
        case let (nil, high?): return "\(Self.format(high))°F or colder"
        case let (low?, nil): return "\(Self.format(low))°F or hotter"
        default: return ""
        }
    }

    /// Words that make the number a maximum or a minimum, matched as whole words.
    private static let colder = #"\b(colder|below|lower|less|cooler|under|max|maximum|at most|no warmer than|no higher than)\b"#
    private static let hotter = #"\b(hotter|above|higher|more|warmer|over|min|minimum|at least|no colder than|no lower than)\b"#

    /// Reads the limits from a standard's words. Nil when they don't state a clear limit.
    public static func parse(_ standard: String) -> TemperatureRule? {
        let text = standard.lowercased()
            .replacingOccurrences(of: "−", with: "-")
            .replacingOccurrences(of: "–", with: "-")
            .replacingOccurrences(of: "—", with: "-")
            .replacingOccurrences(of: "≤", with: " or below ")
            .replacingOccurrences(of: "≥", with: " or above ")
            .replacingOccurrences(of: "<=", with: " or below ")
            .replacingOccurrences(of: ">=", with: " or above ")
        let numbers = Self.numbers(in: text)
        guard !numbers.isEmpty else { return nil }

        // A range: "between 33 and 41", "33-41°F", "33 to 41".
        if numbers.count >= 2 {
            let pair = numbers.prefix(2).sorted()
            let isRange = text.contains("between") || text.range(of: #"\d\s*°?\s*f?\s*(-|to)\s*-?\d"#, options: .regularExpression) != nil
            if isRange { return TemperatureRule(minimum: pair[0], maximum: pair[1]) }
        }
        let value = numbers[0]
        let isMaximum = text.range(of: colder, options: .regularExpression) != nil
        let isMinimum = text.range(of: hotter, options: .regularExpression) != nil
        if isMaximum && !isMinimum { return TemperatureRule(maximum: value) }
        if isMinimum && !isMaximum { return TemperatureRule(minimum: value) }
        return nil
    }

    /// A reading typed by the person: "5", "-10", "38.5", "5°", "5 F". Nil if there's no number.
    public static func reading(from text: String) -> Double? {
        numbers(in: text.replacingOccurrences(of: "−", with: "-")).first
    }

    /// Numbers in order, keeping a minus sign that sits right before a number ("-10") but not a dash
    /// between two numbers ("33-41" is 33 and 41).
    static func numbers(in text: String) -> [Double] {
        guard let regex = try? NSRegularExpression(pattern: #"(?<![\d.])-?\d+(?:\.\d+)?"#) else { return [] }
        let ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).compactMap { match in
            var token = ns.substring(with: match.range)
            // "33-41" or "33 - 41°F": the "-41" follows a number, so it's a dash, not a minus.
            if token.hasPrefix("-") {
                var index = match.range.location - 1
                while index >= 0, ns.substring(with: NSRange(location: index, length: 1)) == " " { index -= 1 }
                if index >= 0 {
                    let before = ns.substring(with: NSRange(location: index, length: 1))
                    if before.rangeOfCharacter(from: .decimalDigits) != nil || before == "°" || before == "f" {
                        token.removeFirst()
                    }
                }
            }
            return Double(token)
        }
    }

    private static func format(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(value)
    }
}
