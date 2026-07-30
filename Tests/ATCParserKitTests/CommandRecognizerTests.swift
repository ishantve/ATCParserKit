//
//  CommandRecognizerTests.swift
//  ATCParserKit
//
//  Multi-command and multi-aircraft recognition — the behaviour this rewrite was
//  started for. The two cases that matter most are the ones the old parser got
//  silently wrong: a second instruction in the same category being dropped, and
//  a second aircraft's instruction being applied to the first aircraft.
//

import XCTest
@testable import ATCParserKit

final class CommandRecognizerTests: XCTestCase {

    private var recognizer: CommandRecognizer!

    override func setUpWithError() throws {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: "templates",
                              withExtension: "json",
                              subdirectory: "Fixtures"))
        recognizer = CommandRecognizer(templates: try TemplateSet(data: Data(contentsOf: url)))
    }

    private func recognize(_ text: String) -> RecognitionResult {
        recognizer.recognize(text)
    }

    private func codes(_ text: String) -> [String] {
        recognize(text).commands.map(\.code)
    }

    // MARK: - Single command still works

    func testSingleCommand() throws {
        let result = recognize("air india 123 turn right heading 250")
        XCTAssertEqual(result.commands.count, 1)
        let command = try XCTUnwrap(result.commands.first)
        XCTAssertEqual(command.code, "247")
        XCTAssertEqual(command.callsign, "air india 123")
        XCTAssertEqual(command.category, "vectoring")
        XCTAssertEqual(command.outcome, .ok)
    }

    // MARK: - The original example

    func testThreeInstructionsInOneTransmission() throws {
        let result = recognize(
            "Air india 123 climb and maintain FL260, increase speed to 300 knots, turn right heading 250")

        // "climb and maintain FL260" resolves to 101 (CLIMB TO FLIGHT LEVEL):
        // the sweep takes the instruction that starts earliest, which is the one
        // that accounts for the word "climb".
        XCTAssertEqual(result.commands.map(\.code), ["101", "359", "247"])
        // One callsign spoken once, inherited by all three.
        XCTAssertEqual(result.commands.map(\.callsign),
                       ["air india 123", "air india 123", "air india 123"])
        XCTAssertEqual(result.commands[0].slot(named: "LEVEL")?.value, .integer(260))
        XCTAssertEqual(result.commands[1].slot(named: "NUMBER")?.value, .integer(300))
        XCTAssertEqual(result.commands[2].slot(named: "THREE DIGITS")?.value, .integer(250))
    }

    func testPunctuationCannotChangeTheResult() {
        // Speech arrives without commas; typed and simulated input has them. The
        // same words must recognise identically either way — this failed once,
        // with the comma-free form landing on "STOP CLIMB AT FLIGHT LEVEL"
        // because a distant "to" hijacked the alignment.
        let punctuated = recognize(
            "Air india 123 climb and maintain FL260, increase speed to 300 knots, turn right heading 250")
        let plain = recognize(
            "Air india 123 climb and maintain FL260 increase speed to 300 knots turn right heading 250")
        XCTAssertEqual(punctuated.normalized, plain.normalized)
        XCTAssertEqual(punctuated.commands.map(\.code), plain.commands.map(\.code))
    }

    func testWordFormMatchesNumeralForm() {
        let words = recognize(
            "air india one two three climb and maintain flight level two six zero increase speed to three zero zero knots turn right heading two five zero")
        let numerals = recognize(
            "air india 123 climb and maintain flight level 260 increase speed to 300 knots turn right heading 250")
        XCTAssertEqual(words.commands.map(\.code), numerals.commands.map(\.code))
    }

    func testInstructionsComeBackInSpokenOrder() {
        // The old parser returned commands in a fixed category order regardless
        // of what was said, which made composing a readback impossible.
        XCTAssertEqual(codes("air india 123 turn right heading 250 reduce speed to 250 knots"),
                       ["247", "361"])
        XCTAssertEqual(codes("air india 123 reduce speed to 250 knots turn right heading 250"),
                       ["361", "247"])
    }

    // MARK: - Same category twice

    func testSecondInstructionInTheSameCategoryIsNotDropped() {
        // The old parser kept only the first flight level and silently discarded
        // the rest.
        let result = recognize(
            "air india 123 descend to flight level 200 then descend to flight level 180")
        XCTAssertEqual(result.commands.map(\.code), ["158", "158"])
        XCTAssertEqual(result.commands.compactMap { $0.slot(named: "LEVEL")?.value },
                       [.integer(200), .integer(180)])
    }

    // MARK: - Several aircraft

    func testEachAircraftKeepsItsOwnInstruction() throws {
        // The old parser applied both of these to the first aircraft, with no
        // error — the worst failure in the old behaviour.
        let result = recognize(
            "air india 123 descend to flight level 200, baw17 turn right heading 090")

        XCTAssertEqual(result.commands.count, 2)
        XCTAssertEqual(result.commands[0].callsign, "air india 123")
        XCTAssertEqual(result.commands[0].code, "158")
        XCTAssertEqual(result.commands[1].callsign, "baw17")
        XCTAssertEqual(result.commands[1].code, "247")
        XCTAssertEqual(result.commands[1].slot(named: "THREE DIGITS")?.value, .integer(90))
    }

    func testGroupingByCallsign() {
        let result = recognize(
            "air india 123 turn left heading 270 reduce speed to 250 knots baw17 climb to flight level 300")
        let groups = result.groupedByCallsign()
        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups[0].callsign, "air india 123")
        XCTAssertEqual(groups[0].commands.count, 2)
        XCTAssertEqual(groups[1].callsign, "baw17")
        XCTAssertEqual(groups[1].commands.count, 1)
    }

    func testCallsignDoesNotLeakBackwards() {
        // A callsign named halfway through must not claim earlier instructions.
        let result = recognize("turn left heading 270 baw17 climb to flight level 300")
        XCTAssertNil(result.commands.first?.callsign)
        XCTAssertEqual(result.commands.last?.callsign, "baw17")
    }

    // MARK: - Unrecognised speech is reported

    func testUnmatchedSpeechIsReportedNotSwallowed() {
        let result = recognize("air india 123 turn right heading 250 and have a nice day")
        XCTAssertEqual(result.commands.map(\.code), ["247"])
        XCTAssertFalse(result.unrecognized.isEmpty)
        XCTAssertTrue(result.unrecognized.joined(separator: " ").contains("nice"))
    }

    func testAdjacentUnmatchedWordsAreOneFragment() {
        let result = recognize("air india 123 turn right heading 250 nice and steady please")
        XCTAssertEqual(result.commands.map(\.code), ["247"])
        // Consecutive unmatched words are reported as one fragment, not four.
        XCTAssertEqual(result.unrecognized, ["nice and steady please"])
    }

    func testClimbAndMaintainTakesTheClimbTemplate() throws {
        // Standard phraseology with no exact template: the payload has
        // "CLIMB TO AND MAINTAIN BLOCK …" but not the non-block variant. The
        // sweep picks 101, which explains "climb", over 219, which does not.
        let result = recognize("air india 123 climb and maintain flight level 260")
        let command = try XCTUnwrap(result.commands.first)
        XCTAssertEqual(command.code, "101")
        XCTAssertEqual(command.slot(named: "LEVEL")?.value, .integer(260))
        XCTAssertEqual(command.callsign, "air india 123")
    }

    func testNothingRecognisedAtAll() {
        let result = recognize("good morning everybody")
        XCTAssertTrue(result.commands.isEmpty)
        XCTAssertEqual(result.unrecognized, ["good morning everybody"])
    }

    func testEmptyInput() {
        let result = recognize("   ")
        XCTAssertTrue(result.isEmpty)
        XCTAssertTrue(result.unrecognized.isEmpty)
    }

    // MARK: - Outcomes

    func testDisabledTemplateIsRecognisedButNotActionable() throws {
        let result = recognize("air india 123 radar service terminated due weather")
        let command = try XCTUnwrap(result.commands.first)
        XCTAssertEqual(command.code, "449")
        XCTAssertEqual(command.outcome, .disabled)
        XCTAssertFalse(command.isActionable)
        XCTAssertFalse(command.isEnabled)
    }

    func testIllegalValueIsItsOwnOutcome() throws {
        let command = try XCTUnwrap(recognize("air india 123 fly heading 450").commands.first)
        XCTAssertEqual(command.outcome, .invalidValue(slot: "THREE DIGITS", value: .integer(450)))
        XCTAssertFalse(command.isActionable)
    }

    func testACommsOnlyPhraseIsAPerfectlyGoodOutcome() throws {
        // No aircraft state changes, but nothing failed either.
        let command = try XCTUnwrap(recognize("air india 123 standby").commands.first)
        XCTAssertEqual(command.code, "432")
        XCTAssertEqual(command.outcome, .ok)
    }

    // MARK: - Mixed number forms across one transmission

    func testWordAndNumeralFormsMixedInOneTransmission() {
        let result = recognize(
            "air india 123 fly heading two seven zero descend to flight level 180")
        XCTAssertEqual(result.commands.map(\.code), ["245", "158"])
        XCTAssertEqual(result.commands[0].slot(named: "THREE DIGITS")?.value, .integer(270))
        XCTAssertEqual(result.commands[1].slot(named: "LEVEL")?.value, .integer(180))
    }

    // MARK: - Spans do not overlap

    func testMatchesNeverClaimTheSameWords() {
        let result = recognize(
            "air india 123 turn right heading 250 reduce speed to 250 knots descend to flight level 180")
        XCTAssertEqual(result.commands.count, 3)
        // Distinct instructions, each with its own value.
        XCTAssertEqual(Set(result.commands.map(\.matchedText)).count, 3)
    }
}
