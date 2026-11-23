import Foundation

/// A follow-up or task the detector found inside free text (meeting notes, associate notes).
/// Suggestions are only created after the person confirms them.
public struct CommitmentSuggestion: Identifiable, Equatable, Sendable {
    public var id: String { sourceLine }
    public var sourceLine: String
    public var parsed: ParsedCapture
}

/// Finds requests and commitments in notes: "I'll get back to Maria about PTO Friday",
/// "Action item: check cooler temps tomorrow", "- [ ] order more pallet jacks".
public enum CommitmentDetector {
    static let commitmentCues = [
        "i'll", "i will", "i’ll", "i need to", "i have to", "i promised", "promised", "i told", "get back to",
        "follow up", "follow-up", "followup", "check with", "check on", "check in with", "circle back",
        "touch base", "remind me", "make sure", "need to", "needs to", "to do", "todo", "action item",
        "action:", "next step", "asked me", "asked for", "wants me to", "requested", "let her know",
        "let him know", "let them know", "talk to", "talk with", "schedule", "by tomorrow", "by friday"
    ]

    public static func detect(in text: String, context: CaptureContext, limit: Int = 12) -> [CommitmentSuggestion] {
        let parser = NaturalLanguageParser()
        var results: [CommitmentSuggestion] = []
        var seenTitles = Set<String>()

        for rawLine in candidateLines(text) {
            var line = rawLine
            var forced = false
            // Checklist syntax counts as an explicit action item.
            for marker in ["- [ ]", "[ ]", "☐", "* [ ]"] where line.hasPrefix(marker) {
                line = String(line.dropFirst(marker.count)).trimmingCharacters(in: .whitespaces)
                forced = true
            }
            for marker in ["action item:", "action:", "todo:", "to do:", "ai:"] where line.lowercased().hasPrefix(marker) {
                line = String(line.dropFirst(marker.count)).trimmingCharacters(in: .whitespaces)
                forced = true
            }
            guard line.count >= 4 else { continue }

            let lower = " " + line.lowercased() + " "
            let hasCue = Lexicon.containsAny(lower, commitmentCues)
            let parsed = parser.parse(line, context: context)
            guard parsed.kind.taskKind != nil else { continue }
            let hasSignal = parsed.associateName != nil || parsed.hasSchedule
            guard forced || hasCue || (hasSignal && parsed.kind == .followUp) else { continue }

            let key = parsed.title.lowercased()
            guard !key.isEmpty, seenTitles.insert(key).inserted else { continue }
            results.append(CommitmentSuggestion(sourceLine: rawLine, parsed: parsed))
            if results.count >= limit { break }
        }
        return results
    }

    /// Splits text into lines, then long lines into sentences.
    static func candidateLines(_ text: String) -> [String] {
        var lines: [String] = []
        for raw in text.components(separatedBy: .newlines) {
            var line = raw.trimmingCharacters(in: .whitespaces)
            for bullet in ["• ", "* ", "- ", "– "] where line.hasPrefix(bullet) && !line.hasPrefix("- [") {
                line = String(line.dropFirst(bullet.count))
            }
            guard !line.isEmpty else { continue }
            if line.count > 90 {
                lines.append(contentsOf: NaturalLanguageParser.splitSentences(line)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty })
            } else {
                lines.append(line)
            }
        }
        return lines
    }
}
