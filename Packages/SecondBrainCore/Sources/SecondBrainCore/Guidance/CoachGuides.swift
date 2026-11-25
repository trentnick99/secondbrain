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

    /// A guide the person wrote for their own store.
    public var isCustom: Bool { id.hasPrefix(CustomGuide.idPrefix) }

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

/// A "what do I do if…" guide the person writes for their store. Kept on the phone; Ask searches it
/// alongside the built-in guides and uses it in written answers.
public struct CustomGuide: Codable, Hashable, Identifiable, Sendable {
    public static let idPrefix = "custom-"

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

    public var guideID: String { Self.idPrefix + id.uuidString }

    public var guide: CoachGuide {
        let cleanSteps = steps.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let titleWords = CoachGuides.tokens(CoachGuides.normalize(title)).filter { !CoachGuides.stopWords.contains($0) && $0.count > 2 }
        let extras = extraKeywords.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return CoachGuide(id: guideID, title: title.trimmingCharacters(in: .whitespaces), category: category,
                          summary: "Your store's own guide.", steps: cleanSteps,
                          checkWith: checkWith.trimmingCharacters(in: .whitespaces).isEmpty ? nil : checkWith,
                          keywords: [CoachGuides.normalize(title)] + titleWords + extras, sources: [])
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
    private static let walmartPolicies = GuideSource("Walmart public policies", "https://corporate.walmart.com/policies")
    private static let walmartEthics = GuideSource("Walmart Ethics & Code of Conduct", "https://www.walmartethics.com")

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
        CoachGuide(
            id: "theft", title: "Suspected shoplifting", category: .safety,
            summary: "Safety over merchandise. Don't chase or confront.",
            steps: [
                "Don't chase, block, touch or accuse anyone.",
                "Get asset protection or the manager on duty involved.",
                "If anyone is threatened or there's a weapon, get to safety and call 911.",
                "Keep notes and descriptions with AP, not in Coach Spark."
            ],
            checkWith: "Your store's asset protection procedures. AP and the manager on duty handle it.",
            keywords: ["shoplifting", "shoplifter", "theft", "stealing", "steal", "concealing", "push out", "walk out"],
            sources: []),
        CoachGuide(
            id: "threat", title: "Threatening or aggressive person", category: .safety,
            summary: "Distance, calm and help. Call 911 if anyone is in danger.",
            steps: [
                "Keep your distance and a clear way out. Don't argue or touch them.",
                "Speak calmly, and don't take it personally.",
                "Get the manager on duty and asset protection.",
                "If there's a weapon or a threat of violence, get people away and call 911.",
                "Afterward, check on the associates involved."
            ],
            checkWith: "Your store's emergency and asset protection procedures.",
            keywords: ["threat", "threatening", "aggressive", "violent", "yelling", "fight", "fighting", "weapon", "angry man", "angry woman", "de-escalate"],
            sources: []),

        // MARK: Leading people
        CoachGuide(
            id: "short-staffed", title: "Short-staffed for the shift", category: .people,
            summary: "Protect safety and the customer first, then freight. Tell your store manager early.",
            steps: [
                "Re-rank the shift: safety and compliance first, customer-facing work next, then freight and projects.",
                "Use the Matrix: keep Do Now, schedule or hand back Plan items, and push anything that can wait.",
                "Ask team leads where they can flex, and look for cross-trained help from other areas.",
                "Tell your store manager early what won't get done, and what you're doing instead.",
                "Run End My Shift so carried-over work isn't lost."
            ],
            checkWith: "Your store manager, for coverage and shifting priorities.",
            keywords: ["short staffed", "short-staffed", "understaffed", "call out", "call outs", "callout", "callouts", "called out", "called off", "no coverage", "not enough people", "coverage"],
            sources: []),
        CoachGuide(
            id: "one-on-one", title: "Running a one-on-one", category: .people,
            summary: "Their meeting, not yours. Listen more than you talk.",
            steps: [
                "Ask how they're doing and what's getting in their way.",
                "Recognize something specific they did well.",
                "Talk about one goal or skill they want to grow.",
                "Agree on one or two next steps with dates, and add your own follow-ups here.",
                "Keep personal, medical or disciplinary details out of Coach Spark."
            ],
            checkWith: nil,
            keywords: ["one on one", "one-on-one", "1:1", "1 on 1", "check in", "check-in", "development", "career"],
            sources: []),
        CoachGuide(
            id: "feedback", title: "Coaching or giving feedback", category: .people,
            summary: "Private, specific and about behavior, with a clear next step.",
            steps: [
                "Talk in private and soon after the moment.",
                "Use Situation, Behavior, Impact: when and where, what you saw, and why it matters.",
                "Ask for their side, and listen.",
                "Agree on what good looks like and when you'll check in.",
                "Follow up. Formal coaching or discipline goes through your People Lead and the approved system, not Coach Spark."
            ],
            checkWith: "Your People Lead, for anything formal.",
            keywords: ["feedback", "coach", "coaching", "correct", "performance", "not performing", "slow", "lazy", "attitude", "conversation"],
            sources: []),
        CoachGuide(
            id: "follow-through", title: "A team lead isn't following through", category: .people,
            summary: "Make expectations and deadlines unmistakable, then remove blockers.",
            steps: [
                "Restate the expectation: what, by when, and what done looks like.",
                "Ask what's getting in the way: time, people, skills or unclear priorities.",
                "Agree on check-in points instead of only checking at the deadline.",
                "Recognize progress when it happens.",
                "If it becomes a pattern, talk with your store manager and People Lead about next steps."
            ],
            checkWith: "Your store manager and People Lead, if it's a pattern.",
            keywords: ["team lead", "follow through", "not following", "accountability", "missed deadline", "doesn't listen", "not doing", "excuses"],
            sources: []),
        CoachGuide(
            id: "conflict", title: "Conflict between associates", category: .people,
            summary: "Separate, listen to each person, focus on work and behavior.",
            steps: [
                "If it's heated, separate them and give everyone a moment.",
                "Talk with each person privately, and listen without taking sides.",
                "Focus on behaviors and the work, not personalities.",
                "Agree on clear expectations going forward, and check back.",
                "If it involves harassment, discrimination or threats, report it. Don't handle it alone."
            ],
            checkWith: "Your People Lead, or Ethics & Compliance for harassment or discrimination.",
            keywords: ["conflict", "argument", "arguing", "don't get along", "drama", "gossip", "disagreement", "tension"],
            sources: [walmartEthics]),
        CoachGuide(
            id: "attendance", title: "An associate keeps coming in late or missing shifts", category: .people,
            summary: "Talk early and privately, find the cause, and apply the policy consistently.",
            steps: [
                "Talk privately and early, before it becomes a pattern.",
                "Ask what's going on. There may be a schedule, transportation or family reason you can help with.",
                "Be clear about what's expected and how it affects the team.",
                "Apply the attendance policy the same way for everyone.",
                "Attendance records belong in the timekeeping system. Here, note only your follow-up, like \"check in with Sam Friday\"."
            ],
            checkWith: "Your store's attendance policy and your People Lead.",
            keywords: ["late", "tardy", "attendance", "showing up late", "coming in late", "missing shifts", "misses shifts", "no show", "absent", "absences", "leaving early"],
            sources: []),
        CoachGuide(
            id: "struggling", title: "An associate is upset or struggling", category: .people,
            summary: "Find a private spot, listen, and point them to support.",
            steps: [
                "Find a private, quiet spot and give them a moment.",
                "Listen. Ask how you can help today, like a short break or a different task.",
                "Don't press for personal or medical details, and don't record them in Coach Spark.",
                "Point them to the associate support resources your People Lead can share.",
                "If they mention hurting themselves, stay with them and call or text 988 (Suicide & Crisis Lifeline). If they're in immediate danger, call 911."
            ],
            checkWith: "Your People Lead, for support resources.",
            keywords: ["crying", "upset", "struggling", "stressed", "stress", "overwhelmed", "personal problems", "going through", "breakdown", "anxious", "sad", "burned out", "burnout"],
            sources: []),
        CoachGuide(
            id: "plan-shift", title: "What to focus on this shift", category: .operations,
            summary: "Safety walk, then Do Now, then follow-ups, then freight.",
            steps: [
                "Start with a quick safety walk of your areas: exits, spills, equipment.",
                "Check Home and the Matrix: do the Do Now items first.",
                "Clear follow-ups due today, especially ones from your store manager or market.",
                "Set the team's top three at the huddle, with owners.",
                "Before you leave, run End My Shift so nothing is lost."
            ],
            checkWith: nil,
            keywords: ["focus", "focus on", "today", "plan my day", "plan my shift", "where to start", "start my shift", "priorit", "first thing"],
            sources: []),
        CoachGuide(
            id: "recognition", title: "Recognizing good work", category: .people,
            summary: "Specific, timely and in a way they like.",
            steps: [
                "Say exactly what they did and why it mattered.",
                "Do it soon, at the huddle or right on the floor.",
                "Ask whether they like public shout-outs or a quiet thank-you.",
                "Tell their team lead and your store manager about standout work."
            ],
            checkWith: nil,
            keywords: ["recognition", "recognize", "thank", "appreciate", "morale", "motivate", "motivation", "shout out", "shout-out"],
            sources: []),
        CoachGuide(
            id: "new-associate", title: "A new associate's first week", category: .people,
            summary: "A buddy, a plan, and frequent check-ins.",
            steps: [
                "Pair them with a reliable buddy for the first few shifts.",
                "Start with safety: exits, equipment rules, how to report a hazard.",
                "Give them a simple plan for what they'll learn each day.",
                "Check in on day one, mid-week and at the end of the week.",
                "Make sure required training is done before they do that work."
            ],
            checkWith: "Your store's onboarding and training requirements.",
            keywords: ["new associate", "new hire", "onboarding", "first week", "training", "new team member", "orientation"],
            sources: []),
        CoachGuide(
            id: "delegation", title: "Delegating to team leads", category: .people,
            summary: "Clear owner, clear finish line, agreed check-in.",
            steps: [
                "Say what needs doing, why it matters and when it's due.",
                "Make one person the owner.",
                "Agree when you'll check in, and set yourself a follow-up here.",
                "Hand over the decision as well as the task where you can.",
                "Thank them, and give feedback when it's done."
            ],
            checkWith: nil,
            keywords: ["delegate", "delegating", "delegation", "hand off", "assign", "ownership", "micromanage"],
            sources: []),
        CoachGuide(
            id: "huddle", title: "Running a good huddle", category: .people,
            summary: "5–10 minutes: safety, yesterday, today, thanks.",
            steps: [
                "Open with one safety message.",
                "Share one result from yesterday, good or not.",
                "Give today's top three priorities and who owns each.",
                "Recognize someone by name.",
                "Ask whether anyone needs help or has a question."
            ],
            checkWith: nil,
            keywords: ["huddle", "meeting", "start of shift", "morning meeting", "rally", "team meeting"],
            sources: []),

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
            sources: []),
        CoachGuide(
            id: "conflicting-priorities", title: "Conflicting priorities", category: .operations,
            summary: "Make the conflict visible and ask which comes first.",
            steps: [
                "List each ask, who it's from and when it's due.",
                "Take the list to your store manager and ask which comes first.",
                "Never drop safety or compliance work to make room.",
                "Tell whoever loses out when to expect it.",
                "Use the Matrix to keep the order straight."
            ],
            checkWith: "Your store manager.",
            keywords: ["conflicting", "too much", "everything urgent", "which first", "two managers", "competing", "want different", "different things", "mixed messages", "contradict", "store manager and market"],
            sources: []),

