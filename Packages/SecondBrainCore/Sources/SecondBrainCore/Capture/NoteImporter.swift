import Foundation

/// One action item found in imported notes.
public struct ImportedItem: Identifiable, Sendable {
    public let id: Int
    /// The cleaned line as written (bullets and "Action:" prefixes removed).
    public let text: String
    /// Areas or departments the item mentions, or that its section heading named.
    public let areas: [String]
    public let isTotalStore: Bool
    /// The heading it appeared under, such as "Fresh" or "Total store".
    public let section: String?
    public let relevance: AreaRelevance
    /// How Quick Capture reads it: title, explicit dates, people, quadrant.
    public let parsed: ParsedCapture

    /// The area to file it under: "Total Store", the first area, or nil.
    public var filingArea: String? {
        if isTotalStore { return StoreAreas.totalStore }
        return areas.first
    }
}

/// The result of reading an email or set of notes.
public struct NoteImport: Sendable {
    /// From a "Subject:" line, without RE:/FW:.
    public let subject: String?
    public let items: [ImportedItem]
    /// Lines skipped as greetings, sign-offs, headers or plain context.
    public let skippedLines: Int

    public func items(_ relevance: AreaRelevance) -> [ImportedItem] { items.filter { $0.relevance == relevance } }
}

/// Turns pasted or shared notes — a market walk recap, a visit follow-up email — into reviewable items.
/// Nothing is saved here; the app shows every item for confirmation first. Dates are only read when the
/// text states them.
public enum NoteImporter {
    public static let maximumItems = 60

