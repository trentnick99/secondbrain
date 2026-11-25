import Foundation

/// The App Group shared by the app and its widget extension.
///
/// The identifier comes from the `SBAppGroupIdentifier` Info.plist key, which is filled from the
/// `APP_GROUP_IDENTIFIER` build setting in `Config/Signing.xcconfig`. When the App Group capability
/// is not provisioned (for example, some free Apple ID signing setups), the app still works with
/// its own private container; only widgets lose access to live data.
enum AppGroup {
    static var identifier: String {
        if let value = Bundle.main.object(forInfoDictionaryKey: "SBAppGroupIdentifier") as? String,
           !value.isEmpty, !value.contains("$(") {
            return value
        }
        return "group.com.example.secondbrain"
    }

    /// Nil when the App Group entitlement is not available to this process.
    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }

    static var isAvailable: Bool { containerURL != nil }

    /// Settings shared between the app, widgets and App Intents.
    static let defaults: UserDefaults = {
        if isAvailable, let shared = UserDefaults(suiteName: identifier) { return shared }
        return .standard
    }()

    /// True inside the widget extension process.
    static var isRunningInExtension: Bool {
        Bundle.main.bundlePath.hasSuffix(".appex")
    }
}

/// URLs used by widgets, notifications and Siri to open specific screens.
enum DeepLink {
    static let scheme = "secondbrain"

    static func url(_ path: String) -> URL {
        URL(string: "\(scheme)://\(path)") ?? URL(string: "\(scheme)://home")!
    }

    static var home: URL { url("home") }
    static var capture: URL { url("capture") }
    static var floorWalk: URL { url("walk") }
    static var walkNotes: URL { url("walknotes") }
    static var tasks: URL { url("tasks") }
    static var matrix: URL { url("matrix") }
    static var associates: URL { url("associates") }
    static var notes: URL { url("notes") }
    static var shift: URL { url("shift") }
    static var planner: URL { url("planner") }
    static var overdue: URL { url("overdue") }

    static func task(_ id: UUID) -> URL { url("task/\(id.uuidString)") }

    static func terms(_ query: String? = nil) -> URL {
        var components = URLComponents()
        components.scheme = scheme
        components.host = "terms"
        if let query, !query.isEmpty { components.queryItems = [URLQueryItem(name: "q", value: query)] }
        return components.url ?? url("terms")
    }
}