        // MARK: Customers
        CoachGuide(
            id: "price-match", title: "Customer asks for a price match", category: .customers,
            summary: "Walmart's public policy: US stores match Walmart.com for the identical item, with restrictions.",
            steps: [
                "Check that it's the identical item on Walmart.com, sold by Walmart.",
                "Walmart's public policy says the store manager on duty has the final say on any price match.",
                "Check the policy page for the current restrictions.",
                "If you're unsure, get the manager on duty rather than guessing."
            ],
            checkWith: "The current public policy and the manager on duty.",
            keywords: ["price match", "price-match", "match price", "cheaper online", "ad match", "competitor price"],
            sources: [walmartPolicies]),
        CoachGuide(
            id: "upset-customer", title: "Upset customer", category: .customers,
            summary: "Listen, acknowledge, solve what you can, and get help if it escalates.",
            steps: [
                "Listen fully without interrupting.",
                "Acknowledge how they feel (\"I understand why that's frustrating\").",
                "Say what you can do, and do it quickly.",
                "Get the manager on duty for anything beyond your authority.",
                "If it turns threatening, step away and get help. Your safety comes first."
            ],
            checkWith: "The manager on duty, for anything beyond your authority.",
            keywords: ["customer", "complaint", "upset", "angry customer", "rude", "yelling", "return", "refund", "manager request"],
            sources: [walmartPolicies]),

