import Foundation

struct PersonHit: Equatable {
    var name: String
    var isKnown: Bool
    var isRole: Bool
    var location: Int
}

/// Finds the people a capture is about. Known associates are matched first; otherwise names are only
/// taken from clear patterns ("follow up with Sarah", "John asked…"), and always flagged for review.
enum PeopleExtraction {
    /// First names that are also everyday words; these only match when capitalised.
    static let ambiguousFirstNames: Set<String> = [
        "mark", "will", "may", "june", "april", "august", "bill", "pat", "sue", "rob", "grant", "chase", "hunter",
        "faith", "hope", "joy", "art", "gene", "rose", "penny", "dawn", "summer", "autumn", "sky", "jack", "frank",
        "drew", "miles", "lane", "rich", "sunny", "amber", "ray", "dean", "major", "case", "sage", "harmony", "angel"
    ]

    static func extract(_ scan: CaptureScan, _ ctx: CaptureContext) -> [PersonHit] {
        var hits: [PersonHit] = []
        let text = scan.text
        let ns = scan.ns
        let full = NSRange(location: 0, length: ns.length)

        // 1. Known associates (full name, then unique first name).
        let known = ctx.knownAssociates
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        var firstNameCounts: [String: Int] = [:]
        for name in known {
            if let first = name.split(separator: " ").first { firstNameCounts[first.lowercased(), default: 0] += 1 }
        }
        for name in known.sorted(by: { $0.count > $1.count }) {
            var patterns: [(String, Bool)] = []   // (token, case-insensitive)
            let parts = name.split(separator: " ").map(String.init)
            if parts.count > 1 {
                patterns.append((name, true))
                if let first = parts.first, firstNameCounts[first.lowercased()] == 1 {
                    patterns.append((first, !ambiguousFirstNames.contains(first.lowercased())))
                }
            } else {
                patterns.append((name, !ambiguousFirstNames.contains(name.lowercased())))
            }
            for (token, insensitive) in patterns {
                let pattern = #"(?<![\w])"# + NSRegularExpression.escapedPattern(for: token) + #"(?:['’]s)?(?![\w])"#
                guard let regex = Lexicon.regex(pattern, caseInsensitive: insensitive) else { continue }
                if let m = regex.firstMatch(in: text, options: [], range: full), scan.isFree(m.range) {
                    hits.append(PersonHit(name: name, isKnown: true, isRole: false, location: m.range.location))
                    break
                }
            }
        }

        // 2. Roles: "talk to the overnight coach", "tell the store manager".
        let roleArea = #"(?:overnight|morning|evening|night|day|weekend|front\s+end|frontend|fe|o/n|(?:stock|cap)\s*[123]|backroom|pharmacy|deli|bakery|grocery|produce|frozen|dairy|meat|fresh|food|fashion|stocking|digital|opd|ap|acc|auto\s+care|online|pickup|apparel|electronics|hardlines|softlines|closing|opening|other|new|assistant|market|regional)"#
        let roleNoun = #"(?:store\s+manager|market\s+manager|market\s+coach|regional\s+manager|people\s+lead|co-?manager|team\s+leads?(?:er)?|coach(?:es)?|manager|supervisor|asset\s+protection|tls?|sm|apa|apch|(?:stock|cap)\s*[123]|(?:overnight|o/n|stocking|night|unload|truck|opd|pickup|fresh|front\s+end)\s+(?:team|crew))"#
        let rolePattern = #"\b(?:with|to|tell|ask|remind|email|text|call|update|inform|from|for|let|see|have|get|by)\s+(?:the\s+|my\s+|our\s+|an?\s+)?((?:"# + roleArea + #"\s+)?"# + roleNoun + #")\b"#
        for m in scan.matches(rolePattern) {
            guard let role = scan.group(m, 1) else { continue }
            hits.append(PersonHit(name: formatRole(role), isKnown: false, isRole: true, location: m.range(at: 1).location))
        }

        // "tell the MOD" — capitals only, so "help with the mod" stays a modular.
        for m in scan.matches(#"\b(?i:with|to|tell|ask|remind|let|have|get|call|text|for|from|by)\s+(?i:the\s+)?(MOD)\b"#, caseInsensitive: false) {
            hits.append(PersonHit(name: "Manager on Duty", isKnown: false, isRole: true, location: m.range(at: 1).location))
        }

        // 3. Capitalised names after a clear trigger ("follow up with Sarah", "ask Maria").
        let namePart = #"([A-Z][a-z]+(?:[-'’][A-Za-z]+)?)(?:\s+([A-Z][a-z]+|[A-Z]\.?))?(?![\w])"#
        let triggers = #"(?i:follow(?:ing)?[ -]?up\s+with|check(?:ing)?\s+(?:in\s+)?(?:with|on)|check\s+back\s+with|talk(?:ing)?\s+(?:to|with)|speak(?:ing)?\s+(?:to|with)|meet(?:ing)?\s+(?:up\s+)?with|get\s+back\s+to|reach\s+out\s+to|touch\s+base\s+with|circle\s+back\s+with|sit\s+down\s+with|let|ask|tell|have|get|remind|help|call|text|email|message|thank|coach|train|see|with|for|to|from)"#
        // The name itself must be uninterpreted; what follows may be a date ("with Avery Friday").
        for m in scan.allMatches(#"\b"# + triggers + #"\s+"# + namePart, caseInsensitive: false) where scan.isFree(m.range(at: 1)) {
            if let hit = makeHit(scan, m, firstGroup: 1, secondGroup: 2) { hits.append(hit) }
        }

        // 4. Sentence-initial subject: "Sarah needs…", "John asked…"
        let verbs = #"(?i:needs|needed|asked|asks|wants|wanted|said|says|requested|requests|is\s+asking|was\s+asking|is\s+requesting|would\s+like|called\s+out|called\s+in|mentioned|told\s+me|brought\s+up|has\s+a\s+question|has\s+questions|is\s+out|is\s+off|is\s+late|will|can't|can’t|cannot|couldn't|couldn’t|didn't|didn’t|did\s+not)"#
        for m in scan.allMatches(#"(?:^|[.!?]\s+)"# + namePart + #"\s+"# + verbs + #"\b"#, caseInsensitive: false) where scan.isFree(m.range(at: 1)) {
            if let hit = makeHit(scan, m, firstGroup: 1, secondGroup: 2) { hits.append(hit) }
        }

        // 5. Possessive: "check John's availability"
        for m in scan.matches(#"\b([A-Z][a-z]+)['’]s\b"#, caseInsensitive: false) {
            if let hit = makeHit(scan, m, firstGroup: 1, secondGroup: nil) { hits.append(hit) }
        }

        // De-duplicate by name (known names win), ordered by position.
        var seen: [String: PersonHit] = [:]
        for hit in hits.sorted(by: { $0.location < $1.location }) {
            let key = hit.name.lowercased()
            if let existing = seen[key] {
                if hit.isKnown && !existing.isKnown { seen[key] = hit }
                continue
            }
            seen[key] = hit
        }
        var result = Array(seen.values).sorted { $0.location < $1.location }
        // If both a known person and unknown ones were found, put known first.
        if let knownIndex = result.firstIndex(where: { $0.isKnown }), knownIndex > 0 {
            let knownHit = result.remove(at: knownIndex)
            result.insert(knownHit, at: 0)
        }
        // Remove unknown hits that are just the first name of a known hit.
        let knownNames = result.filter { $0.isKnown }.map { $0.name.lowercased() }
        result.removeAll { hit in
            !hit.isKnown && knownNames.contains { $0.hasPrefix(hit.name.lowercased() + " ") || $0 == hit.name.lowercased() }
        }
        return result
    }

