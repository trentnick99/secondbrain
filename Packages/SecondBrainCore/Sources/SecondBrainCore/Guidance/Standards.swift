import Foundation

/// One line in a standards list: a name and, if it has one, a value. "Ice cream" · "-10°F or colder",
/// or just a step: "Pull anything past its date."
public struct StandardItem: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var value: String

    public init(id: UUID = UUID(), name: String, value: String = "") {
        self.id = id
        self.name = name
        self.value = value
    }

    public var isEmpty: Bool { name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}

/// A reference list the person keeps for their store: temperatures for certain items, a quality
/// standard, or the steps of a process. Kept on the phone. Nothing here is generated.
public struct StandardList: Codable, Hashable, Identifiable, Sendable {
    public enum Kind: String, CaseIterable, Codable, Sendable {
        case temperatures, quality, process

        public var title: String {
            switch self {
            case .temperatures: return "Temperatures"
            case .quality: return "Quality standards"
            case .process: return "Processes"
            }
        }

        /// What one list of this kind is called: "New temperature list".
        public var singular: String {
            switch self {
            case .temperatures: return "temperature list"
            case .quality: return "quality standard"
            case .process: return "process"
            }
        }

        public var systemImage: String {
            switch self {
            case .temperatures: return "thermometer.medium"
            case .quality: return "checkmark.seal"
            case .process: return "list.number"
            }
        }

        /// Process lists are numbered steps; the others are name and value pairs.
        public var hasValues: Bool { self != .process }

        public var namePlaceholder: String {
            switch self {
            case .temperatures: return "Item, e.g. Ice cream"
            case .quality: return "What to check, e.g. Bananas"
            case .process: return "Step"
            }
        }

        public var valuePlaceholder: String {
            switch self {
            case .temperatures: return "Temperature"
            case .quality: return "Standard"
            case .process: return ""
            }
        }
    }

    public var id: UUID
    public var title: String
    public var kind: Kind
    public var items: [StandardItem]
    /// Where the list comes from or who to check with, e.g. "Posted on the cooler door".
    public var note: String

    public init(id: UUID = UUID(), title: String = "", kind: Kind = .temperatures,
                items: [StandardItem] = [], note: String = "") {
        self.id = id
        self.title = title
        self.kind = kind
        self.items = items
        self.note = note
    }

    /// A guide the person wrote in an earlier version becomes a process list with the same steps.
    public init(migrating guide: CustomGuide) {
        self.init(id: guide.id,
                  title: guide.title.trimmingCharacters(in: .whitespaces),
                  kind: .process,
                  items: guide.steps.map { StandardItem(name: $0.trimmingCharacters(in: .whitespacesAndNewlines)) }
                      .filter { !$0.isEmpty },
                  note: guide.checkWith.trimmingCharacters(in: .whitespaces))
    }

    public var isValid: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty && items.contains { !$0.isEmpty }
    }

    /// Trimmed title and lines, with empty lines dropped. What gets saved.
    public var cleaned: StandardList {
        var list = self
        list.title = title.trimmingCharacters(in: .whitespaces)
        list.note = note.trimmingCharacters(in: .whitespaces)
        list.items = items.compactMap { item in
            let name = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return nil }
            let value = kind.hasValues ? item.value.trimmingCharacters(in: .whitespacesAndNewlines) : ""
            return StandardItem(id: item.id, name: name, value: value)
        }
        return list
    }
}

/// A built-in reference list. Every value comes from the public source listed with it.
public struct ReferenceList: Identifiable, Hashable, Sendable {
    public struct Entry: Hashable, Sendable {
        public let name: String
        public let value: String
        public let detail: String?

        public init(_ name: String, _ value: String, _ detail: String? = nil) {
            self.name = name
            self.value = value
            self.detail = detail
        }
    }

    public let id: String
    public let title: String
    public let kind: StandardList.Kind
    public let summary: String
    public let entries: [Entry]
    public let sources: [GuideSource]
}

/// Standards: a reference library of lists, not a question answerer. Built-in food safety
/// temperatures and general quality checks from public sources, the person's own lists, and the
/// store processes (spills, the freezer door, a frozen truck…) as step lists.
public enum Standards {
    public static let disclaimer = "Public food safety rules and general practice, not company policy. Your store's posted standards, logs and your store manager come first."

    private static let foodCode = GuideSource("FDA Food Code", "https://www.fda.gov/FoodCode")
    private static let cooling = GuideSource("FDA: Cooling cooked TCS foods", "https://www.fda.gov/media/181882/download")
    private static let eggs = GuideSource("21 CFR 115.50: refrigeration of shell eggs at retail",
                                          "https://www.ecfr.gov/current/title-21/chapter-I/subchapter-B/part-115/section-115.50")
    private static let freezing = GuideSource("USDA FSIS: Freezing and food safety",
                                              "https://www.fsis.usda.gov/food-safety/safe-food-handling-and-preparation/food-safety-basics/freezing-and-food-safety")