    public static func parse(_ text: String, role: UserRole?, context: CaptureContext) -> NoteImport {
        let parser = NaturalLanguageParser()
        var subject: String?
        var items: [ImportedItem] = []
        var skipped = 0
        var sectionAreas: [String] = []
        var sectionIsTotal = false
        var sectionTitle: String?
        var seenContent = false

        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")

        var previousBlank = false
        lineLoop: for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { previousBlank = true; continue }
            defer { previousBlank = false }
            let lower = line.lowercased()

            // Email headers.
            if let value = headerValue(line, "subject") {
                subject = cleanSubject(value)
                continue
            }
            if ["from:", "sent:", "to:", "cc:", "bcc:", "date:", "importance:"].contains(where: lower.hasPrefix) {
                if seenContent { break lineLoop }   // an earlier email quoted below this one
                skipped += 1
                continue
            }
            // Where the message ends.
            if isQuoteMarker(lower) || (seenContent && isSignOff(lower)) { break lineLoop }
            if isGreeting(lower) || isNoise(lower) {
                skipped += 1
                continue
            }

            let bullet = bulletPrefix(line)
            var body = bullet.map { String(line.dropFirst($0.count)).trimmingCharacters(in: .whitespaces) } ?? line
            var lineLabel: ([String], Bool)?

            // "Front End - SCO coverage was thin" / "Fresh: fix the signage" — a label for this line only.
            if let (labelAreas, labelTotal, rest) = inlineLabel(body) {
                lineLabel = (labelAreas, labelTotal)
                body = rest
            } else if bullet == nil, let heading = headingText(line) {
                // A heading on its own line starts a section: "Fresh:", "FRONT END", "Total store".
                let (areas, total) = detectAreas(heading)
                sectionAreas = areas
                sectionIsTotal = total
                sectionTitle = heading
                continue
            } else if bullet == nil && previousBlank {
                // Plain prose after a blank line has left the previous section.
                sectionAreas = []
                sectionIsTotal = false
                sectionTitle = nil
            }

            // Items: bullets and labelled lines always; other lines sentence by sentence when actionable.
            let candidates: [String]
            if bullet != nil || lineLabel != nil {
                candidates = [body]
            } else {
                candidates = sentences(body).filter(isActionable)
                if candidates.isEmpty { skipped += 1 }
            }

            for candidate in candidates {
                let cleaned = cleanItem(candidate)
                guard cleaned.split(separator: " ").count >= 2 else { continue }
                seenContent = true
                let (mentioned, mentionsTotal) = detectAreas(cleaned)
                let baseAreas = lineLabel?.0 ?? sectionAreas
                let baseTotal = lineLabel?.1 ?? sectionIsTotal
                var areas = baseAreas
                for area in mentioned where !areas.contains(area) { areas.append(area) }
                // A line that names its own area overrides a "total store" heading.
                let total = mentionsTotal || (baseTotal && mentioned.isEmpty && baseAreas.isEmpty)
                let relevance = role?.relevance(of: areas, isTotalStore: total) ?? (total ? .totalStore : .mine)
                var parsed = parser.parse(cleaned, context: context)
                if let filing = total ? StoreAreas.totalStore : areas.first {
                    parsed.department = filing
                }
                items.append(ImportedItem(id: items.count, text: cleaned, areas: areas, isTotalStore: total,
                                          section: lineLabel == nil ? sectionTitle : nil, relevance: relevance, parsed: parsed))
                if items.count == maximumItems { break lineLoop }
            }
        }
        return NoteImport(subject: subject, items: items, skippedLines: skipped)
    }

    // MARK: - Pieces

    static func headerValue(_ line: String, _ name: String) -> String? {
        guard line.lowercased().hasPrefix(name + ":") else { return nil }
        return String(line.dropFirst(name.count + 1)).trimmingCharacters(in: .whitespaces)
    }

    static func cleanSubject(_ value: String) -> String {
        var s = value
        while let range = s.range(of: #"^\s*(re|fw|fwd)\s*:\s*"#, options: [.regularExpression, .caseInsensitive]) {
            s.removeSubrange(range)
        }
        return s.trimmingCharacters(in: .whitespaces)
    }

    static func isQuoteMarker(_ lower: String) -> Bool {
        lower.hasPrefix("-----original message") || lower.hasPrefix("________________") ||
            (lower.hasPrefix("on ") && lower.hasSuffix("wrote:")) || lower.hasPrefix(">")
    }

    static func isSignOff(_ lower: String) -> Bool {
        let s = lower.trimmingCharacters(in: CharacterSet(charactersIn: " ,.!-"))
        let signOffs = ["thanks", "thank you", "thanks all", "thanks team", "thank you all", "regards", "best",
                        "best regards", "kind regards", "sincerely", "cheers", "respectfully", "--", "-"]
        return signOffs.contains(s) || lower.hasPrefix("sent from my") || lower.hasPrefix("get outlook for")
    }

    static func isGreeting(_ lower: String) -> Bool {
        let s = lower.trimmingCharacters(in: CharacterSet(charactersIn: " ,.!:-"))
        let greetings = ["hi", "hello", "hey", "team", "all", "good morning", "good afternoon", "good evening"]
        if greetings.contains(s) { return true }
        return ["hi ", "hello ", "hey ", "good morning ", "good afternoon ", "good evening "].contains(where: s.hasPrefix)
            && s.split(separator: " ").count <= 4
    }

    static func isNoise(_ lower: String) -> Bool {
        lower.hasPrefix("[external]") || lower.contains("confidential") && lower.contains("intended") ||
            lower.hasPrefix("this email") || lower.hasPrefix("caution:")
    }

    /// "- ", "• ", "* ", "1. ", "1) ", "a) ", "[ ] ", "☐ ".
    static func bulletPrefix(_ line: String) -> String? {
        let pattern = #"^(?:[-•*▪◦‣–—]|\[\s?\]|☐|\(?\d{1,2}[.)]|\(?[a-zA-Z][.)])\s+"#
        guard let range = line.range(of: pattern, options: .regularExpression) else { return nil }
        return String(line[range])
    }

    /// "Front End - SCO coverage was thin" → (["Front End"], false, "SCO coverage was thin").
    static func inlineLabel(_ line: String) -> ([String], Bool, String)? {
        let pattern = #"^([A-Za-z&/()' ]{2,32}?)\s*(?::|\s[-–—]\s)\s*(.+)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let m = regex.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)) else { return nil }
        let ns = line as NSString
        let label = ns.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespaces)
        let rest = ns.substring(with: m.range(at: 2)).trimmingCharacters(in: .whitespaces)
        guard label.split(separator: " ").count <= 4, rest.split(separator: " ").count >= 2 else { return nil }
        let (areas, total) = detectAreas(label)
        guard !areas.isEmpty || total else { return nil }
        return (areas, total, rest)
    }

    /// Short lines that read as headings: "Fresh:", "FRONT END", "Total store -".
    static func headingText(_ line: String) -> String? {
        let words = line.split(separator: " ")
        let beforeColon = line.split(separator: ":", maxSplits: 1).first.map(String.init) ?? line
        if line.contains(":"), beforeColon.split(separator: " ").count <= 4 {
            return beforeColon.trimmingCharacters(in: CharacterSet(charactersIn: " -–—*#"))
        }
        let trimmed = line.trimmingCharacters(in: CharacterSet(charactersIn: " -–—*#"))
        if words.count <= 4, !trimmed.isEmpty, trimmed == trimmed.uppercased() || detectAreas(trimmed).0.count > 0 && words.count <= 3 {
            return trimmed
        }
        return nil
    }

    /// Areas named in text (as coach areas where the department has a clear owner) and whether it's store-wide.
    static func detectAreas(_ text: String) -> ([String], Bool) {
        let lower = text.lowercased()
        let totalPhrases = ["total store", "store-wide", "storewide", "store wide", "whole store", "entire store",
                            "all areas", "all departments", "all coaches", "every coach", "all salesfloor"]
        let total = totalPhrases.contains { lower.contains($0) }
        var areas: [String] = []
        var remaining = text
        // Collect every department mentioned, earliest first.
        for _ in 0..<4 {
            guard let match = DepartmentLexicon.match(in: remaining), match != StoreAreas.totalStore else { break }
            let area = StoreAreas.area(for: match) ?? match
            if !areas.contains(area) { areas.append(area) }
            // Remove the matched alias so the next pass finds another department.
            let aliases = DepartmentLexicon.entries.first { $0.name == match }?.aliases ?? [match.lowercased()]
            var changed = false
            for alias in aliases.sorted(by: { $0.count > $1.count }) {
                if let range = remaining.range(of: #"\b"# + NSRegularExpression.escapedPattern(for: alias) + #"\b"#,
                                               options: [.regularExpression, .caseInsensitive]) {
                    remaining.replaceSubrange(range, with: " ")
                    changed = true
                    break
                }
            }
            if !changed { break }
        }
        return (areas, total)
    }

    /// Splits on ". ", "! " or "? " before a capital or digit (works the same on every platform).
    static func sentences(_ line: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: #"(?<=[.!?])\s+(?=[A-Z0-9"“])"#) else { return [line] }
        let ns = line as NSString
        var result: [String] = []
        var start = 0
        for match in regex.matches(in: line, range: NSRange(location: 0, length: ns.length)) {
            result.append(ns.substring(with: NSRange(location: start, length: match.range.location - start)))
            start = match.range.location + match.range.length
        }
        result.append(ns.substring(from: start))
        let trimmed = result.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return trimmed.isEmpty ? [line] : trimmed
    }

    static let requestMarkers = ["need to", "needs to", "please", "make sure", "ensure", "must", "should", "follow up",
                                 "follow-up", "by end of", "asap", "action:", "action item", "to do:", "todo:", "let's",
                                 "have it", "get it", "get the", "have the", "expect", "i want", "i'd like", "we need",
                                 "needs attention", "needs to be", "be ready", "complete", "fix", "clean up"]

    static func isActionable(_ sentence: String) -> Bool {
        let lower = sentence.lowercased()
        let words = lower.split(whereSeparator: { !$0.isLetter && $0 != "'" })
        guard words.count >= 3 else { return false }
        if let first = words.first, Lexicon.actionStartVerbs.contains(String(first)) { return true }
        return requestMarkers.contains { lower.contains($0) }
    }

    static func cleanItem(_ text: String) -> String {
        var s = text
        if let range = s.range(of: #"^(?:action(?: item)?|to ?do|todo|next steps?|follow[- ]?up)\s*[:\-–]\s*"#,
                               options: [.regularExpression, .caseInsensitive]) {
            s.removeSubrange(range)
        }
        return s.trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: "-–—•*")))
    }
}
