import Foundation

/// The person's own job: their role and the areas they run, primary area first.
/// Used to suggest routines, sort the Season Planner, show "My area" and route imported notes.
public struct UserRole: Codable, Hashable, Sendable {
    public var role: StoreRole
    public var areas: [String]

    public init(role: StoreRole, areas: [String] = []) {
        self.role = role
        self.areas = areas
    }

    public var primaryArea: String? { areas.first }

    /// The store manager sees the whole store, so nothing is ever "another area".
    public var seesWholeStore: Bool { role == .storeManager }

    /// "Food Coach", "Fresh Team Lead", "Store Manager".
    public var title: String {
        switch role {
        case .storeManager: return "Store Manager"
        case .coach, .teamLead:
            let area = primaryArea.map(StoreAreas.shortName) ?? ""
            return area.isEmpty ? role.title : "\(area) \(role.title)"
        case .associate:
            return primaryArea.map { "\(StoreAreas.shortName($0)) Associate" } ?? "Associate"
        }
    }

    /// "Food + Paper & Chemical" — what "My area" covers.
    public var areasSummary: String {
        seesWholeStore ? "Whole store" : (areas.isEmpty ? "No area chosen" : areas.map(StoreAreas.shortName).joined(separator: " + "))
    }

    /// True when an area or department name falls under this person's areas ("Dairy" for a Food coach).
    public func covers(_ name: String?) -> Bool {
        guard let name, !name.isEmpty else { return false }
        if seesWholeStore { return true }
        if areas.contains(name) { return true }
        if let parent = StoreAreas.area(for: name), areas.contains(parent) { return true }
        return false
    }

    /// Where something tagged with these areas belongs for this person.
    public func relevance(of names: [String], isTotalStore: Bool) -> AreaRelevance {
        if isTotalStore || names.contains(StoreAreas.totalStore) { return .totalStore }
        if names.isEmpty { return .unassigned }
        if names.contains(where: covers) { return .mine }
        return .other
    }
}

public enum AreaRelevance: String, Sendable, CaseIterable {
    case mine, totalStore, unassigned, other

    public var title: String {
        switch self {
        case .mine: return "For you"
        case .totalStore: return "Total store"
        case .unassigned: return "No area mentioned"
        case .other: return "Other areas"
        }
    }
}

public extension StoreAreas {
    static let totalStore = "Total Store"

    /// General-merchandise and other departments a coach might also cover (for example a stocking coach
    /// who owns seasonal and electronics freight). Offered as extra areas in the role picker.
    static let otherDepartments: [String] = [
        "Seasonal", "Electronics", "Toys", "Home", "Hardware", "Sporting Goods", "Lawn & Garden",
        "Crafts & Stationery", "Paper & Chemical", "Health & Beauty", "Pets", "Infants", "Jewelry",
        "Backroom & Receiving", "Pharmacy", "Vision Center"
    ]

    /// The area that runs a department, for the clear-cut cases. Departments that vary by store
    /// (electronics, toys, home…) return nil; people add those to their own areas if they cover them.
    static func area(for name: String) -> String? {
        if all.contains(name) { return name }
        switch name {
        case "Produce", "Meat", "Deli", "Bakery": return "Fresh"
        case "Grocery", "Dairy", "Frozen", "Paper & Chemical", "Pets", "Health & Beauty", "Infants": return "Food"
        case "Jewelry": return "Fashion"
        case "Customer Service": return "Front End"
        case "Backroom & Receiving": return "Stocking"
        default: return nil
        }
    }

    /// "Digital (OPD)" → "Digital", "Auto Care Center (ACC)" → "ACC", "Asset Protection" → "AP".
    static func shortName(_ area: String) -> String {
        switch area {
        case "Digital (OPD)": return "Digital"
        case "Auto Care Center (ACC)": return "ACC"
        case "Asset Protection": return "AP"
        default: return area
        }
    }
}
