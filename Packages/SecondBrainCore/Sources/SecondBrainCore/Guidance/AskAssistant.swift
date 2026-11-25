import Foundation

/// Shown at the top of an answer when a question sounds like an emergency.
public struct EmergencyNotice: Equatable, Sendable {
    public let message: String
}

/// Helpers for the Ask screen: emergency detection and links to search the web and Reddit.
/// Everything here works offline.
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
}
