import Foundation

/// Shown at the top of an answer when a question sounds like an emergency.
public struct EmergencyNotice: Equatable, Sendable {
    public let message: String
}

/// Helpers for the Ask screen: emergency detection, links to search the web and Reddit,
/// and the prompt for the on-device model. Everything here works offline.
public enum AskAssistant {
    public static let emergencyMessage = "If anyone is in danger or seriously hurt, call 911 now, then get the manager on duty."

    private static let emergencyPhrases = [
        "on fire", "smoke", "bleeding", "unconscious", "not breathing", "chest pain", "seizure", "gun", "weapon",
        "knife", "shooter", "shooting", "threatening", "threatened", "assault", "attacked", "fighting", "fight",
        "gas leak", "tornado warning", "collapsed", "passed out", "overdose", "heart attack", "stroke", "choking",
        "fell from", "head injury", "can't breathe", "cant breathe", "bomb"
    ]

    /// Non-nil when the question mentions an emergency. Never blocks anything.
    public static func emergency(in question: String) -> EmergencyNotice? {
        let q = CoachGuides.normalize(question)
        guard !q.isEmpty else { return nil }
        for phrase in emergencyPhrases {
            let pattern = "(?<![a-z])" + NSRegularExpression.escapedPattern(for: phrase) + "(?![a-z])"
            if q.range(of: pattern, options: .regularExpression) != nil {
                return EmergencyNotice(message: emergencyMessage)
            }
        }
        return nil
    }

    /// Opens Reddit's own search for r/walmart. Posts there are other people's opinions, not company policy.
    public static func redditSearchURL(_ question: String) -> URL? {
        var c = URLComponents(string: "https://www.reddit.com/r/walmart/search/")
        c?.queryItems = [URLQueryItem(name: "q", value: question.trimmingCharacters(in: .whitespacesAndNewlines)),
                         URLQueryItem(name: "restrict_sr", value: "1")]
        return c?.url
    }

    public static func webSearchURL(_ question: String) -> URL? {
        var c = URLComponents(string: "https://www.google.com/search")
        c?.queryItems = [URLQueryItem(name: "q", value: question.trimmingCharacters(in: .whitespacesAndNewlines))]
        return c?.url
    }

    public static let redditNote = "Reddit posts are other people's opinions and experiences, not company policy. Don't post names or store details."

    /// The numbered or bulleted steps in a written answer, cleaned up so each can become a task.
    public static func steps(fromAnswer answer: String) -> [String] {
        answer.components(separatedBy: .newlines).compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let range = trimmed.range(of: #"^(\d{1,2}[.)]|[-•*])\s+"#, options: .regularExpression) else { return nil }
            var step = String(trimmed[range.upperBound...]).trimmingCharacters(in: .whitespaces)
            step = step.replacingOccurrences(of: "**", with: "")
            return step.count >= 4 ? step : nil
        }
    }

    // MARK: On-device model prompt

    /// Instructions for Apple's on-device model. It knows nothing about this company's internal policies,
    /// so it's told never to invent them.
    public static func instructions(role: UserRole?) -> String {
        let who = role.map { "a \($0.title.lowercased())" + ($0.seesWholeStore ? "" : " (\($0.areasSummary))") } ?? "a retail store leader"
        return """
        You help \(who) in a large retail store with practical leadership and day-to-day store situations. \
        Answer in plain text: one short sentence, then at most 6 short numbered steps. \
        Safety and compliance always come first. If anyone could be in danger, start with: call 911. \
        Use the reference guides when they apply. You don't know this company's internal policies, codes, phone numbers \
        or systems, so never make them up; when a store procedure matters, say to follow the store's procedure or check \
        with the store manager, asset protection or the People Lead. Don't ask for or repeat personal, medical or \
        disciplinary details about anyone. Never suggest confronting or chasing a shoplifter.
        """
    }

    /// The prompt: the question plus the best-matching guides (and the person's own store steps), kept short
    /// enough for the on-device model's context window.
    public static func prompt(question: String, guides: [CoachGuide], storeSteps: [String: String] = [:], budget: Int = 2_400) -> String {
        var reference = ""
        for guide in guides.prefix(3) {
            var block = "\n# \(guide.title)\n\(guide.summary)\n" + guide.steps.map { "- \($0)" }.joined(separator: "\n")
            if let check = guide.checkWith { block += "\nCheck with: \(check)" }
            if let own = storeSteps[guide.id]?.trimmingCharacters(in: .whitespacesAndNewlines), !own.isEmpty {
                block += "\nThis store's own steps (from the user): \(own)"
            }
            if reference.count + block.count > budget { break }
            reference += block + "\n"
        }
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        if reference.isEmpty {
            return "Question: \(q)\n\nNo reference guide matched. Give general, practical advice and say what to check with the store manager."
        }
        return "Question: \(q)\n\nReference guides:\(reference)\nAnswer the question using these guides where they fit."
    }
}
