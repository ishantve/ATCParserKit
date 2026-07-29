//
//  ATCParserKitTests.swift
//  ATCParserKit
//
//  Public-API coverage: parse() semantics + the JSON wire contract.
//

import XCTest
@testable import ATCParserKit

final class ATCParserTests: XCTestCase {

    private let parser = ATCParser()

    // MARK: - Callsign extraction

    func testCallsignAndMultipleCommands() throws {
        let r = try parser.parse("air canada 125 climb flight level 250 turn left heading 270")
        XCTAssertEqual(r.callsign, "air canada 125")
        // parse() order: heading is collected before flight level.
        XCTAssertEqual(r.commands, [
            ParsedCommand(type: .headingTurn, heading: 270, direction: .left),
            ParsedCommand(type: .flightLevel, flightLevel: 250),
        ])
    }

    func testShortCallsignSpokenDigits() throws {
        // "two eight zero" → "280"
        let r = try parser.parse("aca 29 speed two eight zero")
        XCTAssertEqual(r.callsign, "aca 29")
        XCTAssertEqual(r.commands, [ParsedCommand(type: .speed, speed: 280)])
    }

    func testNoCallsignPlainCommand() throws {
        let r = try parser.parse("climb flight level 250")
        XCTAssertNil(r.callsign)
        XCTAssertEqual(r.commands, [ParsedCommand(type: .flightLevel, flightLevel: 250)])
    }

    // MARK: - Individual command families

    func testHold() throws {
        let r = try parser.parse("hold at papa juliet")
        XCTAssertNil(r.callsign)
        XCTAssertEqual(r.commands, [ParsedCommand(type: .hold, fix: "PJ")])
    }

    func testInterceptLocalizer() throws {
        let r = try parser.parse("indigo 2341 intercept the localizer runway 27 left")
        XCTAssertEqual(r.callsign, "indigo 2341")
        XCTAssertEqual(r.commands, [ParsedCommand(type: .interceptLocalizer, runway: "27L")])
    }

    func testPresentHeading() throws {
        let r = try parser.parse("present heading")
        XCTAssertEqual(r.commands, [ParsedCommand(type: .presentHeading)])
    }

    func testAltitudeBlock() throws {
        let r = try parser.parse("maintain block flight level 100 through 120")
        XCTAssertEqual(r.commands, [ParsedCommand(type: .altitudeBlock, altitudeLow: 100, altitudeHigh: 120)])
    }

    func testSpeedFloorAndCeiling() throws {
        XCTAssertEqual(try parser.parse("maintain 250 knots or greater").commands,
                       [ParsedCommand(type: .minSpeed, speed: 250)])
        XCTAssertEqual(try parser.parse("do not exceed 280 knots").commands,
                       [ParsedCommand(type: .maxSpeed, speed: 280)])
    }

    func testUnrecognisedYieldsNoCommands() throws {
        let r = try parser.parse("good morning tower")
        XCTAssertTrue(r.commands.isEmpty)
    }

    // MARK: - Errors

    func testEmptyInputThrows() {
        XCTAssertThrowsError(try parser.parse("   ")) { error in
            XCTAssertEqual(error as? ATCParserError, .emptyInput)
        }
    }

    // MARK: - JSON wire contract

    func testJSONSnapshotHold() throws {
        // Deterministic (sorted keys, nil fields omitted, no Doubles).
        let json = try parser.parseToJSON("hold at pj")
        XCTAssertEqual(json, #"{"commands":[{"fix":"pj","type":"hold"}],"normalized":"hold at pj"}"#)
    }

    func testJSONRoundTrip() throws {
        let input = "air canada 125 climb flight level 250 turn left heading 270"
        let json = try parser.parseToJSON(input)
        let decoded = try JSONDecoder().decode(ParserResult.self,
                                               from: Data(json.utf8))
        XCTAssertEqual(decoded, try parser.parse(input))
    }

    func testJSONOmitsNilFields() throws {
        let json = try parser.parseToJSON("climb flight level 250")
        XCTAssertFalse(json.contains("null"))
        XCTAssertFalse(json.contains("callsign"))   // nil callsign omitted
        XCTAssertTrue(json.contains("\"flightLevel\":250"))
    }
}
