import Foundation

/// A piece of text found in a photo, with its box in normalized coordinates (0–1, origin at the
/// bottom-left, as Apple's Vision framework reports them).
public struct TextBox: Equatable, Sendable {
    public let text: String
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public init(text: String, x: Double, y: Double, width: Double, height: Double) {
        self.text = text
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    var midY: Double { y + height / 2 }
}

/// Turns text recognized from photos, and spoken walk notes, into text that Import notes can read.
public enum RecognizedText {
    /// Lines in reading order: top to bottom, and left to right within a line.
    public static func lines(from boxes: [TextBox]) -> [String] {
        var rows: [[TextBox]] = []
        for box in boxes.sorted(by: { $0.midY > $1.midY }) where !box.text.trimmingCharacters(in: .whitespaces).isEmpty {
            if let index = rows.firstIndex(where: { row -> Bool in
                let rowMid: Double = averageMidY(row)
                let smallest: Double = row.map(\.height).min() ?? box.height
                let tolerance: Double = 0.5 * min(box.height, smallest)
                return abs(rowMid - box.midY) <= tolerance
            }) {
                rows[index].append(box)
            } else {
                rows.append([box])
            }
        }
        let ordered = rows.sorted { averageMidY($0) > averageMidY($1) }
        return ordered.map { row -> String in
            let leftToRight = row.sorted { $0.x < $1.x }
            let words = leftToRight.map { $0.text.trimmingCharacters(in: .whitespaces) }
            return words.joined(separator: " ")
        }
    }

    private static func averageMidY(_ row: [TextBox]) -> Double {
        guard !row.isEmpty else { return 0 }
        let total: Double = row.reduce(0) { $0 + $1.midY }
        return total / Double(row.count)
    }

    /// Recognized text ready for Import notes, with bullet and checkbox marks turned into "- ".
    public static func text(from boxes: [TextBox]) -> String {
        lines(from: boxes).map(normalizeBullet).joined(separator: "\n")
    }

    static func normalizeBullet(_ line: String) -> String {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        for mark in ["•", "◦", "▪", "‣", "●", "○", "■", "□", "☐", "☑", "✓", "✔", "*", "–", "—", "·"] where trimmed.hasPrefix(mark) {
            return "- " + trimmed.dropFirst(mark.count).trimmingCharacters(in: .whitespaces)
        }
        // Handwritten or printed bullets are often read as a lone "o" or "e".
        if trimmed.range(of: #"^[oe]\s+[A-Z]"#, options: .regularExpression) != nil {
            return "- " + trimmed.dropFirst(2).trimmingCharacters(in: .whitespaces)
        }
        return trimmed
    }

    // MARK: Walk notes

    private static let fillers = ["okay so ", "ok so ", "okay ", "ok ", "um ", "uh ", "so ", "and then ", "and ", "also ", "next item ", "next "]

    /// One item per sentence (or per pause the recognizer marked with punctuation), with filler words removed.
    public static func walkNoteItems(from transcript: String) -> [String] {
        let pieces = transcript
            .replacingOccurrences(of: #"(?i)\b(next item|new item)\b[,.]?"#, with: ".", options: .regularExpression)
            .components(separatedBy: .newlines)
            .flatMap { $0.replacingOccurrences(of: #"([.!?;])\s+"#, with: "$1\n", options: .regularExpression).components(separatedBy: "\n") }
        return pieces.compactMap { piece in
            var item = piece.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ".;,")))
            var changed = true
            while changed {
                changed = false
                for filler in fillers where item.lowercased().hasPrefix(filler) {
                    item = String(item.dropFirst(filler.count)).trimmingCharacters(in: .whitespaces)
                    changed = true
                }
            }
            guard item.count >= 3 else { return nil }
            return item.prefix(1).uppercased() + item.dropFirst()
        }
    }

    /// Items as bullet lines, so Import notes keeps every one of them.
    public static func bulleted(_ items: [String]) -> String {
        items.map { "- " + $0 }.joined(separator: "\n")
    }
}
