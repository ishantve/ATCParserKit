//
//  RecognitionWireTests.swift
//  ATCParserKitTests
//
//  Pins the JSON shape the React Native and Unity wrappers depend on.
//
//  These read like trivia — "there is no null anywhere" — but they are the wire contract. The
//  consumers cannot express what Swift can: Unity's `JsonUtility` has no nullable primitives
//  and no sum types, so a single `null` where it expects a string turns into a silent default
//  rather than an error. A Swift change that starts emitting one would compile, pass every
//  other test, and break C# at runtime. That is what these catch.
//

import XCTest
@testable import ATCParserKit

final class RecognitionWireTests: XCTestCase {

    private var recognizer: CommandRecognizer!

    override func setUpWithError() throws {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: "templates", withExtension: "json",
                              subdirectory: "Fixtures"))
        recognizer = CommandRecognizer(templates: try TemplateSet(data: Data(contentsOf: url)))
    }

    private func json(_ transcript: String) throws -> String {
        try recognizer.recognize(transcript).toJSON()
    }

    private func object(_ transcript: String) throws -> [String: Any] {
        try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(try json(transcript).utf8))
            as? [String: Any])
    }

    // MARK: - The constraint the consumers impose

    /// No `null`, anywhere, for any input — including inputs where the Swift side has
    /// optionals (no callsign, no code, no alternate readback, an unparsed slot).
    func testTheWireFormatNeverEmitsNull() throws {
        let transcripts = [
            "air india 123 report passing PJ",
            "report passing PJ",                       // no callsign
            "climb to flight level 260",               // no callsign, different family
            "air india 123 report passing",            // slot left unfilled
            "complete nonsense words here",            // nothing matches
            "",                                        // empty
        ]
        for transcript in transcripts {
            let encoded = try json(transcript)
            XCTAssertFalse(encoded.contains("null"),
                           "null emitted for \"\(transcript)\": \(encoded)")
        }
    }

    /// Every key the wrappers read is present even when nothing was recognised, so a consumer
    /// never has to distinguish "absent" from "empty".
    func testTheEnvelopeIsCompleteEvenWhenNothingMatched() throws {
        let result = try object("complete nonsense words here")
        for key in ["normalized", "commands", "unrecognized", "readbacks"] {
            XCTAssertNotNil(result[key], "missing \(key)")
        }
        XCTAssertEqual((result["commands"] as? [Any])?.count, 0)
        XCTAssertFalse((result["unrecognized"] as? [String] ?? []).isEmpty,
                       "unrecognised speech must be reported, not dropped")
    }

    /// A missing callsign is `""`, not a missing key and not null.
    func testAnAbsentCallsignIsAnEmptyString() throws {
        let commands = try XCTUnwrap(try object("report passing PJ")["commands"]
            as? [[String: Any]])
        XCTAssertEqual(commands.first?["callsign"] as? String, "")
    }

    // MARK: - Outcome

    /// `outcome` is one of three known strings. A consumer switches on it, so a fourth value
    /// or a rename is a breaking change and this is where it gets noticed.
    func testOutcomeIsOneOfThreeKnownStrings() throws {
        let allowed: Set<String> = ["ok", "disabled", "invalidValue"]
        for transcript in ["air india 123 report passing PJ",
                           "air india 123 climb to flight level 260",
                           "air india 123 turn left heading 999"] {
            for command in try object(transcript)["commands"] as? [[String: Any]] ?? [] {
                let outcome = command["outcome"] as? String ?? ""
                XCTAssertTrue(allowed.contains(outcome), "unexpected outcome \"\(outcome)\"")
            }
        }
    }

    /// `isActionable` must agree with `outcome`, since callers are told to trust it. If the two
    /// ever disagreed, a caller would execute an instruction the phraseology refused.
    func testIsActionableAgreesWithOutcome() throws {
        for transcript in ["air india 123 report passing PJ",
                           "air india 123 climb to flight level 260",
                           "speedbird 45 report passing RE01"] {
            for command in try object(transcript)["commands"] as? [[String: Any]] ?? [] {
                XCTAssertEqual(command["isActionable"] as? Bool,
                               command["outcome"] as? String == "ok",
                               "isActionable disagreed with outcome in \(command)")
            }
        }
    }

    // MARK: - Slots

    /// An integer slot carries both forms, so a consumer need not re-parse the string.
    func testAnIntegerSlotCarriesBothItsFormsInAgreement() throws {
        let commands = try XCTUnwrap(
            try object("air india 123 climb to flight level 260")["commands"]
                as? [[String: Any]])
        let slots = commands.flatMap { $0["slots"] as? [[String: Any]] ?? [] }
        let level = try XCTUnwrap(slots.first { $0["hasIntValue"] as? Bool == true },
                                  "expected a numeric slot in a level instruction")
        XCTAssertEqual(level["valueKind"] as? String, "integer")
        XCTAssertEqual(level["value"] as? String, String(level["intValue"] as? Int ?? -1))
    }

    /// A non-integer slot says so, rather than reporting a misleading `intValue` of 0.
    func testANonIntegerSlotFlagsThatItHasNoNumber() throws {
        let commands = try XCTUnwrap(try object("air india 123 report passing PJ")["commands"]
            as? [[String: Any]])
        let slots = commands.flatMap { $0["slots"] as? [[String: Any]] ?? [] }
        let fix = try XCTUnwrap(slots.first { $0["kind"] as? String == "fix" })
        XCTAssertEqual(fix["hasIntValue"] as? Bool, false)
        XCTAssertEqual(fix["intValue"] as? Int, 0)
        XCTAssertFalse((fix["value"] as? String ?? "").isEmpty)
    }

    // MARK: - Readbacks

    /// Readbacks are grouped on the Swift side so neither TypeScript nor C# reimplements the
    /// rule that one aircraft answers once.
    func testReadbacksArriveGroupedPerAircraft() throws {
        let result = try object(
            "air india 123 report passing PJ, speedbird 45 report passing RE01")
        let readbacks = try XCTUnwrap(result["readbacks"] as? [[String: Any]])
        XCTAssertEqual(readbacks.count, 2, "expected one reply per aircraft")
        for readback in readbacks {
            XCTAssertFalse((readback["spoken"] as? String ?? "").isEmpty)
        }
    }

    /// A `Later:` branch reaches the wire. It was rendered but unused once already, which is
    /// exactly the kind of thing a bridge quietly loses.
    func testADeferredReadbackReachesTheWire() throws {
        let commands = try XCTUnwrap(try object("air india 123 report passing PJ")["commands"]
            as? [[String: Any]])
        XCTAssertFalse((commands.first?["readbackDeferred"] as? String ?? "").isEmpty,
                       "the Later: branch must cross the boundary")
    }

    // MARK: - Determinism

    /// Sorted keys, so a consumer can snapshot-test its own integration.
    func testOutputIsDeterministic() throws {
        let first = try json("air india 123 report passing PJ")
        let second = try json("air india 123 report passing PJ")
        XCTAssertEqual(first, second)
    }

    // MARK: - Diagnostics

    func testDiagnosticsEncodeAsAnObjectNotABareArray() throws {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: "templates", withExtension: "json",
                              subdirectory: "Fixtures"))
        let set = try TemplateSet(data: Data(contentsOf: url))
        let decoded = try JSONSerialization.jsonObject(with: Data(try set.diagnosticsJSON().utf8))
        // A top-level array would be unreadable by JsonUtility.
        XCTAssertTrue(decoded is [String: Any], "diagnostics must be a JSON object")
    }
}
