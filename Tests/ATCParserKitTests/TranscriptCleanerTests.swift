import XCTest
@testable import ATCParserKit

final class TranscriptCleanerTests: XCTestCase {

    func testDisplayTextAppliesReplacementsAndUppercases() {
        XCTAssertEqual(TranscriptCleaner.displayText("descend three thousand"),
                       "DESCEND TREE THOUSAND")
        XCTAssertEqual(TranscriptCleaner.displayText("x-ray alpha juliet"),
                       "XRAY ALFA JULIETT")
        XCTAssertEqual(TranscriptCleaner.displayText(""), "")
    }

    func testCleanPreservesCaseForTheParser() {
        // `clean` feeds the matcher (which lowercases), so it does not uppercase.
        XCTAssertEqual(TranscriptCleaner.clean("Turn three"), "Turn tree")
    }

    func testWholeWordOnly() {
        // "threefold" must not become "treefold".
        XCTAssertEqual(TranscriptCleaner.displayText("threefold"), "THREEFOLD")
    }

    func testFragmentDigitsAreSpokenIcaoDigitByDigit() {
        // The "say again" fix: "22 5" must not be read as "twenty two five".
        XCTAssertEqual(NumberWords.spokenFragment("emirates 22 5"), "emirates two two fife")
        XCTAssertEqual(NumberWords.spokenFragment("aca125"), "aca one two fife")
        XCTAssertEqual(NumberWords.spokenFragment("climb 90"), "climb niner zero")
    }
}
