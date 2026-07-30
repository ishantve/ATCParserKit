//
//  ReadbackTests.swift
//  ATCParserKit
//
//  Readback rendering: prose splitting, slot filling, spoken numbers, and the
//  composed reply. The number tests matter most — the app today speaks
//  "heading two hundred fifty", which no controller would accept.
//

import XCTest
@testable import ATCParserKit

final class ReadbackTests: XCTestCase {

    private var set: TemplateSet!
    private var recognizer: CommandRecognizer!

    override func setUpWithError() throws {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: "templates",
                              withExtension: "json",
                              subdirectory: "Fixtures"))
        set = try TemplateSet(data: Data(contentsOf: url))
        recognizer = CommandRecognizer(templates: set)
    }

    private func first(_ text: String) throws -> RecognizedCommand {
        try XCTUnwrap(recognizer.recognize(text).commands.first)
    }

    // MARK: - Numbers are spoken as ATC speaks them

    func testLevelsAreReadDigitByDigit() throws {
        let command = try first("air india 123 descend to flight level 260")
        XCTAssertEqual(command.readback.text,
                       "RADAR DESCEND TO FLIGHT LEVEL two six zero, air india one two three.")
    }

    func testHeadingsKeepTheirLeadingZero() throws {
        let command = try first("air india 123 turn right heading 090")
        XCTAssertEqual(command.readback.text,
                       "RADAR TURN RIGHT HEADING zero nine zero, air india one two three.")
    }

    func testAltitudesAreReadByMagnitude() throws {
        let command = try first("air india 123 climb to eight thousand feet")
        XCTAssertEqual(command.readback.text,
                       "RADAR CLIMB TO eight thousand FEET, air india one two three.")
    }

    func testCallsignDigitsAreNotReadAsAQuantity() throws {
        // "air india 123" must not become "air india one hundred twenty three".
        let command = try first("air india 123 standby")
        XCTAssertEqual(command.readback.text, "STANDING BY, air india one two three.")
    }

    func testGluedCallsignIsSpokenOut() throws {
        let command = try first("aca125 standby")
        XCTAssertEqual(command.readback.text, "STANDING BY, aca one two five.")
    }

    func testSpeedAndRunwayReadbacks() throws {
        XCTAssertEqual(try first("air india 123 reduce speed to 250 knots").readback.text,
                       "RADAR REDUCE SPEED TO two five zero KNOTS, air india one two three.")
        XCTAssertEqual(try first("air india 123 intercept the localizer runway 27 left").readback.text,
                       "RADAR INTERCEPT THE LOCALIZER RUNWAY two seven left, air india one two three.")
    }

    func testHoldingFixIsSpelledOut() throws {
        let command = try first(
            "air india 123 proceed direct to papa juliet ndb and hold as published maintain flight level 260")
        XCTAssertEqual(command.readback.text,
                       """
                       PROCEED DIRECT TO papa juliet NDB AND HOLD AS PUBLISHED, \
                       MAINTAIN FLIGHT LEVEL two six zero, air india one two three.
                       """)
    }

    // MARK: - Repeated slots

    func testBlockClearanceEchoesBothLevelsInOrder() throws {
        // Filling by name alone would put the lower level in both positions.
        let command = try first(
            "air india 123 climb to and maintain block flight level 260 to flight level 280")
        let spoken = try XCTUnwrap(command.readback.text)
        XCTAssertTrue(spoken.contains("two six zero"), spoken)
        XCTAssertTrue(spoken.contains("two eight zero"), spoken)
        XCTAssertLessThan(try XCTUnwrap(spoken.range(of: "two six zero")).lowerBound,
                          try XCTUnwrap(spoken.range(of: "two eight zero")).lowerBound)
    }

    // MARK: - Prose splitting

    func testDeferredBranchIsSeparatedFromTheImmediateReply() throws {
        // "WILCO, [CALLSIGN]. Later: [CALLSIGN], PASSING [SIGNIFICANT POINT]."
        let command = try first("air india 123 report passing papa juliet")
        XCTAssertEqual(command.code, "316")
        XCTAssertEqual(command.readback.primary.spoken, "WILCO, air india one two three")
        XCTAssertNotNil(command.readback.deferred)
        // "Later:" itself is never spoken.
        XCTAssertFalse(try XCTUnwrap(command.readback.text).lowercased().contains("later"))
    }

    func testConditionalBranchIsSeparated() throws {
        // "SQUAWKING [CODE], [CALLSIGN]. If incorrect: NEGATIVE, SQUAWKING …"
        let command = try first("air india 123 confirm squawk 4567")
        XCTAssertEqual(command.readback.primary.spoken,
                       "SQUAWKING four five six seven, air india one two three")
        XCTAssertNotNil(command.readback.alternate)
        XCTAssertFalse(try XCTUnwrap(command.readback.text).lowercased().contains("if incorrect"))
    }

    func testARepeatedMarkerYieldsOneBranch() {
        // Code 411 repeats "If not: NEGATIVE, [CALLSIGN]." twice.
        let split = ReadbackRenderer.split(
            "AFFIRM, ESTABLISHED ON SBAS APPROACH COURSE, [CALLSIGN]. If not: NEGATIVE, [CALLSIGN]. If not: NEGATIVE, [CALLSIGN].")
        XCTAssertEqual(split.primary, "AFFIRM, ESTABLISHED ON SBAS APPROACH COURSE, [CALLSIGN]")
        XCTAssertEqual(split.alternate, "NEGATIVE, [CALLSIGN]")
    }

    func testCommaBeforeAMarkerIsHandled() {
        // Code 409 uses a comma where every other entry uses a full stop.
        let split = ReadbackRenderer.split(
            "AFFIRM, ESTABLISHED ON ILS LOCALIZER, [CALLSIGN], If not: NEGATIVE, [CALLSIGN].")
        XCTAssertEqual(split.primary, "AFFIRM, ESTABLISHED ON ILS LOCALIZER, [CALLSIGN]")
        XCTAssertEqual(split.alternate, "NEGATIVE, [CALLSIGN]")
    }

    func testNoReadbackRequiredIsNotAPhrase() throws {
        // "No pilot readback normally required." is a note, not something to say.
        let command = try first("air india 123 roger")
        XCTAssertEqual(command.code, "435")
        XCTAssertFalse(command.readback.isRequired)
        XCTAssertNil(command.readback.text)
    }

    // MARK: - Values the parser cannot know

    func testStateDerivedSlotsAreReportedNotInvented() throws {
        // "MAINTAINING [LEVEL], [CALLSIGN]. If not: NEGATIVE, [ACTUAL LEVEL] …"
        // The aircraft's real level is not in the transcript.
        let command = try first("air india 123 confirm 260")
        XCTAssertEqual(command.code, "430")
        XCTAssertEqual(command.readback.primary.spoken,
                       "MAINTAINING two six zero, air india one two three")
        let alternate = try XCTUnwrap(command.readback.alternate)
        XCTAssertEqual(alternate.unresolvedSlots, ["ACTUAL LEVEL"])
        XCTAssertNil(alternate.spoken)
    }

    func testCallerCanFillTheMissingValues() throws {
        let command = try first("air india 123 confirm 260")
        let alternate = try XCTUnwrap(command.readback.alternate)
        XCTAssertEqual(alternate.spoken(filling: ["ACTUAL LEVEL": "two eight zero"]),
                       "NEGATIVE, two eight zero, air india one two three")
    }

    func testAReadbackNeedingComputedValuesIsNotSpokenHalfDone() throws {
        // Code 443's reply needs a radial and a VOR name, which have to be worked
        // out from the aircraft's position — geometry the parser has no access to.
        let command = try first("air india 123 report radials")
        XCTAssertEqual(command.code, "443")
        XCTAssertNil(command.readback.primary.spoken)
        XCTAssertEqual(command.readback.primary.unresolvedSlots.sorted(),
                       ["THREE DIGITS", "VOR NAME"])
    }

    // MARK: - Disabled instructions

    func testDisabledInstructionAnswersUnable() throws {
        let command = try first("air india 123 radar service terminated due weather")
        XCTAssertEqual(command.outcome, .disabled)
        XCTAssertEqual(command.readback.text, "UNABLE, air india one two three.")
    }

    func testDisabledReplyCanBeSuppliedByTheCaller() throws {
        let custom = CommandRecognizer(templates: set,
                                       disabledReadback: "NOT AVAILABLE, [CALLSIGN].")
        let command = try XCTUnwrap(custom.recognize(
            "air india 123 radar service terminated due weather").commands.first)
        XCTAssertEqual(command.readback.text, "NOT AVAILABLE, air india one two three.")
    }

    // MARK: - Composition

    func testThreeInstructionsBecomeOneReply() throws {
        let result = recognizer.recognize(
            "Air india 123 climb and maintain FL260, increase speed to 300 knots, turn right heading 250")
        let replies = result.composedReadbacks()
        XCTAssertEqual(replies.count, 1)
        XCTAssertEqual(replies[0].callsign, "air india 123")
        XCTAssertEqual(replies[0].spoken, """
            RADAR CLIMB TO FLIGHT LEVEL two six zero, \
            RADAR INCREASE SPEED TO three zero zero KNOTS, \
            RADAR TURN RIGHT HEADING two five zero, air india one two three
            """)
    }

    func testCallsignIsSpokenOnceNotThreeTimes() throws {
        let result = recognizer.recognize(
            "air india 123 turn left heading 270 reduce speed to 250 knots descend to flight level 180")
        let spoken = try XCTUnwrap(result.composedReadbacks().first?.spoken)
        XCTAssertEqual(spoken.components(separatedBy: "air india one two three").count - 1, 1)
    }

    func testEachAircraftGetsItsOwnReply() throws {
        let result = recognizer.recognize(
            "air india 123 descend to flight level 200, baw17 turn right heading 090")
        let replies = result.composedReadbacks()
        XCTAssertEqual(replies.count, 2)
        XCTAssertEqual(replies[0].callsign, "air india 123")
        XCTAssertTrue(try XCTUnwrap(replies[0].spoken).contains("two zero zero"))
        XCTAssertEqual(replies[1].callsign, "baw17")
        XCTAssertTrue(try XCTUnwrap(replies[1].spoken).contains("zero nine zero"))
    }

    func testAnInstructionNeedingNoReadbackIsLeftOutOfTheReply() throws {
        let result = recognizer.recognize("air india 123 turn right heading 250 roger")
        let spoken = try XCTUnwrap(result.composedReadbacks().first?.spoken)
        XCTAssertTrue(spoken.contains("TURN RIGHT HEADING two five zero"))
        XCTAssertEqual(spoken.components(separatedBy: "air india one two three").count - 1, 1)
    }

    // MARK: - Every template renders

    func testEveryEnabledTemplateProducesAReadbackOrSaysWhyNot() {
        let renderer = ReadbackRenderer()
        for template in set.templates {
            let readback = renderer.render(template, slots: [], callsign: "air india 123")
            guard readback.isRequired else { continue }
            // With no slot values supplied, anything unresolved must be listed —
            // never rendered into the spoken string as a raw placeholder.
            if let spoken = readback.primary.spoken {
                XCTAssertFalse(spoken.contains("["), "[\(template.id)] leaked a placeholder: \(spoken)")
            } else {
                XCTAssertFalse(readback.primary.unresolvedSlots.isEmpty,
                               "[\(template.id)] nil spoken with nothing unresolved")
            }
        }
    }
}
