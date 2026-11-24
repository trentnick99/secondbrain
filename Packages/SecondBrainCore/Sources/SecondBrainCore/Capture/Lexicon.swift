import Foundation

/// Vocabulary used by the on-device capture parser and classifier.
/// Matching is whole-word / whole-phrase and case-insensitive.
enum Lexicon {
    // MARK: Word lists

    static let hazardWords = [
        "spill", "spilled", "spilt", "leak", "leaking", "leaky", "wet floor", "broken glass",
        "blocked exit", "blocked fire exit", "exit blocked", "exit is blocked", "fire exit blocked", "blocked aisle",
        "exposed wire", "exposed wires", "exposed wiring", "hazard", "hazardous", "unsafe", "injury", "injured",
        "hurt", "trip hazard", "slip hazard", "emergency", "danger", "dangerous", "sparking", "gas leak", "smoke alarm"
    ]

    static let urgentWords = [
        "urgent", "urgently", "asap", "a.s.a.p", "immediately", "right away", "right now", "emergency",
        "critical", "time sensitive", "time-sensitive", "rush", "top priority", "stat"
    ]

    static let safetyWords = [
        "safety", "unsafe", "hazard", "hazardous", "spill", "wet floor", "injury", "injured", "incident", "accident",
        "ppe", "ladder", "ladders", "osha", "first aid", "trip hazard", "slip hazard", "blocked exit", "fire exit",
        "fire extinguisher", "extinguisher", "extinguishers", "eyewash", "chemical spill", "sds", "msds", "lockout",
        "tagout", "baler", "compactor", "forklift", "pallet jack", "safety observation", "safety observations",
        "safety walk", "safety huddle", "fire marshal",
        "safety sweep", "safety committee", "safety champion", "fire exit", "fire exits", "emergency exit",
        "emergency exits", "exits clear", "near miss", "near misses", "loto", "lockout/tagout",
        "lock out tag out", "pit", "ple", "pre-use", "pre-use inspection", "pre-use inspections", "equipment inspection",
        "walkie stacker", "walkie rider", "electric pallet jack", "epj", "scissor lift", "ergonomics", "spill response",
        "evacuation", "fire drill", "emergency action plan", "code adam", "code white", "code blue", "active threat"
    ]

    static let complianceWords = [
        "compliance", "compliant", "audit", "audits", "recall", "recalls", "temperature log", "temp log", "temp logs",
        "temp check", "temp checks", "temperature check", "temperature checks", "food safety", "expired",
        "expiration", "date check", "date checks", "code date", "code dates", "out of date", "price accuracy",
        "regulation", "regulatory", "health inspection", "health inspector", "fire inspection", "mandatory",
        "required training", "certification", "license", "licence",
        "cold chain", "expiration pull", "expiration pulls", "date code", "date codes", "ulearn", "ulearns", "cbl", "cbls",
        "meal exception", "meal exceptions", "wercs"
    ]

    static let performanceWords = [
        "results", "metrics", "numbers", "kpi", "kpis", "scores", "performance", "sales", "shrink",
        "productivity", "in-stock", "instock", "inventory accuracy", "on-hand accuracy", "survey scores",
        "customer experience", "pick rate", "fill rate", "scorecard",
        "ftpr", "nil pick", "nil picks", "nil pick rate", "osa", "osca", "in-stock %", "splh", "uph", "pph", "wosh",
        "nps", "5-star", "5 star", "comp sales", "wtd", "mtd", "qtd", "ytd", "yoy", "shrink %", "on-time pick",
        "on time pick", "on-time delivery", "wait time", "wait times", "substitution rate", "physical inventory",
        "pi prep", "labor", "variance", "turnover", "retention", "vizpick %", "topstock %", "overtime"
    ]

    static let accountabilityWords = [
        "make sure", "ensure", "must", "need to", "needs to", "have to", "has to", "required", "committed",
        "promised", "promise", "deadline", "follow through", "accountable", "responsible for"
    ]

    static let importantWords = [
        "important", "high priority", "top priority", "priority", "crucial", "vital", "essential"
    ]

