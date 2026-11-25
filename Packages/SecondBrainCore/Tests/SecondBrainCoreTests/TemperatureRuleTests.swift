import XCTest
@testable import SecondBrainCore

final class TemperatureRuleTests: XCTestCase {
    func testReadsTheCommonWaysStandardsAreWritten() {
        XCTAssertEqual(TemperatureRule.parse("41°F or colder"), TemperatureRule(maximum: 41))
        XCTAssertEqual(TemperatureRule.parse("0°F or colder"), TemperatureRule(maximum: 0))
        XCTAssertEqual(TemperatureRule.parse("-10 F or colder"), TemperatureRule(maximum: -10))
        XCTAssertEqual(TemperatureRule.parse("−10°F or below"), TemperatureRule(maximum: -10))
        XCTAssertEqual(TemperatureRule.parse("Max 38°F"), TemperatureRule(maximum: 38))
        XCTAssertEqual(TemperatureRule.parse("≤ 41°F"), TemperatureRule(maximum: 41))
        XCTAssertEqual(TemperatureRule.parse("135°F or hotter"), TemperatureRule(minimum: 135))
        XCTAssertEqual(TemperatureRule.parse("at least 140"), TemperatureRule(minimum: 140))
        XCTAssertEqual(TemperatureRule.parse("Between 33°F and 41°F"), TemperatureRule(minimum: 33, maximum: 41))
        XCTAssertEqual(TemperatureRule.parse("33-38°F"), TemperatureRule(minimum: 33, maximum: 38))
        XCTAssertEqual(TemperatureRule.parse("33 – 38 °F"), TemperatureRule(minimum: 33, maximum: 38))
        XCTAssertEqual(TemperatureRule.parse("between -5 and 0"), TemperatureRule(minimum: -5, maximum: 0))
        XCTAssertEqual(TemperatureRule.parse("Stored and displayed at 45°F or colder (air temperature)"), TemperatureRule(maximum: 45))
    }

    func testUnclearWordsGiveNoRule() {
        XCTAssertNil(TemperatureRule.parse("Keep it cold"))
        XCTAssertNil(TemperatureRule.parse("41°F"), "A bare number isn't a limit")
        XCTAssertNil(TemperatureRule.parse("Pull anything past its date"))
    }

    func testReadingsAndLimits() {
        let frozen = TemperatureRule(maximum: -10)
        XCTAssertTrue(frozen.allows(-12))
        XCTAssertTrue(frozen.allows(-10))
        XCTAssertFalse(frozen.allows(5))
        let cooler = TemperatureRule(minimum: 33, maximum: 41)
        XCTAssertFalse(cooler.allows(30))
        XCTAssertTrue(cooler.allows(38.5))
        XCTAssertEqual(TemperatureRule.reading(from: "5°"), 5)
        XCTAssertEqual(TemperatureRule.reading(from: "-12 F"), -12)
        XCTAssertEqual(TemperatureRule.reading(from: "38.5"), 38.5)
        XCTAssertNil(TemperatureRule.reading(from: "cold"))
        XCTAssertEqual(frozen.summary, "-10°F or colder")
        XCTAssertEqual(TemperatureRule(minimum: 135).summary, "135°F or hotter")
        XCTAssertEqual(cooler.summary, "33–41°F")
    }
}
