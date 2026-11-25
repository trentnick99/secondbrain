import Foundation

/// An active alert from the National Weather Service (api.weather.gov). NWS text is public domain.
public struct WeatherAlert: Identifiable, Equatable, Codable, Sendable {
    public let id: String
    public let event: String
    public let headline: String
    public let severity: String
    public let urgency: String
    public let areaDescription: String
    public let instruction: String?
    public let details: String?
    public let sender: String?
    public let onset: Date?
    public let ends: Date?

    public init(id: String, event: String, headline: String, severity: String, urgency: String = "Immediate",
                areaDescription: String = "", instruction: String? = nil, details: String? = nil,
                sender: String? = nil, onset: Date? = nil, ends: Date? = nil) {
        self.id = id
        self.event = event
        self.headline = headline
        self.severity = severity
        self.urgency = urgency
        self.areaDescription = areaDescription
        self.instruction = instruction
        self.details = details
        self.sender = sender
        self.onset = onset
        self.ends = ends
    }

    /// Warnings and Severe/Extreme alerts: the ones worth interrupting a shift for.
    public var isImportant: Bool {
        severity == "Extreme" || severity == "Severe" || event.hasSuffix("Warning")
    }

    var rank: Int {
        switch severity {
        case "Extreme": return 0
        case "Severe": return 1
        case "Moderate": return 2
        case "Minor": return 3
        default: return 4
        }
    }
}

public enum WeatherAlerts {
    public static let userAgent = "CoachSpark/1.0 (github.com/trentnick99/secondbrain)"
    public static let moreInfoURL = URL(string: "https://www.weather.gov")!

    /// Active alerts for a point. Coordinates are rounded to about 100 m; nothing else is sent.
    public static func url(latitude: Double, longitude: Double) -> URL? {
        URL(string: String(format: "https://api.weather.gov/alerts/active?point=%.3f,%.3f", latitude, longitude))
    }

    private struct Response: Decodable {
        struct Feature: Decodable { let properties: Properties }
        struct Properties: Decodable {
            let id: String?
            let event: String?
            let headline: String?
            let severity: String?
            let urgency: String?
            let areaDesc: String?
            let instruction: String?
            let description: String?
            let senderName: String?
            let onset: String?
            let ends: String?
            let expires: String?
            let status: String?
            let messageType: String?
        }
        let features: [Feature]
    }

    /// Parses NWS GeoJSON. Test messages and cancellations are dropped; the most severe come first.
    public static func parse(_ data: Data) throws -> [WeatherAlert] {
        let response = try JSONDecoder().decode(Response.self, from: data)
        let alerts: [WeatherAlert] = response.features.compactMap { feature in
            let p = feature.properties
            guard let id = p.id, let event = p.event, p.status ?? "Actual" == "Actual", p.messageType != "Cancel" else { return nil }
            return WeatherAlert(id: id, event: event, headline: p.headline ?? event, severity: p.severity ?? "Unknown",
                                urgency: p.urgency ?? "Unknown", areaDescription: p.areaDesc ?? "",
                                instruction: clean(p.instruction), details: clean(p.description), sender: p.senderName,
                                onset: date(p.onset), ends: date(p.ends) ?? date(p.expires))
        }
        return sorted(alerts)
    }

    public static func sorted(_ alerts: [WeatherAlert]) -> [WeatherAlert] {
        alerts.sorted { a, b in
            if a.rank != b.rank { return a.rank < b.rank }
            if a.event.hasSuffix("Warning") != b.event.hasSuffix("Warning") { return a.event.hasSuffix("Warning") }
            return (a.ends ?? .distantFuture) < (b.ends ?? .distantFuture)
        }
    }

    /// Important alerts that haven't ended yet.
    public static func current(_ alerts: [WeatherAlert], now: Date) -> [WeatherAlert] {
        alerts.filter { $0.isImportant && ($0.ends.map { $0 > now } ?? true) }
    }

    /// "Tornado Warning until 4:45 PM".
    public static func title(_ alert: WeatherAlert, now: Date, calendar: Calendar) -> String {
        guard let ends = alert.ends else { return alert.event }
        let sameDay = calendar.isDate(ends, inSameDayAs: now)
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = sameDay ? "h:mm a" : "EEE h:mm a"
        return "\(alert.event) until \(formatter.string(from: ends))"
    }

    static func date(_ text: String?) -> Date? {
        guard let text else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }

    static func clean(_ text: String?) -> String? {
        guard let text else { return nil }
        let joined = text.replacingOccurrences(of: #"(?<!\n)\n(?!\n)"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return joined.isEmpty ? nil : joined
    }
}