    static let leadershipWords = [
        "store manager", "market manager", "regional manager", "district manager", "co-manager", "comanager",
        "sm asked", "sm wants", "manager asked", "manager wants", "my manager", "boss", "market visit",
        "regional visit", "store visit", "executive visit", "vp visit", "leadership", "corporate visit", "visit prep",
        "market coach", "market is coming", "market coming", "regional is coming", "market walk", "market tour",
        "store tour", "tour ready", "business review", "market call", "regional call", "sm needs", "sm said", "store lead"
    ]

    static let routineWords = [
        "routine", "status update", "status check", "check status", "zone", "zoning", "recovery", "facing",
        "price change", "price changes", "reprint", "print", "labels", "checklist", "paperwork", "data entry",
        "fyi", "cycle count", "cycle counts", "routine inspection", "routine inspections",
        "fast zone", "facing up", "zoning up", "zone recovery"
    ]

    static let lowValueWords = [
        "maybe", "someday", "some day", "eventually", "if time", "if there's time", "if i have time",
        "when possible", "whenever", "low priority", "nice to have", "optional", "not important", "no rush",
        "not urgent", "would be nice", "duplicate", "outdated", "no longer needed"
    ]

    static let issueWords = [
        "broken", "leak", "leaking", "spill", "spilled", "out of stock", "oos", "backlog", "damaged", "missing",
        "not working", "isn't working", "isnt working", "stopped working", "is down", "are down", "went down",
        "jammed", "blocked", "empty", "low on", "shortage", "short staffed", "short-staffed", "outage", "error",
        "problem", "issue", "malfunction", "malfunctioning", "failing", "failed", "overflowing", "stuck",
        "doesn't work", "won't", "no power", "beeping",
        "phantom inventory", "negative on-hand", "negative on hand", "zero on-hand", "nil picks"
    ]

    static let actionStartVerbs: Set<String> = [
        "make", "check", "follow", "talk", "call", "ask", "tell", "fix", "clean", "review", "order", "schedule",
        "get", "send", "print", "set", "update", "remind", "look", "pull", "work", "finish", "submit", "email",
        "text", "meet", "prepare", "prep", "count", "audit", "walk", "zone", "move", "put", "plan", "train",
        "coach", "help", "have", "assign", "find", "take", "bring", "go", "do", "complete", "sign", "approve",
        "write", "read", "see", "verify", "confirm", "report", "request", "contact", "reach", "notify", "let",
        "pick", "file", "ensure", "double", "inspect", "replace", "call", "post", "submit", "start", "stop",
        "respond", "reply", "thank", "recognize", "give", "show", "teach", "organize", "sort", "label", "price"
    ]

    static let followUpPhrases = [
        "follow up", "follow-up", "followup", "check with", "check in with", "check on", "check back with",
        "talk to", "talk with", "speak to", "speak with", "ask", "tell", "get back to", "needs", "needed",
        "asked", "asks", "wants", "wanted", "requested", "meet with", "sit down with", "touch base",
        "circle back", "help", "show", "train", "coach", "remind", "update", "call", "text", "email",
        "reach out", "thank", "recognize", "give feedback", "feedback", "1:1", "one on one", "one-on-one",
        "let her know", "let him know", "let them know", "let", "see"
    ]

