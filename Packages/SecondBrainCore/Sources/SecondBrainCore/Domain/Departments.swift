import Foundation

/// Generic retail department vocabulary used to recognise departments in captured text.
/// These are common industry terms, not any company's proprietary system names.
public enum DepartmentLexicon {
    public struct Entry: Sendable {
        public let name: String
        public let aliases: [String]
    }

    public static let entries: [Entry] = [
        // Store areas (each run by a coach).
        Entry(name: "Stocking", aliases: ["stocking", "day stocking", "stocking team", "stockers", "stock 1", "stock 2", "cap 1", "cap 2"]),
        Entry(name: "Overnight", aliases: ["overnight", "overnights", "overnight stocking", "night crew", "o/n", "stock 3", "cap 3"]),
        Entry(name: "Fresh", aliases: ["fresh", "fcap", "97 wall"]),
        Entry(name: "Food", aliases: ["food", "food and consumables", "consumables"]),
        Entry(name: "Fashion", aliases: ["fashion", "apparel", "softlines", "clothing", "fitting room", "fitting rooms", "shoes"]),
        Entry(name: "Front End", aliases: ["front end", "frontend", "fe", "registers", "checkouts", "checkout", "self checkout", "self-checkout", "sco", "cashiers", "cash office", "bullpen"]),
        Entry(name: "Digital (OPD)", aliases: ["opd", "digital", "online pickup", "pickup", "delivery", "online orders", "ogp", "gif", "gif 2", "ftpr", "nil pick", "nil picks", "staging", "dispense", "dispensing", "bopis", "ship from store", "sfs"]),
        Entry(name: "Asset Protection", aliases: ["asset protection", "ap", "shrink", "apa", "apch", "orc", "cctv", "eas"]),
        Entry(name: "Auto Care Center (ACC)", aliases: ["acc", "accm", "auto care", "auto care center", "auto center", "tire center", "automotive", "oil change", "tle", "tire and lube"]),
        // Departments within areas.
        Entry(name: "Dairy", aliases: ["dairy"]),
        Entry(name: "Frozen", aliases: ["frozen", "freezers"]),
        Entry(name: "Produce", aliases: ["produce", "wet wall"]),
        Entry(name: "Meat", aliases: ["meat", "meat and seafood", "seafood", "meat wall"]),
        Entry(name: "Deli", aliases: ["deli"]),
        Entry(name: "Bakery", aliases: ["bakery"]),
        Entry(name: "Grocery", aliases: ["grocery", "dry grocery", "groceries"]),
        Entry(name: "Health & Beauty", aliases: ["health and beauty", "health & beauty", "hba", "cosmetics"]),
        Entry(name: "Pharmacy", aliases: ["pharmacy"]),
        Entry(name: "Electronics", aliases: ["electronics", "wireless", "vizio", "onn", "tv wall"]),
        Entry(name: "Toys", aliases: ["toys", "toy"]),
        Entry(name: "Home", aliases: ["home", "housewares", "bedding", "domestics"]),
        Entry(name: "Hardware", aliases: ["hardware", "paint"]),
        Entry(name: "Sporting Goods", aliases: ["sporting goods", "sports"]),
        Entry(name: "Lawn & Garden", aliases: ["lawn and garden", "lawn & garden", "garden center", "outdoor living"]),
        Entry(name: "Pets", aliases: ["pets", "pet"]),
        Entry(name: "Paper & Chemical", aliases: ["paper and chemical", "paper & chemical", "chemicals", "chemical aisle", "paper goods"]),
        Entry(name: "Infants", aliases: ["infants", "baby"]),
        Entry(name: "Crafts & Stationery", aliases: ["crafts", "stationery", "fabrics"]),
        Entry(name: "Seasonal", aliases: ["seasonal", "seasonal aisle"]),
        Entry(name: "Jewelry", aliases: ["jewelry"]),
        Entry(name: "Customer Service", aliases: ["customer service", "service desk"]),
        Entry(name: "Backroom & Receiving", aliases: ["backroom", "back room", "receiving", "dock", "loading dock", "vizpick", "viz pick", "bin audit", "bin audits", "trailer yard"]),
        Entry(name: "Fuel Station", aliases: ["fuel station", "gas station"]),
        Entry(name: "Vision Center", aliases: ["vision center", "optical"])
    ]

