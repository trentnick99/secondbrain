import Foundation

/// A routine someone in a role commonly repeats, offered as a suggestion to add with a tap.
public struct RoutineSuggestion: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let recurrence: RecurrenceRule
    public let category: TaskCategory
    public let area: String?

    /// "Every day", "Every Saturday".
    public var scheduleText: String {
        switch recurrence.frequency {
        case .daily: return "Every day"
        case .weekly:
            let symbols = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
            let names = recurrence.weekdays.map { symbols[($0 - 1) % 7] }
            return names.isEmpty ? "Every week" : "Every " + names.joined(separator: ", ")
        case .monthly: return "Every month"
        }
    }
}

/// Common routines by role and area. These are typical retail practices to start from, not company
/// standards — people add only what fits their store.
public enum RolePlaybook {
    public static let disclaimer = "Common routines for this role. Add the ones that fit your store; you can change or remove them any time."

    public static func suggestions(for role: UserRole) -> [RoutineSuggestion] {
        var list: [RoutineSuggestion] = []
        func add(_ id: String, _ title: String, _ rule: RecurrenceRule, _ category: TaskCategory, area: String? = nil) {
            list.append(RoutineSuggestion(id: id, title: title, recurrence: rule, category: category, area: area))
        }
        let daily = RecurrenceRule(frequency: .daily)
        let saturday = RecurrenceRule.weekly(on: [7])
        let monday = RecurrenceRule.weekly(on: [2])
        let wednesday = RecurrenceRule.weekly(on: [4])
        let thursday = RecurrenceRule.weekly(on: [5])

        switch role.role {
        case .storeManager:
            add("sm.walk", "Store walk with the MOD", daily, .operations)
            add("sm.huddle", "Morning huddle with coaches", daily, .meeting)
            add("sm.review", "Business review with coaches (week starts Saturday)", saturday, .admin)
            add("sm.oneonones", "One-on-ones with coaches", wednesday, .people)
            add("sm.safety", "Total-store safety walk", monday, .safety)
            return list
        case .coach:
            add("coach.huddle", "Start-of-shift huddle with your team leads", daily, .meeting)
            add("coach.walk", "Walk your areas for safety, outs and conditions", daily, .safety)
            add("coach.numbers", "Review last week's numbers for your area (week starts Saturday)", saturday, .admin)
            add("coach.oneonones", "One-on-ones with your team leads", wednesday, .people)
        case .teamLead:
            add("tl.assign", "Assign the team's tasks at the start of shift", daily, .people)
            add("tl.checkin", "Check in with your coach on priorities", daily, .meeting)
            add("tl.crosstrain", "Plan cross-training for the week", monday, .development)
        case .associate:
            break
        }

        for area in role.areas {
            switch area {
            case "Stocking":
                add("stock.flow", "Freight flow check: truck worked, pallets cleared, backroom clean", daily, .freight, area: area)
                add("stock.vizpick", "VizPick and topstock progress check", daily, .freight, area: area)
                add("stock.bins", "Bin audit and overstock verification", wednesday, .freight, area: area)
                add("stock.sets", "Check features and modulars for upcoming sets", thursday, .merchandising, area: area)
            case "Overnight":
                add("on.truck", "Truck plan: unload crew and freight by department", daily, .freight, area: area)
                add("on.ple", "PLE pre-use inspections done before freight", daily, .safety, area: area)
                add("on.handoff", "Hand-off notes for day stocking", daily, .operations, area: area)
                add("on.safety", "Safety walk of the backroom and steel", monday, .safety, area: area)
            case "Fresh":
                add("fresh.temps", "Temp logs complete", daily, .compliance, area: area)
                add("fresh.cull", "Culling and rotation in produce", daily, .merchandising, area: area)
                add("fresh.dates", "Date checks and markdowns", daily, .compliance, area: area)
                add("fresh.production", "Production plan for bakery and deli", monday, .operations, area: area)
            case "Food":
                add("food.outs", "Outs walk in grocery, dairy and frozen", daily, .merchandising, area: area)
                add("food.dates", "Date code checks and rotation", daily, .compliance, area: area)
                add("food.dsd", "DSD vendor check-ins", wednesday, .operations, area: area)
                add("food.features", "Feature and endcap sets for next week", thursday, .merchandising, area: area)
            case "Fashion":
                add("fashion.fitting", "Fitting room recovery and returns", daily, .merchandising, area: area)
                add("fashion.zone", "Zone recovery in apparel", daily, .merchandising, area: area)
                add("fashion.clearance", "Clearance and markdown review", monday, .merchandising, area: area)
                add("fashion.sets", "Modular and seasonal set check", thursday, .merchandising, area: area)
            case "Front End":
                add("fe.coverage", "Register and SCO coverage plan for the peaks", daily, .people, area: area)
                add("fe.cashoffice", "Cash office close check", daily, .operations, area: area)
                add("fe.schedule", "Front end schedule review for next week", thursday, .people, area: area)
                add("fe.experience", "Customer experience review: wait times and feedback", monday, .customer, area: area)
            case "Digital (OPD)":
                add("opd.picks", "Pick walks on track and staging ready", daily, .operations, area: area)
                add("opd.ftpr", "Review FTPR and nil picks", daily, .admin, area: area)
                add("opd.wait", "Dispense wait-time review", monday, .customer, area: area)
                add("opd.equipment", "Equipment check: carts, totes and coolers", wednesday, .operations, area: area)
            case "Asset Protection":
                add("ap.walk", "High-shrink and EAS walk", daily, .operations, area: area)
                add("ap.sweep", "Safety sweep", daily, .safety, area: area)
                add("ap.shrink", "Shrink and claims review", monday, .admin, area: area)
                add("ap.exits", "Emergency equipment and exits check", wednesday, .safety, area: area)
            case "Auto Care Center (ACC)":
                add("acc.bays", "Bay safety and equipment pre-use check", daily, .safety, area: area)
                add("acc.stock", "Tire and battery stock check", daily, .freight, area: area)
                add("acc.service", "Service wait times and appointments review", monday, .customer, area: area)
                add("acc.loto", "Lift inspections and LOTO log", wednesday, .safety, area: area)
            default:
                add("dept.\(area)", "Walk \(area) for outs, zoning and features", daily, .merchandising, area: area)
            }
        }
        return list
    }
}
