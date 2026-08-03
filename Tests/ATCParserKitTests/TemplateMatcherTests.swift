//
//  TemplateMatcherTests.swift
//  ATCParserKit
//
//  The headline test here is the round trip: every template in the payload is
//  turned back into the utterance a controller would speak, then matched. It
//  must come back as itself. That is 75 assertions for the price of one, and it
//  catches the failure mode that matters most — one template quietly stealing
//  another's phrasing.
//

import XCTest
@testable import ATCParserKit

final class TemplateMatcherTests: XCTestCase {

    private var set: TemplateSet!
    private var matcher: TemplateMatcher!
    private let normalizer = TranscriptNormalizer()

    override func setUpWithError() throws {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: "templates",
                              withExtension: "json",
                              subdirectory: "Fixtures"))
        set = try TemplateSet(data: Data(contentsOf: url))
        matcher = TemplateMatcher(templates: set)
    }

    // MARK: - Helpers

    private func match(_ transcript: String) -> TemplateMatch? {
        matcher.bestMatch(in: normalizer.tokens(transcript))
    }

    private func id(_ transcript: String) -> String? {
        match(transcript)?.template.id
    }

    /// Sample spoken value for each slot kind, so a template can be turned back
    /// into a plausible utterance.
    private func sample(for kind: SlotKind) -> String {
        switch kind {
        case .callsign:      return "air india 123"
        case .flightLevel:   return "260"
        case .altitudeFeet:  return "8000"
        case .heading:       return "270"
        case .speedKnots:    return "300"
        case .degrees:       return "30"
        case .runway:        return "27"
        case .squawk:        return "4567"
        case .pressure:      return "1013"
        case .distance:      return "10"
        case .time:          return "1420"
        case .frequency:     return "121 decimal 5"
        case .fix:           return "papa juliet"
        case .freeText:      return "weather"
        case .integer:       return "5"
        }
    }

    /// Rebuilds the utterance a controller would speak for a template.
    private func canonicalUtterance(for template: CommandTemplate) -> String {
        let registry = SlotRegistry.default
        var words: [String] = []
        for (index, token) in template.pattern.tokens.enumerated() {
            switch token {
            case .literal(let word):
                words.append(word)
            case .slot:
                words.append(sample(for: registry.kind(at: index, in: template.pattern)))
            }
        }
        return words.joined(separator: " ")
    }

    // MARK: - Round trip

    func testEveryTemplateMatchesItself() {
        var failures: [String] = []
        for template in set.templates {
            let utterance = canonicalUtterance(for: template)
            guard let match = match(utterance) else {
                failures.append("[\(template.id)] no match for \"\(utterance)\"")
                continue
            }
            // A reported tie is an acceptable outcome: the payload contains
            // templates that are word-for-word identical, so the words alone
            // cannot single one out. Silently picking the wrong one is not.
            let resolved = match.template.id == template.id
                || match.tiedWith.contains(template.id)
            if !resolved {
                failures.append("""
                    [\(template.id)] lost to [\(match.template.id)] \
                    (score \(match.score), literals \(match.matchedLiterals), \
                    specificity \(match.specificity)) for "\(utterance)"
                    """)
            }
        }
        XCTAssertTrue(failures.isEmpty,
                      "\(failures.count)/\(set.templates.count) templates failed:\n"
                      + failures.joined(separator: "\n"))
    }

    func testEveryTemplateFillsItsSlots() {
        var failures: [String] = []
        for template in set.templates {
            guard let match = match(canonicalUtterance(for: template)),
                  match.template.id == template.id else { continue }
            for slot in match.slots where !slot.isValid && !slot.isStateDerived {
                failures.append("[\(template.id)] slot \(slot.name) → \(slot.outcome)")
            }
        }
        XCTAssertTrue(failures.isEmpty, failures.joined(separator: "\n"))
    }

    // MARK: - Genuinely ambiguous payload entries

    func testIdenticallyWordedTemplatesAreReportedAsTiedNotGuessed() throws {
        // 317 and 318 read "REPORT [DISTANCE] MILES GNSS FROM [x]", where x is a
        // DME station in one and a significant point in the other. Both are just
        // names, so no lexical rule separates them — the caller's navigation
        // data has to.
        let match = try XCTUnwrap(match("air india 123 report 10 miles gnss from papa juliet"))
        XCTAssertEqual(Set([match.template.id] + match.tiedWith), ["317", "318"])
    }

    func testTimeVersusPointIsResolvedByValueShape() {
        // 122 and 123 are also identically worded, but their last argument is a
        // time in one and a point in the other — that *is* separable, because a
        // time is four digits and a fix name is not.
        XCTAssertEqual(id("air india 123 radar request level change from delhi at 1420"), "122")
        XCTAssertEqual(id("air india 123 radar request level change from delhi at papa juliet"), "123")
    }

    func testPayloadReportsWhichTemplatesAreIndistinguishable() {
        let pairs = set.diagnostics.compactMap { diagnostic -> [String]? in
            if case .indistinguishable(let ids, _) = diagnostic { return ids }
            return nil
        }
        // Three pairs share wording; only the reports pairs are unresolvable.
        XCTAssertEqual(pairs.sorted { $0.first! < $1.first! },
                       [["122", "123"], ["317", "318"], ["319", "320"]])
    }

    // MARK: - Specificity

    func testMoreSpecificPhraseWins() {
        // Both score 1.0; the longer literal run is the one actually spoken.
        XCTAssertEqual(id("air india 123 radar maintain 300 knots"), "344")
        XCTAssertEqual(id("air india 123 radar maintain 300 knots or greater"), "346")
        XCTAssertEqual(id("air india 123 radar maintain 300 knots or less"), "348")
    }

    func testLeftAndRightAreNotConfused() {
        XCTAssertEqual(id("air india 123 radar turn left heading 270"), "246")
        XCTAssertEqual(id("air india 123 radar turn right heading 270"), "247")
    }

    func testStopAndContinueVariantsAreDistinguished() {
        XCTAssertEqual(id("air india 123 radar stop climb at flight level 260"), "124")
        XCTAssertEqual(id("air india 123 radar continue descent to flight level 260"), "184")
        XCTAssertEqual(id("air india 123 radar stop turn heading 270"), "254")
        XCTAssertEqual(id("air india 123 radar continue present heading"), "243")
    }

    func testSquawkCharlieIsNotASquawkCode() {
        // "SQUAWK [CODE]" must not claim "charlie" — the code slot is required
        // and unparseable, so that candidate is discarded.
        XCTAssertEqual(id("air india 123 squawk charlie"), "371")
        XCTAssertEqual(id("air india 123 stop squawk charlie"), "437")
        XCTAssertEqual(id("air india 123 squawk 4567"), "218")
        XCTAssertEqual(id("air india 123 confirm squawk 4567"), "216")
    }

    // MARK: - Real phrasings, not template text

    func testAbbreviatedFlightLevelStillMatches() throws {
        // "FL260" contains neither "flight" nor "level" until the lexicon runs.
        // Without that layer this scores 0.2 and matches nothing.
        let match = try XCTUnwrap(match("air india 123 climb to fl260"))
        XCTAssertEqual(match.template.id, "101")
        XCTAssertEqual(match.slot(named: "LEVEL")?.value, .integer(260))
    }

    func testRadarPrefixIsOptional() {
        // Controllers routinely drop "RADAR".
        XCTAssertEqual(id("air india 123 turn left heading 270"), "246")
        XCTAssertEqual(id("air india 123 descend to flight level 260"), "158")
        XCTAssertEqual(id("air india 123 reduce speed to 250 knots"), "361")
    }

    func testNumberWordsFlowThroughToSlots() throws {
        let match = try XCTUnwrap(match("air india 123 fly heading two seven zero"))
        XCTAssertEqual(match.template.id, "245")
        XCTAssertEqual(match.slot(named: "THREE DIGITS")?.value, .integer(270))
    }

    func testTensWordHeading() throws {
        let match = try XCTUnwrap(match("air india 123 fly heading two seventy"))
        XCTAssertEqual(match.slot(named: "THREE DIGITS")?.value, .integer(270))
    }

    func testRunwayTensWordDoesNotBecomeThreeDigits() throws {
        let match = try XCTUnwrap(match("air india 123 radar runway twenty seven cleared for take off"))
        XCTAssertEqual(match.template.id, "436")
        XCTAssertEqual(match.slot(named: "NUMBER")?.value, .runway("27"))
    }

    func testFeetAltitudeIsReadAsMagnitude() throws {
        let match = try XCTUnwrap(match("air india 123 climb to eight thousand feet"))
        XCTAssertEqual(match.template.id, "102")
        XCTAssertEqual(match.slot(named: "ALTITUDE")?.value, .integer(8000))
    }

    // MARK: - Guards against junk matches

    func testASingleMatchedWordIsNotEnough() {
        // "GO TO [WAYPOINT/FIX]" used to claim this on the strength of "to",
        // capturing "300knots" as the fix.
        let ranked = matcher.allMatches(in: normalizer.tokens("increase speed to 300 knots"))
        XCTAssertFalse(ranked.contains { $0.template.id == "446" })
        XCTAssertEqual(ranked.first?.template.id, "359")
    }

    func testCallsignDoesNotAbsorbTheInstruction() throws {
        // Unbounded, the leading [CALLSIGN] slot swallowed everything before the
        // first matched literal — the whole instruction became the callsign.
        let match = try XCTUnwrap(match("air india 123 maintain flight level 260"))
        XCTAssertEqual(match.slot(named: "CALLSIGN")?.value, .text("air india 123"))
        XCTAssertEqual(match.slot(named: "LEVEL")?.value, .integer(260))
    }

    func testCallsignIsNotTakenFromAcrossAnotherInstruction() throws {
        // The speed template's callsign slot must not reach back over the
        // heading instruction to collect "air india 123" — if it does, every
        // match appears to start at word zero and instructions cannot be picked
        // out in order.
        let tokens = normalizer.tokens("air india 123 turn right heading 250 reduce speed to 250 knots")
        let speed = try XCTUnwrap(matcher.allMatches(in: tokens).first { $0.template.id == "361" })
        XCTAssertEqual(speed.slot(named: "CALLSIGN")?.tokens, [])
        XCTAssertGreaterThan(speed.range.lowerBound, 0)
    }

    func testCallsignWithoutAFlightNumberIsNotInvented() throws {
        // Better to report no callsign than to route the instruction to an
        // aircraft the controller never named.
        let match = try XCTUnwrap(match("climb and maintain flight level 260"))
        XCTAssertEqual(match.slot(named: "CALLSIGN")?.tokens, [])
    }

    func testGluedCallsignIsRecognised() throws {
        let match = try XCTUnwrap(match("aca125 fly heading 270"))
        XCTAssertEqual(match.slot(named: "CALLSIGN")?.value, .text("aca125"))
    }

    func testOmittingRadarDoesNotPushMatchesToTheThreshold() throws {
        // With "RADAR" counted, this scored exactly 0.50 — one dropped word from
        // failing. It should be a comfortable match.
        let match = try XCTUnwrap(match("air india 123 turn left heading 270"))
        XCTAssertEqual(match.template.id, "246")
        XCTAssertGreaterThan(match.score, 0.9)
    }

    // MARK: - Phrasings the payload has no exact template for

    func testClimbAndMaintainIsScoredAgainstBothCandidates() throws {
        // The payload has "CLIMB TO AND MAINTAIN **BLOCK** …" but no non-block
        // variant, so "climb and maintain FL260" matches two templates partially:
        // 219 (MAINTAIN FLIGHT LEVEL) scores higher in isolation, while 101
        // (CLIMB TO FLIGHT LEVEL) is the one that explains the word "climb".
        // Which one wins is decided by the left-to-right sweep in
        // CommandRecognizer, not here; both must at least be candidates.
        let ranked = matcher.allMatches(in: normalizer.tokens(
            "air india 123 climb and maintain flight level 260"))
        let ids = ranked.map(\.template.id)
        XCTAssertTrue(ids.contains("219"))
        XCTAssertTrue(ids.contains("101"))
    }

    func testBlockClearanceStillBeatsTheSingleLevelTemplates() throws {
        // The same wording with "block" must not collapse into 219.
        let match = try XCTUnwrap(match(
            "air india 123 climb to and maintain block flight level 260 to flight level 280"))
        XCTAssertEqual(match.template.id, "103")
    }

    // MARK: - Callsign and slots

    func testCallsignIsCaptured() throws {
        let match = try XCTUnwrap(match("air india 123 radar fly heading 270"))
        XCTAssertEqual(match.slot(named: "CALLSIGN")?.value, .text("air india 123"))
    }

    func testCallsignIsOptional() throws {
        // A plain command with no callsign must still match.
        let match = try XCTUnwrap(match("fly heading 270"))
        XCTAssertEqual(match.template.id, "245")
        XCTAssertEqual(match.slot(named: "CALLSIGN")?.tokens, [])
    }

    func testAdjacentSlotsAreSplitByShape() throws {
        // "CONTACT [UNIT CALL SIGN] [FREQUENCY] NOW" — the only template in the
        // payload with two slots side by side.
        let match = try XCTUnwrap(match("air india 123 contact delhi approach 121 decimal 5 now"))
        XCTAssertEqual(match.template.id, "448")
        XCTAssertEqual(match.slot(named: "UNIT CALL SIGN")?.value, .text("delhi approach"))
        XCTAssertEqual(match.slot(named: "FREQUENCY")?.value, .frequency("121.5"))
    }

    func testRepeatedSlotsBothGetValues() throws {
        let match = try XCTUnwrap(match(
            "air india 123 radar climb to and maintain block flight level 260 to flight level 280"))
        XCTAssertEqual(match.template.id, "103")
        let levels = match.slots.filter { $0.name == "LEVEL" }.map(\.value)
        XCTAssertEqual(levels, [.integer(260), .integer(280)])
    }

    func testHoldingFixIsFolded() throws {
        let match = try XCTUnwrap(match(
            "air india 123 proceed direct to papa juliet ndb and hold as published maintain flight level 260"))
        XCTAssertEqual(match.template.id, "453")
        XCTAssertEqual(match.slot(named: "HOLDING FIX")?.value, .fix("PJ"))
        XCTAssertEqual(match.slot(named: "LEVEL")?.value, .integer(260))
    }

    // MARK: - Out-of-range values survive as reports

    func testIllegalHeadingIsReportedNotDropped() throws {
        let match = try XCTUnwrap(match("air india 123 fly heading 450"))
        XCTAssertEqual(match.template.id, "245")
        XCTAssertEqual(match.invalidSlot?.name, "THREE DIGITS")
    }

    // MARK: - Disabled templates still match

    func testDisabledTemplatesAreMatchedNotHidden() throws {
        // show == 0 gates execution, not recognition.
        let match = try XCTUnwrap(match("air india 123 radar service terminated due weather"))
        XCTAssertEqual(match.template.id, "449")
        XCTAssertFalse(match.template.isEnabled)
    }

    // MARK: - Non-matches

    func testUnrelatedSpeechMatchesNothing() {
        XCTAssertNil(match("good morning everybody"))
        XCTAssertNil(match(""))
    }

    // MARK: - Span accuracy

    func testMatchSpanCoversExactlyTheInstruction() throws {
        let tokens = normalizer.tokens("air india 123 radar fly heading 270")
        let match = try XCTUnwrap(matcher.bestMatch(in: tokens))
        XCTAssertEqual(match.range, 0..<tokens.count)
    }

    func testStructuredSlotDoesNotSwallowTrailingWords() throws {
        // The level slot must stop at "260" and leave "and thank you" behind,
        // otherwise selecting a second instruction from one transcript is
        // impossible.
        let tokens = normalizer.tokens("air india 123 descend to flight level 260 and thank you")
        let match = try XCTUnwrap(matcher.bestMatch(in: tokens))
        XCTAssertEqual(match.template.id, "158")
        XCTAssertEqual(match.slot(named: "LEVEL")?.value, .integer(260))
        XCTAssertLessThan(match.range.upperBound, tokens.count)
    }
}