    static let categoryKeywords: [(TaskCategory, [String])] = [
        (.safety, safetyWords),
        (.compliance, complianceWords),
        (.people, [
            "schedule", "schedules", "availability", "time off", "pto", "vacation", "call out", "called out",
            "callout", "attendance", "break", "breaks", "lunch", "shift swap", "swap", "recognition", "recognize",
            "shoutout", "shout out", "thank", "morale", "concern", "concerns", "question", "questions", "conflict",
            "associate", "associates", "staffing", "coverage", "short staffed", "hire", "hiring", "interview",
            "interviews", "onboarding", "new hire", "orientation", "1:1", "one on one", "one-on-one", "feedback",
            "conversation", "punch", "punches", "time card", "timecard", "ncns", "no call no show", "meal punch",
            "time adjustment", "time adjustments", "ppto", "loa", "open availability", "availability change",
            "schedule adherence", "headcount", "huddle with", "touch base", "cover", "covering"
        ]),
        (.development, [
            "training", "develop", "development", "coaching", "career", "growth", "mentor", "mentoring",
            "cross-train", "cross train", "learning", "skills", "promotion", "development plan", "evaluation",
            "evaluations", "performance review", "cross-training", "ulearn", "academy", "succession", "bench",
            "talent pipeline", "calibration", "coach trainee", "mit"
        ]),
        (.freight, [
            "freight", "truck", "trucks", "pallet", "pallets", "unload", "unloading", "backlog", "stock",
            "stocking", "overstock", "top stock", "topstock", "bins", "binning", "picking", "pick list", "capacity",
            "cases", "totes", "rolltainer", "rolltainers", "steel", "backstock", "remix", "vizpick", "viz pick",
            "picks", "pick walk", "downstack", "breakpack", "casepack", "condense", "rework", "freight flow",
            "running freight", "working freight", "throwing freight", "throw freight", "working topstock",
            "chasing picks", "bin audit", "bin audits", "overstock verification", "live freight", "unworked freight",
            "dsd", "fdd", "hvdc", "rdc", "truck process", "mixed pallet", "mixed pallets", "replenishment", "pallet drop",
            "pallet drops"
        ]),
        (.merchandising, [
            "modular", "modulars", "mod", "mods", "feature", "features", "endcap", "endcaps", "display", "displays",
            "planogram", "pog", "signage", "price change", "price changes", "rollback", "rollbacks", "clearance",
            "markdown", "markdowns", "zone", "zoning", "out of stock", "outs", "labels", "reset", "resets",
            "action alley", "seasonal set", "mod set", "mod sets", "mod flex", "mod reset", "modular integrity",
            "wing stack", "wing stacks", "sidekick", "sidekicks", "pdq", "pdqs", "stack base", "flexing", "plugging",
            "feature-to-home", "feature to home", "fast zone", "zone recovery", "facing up", "secondary location",
            "end of aisle", "seasonal transition", "feature quantity", "price change", "osa", "digital shelf labels",
            "digital shelf label", "shelf labels", "dsl", "dsls", "esl", "esls", "halloween set", "christmas set",
            "holiday set", "easter set", "back-to-school set", "back to school set", "summer set", "seasonal conversion"
        ]),
        (.operations, [
            "clean", "cleaned", "cleaning", "cleanup", "clean up", "cleaned up", "maintenance", "broken", "repair",
            "repairs", "fix", "equipment", "cooler", "coolers", "freezer", "freezers", "leak", "leaking", "register",
            "registers", "scanner", "scanners", "handheld", "handhelds", "battery", "batteries", "printer", "lights",
            "door", "doors", "order", "ordering", "supplies", "supply", "bags", "trash", "cardboard", "keys",
            "cash office", "till", "opening", "closing", "store walk", "walk the store", "carts", "baler", "bale",
            "bales", "compactor", "clean backroom", "trailer", "trailers", "cash recycler", "tour ready",
            "store ready", "customer ready", "walking the store", "queue line", "queue lines", "crowd plan",
            "holiday hours", "store hours"
        ]),
        (.customer, [
            "customer", "customers", "complaint", "complaints", "guest", "guests", "shopper", "shoppers", "refund",
            "return", "returns", "special order", "customer experience", "price match", "price override", "nps",
            "5-star", "wait time", "bopis", "dispense", "dispensing", "10-foot rule"
        ]),
        (.meeting, [
            "meeting", "meetings", "huddle", "conference", "agenda", "market visit", "store visit", "visit",
            "presentation", "sync", "business review", "market call", "market walk", "store tour", "market tour"
        ]),
        (.admin, [
            "report", "reports", "email", "emails", "paperwork", "sign off", "approve", "approval", "submit",
            "results", "metrics", "numbers", "kpi", "kpis", "data", "spreadsheet", "payroll", "exceptions",
            "scorecard", "wtd", "mtd", "splh", "wosh", "budgeted hours", "on-hand adjustment", "isa", "labor"
        ])
    ]

    static let criticalWords = [
        "emergency", "injury", "injured", "blocked exit", "blocked fire exit", "exit blocked", "fire exit blocked",
        "exposed wire", "exposed wires", "exposed wiring", "gas leak", "critical", "danger", "dangerous", "unsafe",
        "hazard", "hazardous", "spill", "spilled", "broken glass", "wet floor"
    ]

    static let highWords = [
        "urgent", "urgently", "asap", "a.s.a.p", "immediately", "right away", "right now", "important",
        "high priority", "top priority", "priority", "time sensitive", "time-sensitive"
    ]

