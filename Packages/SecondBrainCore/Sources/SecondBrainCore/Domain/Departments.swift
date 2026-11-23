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
        Entry(name: "Stocking", aliases: ["stocking", "day stocking", "stocking team", "stockers"]),
        Entry(name: "Overnight", aliases: ["overnight", "overnights", "overnight stocking", "night crew"]),
        Entry(name: "Fresh", aliases: ["fresh"]),
        Entry(name: "Food", aliases: ["food", "food and consumables", "consumables"]),
        Entry(name: "Fashion", aliases: ["fashion", "apparel", "softlines", "clothing", "fitting room", "fitting rooms", "shoes"]),
        Entry(name: "Front End", aliases: ["front end", "frontend", "registers", "checkouts", "checkout", "self checkout", "self-checkout", "cashiers"]),
        Entry(name: "Digital (OPD)", aliases: ["opd", "digital", "online pickup", "pickup", "delivery", "online orders", "ogp"]),
        Entry(name: "Asset Protection", aliases: ["asset protection", "ap", "shrink"]),
        Entry(name: "Auto Care Center (ACC)", aliases: ["acc", "auto care", "auto care center", "auto center", "tire center", "automotive", "oil change"]),
        // Departments within areas.
        Entry(name: "Dairy", aliases: ["dairy"]),
        Entry(name: "Frozen", aliases: ["frozen", "freezers"]),
        Entry(name: "Produce", aliases: ["produce"]),
        Entry(name: "Meat", aliases: ["meat", "meat and seafood", "seafood"]),
        Entry(name: "Deli", aliases: ["deli"]),
        Entry(name: "Bakery", aliases: ["bakery"]),
        Entry(name: "Grocery", aliases: ["grocery", "dry grocery", "groceries"]),
        Entry(name: "Health & Beauty", aliases: ["health and beauty", "health & beauty", "hba", "cosmetics"]),
        Entry(name: "Pharmacy", aliases: ["pharmacy"]),
        Entry(name: "Electronics", aliases: ["electronics", "wireless"]),
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
        Entry(name: "Backroom & Receiving", aliases: ["backroom", "back room", "receiving", "dock", "loading dock"]),
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
        let lower = text.lowercased()
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
        return best?.name
    }
}