    private static func makeHit(_ scan: CaptureScan, _ m: NSTextCheckingResult, firstGroup: Int, secondGroup: Int?) -> PersonHit? {
        guard var first = scan.group(m, firstGroup) else { return nil }
        for suffix in ["'s", "’s"] where first.hasSuffix(suffix) { first = String(first.dropLast(2)) }
        guard first.count >= 2, !Lexicon.nameStopWords.contains(first.lowercased()) else { return nil }
        var name = first
        if let secondGroup, var second = scan.group(m, secondGroup), scan.isFree(m.range(at: secondGroup)) {
            for suffix in ["'s", "’s"] where second.hasSuffix(suffix) { second = String(second.dropLast(2)) }
            let lowered = second.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
            if !Lexicon.nameStopWords.contains(lowered) && CalendarWords.weekdayNumber(lowered) == nil {
                name += " " + second
            }
        }
        return PersonHit(name: name, isKnown: false, isRole: false, location: m.range(at: firstGroup).location)
    }

    static func formatRole(_ role: String) -> String {
        let lowered = role.lowercased().split(whereSeparator: { $0 == " " || $0 == "\t" }).joined(separator: " ")
        if lowered == "sm" { return "Store Manager" }
        if let regex = Lexicon.regex(#"^(stock|cap)\s*([123])(.*)$"#), let m = regex.firstMatch(in: lowered, options: [], range: NSRange(location: 0, length: (lowered as NSString).length)) {
            let ns = lowered as NSString
            let team = (ns.substring(with: m.range(at: 1)) == "cap" ? "CAP " : "Stock ") + ns.substring(with: m.range(at: 2))
            let rest = ns.substring(with: m.range(at: 3)).trimmingCharacters(in: .whitespaces)
            return rest.isEmpty ? team : team + " " + formatRole(rest)
        }
        let acronyms: [String: String] = [
            "tl": "TL", "tls": "TLs", "ap": "AP", "acc": "ACC", "opd": "OPD", "sm": "SM", "fe": "FE", "o/n": "O/N",
            "apa": "APA", "apch": "APCH"
        ]
        return lowered.split(separator: " ")
            .map { word -> String in
                let w = String(word)
                if let acronym = acronyms[w] { return acronym }
                if w.hasPrefix("co-") || w == "comanager" { return "Co-Manager" }
                return w.prefix(1).uppercased() + w.dropFirst()
            }
            .joined(separator: " ")
    }
}