    public static let foodTemperatures = ReferenceList(
        id: "food-temps", title: "Food safety temperatures", kind: .temperatures,
        summary: "Cold, hot and frozen holding temperatures from the FDA Food Code and USDA.",
        entries: [
            .init("Refrigerated food (cold holding)", "41°F or colder", "FDA Food Code"),
            .init("Hot food (hot holding)", "135°F or hotter", "FDA Food Code"),
            .init("Danger zone", "Between 41°F and 135°F", "Bacteria grow fastest here. FDA Food Code"),
            .init("Cooling cooked food", "135°F to 70°F within 2 hours, then to 41°F within 4 more",
                  "6 hours total. FDA Food Code"),
            .init("Shell eggs", "Stored and displayed at 45°F or colder (air temperature)", "21 CFR 115.50"),
            .init("Frozen food", "0°F or colder", "USDA FSIS")
        ],
        sources: [foodCode, cooling, eggs, freezing])

    public static let qualityChecks = ReferenceList(
        id: "quality-checks", title: "Product quality checks", kind: .quality,
        summary: "General checks when working freight or zoning. Your store's standards come first.",
        entries: [
            .init("Rotation", "Oldest date to the front (first in, first out)"),
            .init("Dates", "Pull anything past its date"),
            .init("Packaging", "Pull damaged, leaking, swollen or open packages"),
            .init("Frozen", "Frozen solid. Report anything soft or thawed instead of putting it out"),
            .init("Eggs", "No cracked or leaking eggs on the shelf"),
            .init("Cold product", "Back in the cooler or freezer quickly, not left on the floor")
        ],
        sources: [])

    public static let references: [ReferenceList] = [foodTemperatures, qualityChecks]

    /// Store processes kept from the guides: step lists for the floor and for safety.
    public static let processIDs = [
        "freezer-door", "frozen-truck", "warm-case", "broken-equipment", "freight-behind", "market-walk",
        "spill", "blocked-exit", "injury", "severe-weather", "crowd", "recall", "equipment"
    ]

    public static var processes: [CoachGuide] { processIDs.compactMap { CoachGuides.guide(id: $0) } }

    public static func reference(id: String) -> ReferenceList? { references.first { $0.id == id } }

    /// Lists from guides the person wrote in an earlier version, skipping any already kept.
    public static func migrate(_ guides: [CustomGuide], into lists: [StandardList]) -> [StandardList] {
        let kept = Set(lists.map(\.id))
        return lists + guides.filter { $0.isValid && !kept.contains($0.id) }.map(StandardList.init(migrating:))
    }

    // MARK: Sharing

    /// Plain text to send a team lead: the title, each line, and where it comes from.
    public static func shareText(_ list: StandardList) -> String {
        var lines = [list.title]
        for (index, item) in list.items.enumerated() {
            if list.kind.hasValues {
                lines.append(item.value.isEmpty ? "• \(item.name)" : "• \(item.name): \(item.value)")
            } else {
                lines.append("\(index + 1). \(item.name)")
            }
        }
        if !list.note.isEmpty { lines.append(list.note) }
        return lines.joined(separator: "\n")
    }

    public static func shareText(_ reference: ReferenceList) -> String {
        var lines = [reference.title]
        lines += reference.entries.map { "• \($0.name): \($0.value)" }
        if !reference.sources.isEmpty { lines.append("Sources: " + reference.sources.map(\.title).joined(separator: "; ")) }
        lines.append(disclaimer)
        return lines.joined(separator: "\n")
    }

    public static func shareText(_ guide: CoachGuide) -> String {
        var lines = [guide.title]
        lines += guide.steps.enumerated().map { "\($0.offset + 1). \($0.element)" }
        if let check = guide.checkWith { lines.append("Check with: \(check)") }
        return lines.joined(separator: "\n")
    }

    // MARK: Filter

    /// True when every word typed appears at the start of a word in the text ("temp" finds
    /// "temperature", "egg" finds "eggs"). A plain filter: it never ranks or answers.
    public static func matches(_ query: String, in text: String) -> Bool {
        let words = queryWords(query)
        guard !words.isEmpty else { return true }
        let haystack = Set(CoachGuides.tokens(CoachGuides.normalize(text)))
        return words.allSatisfy { word in
            haystack.contains { $0.hasPrefix(word) || CoachGuides.isWordForm(word, of: $0) }
        }
    }

    public static func searchText(_ list: StandardList) -> String {
        ([list.title, list.kind.title, list.note] + list.items.flatMap { [$0.name, $0.value] }).joined(separator: " ")
    }

    public static func searchText(_ list: ReferenceList) -> String {
        ([list.title, list.kind.title, list.summary] + list.entries.flatMap { [$0.name, $0.value] }).joined(separator: " ")
    }

    public static func searchText(_ guide: CoachGuide) -> String {
        ([guide.title, guide.summary] + guide.keywords + guide.steps).joined(separator: " ")
    }

    /// The lines of a list worth showing under it for a search: the ones that match, or the first few.
    public static func preview(_ lines: [String], for query: String, limit: Int = 3) -> [String] {
        let hits = lines.filter { matches(query, in: $0) }
        return Array((hits.isEmpty ? lines : hits).prefix(limit))
    }

    static func queryWords(_ query: String) -> [String] {
        CoachGuides.tokens(CoachGuides.normalize(query)).filter { !$0.isEmpty && !filterStopWords.contains($0) }
    }

    private static let filterStopWords: Set<String> = [
        "a", "an", "the", "and", "or", "of", "to", "for", "with", "at", "is", "are", "what", "how", "do", "does",
        "should", "my", "our", "i"
    ]
}
