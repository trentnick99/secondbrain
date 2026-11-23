import Foundation

/// Result of classifying a task into an Eisenhower quadrant, with human-readable reasons
/// so the suggestion is transparent and easy to override.
public struct EisenhowerClassification: Codable, Equatable, Sendable {
    public enum Confidence: String, Codable, Sendable { case high, medium, low }

    public var quadrant: Quadrant
    public var isUrgent: Bool
    public var isImportant: Bool
    public var urgencyScore: Int
    public var importanceScore: Int
    public var reasons: [String]
    /// Safety / compliance work is pinned to "important" regardless of deadline.
    public var isSafetyLocked: Bool
    public var suggestsDelegation: Bool
    public var confidence: Confidence

    public init(quadrant: Quadrant, isUrgent: Bool, isImportant: Bool, urgencyScore: Int, importanceScore: Int,
                reasons: [String], isSafetyLocked: Bool, suggestsDelegation: Bool, confidence: Confidence) {
        self.quadrant = quadrant
        self.isUrgent = isUrgent
        self.isImportant = isImportant
        self.urgencyScore = urgencyScore
        self.importanceScore = importanceScore
        self.reasons = reasons
        self.isSafetyLocked = isSafetyLocked
        self.suggestsDelegation = suggestsDelegation
        self.confidence = confidence
    }

    public static func manual(_ quadrant: Quadrant) -> EisenhowerClassification {
        EisenhowerClassification(quadrant: quadrant, isUrgent: quadrant.isUrgent, isImportant: quadrant.isImportant,
                                 urgencyScore: 0, importanceScore: 0, reasons: ["Set manually"],
                                 isSafetyLocked: false, suggestsDelegation: quadrant == .delegate, confidence: .high)
    }
}

public struct ClassificationInput: Sendable {
    public var text: String
    public var category: TaskCategory
    public var kind: TaskKind
    public var priority: TaskPriority
    public var dueDate: Date?
    public var hasDueTime: Bool
    public var now: Date
    public var calendar: Calendar

    public init(text: String, category: TaskCategory, kind: TaskKind, priority: TaskPriority,
                dueDate: Date?, hasDueTime: Bool = false, now: Date, calendar: Calendar) {
        self.text = text
        self.category = category
        self.kind = kind
        self.priority = priority
        self.dueDate = dueDate
        self.hasDueTime = hasDueTime
        self.now = now
        self.calendar = calendar
    }
}

/// Rule-based, on-device Eisenhower classifier. No network or AI service required.
///
/// Principles enforced:
/// * Urgency comes from time pressure and active hazards; importance from impact and responsibility.
/// * An approaching deadline raises urgency only — never importance.
/// * Safety and compliance responsibilities are always important, even when far off.
public enum EisenhowerClassifier {
    static let urgencyThreshold = 2
    static let importanceThreshold = 2

