import XCTest
@testable import ATCParserKit

final class TranscriptCleanerTests: XCTestCase {

    func testDisplayTextAppliesReplacementsAndUppercases() {
        XCTAssertEqual(TranscriptCleaner.displayText("descend three thousand"),
                       "DESCEND TREE THOUSAND")
        // x-ray→xray replacement lets the phonetic run fold to a code (XAJ).
        XCTAssertEqual(TranscriptCleaner.displayText("x-ray alpha juliet"), "XAJ")
        XCTAssertEqual(TranscriptCleaner.displayText(""), "")
    }

    func testCleanPreservesCaseForTheParser() {
        // `clean` feeds the matcher (which lowercases), so it does not uppercase.
        XCTAssertEqual(TranscriptCleaner.clean("Turn three"), "Turn tree")
    }

    func testRemovesUnkAndStrayCommas() {
        XCTAssertEqual(TranscriptCleaner.displayText("descend [unk] flight level 260"),
                       "DESCEND FLIGHT LEVEL 260")
        XCTAssertEqual(TranscriptCleaner.displayText("turn left, heading 270"),
                       "TURN LEFT HEADING 270")
        XCTAssertEqual(TranscriptCleaner.displayText("[unk]"), "")
    }

    /// A comma must survive `clean`: `TranscriptNormalizer` reads it as a clause
    /// boundary, which is how two aircraft in one transmission stay separate (see
    /// `RecognitionWireTests.testReadbacksArriveGroupedPerAircraft`). Only the display
    /// drops it.
    func testCleanKeepsCommasSoClauseBoundariesSurvive() {
        XCTAssertEqual(TranscriptCleaner.clean("turn left, heading 270"),
                       "turn left, heading 270")
        XCTAssertEqual(TranscriptCleaner.displayText("turn left, heading 270"),
                       "TURN LEFT HEADING 270")
    }

    func testWholeWordOnly() {
        // "threefold" must not become "treefold".
        XCTAssertEqual(TranscriptCleaner.displayText("threefold"), "THREEFOLD")
    }

    func testLeadingPhoneticCallsignFolds() {
        // "Echo Tango Delta" → "ETD" so the callsign matches its aircraft.
        XCTAssertEqual(TranscriptCleaner.displayText("echo tango delta 615 descend"),
                       "ETD 615 DESCEND")
        XCTAssertEqual(TranscriptCleaner.clean("Echo Tango Delta 615"), "ETD 615")
        // A lone phonetic word (e.g. the airline "Delta") is left alone.
        XCTAssertEqual(TranscriptCleaner.displayText("delta 615"), "DELTA 615")
        // A spoken airline name ("air india") is not a phonetic run.
        XCTAssertEqual(TranscriptCleaner.displayText("air india 235"), "AIR INDIA 235")
    }

    func testFragmentDigitsAreSpokenIcaoDigitByDigit() {
        // The "say again" fix: "22 5" must not be read as "twenty two five".
        XCTAssertEqual(NumberWords.spokenFragment("emirates 22 5"), "emirates two two fife")
        XCTAssertEqual(NumberWords.spokenFragment("aca125"), "aca one two fife")
        XCTAssertEqual(NumberWords.spokenFragment("climb 90"), "climb niner zero")
    }
}
