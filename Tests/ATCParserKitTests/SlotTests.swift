//
//  SlotTests.swift
//  ATCParserKit
//
//  Slot resolution (which kind a placeholder is) and slot values (parsing and
//  reading back). The overloaded [NUMBER] cases are the reason resolution is
//  contextual at all, so they get explicit coverage against the real payload.
//

import XCTest
@testable import ATCParserKit

final class SlotTests: XCTestCase {

    private let registry = SlotRegistry.default
    private var set: TemplateSet!

    override func setUpWithError() throws {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: "templates",
                              withExtension: "json",
                              subdirectory: "Fixtures"))
        set = try TemplateSet(data: Data(contentsOf: url))
    }

    // MARK: - Contextual resolution

    func testNumberBesideKnotsIsASpeed() throws {
        let template = try XCTUnwrap(set.template(id: "344"))   // MAINTAIN [NUMBER] KNOTS
        let slots = registry.resolve(template.pattern)
        XCTAssertEqual(slots.map(\.kind), [.callsign, .speedKnots])
    }

    func testNumberAfterRunwayIsARunway() throws {
        let template = try XCTUnwrap(set.template(id: "454"))   // … RUNWAY [NUMBER]
        let slots = registry.resolve(template.pattern)
        XCTAssertEqual(slots.map(\.kind), [.callsign, .runway])
    }

    func testTheSamePlaceholderResolvesDifferentlyPerTemplate() throws {
        // This is the whole point of context rules — one name, two ranges.
        let speed = try XCTUnwrap(set.template(id: "361"))      // REDUCE SPEED TO [NUMBER] KNOTS
        let runway = try XCTUnwrap(set.template(id: "436"))     // RUNWAY [NUMBER] CLEARED FOR TAKEOFF
        XCTAssertEqual(registry.resolve(speed.pattern).last?.kind, .speedKnots)
        XCTAssertEqual(registry.resolve(runway.pattern)[1].kind, .runway)
    }

    func testEveryPayloadSlotResolvesToSomethingUsable() {
        for template in set.templates {
            for slot in registry.resolve(template.pattern) {
                // freeText is the fallback; flag it only for names we should
                // have classified, so a new backend placeholder is visible.
                if slot.kind == .freeText {
                    XCTAssertNotNil(registry.kinds[slot.name],
                                    "[\(template.id)] unclassified slot \(slot.name)")
                }
            }
        }
    }

    func testRepeatedSlotsAreResolvedPositionally() throws {
        let template = try XCTUnwrap(set.template(id: "103"))   // BLOCK FL [LEVEL] TO FL [LEVEL]
        let slots = registry.resolve(template.pattern)
        XCTAssertEqual(slots.map(\.name), ["CALLSIGN", "LEVEL", "LEVEL"])
        XCTAssertEqual(Set(slots.map(\.tokenIndex)).count, 3)
    }

    func testStateDerivedSlotsAreFlagged() throws {
        let template = try XCTUnwrap(set.template(id: "430"))   // CONFIRM [LEVEL]
        let readbackSlots = registry.resolve(template.readback)
        let actual = try XCTUnwrap(readbackSlots.first { $0.name == "ACTUAL LEVEL" })
        XCTAssertTrue(actual.isStateDerived)
        XCTAssertFalse(readbackSlots.first { $0.name == "LEVEL" }!.isStateDerived)
    }

    // MARK: - Numeric values

    func testFlightLevelInRange() {
        XCTAssertEqual(SlotValue.parse(["260"], as: .flightLevel), .ok(.integer(260)))
    }

    func testOutOfRangeIsReportedNotDropped() {
        // A rejected value can be explained to the controller; a dropped one
        // just looks like the command vanished.
        XCTAssertEqual(SlotValue.parse(["450"], as: .heading), .outOfRange(.integer(450)))
        XCTAssertEqual(SlotValue.parse(["900"], as: .flightLevel), .outOfRange(.integer(900)))
        XCTAssertEqual(SlotValue.parse(["40"], as: .speedKnots), .outOfRange(.integer(40)))
    }

    func testUnparsedWhenThereIsNoNumber() {
        XCTAssertEqual(SlotValue.parse(["banana"], as: .flightLevel), .unparsed)
        XCTAssertEqual(SlotValue.parse([], as: .flightLevel), .unparsed)
    }

    // MARK: - Fixed-width recovery

    func testHomophoneRecoveryOnAShortHeading() {
        // "heading to seven zero" — the recogniser wrote "to" for two. Without
        // recovery this is heading 070, a 200° error.
        XCTAssertEqual(SlotValue.parse(["to", "70"], as: .heading), .ok(.integer(270)))
        // Recovery reaches the right width but the value is still illegal —
        // reported, not silently accepted.
        XCTAssertEqual(SlotValue.parse(["for", "50"], as: .heading),
                       .outOfRange(.integer(450)))
    }

    func testHomophoneIsNotUsedWhenTheWidthIsAlreadyRight() {
        // "270" is already three digits, so a nearby "to" must be ignored.
        XCTAssertEqual(SlotValue.parse(["to", "270"], as: .heading), .ok(.integer(270)))
    }

    func testNonFixedWidthSlotsNeverUseHomophones() {
        // [LEVEL] has no fixed width, so "to" stays a preposition.
        XCTAssertEqual(SlotValue.parse(["to", "260"], as: .flightLevel), .ok(.integer(260)))
    }

    // MARK: - Runway

    func testRunwayWithSideSuffix() {
        XCTAssertEqual(SlotValue.parse(["27", "left"], as: .runway), .ok(.runway("27L")))
        XCTAssertEqual(SlotValue.parse(["09", "right"], as: .runway), .ok(.runway("09R")))
        XCTAssertEqual(SlotValue.parse(["27", "centre"], as: .runway), .ok(.runway("27C")))
    }

    func testRunwayIsPaddedToTwoDigits() {
        XCTAssertEqual(SlotValue.parse(["7"], as: .runway), .ok(.runway("07")))
    }

    func testRunwayOutOfRange() {
        XCTAssertEqual(SlotValue.parse(["40"], as: .runway), .outOfRange(.runway("40")))
    }

    // MARK: - Squawk

    func testSquawkMustBeFourOctalDigits() {
        XCTAssertEqual(SlotValue.parse(["4567"], as: .squawk), .ok(.integer(4567)))
        // 8 and 9 are not octal digits — a real mis-hearing, worth rejecting.
        XCTAssertEqual(SlotValue.parse(["4589"], as: .squawk), .outOfRange(.integer(4589)))
        XCTAssertEqual(SlotValue.parse(["456"], as: .squawk), .outOfRange(.integer(456)))
    }

    // MARK: - Fix

    func testPhoneticFixIsFolded() {
        XCTAssertEqual(SlotValue.parse(["papa", "juliet"], as: .fix), .ok(.fix("PJ")))
        XCTAssertEqual(SlotValue.parse(["romeo", "echo", "01"], as: .fix), .ok(.fix("RE01")))
    }

    func testNamedFixIsKeptWhole() {
        XCTAssertEqual(SlotValue.parse(["clink"], as: .fix), .ok(.fix("CLINK")))
    }

    // MARK: - Frequency

    func testFrequency() {
        XCTAssertEqual(SlotValue.parse(["121", "decimal", "5"], as: .frequency),
                       .ok(.frequency("121.5")))
        XCTAssertEqual(SlotValue.parse(["121", "point", "5"], as: .frequency),
                       .ok(.frequency("121.5")))
    }

    // MARK: - Free text

    func testFreeTextIsCapturedVerbatim() {
        XCTAssertEqual(SlotValue.parse(["radar", "failure"], as: .freeText),
                       .ok(.text("radar failure")))
    }

    // MARK: - Readback rendering

    func testLevelsAndHeadingsReadDigitByDigit() {
        XCTAssertEqual(SlotValue.integer(260).spoken(as: .flightLevel), "two six zero")
        XCTAssertEqual(SlotValue.integer(90).spoken(as: .heading), "zero niner zero")
        XCTAssertEqual(SlotValue.integer(300).spoken(as: .speedKnots), "tree zero zero")
    }

    func testAltitudesReadByMagnitude() {
        XCTAssertEqual(SlotValue.integer(8000).spoken(as: .altitudeFeet), "eight thousand")
    }

    func testRunwayReadsWithItsSide() {
        XCTAssertEqual(SlotValue.runway("27L").spoken(as: .runway), "two seven left")
    }

    func testFixIsSpelledOut() {
        XCTAssertEqual(SlotValue.fix("PJ").spoken(as: .fix), "papa juliet")
        XCTAssertEqual(SlotValue.fix("RE01").spoken(as: .fix), "romeo echo zero one")
    }

    // MARK: - Lexicon

    func testAbbreviationGluedToItsValueIsSplitAndExpanded() {
        // Without this, "FL260" scores nothing against "FLIGHT LEVEL [LEVEL]".
        XCTAssertEqual(Lexicon.default.normalize(["fl260"]), ["flight", "level", "260"])
        XCTAssertEqual(Lexicon.default.normalize(["fl", "260"]), ["flight", "level", "260"])
    }

    func testCallsignIsNotSplit() {
        // "aca125" looks like an abbreviation glued to digits but is not one.
        XCTAssertEqual(Lexicon.default.normalize(["aca125"]), ["aca125"])
    }

    func testOtherAbbreviations() {
        XCTAssertEqual(Lexicon.default.normalize(["hdg", "270"]), ["heading", "270"])
        XCTAssertEqual(Lexicon.default.normalize(["rwy", "27"]), ["runway", "27"])
        XCTAssertEqual(Lexicon.default.normalize(["250", "kts"]), ["250", "knots"])
    }

    func testSpellingVariants() {
        XCTAssertEqual(Lexicon.default.normalize(["localiser"]), ["localizer"])
        XCTAssertEqual(Lexicon.default.normalize(["centre"]), ["center"])
    }

    func testContractionOnlyWhereTheTemplateIsOneToken() {
        XCTAssertEqual(Lexicon.default.normalize(["cleared", "for", "take", "off"]),
                       ["cleared", "for", "takeoff"])
        // Template 327 writes "GO AROUND" as two words, so it must stay two.
        XCTAssertEqual(Lexicon.default.normalize(["go", "around"]), ["go", "around"])
    }
}
