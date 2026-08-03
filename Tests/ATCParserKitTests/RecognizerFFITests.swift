//
//  RecognizerFFITests.swift
//  ATCParserKitTests
//
//  Drives the C ABI the way Unity does — create a handle, recognise through it, release it —
//  and checks the wire JSON is what a C# or TypeScript caller can actually read.
//
//  Worth testing here rather than trusting a Unity build: the handle path is the only place in
//  this package with manual memory management and untyped pointers, and a real Unity iOS build
//  is a slow, manual step. A mistake in the retain/release pairing shows up as a crash or a
//  leak in a game engine, which is the worst place to find it.
//

import XCTest
@testable import ATCParserFFI
@testable import ATCParserKit

final class RecognizerFFITests: XCTestCase {

    private var templatesJSON = ""

    override func setUpWithError() throws {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: "templates", withExtension: "json",
                              subdirectory: "Fixtures"))
        templatesJSON = try String(contentsOf: url, encoding: .utf8)
    }

    // MARK: - Helpers

    /// Creates a handle, hands it to the body, and always releases it.
    private func withHandle(_ body: (UnsafeMutableRawPointer) throws -> Void) throws {
        var error: UnsafeMutablePointer<CChar>?
        let handle = try XCTUnwrap(templatesJSON.withCString {
            atc_recognizer_create($0, &error)
        }, "create failed: \(error.map { String(cString: $0) } ?? "no detail")")
        defer { atc_recognizer_release(handle) }
        try body(handle)
    }

    /// Recognises through the C boundary and decodes the JSON, freeing the string as a real
    /// caller must.
    private func recognize(_ transcript: String,
                           through handle: UnsafeMutableRawPointer) throws
        -> WireRecognitionResult {
        let pointer = try XCTUnwrap(transcript.withCString {
            atc_recognizer_recognize(handle, $0)
        })
        defer { atc_parser_free(pointer) }
        let json = String(cString: pointer)
        return try JSONDecoder().decode(WireRecognitionResult.self,
                                        from: Data(json.utf8))
    }

    // MARK: - Lifecycle

    func testAHandleRecognizesAndReleases() throws {
        try withHandle { handle in
            let result = try recognize("air india 123 report passing PJ", through: handle)
            XCTAssertEqual(result.commands.count, 1)
            XCTAssertEqual(result.commands[0].code, "316")
        }
    }

    /// The reason the boundary is create/use/release rather than one call: the payload is
    /// decoded once and reused. If a handle were single-use this would fail on the second
    /// transcript.
    func testOneHandleServesManyTranscripts() throws {
        try withHandle { handle in
            for transcript in ["air india 123 report passing PJ",
                               "speedbird 45 report passing RE01",
                               "air india 123 report passing PJ"] {
                XCTAssertFalse(try recognize(transcript, through: handle).commands.isEmpty,
                               "handle stopped working for: \(transcript)")
            }
        }
    }

    /// Two live handles must not disturb each other — a released one must not take the
    /// other's payload with it.
    func testTwoHandlesAreIndependent() throws {
        var error: UnsafeMutablePointer<CChar>?
        let first = try XCTUnwrap(templatesJSON.withCString { atc_recognizer_create($0, &error) })
        let second = try XCTUnwrap(templatesJSON.withCString { atc_recognizer_create($0, &error) })

        atc_recognizer_release(first)

        // `second` still works after `first` is gone.
        XCTAssertFalse(try recognize("air india 123 report passing PJ", through: second)
            .commands.isEmpty)
        atc_recognizer_release(second)
    }

    /// A NULL handle returns NULL rather than trapping. A C caller that ignored a failed
    /// create would otherwise crash inside the library instead of at its own mistake.
    func testNullHandleIsNotFatal() {
        XCTAssertNil("anything".withCString { atc_recognizer_recognize(nil, $0) })
        XCTAssertNil(atc_recognizer_diagnostics(nil))
        atc_recognizer_release(nil)      // must not crash
    }

    // MARK: - Failure reporting

    /// A bad payload reports *why*. Collapsing this into NULL would leave a Unity developer
    /// with a plugin that silently recognises nothing.
    func testABadPayloadReportsTheReason() throws {
        var error: UnsafeMutablePointer<CChar>?
        let handle = "{ not json".withCString { atc_recognizer_create($0, &error) }
        XCTAssertNil(handle)

        let pointer = try XCTUnwrap(error, "create failed without saying why")
        defer { atc_parser_free(pointer) }
        XCTAssertTrue(String(cString: pointer).contains("decode_failed"))
    }

    func testANullPayloadIsDistinguishedFromABadOne() throws {
        var error: UnsafeMutablePointer<CChar>?
        XCTAssertNil(atc_recognizer_create(nil, &error))
        let pointer = try XCTUnwrap(error)
        defer { atc_parser_free(pointer) }
        XCTAssertTrue(String(cString: pointer).contains("null_input"))
    }

    /// The error envelope has to survive being embedded in JSON — a decoder detail with
    /// quotes in it must not produce a string no consumer can parse.
    func testTheErrorEnvelopeIsValidJSON() throws {
        var error: UnsafeMutablePointer<CChar>?
        _ = #"{"categories": [ }"#.withCString { atc_recognizer_create($0, &error) }
        let pointer = try XCTUnwrap(error)
        defer { atc_parser_free(pointer) }

        let decoded = try JSONSerialization.jsonObject(
            with: Data(String(cString: pointer).utf8)) as? [String: Any]
        XCTAssertEqual(decoded?["error"] as? String, "decode_failed")
    }

    // MARK: - Diagnostics

    /// Payload problems cross the bridge. Without this a broken template is invisible to a
    /// Unity or React Native caller: it just never matches.
    func testDiagnosticsCrossTheBoundary() throws {
        try withHandle { handle in
            let pointer = try XCTUnwrap(atc_recognizer_diagnostics(handle))
            defer { atc_parser_free(pointer) }
            let wire = try JSONDecoder().decode(WireDiagnostics.self,
                                                from: Data(String(cString: pointer).utf8))
            XCTAssertGreaterThan(wire.templateCount, 0)
            XCTAssertLessThanOrEqual(wire.enabledCount, wire.templateCount)
        }
    }
}