    public static var allNames: [String] { entries.map(\.name) }

    /// Single words that look like proper nouns when capitalised but are department words.
    static var stopWords: Set<String> {
        var words = Set<String>()
        for entry in entries {
            for alias in entry.aliases {
                for word in alias.split(separator: " ") { words.insert(String(word).lowercased()) }
            }
            for word in entry.name.split(separator: " ") { words.insert(String(word).lowercased()) }
        }
        return words
    }

    /// Returns the canonical department name for the first (longest) alias found in the text.
    public static func match(in text: String) -> String? {
        // "Digital shelf labels" are store-wide price tags, not the Digital (OPD) area.
        let lower = text.lowercased().replacingOccurrences(of: "digital shelf label", with: "dsl shelf label")
        var best: (name: String, length: Int, location: Int)?
        for entry in entries {
            for alias in entry.aliases {
                let pattern = "\\b" + NSRegularExpression.escapedPattern(for: alias) + "\\b"
                guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
                let ns = lower as NSString
                if let match = regex.firstMatch(in: lower, options: [], range: NSRange(location: 0, length: ns.length)) {
                    let candidate = (name: entry.name, length: alias.count, location: match.range.location)
                    if let current = best {
                        if candidate.location < current.location || (candidate.location == current.location && candidate.length > current.length) {
                            best = candidate
                        }
                    } else {
                        best = candidate
                    }
                }
            }
        }
        if let number = departmentNumber(in: lower),
           best == nil || number.location < best!.location {
            return number.name
        }
        return best?.name
    }

    /// Store department numbers mapped onto the names above where one fits ("dept 94" → Produce);
    /// otherwise the department's own name from the glossary ("D1" → Candy and Tobacco).
    static let numberedDepartments: [Int: String] = [
        2: "Health & Beauty", 46: "Health & Beauty", 3: "Crafts & Stationery", 19: "Crafts & Stationery",
        44: "Crafts & Stationery", 4: "Paper & Chemical", 13: "Paper & Chemical", 5: "Electronics",
        72: "Electronics", 87: "Electronics", 7: "Toys", 8: "Pets", 9: "Sporting Goods", 11: "Hardware",
        12: "Hardware", 14: "Home", 17: "Home", 20: "Home", 22: "Home", 74: "Home", 16: "Lawn & Garden",
        56: "Lawn & Garden", 18: "Seasonal", 23: "Fashion", 24: "Fashion", 25: "Fashion", 26: "Fashion",
        27: "Fashion", 28: "Fashion", 29: "Fashion", 30: "Fashion", 31: "Fashion", 33: "Fashion",
        34: "Fashion", 35: "Fashion", 36: "Fashion", 41: "Fashion", 32: "Jewelry",
        37: "Auto Care Center (ACC)", 38: "Pharmacy", 40: "Pharmacy", 49: "Vision Center", 65: "Fuel Station",
        79: "Infants", 80: "Deli", 81: "Bakery", 98: "Bakery", 90: "Dairy", 91: "Frozen", 92: "Grocery",
        95: "Grocery", 93: "Meat", 97: "Meat", 94: "Produce"
    ]

    /// "dept 94", "department 92", "D90", "dept #13".
    static func departmentNumber(in lower: String) -> (name: String, location: Int)? {
        let pattern = #"\b(?:(?:dept\.?|department)\s*#?\s*|d)(\d{1,2})\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let ns = lower as NSString
        for match in regex.matches(in: lower, options: [], range: NSRange(location: 0, length: ns.length)) {
            guard let number = Int(ns.substring(with: match.range(at: 1))) else { continue }
            if let name = numberedDepartments[number] ?? StoreGlossary.departmentName(number: number) {
                return (name, match.range.location)
            }
        }
        return nil
    }
}
