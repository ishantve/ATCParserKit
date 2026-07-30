//
//  ReadbackComposer.swift
//  ATCParserKit
//
//  Joins several instructions' readbacks into the single reply a pilot actually
//  gives.
//
//  Real exchange:
//
//      ATC   "Air India 123, climb to FL260, increase speed to 300 knots,
//             turn right heading 250."
//      pilot "Climb to flight level two six zero, increase speed to three zero
//             zero knots, turn right heading two five zero, Air India one two
//             three."
//
//  One transmission, callsign once, at the end. Speaking each readback separately
//  would repeat the callsign three times — and with a synthesiser that cancels its
//  previous utterance, only the last of them would be heard at all.
//
//  This lives in the kit rather than the app because it is pure text assembly, and
//  a caller on any platform needs the same result.
//

import Foundation

public enum ReadbackComposer {

    /// The spoken reply for one aircraft's instructions, or nil when none of them
    /// call for a readback.
    ///
    /// Callsign segments are dropped from the individual phrases and one is
    /// appended at the end. Instructions still carrying unresolved slots are left
    /// out: a phrase read aloud with "[ACTUAL LEVEL]" in it is worse than a
    /// shorter reply.
    public static func compose(_ commands: [RecognizedCommand],
                               callsign: String?) -> String? {
        let parts = commands
            .filter { $0.readback.isRequired }
            .compactMap { spokenBody(of: $0.readback.primary) }
            .filter { !$0.isEmpty }

        guard !parts.isEmpty else { return nil }

        var spoken = parts.joined(separator: ", ")
        if let callsign, !callsign.isEmpty {
            spoken += ", " + SlotValue.text(callsign).spoken(as: .callsign)
        }
        return tidy(spoken)
    }

    /// A phrase with its callsign removed, so the composed reply can carry one.
    private static func spokenBody(of phrase: Phrase) -> String? {
        guard phrase.unresolvedSlots.allSatisfy({ $0 == "CALLSIGN" }) else { return nil }

        var body = ""
        for segment in phrase.segments {
            switch segment {
            case .literal(let run):
                body += run
            case .slot(let name, _, let spoken):
                guard name != "CALLSIGN" else { continue }
                body += spoken ?? ""
            }
        }
        return tidy(body).isEmpty ? nil : tidy(body)
    }

    /// Cleans up the punctuation left behind when a callsign is lifted out of the
    /// middle of a phrase.
    private static func tidy(_ text: String) -> String {
        text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: " ,", with: ",")
            .replacingOccurrences(of: " .", with: ".")
            .replacingOccurrences(of: ",,", with: ",")
            .replacingOccurrences(of: ", ,", with: ",")
            .trimmingCharacters(in: CharacterSet(charactersIn: " ,.;:"))
    }
}
