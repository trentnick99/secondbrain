import Foundation

/// A gentle, non-blocking nudge shown when text looks like it holds information that belongs in an
/// approved company system rather than a personal organizer.
public struct SensitivityNotice: Equatable, Sendable {
    public enum Kind: String, Sendable { case disciplinary, medical, attendance, assetProtection, credentials, personal }

    public let kind: Kind
    public let message: String
}

/// Spots disciplinary, medical, attendance, asset-protection, credential and personal-identifier details.
/// It never blocks saving or changes the text; it only suggests keeping the note to the task itself.
public enum SensitiveContent {
    private static let rules: [(SensitivityNotice.Kind, [String], String)] = [
        (.credentials, ["password", "passwords", "passcode", "pin number", "login info", "username and password", "my win", "win number", "win #"],
         "Looks like a password or ID. Don't keep credentials or associate ID numbers in Coach Spark."),
        (.disciplinary, ["write up", "write-up", "writeup", "written up", "disciplinary", "discipline", "1st written",
                         "2nd written", "3rd written", "first written", "second written", "third written",
                         "final written", "documented coaching", "coaching for", "termination", "terminate",
                         "terminated", "fire him", "fire her", "let go", "final warning", "being coached"],
         "Looks like disciplinary detail. Keep just the task here (“talk with Sam today”) and record the details in the approved system."),
        (.attendance, ["ncns", "no call no show", "no-call no-show", "attendance points", "attendance point",
                       "attendance occurrence", "attendance occurrences"],
         "Attendance records belong in the timekeeping system. Here, note only what you need to do — like “find coverage for Stock 2”."),
        (.medical, ["fmla", "ada accommodation", "accommodation request", "medical", "diagnosis", "diagnosed", "surgery",
                    "doctor's note", "doctors note", "pregnant", "pregnancy", "prescription", "medication", "therapy",
                    "mental health", "disability", "workers comp", "workers' comp", "loa", "leave of absence"],
         "Looks like medical or leave detail. Keep health and leave information out of Coach Spark — note only the task."),
        (.assetProtection, ["internal theft", "orc case", "case file", "apprehension", "apprehended", "shoplifter",
                            "ethics complaint", "ethics case", "theft investigation", "ap investigation"],
         "Looks like an asset-protection or investigation detail. Those stay with AP and the approved systems."),
        (.personal, ["ssn", "social security", "date of birth", "dob", "home address", "pay rate", "salary",
                     "bank account", "driver's license", "drivers license"],
         "Looks like personal information. Don't store protected personal details in Coach Spark.")
    ]

    /// The first matching notice, or nil when the text looks fine.
    public static func check(_ text: String) -> SensitivityNotice? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return nil }
        // Short acronyms only count in capitals: "DA" (disciplinary action), "ADA".
        let full = NSRange(location: 0, length: (trimmed as NSString).length)
        if Lexicon.regex(#"(?<![\w])DAs?(?![\w])"#, caseInsensitive: false)?.firstMatch(in: trimmed, options: [], range: full) != nil {
            return notice(.disciplinary)
        }
        if Lexicon.regex(#"(?<![\w])ADA(?![\w])"#, caseInsensitive: false)?.firstMatch(in: trimmed, options: [], range: full) != nil {
            return notice(.medical)
        }
        for (kind, words, message) in rules where Lexicon.containsAny(trimmed, words) {
            return SensitivityNotice(kind: kind, message: message)
        }
        return nil
    }

    private static func notice(_ kind: SensitivityNotice.Kind) -> SensitivityNotice? {
        rules.first { $0.0 == kind }.map { SensitivityNotice(kind: kind, message: $0.2) }
    }
}
