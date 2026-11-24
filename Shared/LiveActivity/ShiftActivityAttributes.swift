import ActivityKit
import Foundation

/// Today's shift on the Lock Screen and in the Dynamic Island: time left, progress, and the top three.
/// Shared by the app (which starts and updates it) and the widget extension (which draws it).
struct ShiftActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var priorities: [String]
        var done: Int
        var total: Int
        var overdue: Int
    }

    var shiftLabel: String
    var start: Date
    var end: Date
}
