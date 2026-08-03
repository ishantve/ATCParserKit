//
//  NumberWordsTests.swift
//  ATCParserKit
//
//  The recogniser emits numbers three different ways for the same phrase, and
//  getting one of them wrong turns an aircraft in the wrong direction without
//  any error. These tests are the guard on that.
//

import XCTest
@testable import ATCParserKit

final class NumberWordsTests: XCTestCase {

    private func expand(_ text: String) -> String {
        NumberWords.expandToString(text.split(separator: " ").map(String.init))
    }

    // MARK: - The three recogniser forms converge

    func testAllThreeFormsProduceTheSameValue() {
        XCTAssertEqual(expand("flight level two six zero"), "flight level 260")
        XCTAssertEqual(expand("flight level 2 6 0"), "flight level 260")
        XCTAssertEqual(expand("flight level 260"), "flight level 260")
    }

    // MARK: - Literal concatenation

    func testDigitWordsConcatenate() {
        XCTAssertEqual(expand("heading two seven zero"), "heading 270")
        XCTAssertEqual(expand("squawk four five six seven"), "squawk 4567")
        XCTAssertEqual(expand("nine zero"), "90")
    }

    func testDigitThenTensConcatenates() {
        XCTAssertEqual(expand("heading two seventy"), "heading 270")
        XCTAssertEqual(expand("flight level two sixty"), "flight level 260")
        XCTAssertEqual(expand("heading three sixty"), "heading 360")
        XCTAssertEqual(expand("one twenty"), "120")
    }

    func testTensThenUnitAdds() {
        // "runway twenty seven" is 27, not 207 — the ordering exception.
        XCTAssertEqual(expand("runway twenty seven left"), "runway 27 left")
        XCTAssertEqual(expand("twenty one"), "21")
        XCTAssertEqual(expand("ninety nine"), "99")
    }

    func testBothOrderingsInOneUtterance() {
        // "two seventy" concatenates, "twenty seven" adds.
        XCTAssertEqual(expand("heading two seventy runway twenty seven"),
                       "heading 270 runway 27")
    }

    func testTeensAreSingleTokens() {
        XCTAssertEqual(expand("one fifteen"), "115")
        XCTAssertEqual(expand("fifteen"), "15")
    }

    func testHundredAndThousandFallOutOfTheSameRule() {
        XCTAssertEqual(expand("eight thousand feet"), "8000 feet")
        XCTAssertEqual(expand("one hundred"), "100")
        XCTAssertEqual(expand("flight level one hundred"), "flight level 100")
    }

    func testSpokenVariantsAreAccepted() {
        XCTAssertEqual(expand("niner niner"), "99")
        XCTAssertEqual(expand("oh nine zero"), "090")
    }

    // MARK: - Merging is not unconditional

    func testTwoStandaloneNumeralsDoNotFuse() {
        // A flight number must never merge into the value beside it.
        XCTAssertEqual(expand("125 250"), "125 250")
    }

    func testWordDerivedNumbersStillMergeAcrossWidths() {
        // "eight" + "000" — the second is multi-digit but word-derived.
        XCTAssertEqual(expand("eight thousand"), "8000")
    }

    func testNonNumericTokensBreakTheRun() {
        XCTAssertEqual(expand("two six zero knots two five zero"), "260 knots 250")
    }

    // MARK: - Homophones stay out of normalisation

    func testHomophonesAreNotExpandedGlobally() {
        // Expanding these here would corrupt real phraseology.
        XCTAssertEqual(expand("cleared for takeoff"), "cleared for takeoff")
        XCTAssertEqual(expand("descend to 8000 feet"), "descend to 8000 feet")
        XCTAssertEqual(expand("vectoring for ils approach"), "vectoring for ils approach")
    }

    // MARK: - Digits → words

    func testDigitByDigitReadback() {
        XCTAssertEqual(NumberWords.spokenDigits("260"), "two six zero")
        XCTAssertEqual(NumberWords.spokenDigits("27"), "two seven")
        XCTAssertEqual(NumberWords.spokenDigits(90, padTo: 3), "zero nine zero")
    }

    func testMagnitudeReadback() {
        XCTAssertEqual(NumberWords.spokenMagnitude(8000), "eight thousand")
        XCTAssertEqual(NumberWords.spokenMagnitude(8500), "eight thousand five hundred")
        XCTAssertEqual(NumberWords.spokenMagnitude(12000), "one two thousand")
        XCTAssertEqual(NumberWords.spokenMagnitude(500), "five hundred")
    }

    func testFrequencyReadback() {
        XCTAssertEqual(NumberWords.spokenDigits("121.5"),
                       "one two one decimal five")
    }
}