        // MARK: Ethics & conduct
        CoachGuide(
            id: "ethics", title: "Something seems wrong (ethics concern)", category: .ethics,
            summary: "Speak up. Retaliation is prohibited.",
            steps: [
                "Walmart's public Code of Conduct says to speak up when something seems wrong.",
                "You can go to your manager, a People Lead or Ethics & Compliance.",
                "The Ethics Helpline is 1-800-WM-ETHIC (800-963-8442) in the U.S., open 24/7.",
                "The Code prohibits retaliation against anyone who reports a concern.",
                "Keep case details out of Coach Spark."
            ],
            checkWith: "Ethics & Compliance, your People Lead or your manager.",
            keywords: ["ethics", "unethical", "wrong", "report", "concern", "fraud", "speak up", "retaliation", "code of conduct", "hotline", "helpline"],
            sources: [walmartEthics]),
        CoachGuide(
            id: "harassment", title: "Harassment or discrimination", category: .ethics,
            summary: "Take it seriously and report it. Don't investigate yourself.",
            steps: [
                "Listen, and thank them for telling you.",
                "Don't promise to keep it secret. Say you'll get it to the right people.",
                "Report it to your People Lead or Ethics & Compliance, as the Code of Conduct says.",
                "Don't investigate or confront anyone yourself.",
                "Keep the details out of Coach Spark. Note only the task, like \"talk with People Lead today\"."
            ],
            checkWith: "Your People Lead or Ethics & Compliance.",
            keywords: ["harassment", "harassing", "discrimination", "inappropriate", "comments", "hostile", "bullying", "bully", "uncomfortable"],
            sources: [walmartEthics])
    ]

    public static func guide(id: String, including extra: [CoachGuide] = []) -> CoachGuide? {
        (extra + all).first { $0.id == id }
    }

    /// Guides that best match a question, best first, including the person's own guides. Works offline.
    public static func search(_ query: String, limit: Int = 5, including extra: [CoachGuide] = []) -> [CoachGuide] {
        let q = normalize(query)
        let words = Set(tokens(q)).subtracting(stopWords)
        guard !words.isEmpty || !q.isEmpty else { return [] }
        let scored: [(CoachGuide, Int)] = (extra + all).map { guide in
            var score = 0
            var used = Set<String>()   // each word of the question counts once per guide
            for keyword in guide.keywords {
                let k = normalize(keyword)
                if k.contains(" ") || k.contains("-") {
                    if q.contains(k) { score += 6 }
                } else if let word = (words.contains(k) ? k : words.first(where: { isWordForm($0, of: k) })),
                          used.insert(word).inserted {
                    score += 4
                }
            }
            let titleWords = Set(tokens(normalize(guide.title))).subtracting(stopWords)
            score += 3 * words.intersection(titleWords).count
            let strong = score > 0
            let bodyWords = Set(tokens(normalize(guide.summary + " " + guide.steps.joined(separator: " ")))).subtracting(stopWords)
            score += words.intersection(bodyWords).count
            // A guide needs a keyword or title match; body words only add to that.
            return (guide, strong ? score + (guide.isCustom ? 2 : 0) : 0)
        }
        return scored.filter { $0.1 >= 3 }
            .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0.title < $1.0.title }
            .prefix(limit)
            .map(\.0)
    }

    /// A starting set of guides for someone's role, shown before they type.
    public static func suggested(for role: UserRole?) -> [CoachGuide] {
        var ids = ["short-staffed", "feedback", "one-on-one", "huddle"]
        switch role?.primaryArea {
        case "Stocking", "Overnight": ids = ["freight-behind", "equipment", "blocked-exit"] + ids
        case "Fresh", "Food": ids = ["recall", "freight-behind", "spill"] + ids
        case "Front End": ids = ["upset-customer", "price-match", "crowd"] + ids
        case "Asset Protection": ids = ["theft", "threat", "crowd"] + ids
        default: ids = ["market-walk", "blocked-exit"] + ids
        }
        if role?.role == .storeManager { ids = ["conflicting-priorities", "follow-through", "crowd"] + ids }
        var seen = Set<String>()
        return ids.compactMap { id in seen.insert(id).inserted ? guide(id: id) : nil }.prefix(6).map { $0 }
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

    static let stopWords: Set<String> = [
        "a", "an", "the", "and", "or", "of", "to", "in", "on", "for", "with", "at", "by", "is", "are", "was", "be",
        "i", "my", "me", "we", "our", "you", "your", "it", "this", "that", "what", "how", "do", "does", "should",
        "can", "if", "when", "there", "their", "they", "them", "about", "get", "have", "has", "im", "i'm", "someone",
        "something", "need", "want", "help", "best", "way", "tip", "tips", "store", "walmart", "coach", "up", "out",
        "keep", "keeps", "associate", "employee", "worker", "team", "member", "people", "person", "go", "going", "got",
        "just", "really", "very", "so", "too", "not", "no", "from", "into", "will", "would", "could", "all", "any",
        "first", "tonight", "now", "right", "thing", "things"
    ]
}
