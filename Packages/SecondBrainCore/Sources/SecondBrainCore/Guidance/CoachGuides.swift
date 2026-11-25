import Foundation

/// A public source behind a guide. Only official, public pages are listed.
public struct GuideSource: Hashable, Sendable {
    public let title: String
    public let url: String

    public init(_ title: String, _ url: String) {
        self.title = title
        self.url = url
    }
}

/// A short, practical "what do I do if…" guide for store leaders.
///
/// Guides hold general leadership and safety practice plus facts from public sources. They never
/// invent company procedures: where a store procedure matters, they say to follow it and who to ask.
public struct CoachGuide: Identifiable, Hashable, Sendable {
    public enum Category: String, CaseIterable, Codable, Sendable {
        case safety, people, operations, customers, ethics

        public var title: String {
            switch self {
            case .safety: return "Safety"
            case .people: return "Leading people"
            case .operations: return "Running the floor"
            case .customers: return "Customers"
            case .ethics: return "Ethics & conduct"
            }
        }

        public var systemImage: String {
            switch self {
            case .safety: return "shield.lefthalf.filled"
            case .people: return "person.2"
            case .operations: return "shippingbox"
            case .customers: return "cart"
            case .ethics: return "checkmark.seal"
            }
        }
    }

    public let id: String
    public let title: String
    public let category: Category
    public let summary: String
    public let steps: [String]
    /// Who to involve or which store procedure to follow. Shown on every guide that needs it.
    public let checkWith: String?
    public let keywords: [String]
    public let sources: [GuideSource]

    public var isSafety: Bool { category == .safety }

    public init(id: String, title: String, category: Category, summary: String, steps: [String], checkWith: String?,
                keywords: [String], sources: [GuideSource]) {
        self.id = id
        self.title = title
        self.category = category
        self.summary = summary
        self.steps = steps
        self.checkWith = checkWith
        self.keywords = keywords
        self.sources = sources
    }
}

/// A guide written in an earlier version of the app. Kept only so Standards can move it into a
/// process list the first time it opens (see `Standards.migrate`).
public struct CustomGuide: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var title: String
    public var category: CoachGuide.Category
    public var steps: [String]
    public var checkWith: String
    public var extraKeywords: String

    public init(id: UUID = UUID(), title: String = "", category: CoachGuide.Category = .operations,
                steps: [String] = [], checkWith: String = "", extraKeywords: String = "") {
        self.id = id
        self.title = title
        self.category = category
        self.steps = steps
        self.checkWith = checkWith
        self.extraKeywords = extraKeywords
    }

    public var isValid: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty && steps.contains { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }
}

public enum CoachGuides {
    public static let disclaimer = "General guidance, not company policy. Your store's procedures and your store manager come first. In an emergency, call 911."

    private static let osha = GuideSource("OSHA", "https://www.osha.gov")
    private static let exitRoutes = GuideSource("OSHA: exit routes (1910.37)", "https://www.osha.gov/laws-regs/regulations/standardnumber/1910/1910.37")
    private static let forklifts = GuideSource("OSHA: powered industrial trucks (1910.178)", "https://www.osha.gov/laws-regs/regulations/standardnumber/1910/1910.178")
    private static let crowd = GuideSource("OSHA: Crowd Management Safety Guidelines for Retailers", "https://www.osha.gov/sites/default/files/publications/Crowd_Control.pdf")
    private static let weather = GuideSource("National Weather Service", "https://www.weather.gov")
    private static let fdaRecalls = GuideSource("FDA recalls", "https://www.fda.gov/safety/recalls-market-withdrawals-safety-alerts")
    private static let fsisRecalls = GuideSource("USDA FSIS recalls (meat, poultry, eggs)", "https://www.fsis.usda.gov/recalls")
    private static let cpscRecalls = GuideSource("CPSC product recalls", "https://www.cpsc.gov/Recalls")

