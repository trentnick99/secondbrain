import XCTest
@testable import SecondBrainCore

final class StandardsTests: XCTestCase {
    func testBuiltInTemperaturesMatchThePublicRules() {
        let temps = Standards.foodTemperatures
        let values = Dictionary(uniqueKeysWithValues: temps.entries.map { ($0.name, $0.value) })
        XCTAssertEqual(values["Refrigerated food (cold holding)"], "41°F or colder")
        XCTAssertEqual(values["Hot food (hot holding)"], "135°F or hotter")
        XCTAssertEqual(values["Frozen food"], "0°F or colder")
        XCTAssertTrue(values["Shell eggs"]?.contains("45°F") == true)
        XCTAssertTrue(values["Cooling cooked food"]?.contains("2 hours") == true)
        XCTAssertFalse(temps.sources.isEmpty)
        for source in Standards.references.flatMap(\.sources) {
            XCTAssertTrue(source.url.hasPrefix("https://"), source.url)
        }
        XCTAssertEqual(Set(Standards.references.map(\.id)).count, Standards.references.count)
    }

    func testProcessesAreTheFloorAndSafetyGuides() {
        let ids = Standards.processes.map(\.id)
        XCTAssertEqual(ids.count, Standards.processIDs.count, "Every process id has a guide")
        XCTAssertTrue(ids.contains("freezer-door"))
        XCTAssertTrue(ids.contains("frozen-truck"))
        XCTAssertTrue(ids.contains("spill"))
        XCTAssertFalse(ids.contains("conflict"), "People scenarios aren't in Standards")
        XCTAssertFalse(ids.contains("upset-customer"))
        XCTAssertFalse(ids.contains("ethics"))
    }

    func testFilterFindsWordsAtTheStartOfWords() {
        let temps = Standards.searchText(Standards.foodTemperatures)
        XCTAssertTrue(Standards.matches("egg", in: temps))
        XCTAssertTrue(Standards.matches("temp", in: temps))
        XCTAssertTrue(Standards.matches("frozen 0", in: temps))
        XCTAssertTrue(Standards.matches("41", in: temps))
        XCTAssertFalse(Standards.matches("baler", in: temps))
        XCTAssertTrue(Standards.matches("", in: temps), "An empty search shows everything")

        let door = CoachGuides.guide(id: "freezer-door")!
        XCTAssertTrue(Standards.matches("freezer door", in: Standards.searchText(door)))
        XCTAssertFalse(Standards.matches("door", in: "Outdoor living"), "Only the start of a word counts")
    }

    func testPreviewShowsMatchingLines() {
        let lines = ["Milk · 41°F", "Ice cream · -10°F", "Eggs · 45°F"]
        XCTAssertEqual(Standards.preview(lines, for: "ice"), ["Ice cream · -10°F"])
        XCTAssertEqual(Standards.preview(lines, for: "", limit: 2), ["Milk · 41°F", "Ice cream · -10°F"])
    }

    func testCleanedListDropsEmptyLinesAndValuesOnProcesses() {
        var list = StandardList(title: "  Cooler checks ", kind: .temperatures, items: [
            StandardItem(name: " Ice cream ", value: " -10°F "),
            StandardItem(name: "   ", value: "41°F")
        ])
        XCTAssertTrue(list.isValid)
        let cleaned = list.cleaned
        XCTAssertEqual(cleaned.title, "Cooler checks")
        XCTAssertEqual(cleaned.items.map(\.name), ["Ice cream"])
        XCTAssertEqual(cleaned.items.first?.value, "-10°F")

        list.kind = .process
        XCTAssertEqual(list.cleaned.items.first?.value, "", "Process steps have no values")

        XCTAssertFalse(StandardList(title: "Empty", items: [StandardItem(name: " ")]).isValid)
        XCTAssertFalse(StandardList(title: " ", items: [StandardItem(name: "Milk")]).isValid)
    }

    func testOldGuidesBecomeProcessListsOnce() {
        let guide = CustomGuide(title: "Baler won't start", category: .operations,
                                steps: ["Check the key switch", " ", "Call maintenance"], checkWith: "Manager on duty")
        let lists = Standards.migrate([guide, CustomGuide(title: "", steps: [])], into: [])
        XCTAssertEqual(lists.count, 1, "Incomplete guides are skipped")
        XCTAssertEqual(lists[0].id, guide.id)
        XCTAssertEqual(lists[0].kind, .process)
        XCTAssertEqual(lists[0].items.map(\.name), ["Check the key switch", "Call maintenance"])
        XCTAssertEqual(lists[0].note, "Manager on duty")
        XCTAssertEqual(Standards.migrate([guide], into: lists).count, 1, "Already kept, not added twice")
    }

    func testListsSurviveJSON() throws {
        let list = StandardList(title: "Deli temps", kind: .temperatures,
                                items: [StandardItem(name: "Hot case", value: "135°F or hotter")], note: "Posted in deli")
        let data = try JSONEncoder().encode([list])
        XCTAssertEqual(try JSONDecoder().decode([StandardList].self, from: data), [list])
    }

    func testShareTextIsPlainAndComplete() {
        let temps = StandardList(title: "Cooler temps", kind: .temperatures,
                                 items: [StandardItem(name: "Ice cream", value: "-10°F or colder"), StandardItem(name: "Milk")],
                                 note: "Posted on the cooler door")
        XCTAssertEqual(Standards.shareText(temps), "Cooler temps\n• Ice cream: -10°F or colder\n• Milk\nPosted on the cooler door")
        let process = StandardList(title: "Baler", kind: .process, items: [StandardItem(name: "Check the e-stop"), StandardItem(name: "Call facilities")])
        XCTAssertEqual(Standards.shareText(process), "Baler\n1. Check the e-stop\n2. Call facilities")
        let food = Standards.shareText(Standards.foodTemperatures)
        XCTAssertTrue(food.contains("Shell eggs: Stored and displayed at 45°F or colder"))
        XCTAssertTrue(food.contains("FDA Food Code"))
        XCTAssertTrue(food.hasSuffix(Standards.disclaimer))
        let door = Standards.shareText(CoachGuides.guide(id: "freezer-door")!)
        XCTAssertTrue(door.hasPrefix("Freezer or cooler door won't open on its own\n1. "))
    }
}
