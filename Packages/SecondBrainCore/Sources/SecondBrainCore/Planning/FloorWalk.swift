import Foundation

/// One thing to look at on a floor walk, with how to phrase the fix as a task.
public struct WalkCheck: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let title: String
    public let fix: String
    public let isSafety: Bool

    public init(_ id: String, _ title: String, fix: String, safety: Bool = false) {
        self.id = id
        self.title = title
        self.fix = fix
        self.isSafety = safety
    }
}

/// The checks for one area, safety first.
public struct WalkSection: Identifiable, Hashable, Sendable {
    public let area: String
    public let checks: [WalkCheck]
    public var id: String { area }

    /// Whether the area should be saved on tasks (not the generic "Sales floor").
    public var isRealArea: Bool { area != FloorWalkChecklist.genericArea && area != FloorWalkChecklist.wholeStore }
}

/// A walk in progress: what's been checked, and notes on what needs work. Kept on the phone so
/// leaving the screen doesn't lose it.
public struct FloorWalkState: Codable, Equatable, Sendable {
    public enum Mark: String, Codable, Sendable { case ok, needsWork }

    public var startedAt: Date
    public var marks: [String: Mark]
    public var notes: [String: String]

    public init(startedAt: Date = Date()) {
        self.startedAt = startedAt
        marks = [:]
        notes = [:]
    }

    public static func key(_ area: String, _ check: WalkCheck) -> String { "\(area)|\(check.id)" }

    public func mark(_ area: String, _ check: WalkCheck) -> Mark? { marks[Self.key(area, check)] }

    public mutating func set(_ mark: Mark?, _ area: String, _ check: WalkCheck) {
        marks[Self.key(area, check)] = mark
        if mark != .needsWork { notes[Self.key(area, check)] = nil }
    }
}

/// Something that needs work after a walk, ready to become a task.
public struct WalkFinding: Identifiable, Hashable, Sendable {
    public let area: String
    public let check: WalkCheck
    public let note: String
    public let fileUnderArea: Bool

    public var id: String { FloorWalkState.key(area, check) }

    /// The task title: the note if there is one, otherwise the check's fix phrasing.
    public var title: String {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return fileUnderArea ? "\(check.fix) (\(StoreAreas.shortName(area)))" : check.fix
    }
}

public enum FloorWalkChecklist {
    public static let genericArea = "Sales floor"
    public static let wholeStore = "Whole store"

    public static let common: [WalkCheck] = [
        WalkCheck("exits", "Exits and fire equipment clear", fix: "Clear the exits and fire equipment", safety: true),
        WalkCheck("spills", "No spills or trip hazards", fix: "Clean up spills and trip hazards", safety: true),
        WalkCheck("equipment", "Ladders, carts and pallet jacks put away", fix: "Put away ladders, carts and pallet jacks", safety: true),
        WalkCheck("aisles", "Pallets and freight off the main aisles", fix: "Move pallets and freight off the main aisles", safety: true),
        WalkCheck("holes", "Holes filled or flagged", fix: "Fill or flag the holes"),
        WalkCheck("features", "Features and endcaps full and signed", fix: "Fill and sign the features and endcaps"),
        WalkCheck("signs", "Price signs and labels right", fix: "Fix price signs and labels"),
        WalkCheck("mods", "Mods and price changes done", fix: "Finish mods and price changes"),
        WalkCheck("zoned", "Shelves zoned and faced", fix: "Zone and face the shelves"),
        WalkCheck("clean", "Clean and customer-ready (no empty boxes or trash)", fix: "Clear empty boxes and trash")
    ]