    public static let all: [CoachGuide] = [
        // MARK: Safety
        CoachGuide(
            id: "spill", title: "Spill or slip hazard", category: .safety,
            summary: "Guard it, clean it, then fix what caused it.",
            steps: [
                "Stay with the spill or have someone guard it so nobody walks through it.",
                "Put out a wet-floor sign and get the right cleanup supplies.",
                "Clean it fully, then check the cause: a leaking product, a cooler, the roof.",
                "Pull damaged product and handle it per your store's claims or damages process.",
                "Report it per your store's procedure if anyone slipped or was hurt."
            ],
            checkWith: "Use your store's spill cleanup supplies and procedure.",
            keywords: ["spill", "slip", "wet floor", "leak", "leaking", "broken jar", "trip", "fall hazard"],
            sources: [osha]),
        CoachGuide(
            id: "blocked-exit", title: "Blocked exit or aisle", category: .safety,
            summary: "Exit routes must stay clear at all times, even for a minute.",
            steps: [
                "Clear the exit or aisle right away: pallets, carts, freight, displays.",
                "Walk the other exits and fire equipment (extinguishers, pull stations, panels) while you're at it.",
                "Find out why it was blocked and fix the cause, like staging space or where freight lands.",
                "Tell your team leads that exits stay clear during every freight push, including Black Friday."
            ],
            checkWith: nil,
            keywords: ["fire exit", "exit", "blocked", "egress", "aisle blocked", "action alley", "fire extinguisher", "fire panel"],
            sources: [exitRoutes]),
        CoachGuide(
            id: "injury", title: "Someone is hurt", category: .safety,
            summary: "Get help first, keep the area safe, then report.",
            steps: [
                "If it's serious (head injury, heavy bleeding, not breathing, chest pain), call 911 now.",
                "Get the manager on duty and the first aid kit or AED. Don't move someone with a possible head, neck or back injury unless they're in danger.",
                "Keep the area safe and keep a crowd from forming.",
                "Report it the same shift using your store's incident process.",
                "Don't discuss fault, and don't record medical details in Coach Spark."
            ],
            checkWith: "Follow your store's incident reporting process and involve the manager on duty.",
            keywords: ["hurt", "injured", "injury", "accident", "cut", "bleeding", "fell", "fall", "first aid", "aed", "customer fell", "associate hurt"],
            sources: [osha]),
        CoachGuide(
            id: "severe-weather", title: "Severe weather warning", category: .safety,
            summary: "Follow the store's emergency plan and the manager on duty.",
            steps: [
                "Check the active alert for your area at weather.gov.",
                "For a tornado warning, move customers and associates to the store's designated shelter areas.",
                "Pull associates in from the lot, the garden center and cart runs.",
                "Follow the store's emergency plan and the manager on duty. Don't improvise.",
                "Afterward, check the building, lot and freight for damage before you reopen areas."
            ],
            checkWith: "Your store's emergency plan and the manager on duty.",
            keywords: ["tornado", "storm", "weather", "hurricane", "snow", "ice", "winter storm", "lightning", "flood", "shelter"],
            sources: [weather]),
        CoachGuide(
            id: "crowd", title: "Big crowds for Black Friday or a launch", category: .safety,
            summary: "For Black Friday and launches: plan, set up early, control entry.",
            steps: [
                "Plan ahead: trained security or police on site when large crowds are expected, plus a staffing plan with a spot for each associate.",
                "Set up barricades or rope lines well before customers arrive, not starting right at the entrance.",
                "Manage entry at every entrance, including the ones you're not using, and use announcements to keep people informed.",
                "Stop letting people in once the store reaches maximum occupancy.",
                "Keep exits clear, and in an emergency follow first responders' instructions."
            ],
            checkWith: "Your store's event plan and the manager on duty.",
            keywords: ["black friday", "crowd", "doorbuster", "line", "lines", "event", "launch", "rush", "grand opening", "occupancy"],
            sources: [crowd]),
        CoachGuide(
            id: "recall", title: "Recalled product on the shelf", category: .safety,
            summary: "Pull it now, hold it securely, then follow the recall process.",
            steps: [
                "Pull every unit from the shelf, features, clearance and the backroom.",
                "Hold it in a secure spot away from anything that's for sale.",
                "Check online orders, picking locations and returns for the same item.",
                "Follow your store's recall and claims process, and tell your team leads what to look for.",
                "Check the official recall notice for the exact lot numbers, sizes and dates."
            ],
            checkWith: "Your store's recall process. Use the official notice for exact lots and dates.",
            keywords: ["recall", "recalled", "withdrawal", "pull product", "hold", "contaminated", "listeria", "salmonella"],
            sources: [fdaRecalls, fsisRecalls, cpscRecalls]),
        CoachGuide(
            id: "equipment", title: "Pallet jacks, ladders and equipment", category: .safety,
            summary: "Only trained, authorized associates use powered equipment.",
            steps: [
                "Make sure only associates trained and authorized for the equipment use it.",
                "Check equipment before use, and tag out anything damaged.",
                "Use ladders, not shelves or carts, to reach high.",
                "Keep loads stable and within limits, and never ride or race equipment.",
                "Coach right away when you see unsafe use. Safety isn't optional."
            ],
            checkWith: "Your store's equipment training and authorization records.",
            keywords: ["pallet jack", "electric pallet jack", "forklift", "ladder", "equipment", "reach truck", "cherry picker", "lift", "certified", "certification"],
            sources: [forklifts]),
        CoachGuide(
            id: "freezer-door", title: "Freezer or cooler door won't open on its own", category: .operations,
            summary: "Open it manually if you've been shown how, secure it, keep product cold, and get it fixed.",
            steps: [
                "Use the door's manual open (pull chain, hand crank or manual release) if you've been shown how. Don't force a jammed door.",
                "Raise it all the way and make sure it stays up before anyone works under it or drives a pallet jack through.",
                "Check that the inside release works before anyone goes in, so nobody can get shut in.",
                "Keep the freight moving: break the frozen and dairy pallets down at the door, frozen first, and get product inside fast.",
                "Lower it by hand between loads to hold the temperature.",
                "Report the door through your store's maintenance process and tell the manager on duty."
            ],
            checkWith: "Your store's maintenance request process and the manager on duty.",
            keywords: ["freezer door", "cooler door", "roll up door", "roll-up door", "dock door", "door won't open", "door will not open",
                       "won't open", "will not open", "doesn't open", "open manually", "manually", "manual", "stuck door", "door stuck",
                       "freezer", "cooler"],
            sources: []),
        CoachGuide(
            id: "frozen-truck", title: "Breaking down a frozen and dairy truck", category: .operations,
            summary: "Frozen first, one pallet at a time, and keep product cold.",
            steps: [
                "Pull frozen pallets first, then dairy, then dry grocery.",
                "Break down and sort inside the freezer or cooler, or right at its door, by aisle or department.",
                "Work one pallet at a time so product isn't left sitting out.",
                "Get soft items like ice cream put away or into the freezer first.",
                "If product sat out too long, follow your store's cold-chain rules before it goes on the shelf.",
                "Keep the freezer floor clear, and wear gloves and freezer gear."
            ],
            checkWith: "Your store's cold-chain time limits.",
            keywords: ["frozen", "dairy", "break down", "broke down", "breakdown", "break the pallets", "sort", "sorted", "separate",
                       "separated", "cold chain", "frozen truck", "dairy truck", "ice cream", "perishable"],
            sources: []),
        CoachGuide(
            id: "broken-equipment", title: "Broken equipment (baler, compactor, cooler, pallet jack)", category: .operations,
            summary: "Stop using it, tag it, use a backup, and report it.",
            steps: [
                "Stop using it, and keep people away if it's unsafe.",
                "Tag it out of service so nobody else uses it.",
                "Use a backup: another pallet jack, the other baler, or space in another cooler.",
                "Report it through your store's maintenance process and tell the manager on duty.",
                "Never reach into a baler or compactor, or bypass a guard or switch."
            ],
            checkWith: "Your store's maintenance request process.",
            keywords: ["broken", "broke", "not working", "doesn't work", "won't work", "baler", "compactor", "jammed", "jam",
                       "out of order", "maintenance", "repair", "dead battery", "won't charge", "won't start"],
            sources: []),
        CoachGuide(
            id: "warm-case", title: "Cooler or freezer running warm", category: .safety,
            summary: "Protect the product, find the cause, report it, and follow food safety rules.",
            steps: [
                "Check the obvious first: a door left open, an overloaded case, ice buildup or blocked vents.",
                "Move product to a working cooler or freezer if the temperature keeps climbing.",
                "Report it through your store's maintenance process right away.",
                "Follow your store's food safety rules for product that got too warm. Don't guess."
            ],
            checkWith: "Your store's food safety and temperature procedures.",
            keywords: ["warm", "temperature", "temp", "too warm", "not cold", "thawing", "melting", "temp alarm", "alarm"],
            sources: [fdaRecalls]),
        // MARK: Running the floor
        CoachGuide(
            id: "freight-behind", title: "Freight is behind", category: .operations,
            summary: "Work the holes and top sellers first, keep aisles safe, tell your store manager early.",
            steps: [
                "Prioritize empty shelf spots, features and fast sellers before full aisles.",
                "Stage freight by aisle, and keep aisles and exits clear while you work.",
                "Move people to where the freight is, and ask other areas for help.",
                "Set short goals (\"this aisle by noon\") and check progress.",
                "Tell your store manager early what will carry over, and note it in End My Shift."
            ],
            checkWith: "Your store manager, for help from other areas.",
            keywords: ["freight", "truck", "behind", "backroom full", "holes", "outs", "out of stock", "stocking", "pallets", "overnight", "zone"],
            sources: []),
        CoachGuide(
            id: "market-walk", title: "Getting ready for a market or store manager walk", category: .operations,
            summary: "Walk it first, fix safety, know your numbers and your plan.",
            steps: [
                "Walk your areas first: exits clear, spills, ladders and equipment put away.",
                "Fix the obvious: empty shelf spots, features, endcaps, signs, clutter.",
                "Know your area's top three opportunities and what you're doing about each.",
                "Have the status of earlier follow-ups ready.",
                "Afterward, turn the notes into tasks (Import notes helps) and follow up quickly."
            ],
            checkWith: nil,
            keywords: ["market", "market manager", "visit", "walk", "store walk", "tour", "regional", "inspection", "prep for"],
            sources: [])
    ]

    public static func guide(id: String, including extra: [CoachGuide] = []) -> CoachGuide? {
        (extra + all).first { $0.id == id }
    }

    /// "spills"/"spill", "recalled"/"recall", "manually"/"manual": the same word with a short ending.
    /// "door" doesn't match "doorbuster".
    static func isWordForm(_ word: String, of keyword: String) -> Bool {
        guard word.count > 3, keyword.count > 3 else { return false }
        if word.hasPrefix(keyword) { return word.count - keyword.count <= 3 }
        if keyword.hasPrefix(word) { return keyword.count - word.count <= 2 }
        return false
    }

    static func normalize(_ text: String) -> String {
        text.lowercased()
            .replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: "[^a-z0-9:' -]+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    static func tokens(_ text: String) -> [String] {
        text.split(whereSeparator: { $0 == " " || $0 == "-" }).map(String.init).map { word in
            // Light plural/verb folding: "spills" → "spill", "leaking" stays.
            if word.count > 4, word.hasSuffix("s"), !word.hasSuffix("ss") { return String(word.dropLast()) }
            return word
        }
    }
}
