import Foundation
import SecondBrainCore
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Optional AI layer. The deterministic, on-device `BriefingBuilder` always produces the briefing;
/// when the person turns on "Apple Intelligence briefing" and the device supports Apple's on-device
/// foundation model (iOS 26+), the text is rephrased more naturally. No account, subscription or
/// network service is involved, and nothing is changed without confirmation.
enum BriefingAssistant {
    static var isAppleIntelligenceAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return SystemLanguageModel.default.isAvailable
        }
        #endif
        return false
    }

    static var availabilityText: String {
        if isAppleIntelligenceAvailable { return "Available on this iPhone" }
        return "Requires iOS 26 and an Apple Intelligence–capable iPhone with Apple Intelligence turned on."
    }

    /// Returns the briefing, optionally polished by the on-device model. Always falls back to the plain text.
    static func briefing(for agenda: DayAgenda, now: Date = Date()) async -> String {
        let plain = BriefingBuilder.dailyBriefing(agenda, now: now, calendar: .current)
        guard AppSettings.appleIntelligence, isAppleIntelligenceAvailable else { return plain }
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            do {
                let session = LanguageModelSession(instructions: """
                You rewrite a retail store coach's daily task briefing. Keep every task, name, count and time exactly. \
                Do not add tasks, people, dates or advice that are not in the input. Use 2–4 short, direct sentences.
                """)
                let response = try await session.respond(to: plain)
                let text = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
                return text.isEmpty ? plain : text
            } catch {
                return plain
            }
        }
        #endif
        return plain
    }
}