    static let areaChecks: [String: [WalkCheck]] = [
        "Fresh": [
            WalkCheck("fresh-dates", "Out-of-date product pulled", fix: "Pull out-of-date product", safety: true),
            WalkCheck("fresh-rotate", "Produce and wet wall rotated, culls pulled", fix: "Rotate produce and pull culls"),
            WalkCheck("fresh-cases", "Cooler and freezer doors closed, cases clean", fix: "Close and clean the cooler and freezer cases")
        ],
        "Food": [
            WalkCheck("food-dates", "Out-of-date product pulled", fix: "Pull out-of-date product", safety: true),
            WalkCheck("food-doors", "Dairy and frozen doors closed, no frost buildup", fix: "Check dairy and frozen doors for frost")
        ],
        "Stocking": [
            WalkCheck("stock-top", "Top stock safe: heavy items low, nothing hanging over", fix: "Make the top stock safe", safety: true),
            WalkCheck("stock-backroom", "Backroom aisles and exits clear", fix: "Clear the backroom aisles and exits", safety: true),
            WalkCheck("stock-staged", "Freight staged by aisle", fix: "Stage freight by aisle")
        ],
        "Overnight": [
            WalkCheck("on-top", "Top stock safe: heavy items low, nothing hanging over", fix: "Make the top stock safe", safety: true),
            WalkCheck("on-backroom", "Backroom aisles and exits clear", fix: "Clear the backroom aisles and exits", safety: true),
            WalkCheck("on-worked", "Freight worked and cardboard cleared", fix: "Finish freight and clear the cardboard")
        ],
        "Front End": [
            WalkCheck("fe-entrances", "Entrances clear, mats flat", fix: "Clear the entrances and flatten the mats", safety: true),
            WalkCheck("fe-registers", "Registers and self-checkouts stocked", fix: "Stock the registers and self-checkouts"),
            WalkCheck("fe-carts", "Carts and baskets ready", fix: "Bring in carts and baskets")
        ],
        "Fashion": [
            WalkCheck("fa-fitting", "Fitting rooms cleared", fix: "Clear the fitting rooms"),
            WalkCheck("fa-sizes", "Racks sized and in order", fix: "Size the racks")
        ],
        "Digital (OPD)": [
            WalkCheck("opd-pickup", "Pickup area clean and staged", fix: "Clean and stage the pickup area"),
            WalkCheck("opd-totes", "Totes and carts put away", fix: "Put away totes and carts")
        ],
        "Asset Protection": [
            WalkCheck("ap-entrances", "Entrances and exits clear", fix: "Clear the entrances and exits", safety: true)
        ],
        "Auto Care Center (ACC)": [
            WalkCheck("acc-bays", "Bays clean, tools put away", fix: "Clean the bays and put tools away", safety: true),
            WalkCheck("acc-waiting", "Waiting area clean", fix: "Clean the waiting area")
        ]
    ]

    /// One section per area the person covers (or the whole store for a store manager).
    public static func sections(for role: UserRole?) -> [WalkSection] {
        guard let role else { return [WalkSection(area: genericArea, checks: common)] }
        if role.seesWholeStore { return [WalkSection(area: wholeStore, checks: common)] }
        let areas = role.areas.isEmpty ? [genericArea] : role.areas
        return areas.map { area in
            let extra = areaChecks[area] ?? []
            let safety = common.filter(\.isSafety) + extra.filter(\.isSafety)
            let other = common.filter { !$0.isSafety } + extra.filter { !$0.isSafety }
            return WalkSection(area: area, checks: safety + other)
        }
    }

    public static func checkCount(_ sections: [WalkSection]) -> Int { sections.reduce(0) { $0 + $1.checks.count } }

    public static func markedCount(_ state: FloorWalkState, _ sections: [WalkSection]) -> Int {
        sections.reduce(0) { total, section in total + section.checks.filter { state.mark(section.area, $0) != nil }.count }
    }

    /// What needs work, safety first.
    public static func findings(_ state: FloorWalkState, _ sections: [WalkSection]) -> [WalkFinding] {
        let all = sections.flatMap { section in
            section.checks.compactMap { check -> WalkFinding? in
                guard state.mark(section.area, check) == .needsWork else { return nil }
                return WalkFinding(area: section.area, check: check,
                                   note: state.notes[FloorWalkState.key(section.area, check)] ?? "",
                                   fileUnderArea: section.isRealArea)
            }
        }
        return all.filter(\.check.isSafety) + all.filter { !$0.check.isSafety }
    }

    /// A short record of the walk for a note.
    public static func summary(_ state: FloorWalkState, _ sections: [WalkSection], calendar: Calendar = .current) -> String {
        let findings = findings(state, sections)
        let ok = sections.reduce(0) { total, section in total + section.checks.filter { state.mark(section.area, $0) == .ok }.count }
        var lines = ["Floor walk: \(sections.map(\.area).joined(separator: ", "))",
                     "\(ok) OK · \(findings.count) need work · \(checkCount(sections) - markedCount(state, sections)) not checked"]
        if !findings.isEmpty {
            lines.append("")
            lines.append("Needs work:")
            lines += findings.map { "- \($0.title)" + ($0.check.isSafety ? " (safety)" : "") }
        }
        return lines.joined(separator: "\n")
    }
}
