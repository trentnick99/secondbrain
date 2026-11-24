import XCTest
@testable import SecondBrainCore

final class CoachGuideTests: XCTestCase {
    func testEveryGuideIsComplete() {
        XCTAssertGreaterThanOrEqual(CoachGuides.all.count, 20)
        XCTAssertEqual(Set(CoachGuides.all.map(\.id)).count, CoachGuides.all.count, "Guide ids are unique")
        for guide in CoachGuides.all {
            XCTAssertFalse(guide.summary.isEmpty, guide.id)
            XCTAssertGreaterThanOrEqual(guide.steps.count, 3, guide.id)
            XCTAssertFalse(guide.keywords.isEmpty, guide.id)
            for source in guide.sources {
                XCTAssertTrue(source.url.hasPrefix("https://"), source.url)
            }
        }
        for category in CoachGuide.Category.allCases {
            XCTAssertTrue(CoachGuides.all.contains { $0.category == category }, "\(category) has guides")
        }
    }

    func testSafetyGuidesNeverSendSomeoneAfterAShoplifter() {
        let theft = CoachGuides.guide(id: "theft")!
        XCTAssertTrue(theft.steps.joined().contains("Don't chase"))
        XCTAssertNotNil(theft.checkWith)
    }

    func testSearchFindsTheRightGuide() {
        XCTAssertEqual(CoachGuides.search("We're short staffed tonight, two call outs").first?.id, "short-staffed")
        XCTAssertEqual(CoachGuides.search("what do I do about a spill in aisle 5").first?.id, "spill")
        XCTAssertEqual(CoachGuides.search("fire exit blocked by pallets").first?.id, "blocked-exit")
        XCTAssertEqual(CoachGuides.search("Black Friday crowd at the doors").first?.id, "crowd")
        XCTAssertEqual(CoachGuides.search("how do I give feedback to a slow associate").first?.id, "feedback")
        XCTAssertEqual(CoachGuides.search("customer wants a price match").first?.id, "price-match")
        XCTAssertEqual(CoachGuides.search("my team lead keeps missing deadlines").first?.id, "follow-through")
        XCTAssertEqual(CoachGuides.search("recalled lettuce on the shelf").first?.id, "recall")
        XCTAssertEqual(CoachGuides.search("prep for market manager visit tomorrow").first?.id, "market-walk")
        XCTAssertEqual(CoachGuides.search("associate keeps showing up late").first?.id, "attendance")
        XCTAssertEqual(CoachGuides.search("employee crying in the breakroom").first?.id, "struggling")
        XCTAssertEqual(CoachGuides.search("what should I focus on today").first?.id, "plan-shift")
        XCTAssertEqual(CoachGuides.search("my store manager and market manager want different things").first?.id, "conflicting-priorities")
        let rush = CoachGuides.search("Short staffed tonight and freight is behind, what first?").map(\.id)
        XCTAssertEqual(Set(rush.prefix(2)), ["short-staffed", "freight-behind"])
        XCTAssertFalse(rush.contains("new-associate"), "“what first?” isn't about a first week")
        XCTAssertEqual(CoachGuides.search("new associate first week").first?.id, "new-associate")
        XCTAssertTrue(CoachGuides.search("zzzz qqqq").isEmpty)
        XCTAssertTrue(CoachGuides.search("").isEmpty)
    }

    func testSuggestedGuidesFitTheRole() {
        let stocking = CoachGuides.suggested(for: UserRole(role: .coach, areas: ["Stocking"]))
        XCTAssertEqual(stocking.first?.id, "freight-behind")
        XCTAssertLessThanOrEqual(stocking.count, 6)
        XCTAssertEqual(CoachGuides.suggested(for: UserRole(role: .coach, areas: ["Fresh"])).first?.id, "recall")
        XCTAssertFalse(CoachGuides.suggested(for: nil).isEmpty)
    }
}

final class AskAssistantTests: XCTestCase {
    func testEmergencyWordsShowTheNotice() {
        XCTAssertNotNil(AskAssistant.emergency(in: "A customer collapsed by the pharmacy"))
        XCTAssertNotNil(AskAssistant.emergency(in: "someone has a knife in electronics"))
        XCTAssertNotNil(AskAssistant.emergency(in: "There's smoke in the backroom"))
        XCTAssertNil(AskAssistant.emergency(in: "fire exit blocked by pallets"), "A blocked fire exit isn't an emergency call")
        XCTAssertNil(AskAssistant.emergency(in: "how do I run a better huddle"))
        XCTAssertNil(AskAssistant.emergency(in: "knifes and gunsmith"), "Whole words only")
    }

    func testSearchLinks() {
        let reddit = AskAssistant.redditSearchURL("short staffed on truck day")!.absoluteString
        XCTAssertTrue(reddit.hasPrefix("https://www.reddit.com/r/walmart/search/?q=short%20staffed%20on%20truck%20day"), reddit)
        XCTAssertTrue(reddit.contains("restrict_sr=1"))
        XCTAssertEqual(AskAssistant.webSearchURL("price match")?.absoluteString, "https://www.google.com/search?q=price%20match")
    }

    func testPromptUsesGuidesAndStaysShort() {
        let guides = CoachGuides.search("short staffed and freight is behind")
        let prompt = AskAssistant.prompt(question: "Short staffed and freight is behind, what first?", guides: guides,
                                         storeSteps: ["short-staffed": "Text the SM before 9."])
        XCTAssertTrue(prompt.contains("Short-staffed for the shift"))
        XCTAssertTrue(prompt.contains("Text the SM before 9."))
        XCTAssertLessThan(prompt.count, 3_200, "Fits the on-device model's context window")
        let none = AskAssistant.prompt(question: "zzzz", guides: [])
        XCTAssertTrue(none.contains("No reference guide matched"))
    }

    func testInstructionsNeverLetTheModelInventPolicy() {
        let text = AskAssistant.instructions(role: UserRole(role: .coach, areas: ["Food"]))
        XCTAssertTrue(text.contains("food coach") || text.contains("coach"), text)
        XCTAssertTrue(text.contains("never make them up"))
        XCTAssertTrue(text.contains("call 911"))
    }
}