    public static func classify(_ input: ClassificationInput) -> EisenhowerClassification {
        let text = " " + input.text.lowercased() + " "
        var reasons: [String] = []
        var urgency = 0
        var importance = 1   // neutral baseline
        var signals = 0

        // MARK: Urgency — time pressure and active hazards
        if let due = input.dueDate {
            let math = DateMath(calendar: input.calendar)
            let days = math.daysBetween(input.now, due)
            let overdue = input.hasDueTime ? due < input.now : days < 0
            if overdue {
                urgency += 3; reasons.append("Urgent: overdue")
            } else if days == 0 {
                urgency += 3; reasons.append("Urgent: due today")
            } else if days == 1 {
                urgency += 2; reasons.append("Urgent: due tomorrow")
            } else if days == 2 {
                urgency += 1
            }
            signals += 1
        }
        if Lexicon.containsAny(text, Lexicon.hazardWords) {
            urgency += 3; importance += 2
            reasons.append("Active hazard — handle immediately")
            signals += 1
        }
        if Lexicon.containsAny(text, Lexicon.urgentWords) {
            urgency += 2; reasons.append("Urgent wording")
            signals += 1
        }
        switch input.priority {
        case .critical: urgency += 2; importance += 2; reasons.append("Critical priority")
        case .high: urgency += 1; importance += 1
        case .low: importance -= 1
        case .normal: break
        }

        // MARK: Importance — impact, responsibility, commitments
        var safetyLocked = false
        if input.category.isSafetyCritical || Lexicon.containsAny(text, Lexicon.safetyWords) || Lexicon.containsAny(text, Lexicon.complianceWords) {
            safetyLocked = true
            importance = max(importance + 2, 3)
            reasons.append("Important: safety & compliance are never unimportant")
            signals += 1
        }
        if input.kind == .followUp {
            importance += 1; reasons.append("Important: a commitment to someone")
            signals += 1
        }
        switch input.category {
        case .people, .development:
            importance += 1; reasons.append("Important: people & development")
            signals += 1
        case .operations, .freight, .customer, .meeting:
            importance += 1; signals += 1
        case .admin where Lexicon.containsAny(text, Lexicon.performanceWords):
            importance += 1; reasons.append("Important: performance results")
            signals += 1
        default:
            break
        }
        if input.category != .admin && Lexicon.containsAny(text, Lexicon.performanceWords) {
            importance += 1; signals += 1
        }
        if Lexicon.containsAny(text, Lexicon.accountabilityWords) {
            importance += 1; signals += 1
        }
        if Lexicon.containsAny(text, Lexicon.importantWords) {
            importance += 2; reasons.append("Marked important")
            signals += 1
        }
        if Lexicon.containsAny(text, Lexicon.leadershipWords) {
            importance += 2; reasons.append("Important: assigned by leadership")
            signals += 1
        }
        var routine = false
        if Lexicon.containsAny(text, Lexicon.routineWords) {
            importance -= 1; routine = true
            signals += 1
        }
        if Lexicon.containsAny(text, Lexicon.lowValueWords) {
            importance -= 2; reasons.append("Optional / low-value wording")
            signals += 1
        }

        var isImportant = importance >= importanceThreshold
        if safetyLocked { isImportant = true }
        let isUrgent = urgency >= urgencyThreshold
        let quadrant = Quadrant(urgent: isUrgent, important: isImportant)

        let suggestsDelegation = quadrant == .delegate || (routine && !safetyLocked && quadrant != .doFirst)
        switch quadrant {
        case .delegate:
            reasons.append("Routine and time-sensitive — consider delegating, then confirm the hand-off")
        case .eliminate:
            reasons.append("No urgency or importance signals — review whether it's still needed")
        case .schedule where !isUrgent:
            if input.dueDate == nil { reasons.append("Not time-sensitive — schedule it") }
        default:
            break
        }

        let confidence: EisenhowerClassification.Confidence
        if safetyLocked || signals >= 3 { confidence = .high }
        else if signals >= 1 { confidence = .medium }
        else { confidence = .low }

        return EisenhowerClassification(
            quadrant: quadrant, isUrgent: isUrgent, isImportant: isImportant,
            urgencyScore: urgency, importanceScore: importance,
            reasons: dedupe(reasons), isSafetyLocked: safetyLocked,
            suggestsDelegation: suggestsDelegation, confidence: confidence
        )
    }

    /// Suggests a quadrant change when time has made a task more urgent (e.g. Q2 → Q1 the day before
    /// it's due). Suggestions are never applied automatically — the UI asks for confirmation.
    public static func urgencyEscalation(current: Quadrant, dueDate: Date?, hasDueTime: Bool, isSafetyCritical: Bool,
                                         now: Date, calendar: Calendar) -> Quadrant? {
        guard let due = dueDate, !current.isUrgent else { return nil }
        let math = DateMath(calendar: calendar)
        let days = math.daysBetween(now, due)
        let overdue = hasDueTime ? due < now : days < 0
        guard overdue || days <= 1 else { return nil }
        let important = current.isImportant || isSafetyCritical
        return Quadrant(urgent: true, important: important)
    }

    private static func dedupe(_ items: [String]) -> [String] {
        var seen = Set<String>()
        return items.filter { seen.insert($0).inserted }
    }
}
