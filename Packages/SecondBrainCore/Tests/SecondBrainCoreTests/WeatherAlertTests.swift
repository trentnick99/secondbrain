import XCTest
@testable import SecondBrainCore

final class WeatherAlertTests: XCTestCase {
    private let sample = """
    {"type":"FeatureCollection","features":[
      {"properties":{"id":"urn:a1","event":"Wind Advisory","headline":"Wind Advisory issued","severity":"Moderate",
        "urgency":"Expected","areaDesc":"Benton, AR","status":"Actual","messageType":"Alert",
        "onset":"2026-11-24T12:00:00-06:00","ends":"2026-11-24T21:00:00-06:00"}},
      {"properties":{"id":"urn:a2","event":"Tornado Warning","headline":"Tornado Warning issued November 24",
        "severity":"Extreme","urgency":"Immediate","areaDesc":"Benton, AR","status":"Actual","messageType":"Alert",
        "instruction":"TAKE COVER NOW!\\nMove to a basement or an interior room\\non the lowest floor.",
        "senderName":"NWS Tulsa OK","onset":"2026-11-24T15:30:00-06:00","ends":null,"expires":"2026-11-24T16:45:00-06:00"}},
      {"properties":{"id":"urn:a3","event":"Test Message","severity":"Unknown","status":"Test","messageType":"Alert"}},
      {"properties":{"id":"urn:a4","event":"Severe Thunderstorm Warning","severity":"Severe","status":"Actual","messageType":"Cancel"}}
    ]}
    """

    func testParsesAndRanksAlerts() throws {
        let alerts = try WeatherAlerts.parse(Data(sample.utf8))
        XCTAssertEqual(alerts.map(\.event), ["Tornado Warning", "Wind Advisory"], "Tests and cancellations are dropped; worst first")
        let tornado = alerts[0]
        XCTAssertTrue(tornado.isImportant)
        XCTAssertFalse(alerts[1].isImportant, "A moderate advisory doesn't interrupt a shift")
        XCTAssertEqual(tornado.instruction, "TAKE COVER NOW! Move to a basement or an interior room on the lowest floor.")
        XCTAssertNotNil(tornado.ends, "Falls back to the expiry time")
    }

    func testCurrentAlertsAndTitles() throws {
        let alerts = try WeatherAlerts.parse(Data(sample.utf8))
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/Chicago")!
        let at3 = WeatherAlerts.date("2026-11-24T15:00:00-06:00")!
        let at5 = WeatherAlerts.date("2026-11-24T17:00:00-06:00")!
        XCTAssertEqual(WeatherAlerts.current(alerts, now: at3).map(\.event), ["Tornado Warning"])
        XCTAssertTrue(WeatherAlerts.current(alerts, now: at5).isEmpty, "Expired alerts go away")
        XCTAssertEqual(WeatherAlerts.title(alerts[0], now: at3, calendar: cal), "Tornado Warning until 4:45 PM")
    }

    func testURLRoundsTheLocation() {
        XCTAssertEqual(WeatherAlerts.url(latitude: 36.372854, longitude: -94.208817)?.absoluteString,
                       "https://api.weather.gov/alerts/active?point=36.373,-94.209")
    }
}