    /// Capitalised words that should never be taken as a person's name.
    static let nameStopWords: Set<String> = {
        var words: Set<String> = [
            "i", "i'm", "im", "i'll", "me", "my", "we", "our", "us", "you", "your", "he", "she", "they", "them",
            "the", "a", "an", "this", "that", "these", "those", "it", "its", "there", "here", "and", "or", "but",
            "today", "tonight", "tomorrow", "yesterday", "next", "last", "every", "each", "week", "month", "year",
            "morning", "afternoon", "evening", "night", "noon", "midnight",
            "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday",
            "mon", "tue", "tues", "wed", "thu", "thur", "thurs", "fri", "sat", "sun",
            "january", "february", "march", "april", "may", "june", "july", "august", "september", "october",
            "november", "december", "jan", "feb", "mar", "apr", "jun", "jul", "aug", "sep", "sept", "oct", "nov", "dec",
            "remind", "make", "check", "follow", "talk", "call", "ask", "tell", "please", "don't", "dont", "need",
            "needs", "get", "review", "update", "clean", "order", "print", "send", "set", "put", "move", "fix",
            "look", "schedule", "prep", "prepare", "walk", "count", "audit", "train", "zone", "pull", "work",
            "do", "finish", "start", "submit", "email", "text", "meet", "see", "find", "help", "sign", "approve",
            "plan", "write", "read", "go", "take", "bring", "have", "let", "must", "should", "can", "will", "is",
            "are", "was", "were", "be", "been", "note", "idea", "issue", "task", "todo", "meeting", "reminder",
            "coach", "manager", "team", "lead", "store", "market", "associate", "associates", "customer",
            "walmart", "sam's", "ok", "okay", "am", "pm", "eod", "eos", "asap", "fyi", "safety", "after", "before",
            "about", "with", "for", "to", "on", "at", "by", "from", "in", "of", "who", "what", "when", "where",
            "why", "how", "new", "old", "all", "everyone", "anyone", "someone", "somebody", "nobody", "him", "her",
            "his", "hers", "their", "mine", "yes", "no", "hi", "hey", "thanks", "thank", "due", "until", "end",
            "first", "second", "third", "christmas", "thanksgiving", "easter", "halloween", "black",
            "code", "stock", "cap", "remix", "mod", "feature", "vizpick", "topstock", "freight", "huddle", "vizio", "onn",
            "cyber", "deals", "sparky",
            "regional", "green", "red", "dept", "department"
        ]
        words.formUnion(DepartmentLexicon.stopWords)
        return words
    }()

    // MARK: Matching

    private static let regexCache = RegexCache()

    /// True when any word/phrase occurs as a whole word in `text` (case-insensitive).
    static func containsAny(_ text: String, _ words: [String]) -> Bool {
        guard let regex = regexCache.alternation(words) else { return false }
        let ns = text as NSString
        return regex.firstMatch(in: text, options: [], range: NSRange(location: 0, length: ns.length)) != nil
    }

    static func countMatches(_ text: String, _ words: [String]) -> Int {
        guard let regex = regexCache.alternation(words) else { return 0 }
        let ns = text as NSString
        return regex.numberOfMatches(in: text, options: [], range: NSRange(location: 0, length: ns.length))
    }

    static func regex(_ pattern: String, caseInsensitive: Bool = true) -> NSRegularExpression? {
        regexCache.regex(pattern, caseInsensitive: caseInsensitive)
    }
}

/// Thread-safe cache of compiled regular expressions.
final class RegexCache: @unchecked Sendable {
    private var storage: [String: NSRegularExpression] = [:]
    private let lock = NSLock()

    func regex(_ pattern: String, caseInsensitive: Bool) -> NSRegularExpression? {
        let key = (caseInsensitive ? "i:" : "s:") + pattern
        lock.lock()
        defer { lock.unlock() }
        if let cached = storage[key] { return cached }
        let options: NSRegularExpression.Options = caseInsensitive ? [.caseInsensitive] : []
        guard let compiled = try? NSRegularExpression(pattern: pattern, options: options) else { return nil }
        storage[key] = compiled
        return compiled
    }

    func alternation(_ words: [String]) -> NSRegularExpression? {
        // Longest first so multi-word phrases win over their prefixes.
        let sorted = words.sorted { $0.count > $1.count }
        let body = sorted.map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "|")
        return regex("(?<![\\w])(?:" + body + ")(?![\\w])", caseInsensitive: true)
    }
}
