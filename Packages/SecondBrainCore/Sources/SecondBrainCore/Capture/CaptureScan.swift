import Foundation

/// Tracks which parts of the captured text have already been interpreted, so each phrase is
/// used once and the remainder becomes the task title.
final class CaptureScan {
    let text: String
    let ns: NSString
    private(set) var consumed: [NSRange] = []
    private(set) var phrases: [String] = []

    init(_ text: String) {
        self.text = text
        self.ns = text as NSString
    }

    var fullRange: NSRange { NSRange(location: 0, length: ns.length) }

    static func intersects(_ a: NSRange, _ b: NSRange) -> Bool {
        let aEnd = a.location + a.length
        let bEnd = b.location + b.length
        return a.location < bEnd && b.location < aEnd
    }

    func isFree(_ range: NSRange) -> Bool {
        !consumed.contains { Self.intersects($0, range) }
    }

    func consume(_ range: NSRange, recordPhrase: Bool = true) {
        guard range.location != NSNotFound, range.length > 0 else { return }
        consumed.append(range)
        if recordPhrase {
            let phrase = ns.substring(with: range).trimmingCharacters(in: .whitespacesAndNewlines)
            if !phrase.isEmpty { phrases.append(phrase) }
        }
    }

    func matches(_ pattern: String, caseInsensitive: Bool = true) -> [NSTextCheckingResult] {
        guard let regex = Lexicon.regex(pattern, caseInsensitive: caseInsensitive) else { return [] }
        return regex.matches(in: text, options: [], range: fullRange).filter { isFree($0.range) }
    }

    func allMatches(_ pattern: String, caseInsensitive: Bool = true) -> [NSTextCheckingResult] {
        guard let regex = Lexicon.regex(pattern, caseInsensitive: caseInsensitive) else { return [] }
        return regex.matches(in: text, options: [], range: fullRange)
    }

    func firstMatch(_ pattern: String, caseInsensitive: Bool = true) -> NSTextCheckingResult? {
        matches(pattern, caseInsensitive: caseInsensitive).first
    }

    func group(_ match: NSTextCheckingResult, _ index: Int) -> String? {
        guard index < match.numberOfRanges else { return nil }
        let r = match.range(at: index)
        guard r.location != NSNotFound, r.length > 0 else { return nil }
        return ns.substring(with: r)
    }

    func substring(_ range: NSRange) -> String { ns.substring(with: range) }

    /// The text with every consumed range blanked out.
    func remainingText() -> String {
        var units = Array(text.utf16)
        for r in consumed {
            let end = min(r.location + r.length, units.count)
            guard r.location < end else { continue }
            for i in r.location..<end { units[i] = 32 }
        }
        return String(decoding: units, as: UTF16.self)
    }
}

enum CalendarWords {
    static let weekdayFull = "sunday|monday|tuesday|wednesday|thursday|friday|saturday"
    static let weekdayAbbrev = "sun|mon|tues|tue|wed|thurs|thur|thu|fri|sat"
    static let weekdayPlural = "sundays|mondays|tuesdays|wednesdays|thursdays|fridays|saturdays"
    static var weekdayAny: String { weekdayFull + "|" + weekdayAbbrev }
    static let months = "january|february|march|april|may|june|july|august|september|october|november|december|sept|jan|feb|mar|apr|jun|jul|aug|sep|oct|nov|dec"

    /// Abbreviations that are also everyday words; only accepted after "on", "by", "next", etc.
    static let restrictedAbbreviations: Set<String> = ["sun", "sat", "wed", "mon"]

    static func weekdayNumber(_ token: String) -> Int? {
        let t = token.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        guard t.count >= 3 else { return nil }
        switch String(t.prefix(3)) {
        case "sun": return 1
        case "mon": return 2
        case "tue": return 3
        case "wed": return 4
        case "thu": return 5
        case "fri": return 6
        case "sat": return 7
        default: return nil
        }
    }

    static func monthNumber(_ token: String) -> Int? {
        let t = token.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        guard t.count >= 3 else { return nil }
        let order = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]
        guard let index = order.firstIndex(of: String(t.prefix(3))) else { return nil }
        return index + 1
    }
}

enum NumberWords {
    static let pattern = #"\d{1,3}|an?|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|fifteen|twenty|thirty|forty[- ]five|a\s+couple(?:\s+of)?|couple(?:\s+of)?|a\s+few|few"#

    static func value(_ token: String) -> Int? {
        let t = token.lowercased()
            .replacingOccurrences(of: "-", with: " ")
            .split(whereSeparator: { $0 == " " || $0 == "\t" })
            .joined(separator: " ")
        if let n = Int(t) { return n }
        let map: [String: Int] = [
            "a": 1, "an": 1, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7,
            "eight": 8, "nine": 9, "ten": 10, "eleven": 11, "twelve": 12, "fifteen": 15, "twenty": 20,
            "thirty": 30, "forty five": 45, "a couple": 2, "a couple of": 2, "couple": 2, "couple of": 2,
            "a few": 3, "few": 3
        ]
        return map[t]
    }
}
