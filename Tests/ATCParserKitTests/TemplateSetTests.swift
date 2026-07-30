//
//  TemplateSetTests.swift
//  ATCParserKit
//
//  Locks the backend phraseology contract against the real payload fixture:
//  inventory (what we have), sanitisation (what we clean), and diagnostics
//  (what the backend should fix). If the payload changes shape, these fail
//  loudly instead of the matcher silently losing templates.
//

import XCTest
@testable import ATCParserKit

final class TemplateSetTests: XCTestCase {

    private var set: TemplateSet!

    override func setUpWithError() throws {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: "templates",
                              withExtension: "json",
                              subdirectory: "Fixtures"),
            "templates.json fixture missing")
        set = try TemplateSet(data: Data(contentsOf: url))
    }

    // MARK: - Inventory

    func testInventory() {
        XCTAssertEqual(set.categories.count, 24)
        XCTAssertEqual(set.templates.count, 75)
        XCTAssertEqual(set.enabled.count, 67)
        XCTAssertEqual(set.disabled.count, 8)
    }

    func testCategoriesAreSortedAndComplete() {
        XCTAssertEqual(set.categories, [
            "approach", "climb", "departure", "descend", "freqtransfer",
            "genphrase", "hold", "identification", "ilsvectoring", "levelcheck",
            "maintain", "missed", "pressurealt", "qnhtrans", "radarterm",
            "reports", "roger", "speedcontrol", "squawk", "standby",
            "takeoffclr", "termpressalt", "vectorapproach", "vectoring",
        ])
    }

    func testPerCategoryCounts() {
        let expected = [
            "approach": 2, "climb": 9, "departure": 1, "descend": 6,
            "freqtransfer": 1, "genphrase": 5, "hold": 3, "identification": 2,
            "ilsvectoring": 8, "levelcheck": 1, "maintain": 5, "missed": 1,
            "pressurealt": 2, "qnhtrans": 1, "radarterm": 1, "reports": 5,
            "roger": 1, "speedcontrol": 6, "squawk": 2, "standby": 3,
            "takeoffclr": 1, "termpressalt": 1, "vectorapproach": 1, "vectoring": 7,
        ]
        for (category, count) in expected {
            XCTAssertEqual(set.templates(in: category).count, count, "category '\(category)'")
        }
    }

    func testDisabledTemplatesAreTheExpectedOnes() {
        XCTAssertEqual(set.disabled.map(\.id).sorted(),
                       ["267", "406", "407", "408", "410", "411", "412", "449"])
    }

    func testEveryTemplateHasAUsablePatternAndReadback() {
        for template in set.templates {
            XCTAssertFalse(template.pattern.isEmpty, "[\(template.id)] empty pattern")
            XCTAssertFalse(template.readback.isEmpty, "[\(template.id)] empty readback")
        }
    }

    func testIDsAreUnique() {
        XCTAssertEqual(Set(set.templates.map(\.id)).count, set.templates.count)
    }

    // MARK: - Slot inventory

    /// The placeholder vocabulary the SlotRegistry has to cover. A new
    /// placeholder from the backend should fail here, not go unnoticed.
    func testSlotVocabulary() {
        let slots = Set(set.templates.flatMap { $0.pattern.slotNames + $0.readback.slotNames })
        XCTAssertEqual(slots.sorted(), [
            "ACTUAL CODE", "ACTUAL LEVEL", "ALTITUDE", "CALLSIGN", "CODE",
            "DISTANCE", "DME STATION", "FREQUENCY", "HOLDING FIX", "INTENTIONS",
            "LEVEL", "NUMBER", "NUMBER OF DEGREES", "POSITION", "REASON",
            "SIGNIFICANT POINT", "STANDARD DEPARTURE NAME AND NUMBER",
            "THREE DIGITS", "TIME", "TYPE OF APPROACH", "UNIT CALL SIGN",
            "UNIT NAME", "VALUE", "VOR NAME", "WAYPOINT/FIX",
        ])
    }

    // MARK: - Sanitisation

    func testInnerWhitespaceInSlotNameIsStripped() throws {
        // Payload ships "[TIME ]".
        let template = try XCTUnwrap(set.template(id: "122"))
        XCTAssertTrue(template.pattern.slotNames.contains("TIME"))
        XCTAssertFalse(template.pattern.text.contains("[TIME ]"))
    }

    func testTrailingSeparatorInSlotNameIsStripped() throws {
        // Payload ships "[WAYPOINT/FIX/]" in the template and "[WAYPOINT/FIX]"
        // in the readback — both must land on one name.
        let template = try XCTUnwrap(set.template(id: "445"))
        XCTAssertEqual(template.pattern.slotNames, ["CALLSIGN", "WAYPOINT/FIX"])
        XCTAssertEqual(template.readback.slotNames, ["WAYPOINT/FIX", "CALLSIGN"])
    }

    func testDoubleSpacesAreCollapsed() throws {
        let template = try XCTUnwrap(set.template(id: "158"))
        XCTAssertEqual(template.pattern.text,
                       "[CALLSIGN] RADAR DESCEND TO FLIGHT LEVEL [LEVEL]")
    }

    func testPunctuationSurvivesRenderingButNotMatching() throws {
        let template = try XCTUnwrap(set.template(id: "327"))
        // Rendering keeps the comma — TTS needs the pause.
        XCTAssertEqual(template.pattern.text, "[CALLSIGN], GO AROUND")
        // Matching sees clean lowercase words.
        XCTAssertEqual(template.pattern.tokens,
                       [.slot("CALLSIGN"), .literal("go"), .literal("around")])
    }

    func testRepeatedSlotIsPreservedAsAList() throws {
        // Block clearances use [LEVEL] twice — a name-keyed dictionary would
        // silently drop one of them.
        let template = try XCTUnwrap(set.template(id: "103"))
        XCTAssertEqual(template.pattern.slotNames, ["CALLSIGN", "LEVEL", "LEVEL"])
    }

    func testBlankOptionalFieldsBecomeNil() throws {
        let template = try XCTUnwrap(set.template(id: "101"))
        XCTAssertNil(template.keyboardShortcut)   // payload sends ""
        XCTAssertNil(template.comments)           // payload sends ""
    }

    // MARK: - Diagnostics

    func testMissingCodesAreReportedAndGivenFallbackIDs() {
        let missing = set.diagnostics.compactMap { diagnostic -> String? in
            if case .missingCode(let id, _) = diagnostic { return id } else { return nil }
        }
        XCTAssertEqual(missing.sorted(), ["hold#1", "hold#2"])
    }

    func testCode320SlotMismatchIsReported() {
        // Template says "FROM [SIGNIFICANT POINT]", readback says
        // "FROM [DME STATION]" — a copy-paste slip.
        let reported = set.diagnostics.contains { diagnostic in
            if case .slotsMissingFromReadback(let id, let slots) = diagnostic {
                return id == "320" && slots.contains("SIGNIFICANT POINT")
            }
            return false
        }
        XCTAssertTrue(reported, "code 320 template/readback slot mismatch not reported")
    }

    func testRepeatedReadbackClauseIsReported() {
        // Code 411 repeats "If not: NEGATIVE, [CALLSIGN]." twice.
        let reported = set.diagnostics.contains { diagnostic in
            if case .repeatedReadbackClause(let id, _, let count) = diagnostic {
                return id == "411" && count == 2
            }
            return false
        }
        XCTAssertTrue(reported, "code 411 duplicated clause not reported")
    }

    func testStateDerivedReadbackSlotsAreReported() {
        // These need aircraft state, not transcript text — the app has to fill
        // them, so the parser must surface that they exist.
        let byID = Dictionary(grouping: set.diagnostics.compactMap { diagnostic -> (String, [String])? in
            if case .slotsNotInTemplate(let id, let slots) = diagnostic { return (id, slots) }
            return nil
        }, by: \.0).mapValues { $0.flatMap(\.1) }

        XCTAssertEqual(byID["430"], ["ACTUAL LEVEL"])
        XCTAssertEqual(byID["216"], ["ACTUAL CODE"])
        XCTAssertEqual(byID["442"], ["INTENTIONS"])
        XCTAssertEqual(byID["258"]?.sorted(), ["LEVEL", "THREE DIGITS"])
    }

    func testNoDuplicateCodes() {
        let duplicates = set.diagnostics.filter {
            if case .duplicateCode = $0 { return true } else { return false }
        }
        XCTAssertTrue(duplicates.isEmpty, "unexpected duplicate codes: \(duplicates)")
    }

    /// Not an assertion so much as a printed work-list for the backend.
    func testPrintDiagnosticSummary() {
        let grouped = Dictionary(grouping: set.diagnostics) { diagnostic -> String in
            switch diagnostic {
            case .missingCode:               return "missingCode"
            case .duplicateCode:             return "duplicateCode"
            case .emptyTemplate:             return "emptyTemplate"
            case .emptyReadback:             return "emptyReadback"
            case .sanitised:                 return "sanitised"
            case .slotsNotInTemplate:        return "slotsNotInTemplate"
            case .slotsMissingFromReadback:  return "slotsMissingFromReadback"
            case .repeatedReadbackClause:    return "repeatedReadbackClause"
            case .indistinguishable:         return "indistinguishable"
            }
        }
        print("── TemplateSet diagnostics (\(set.diagnostics.count)) ──")
        for key in grouped.keys.sorted() {
            print("\(key): \(grouped[key]!.count)")
            for diagnostic in grouped[key]! { print("   • \(diagnostic)") }
        }
    }
}
