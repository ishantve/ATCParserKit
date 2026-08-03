//
//  Readback.swift
//  ATCParserKit
//
//  What the pilot says back, ready to speak.
//
//  The backend's `readBackText` cannot be sent to a synthesiser as it stands. It
//  carries English control-flow baked into the string:
//
//      "WILCO, [CALLSIGN]. Later: [CALLSIGN], PASSING [SIGNIFICANT POINT]."
//      "MAINTAINING [LEVEL], [CALLSIGN]. If not: NEGATIVE, [ACTUAL LEVEL], …"
//      "No pilot readback normally required."
//
//  "Later:" and "If not:" are instructions to a reader, not words to utter, and
//  the third is a note rather than a phrase at all. So one field becomes three
//  branches plus a flag.
//
//  Not every slot can be filled from speech. A readback may need the aircraft's
//  *actual* level, or a radial that has to be computed from its position — values
//  the parser has no access to. Those are listed in `unresolvedSlots` and leave
//  `spoken` nil, so a caller fills them from its own state before speaking rather
//  than a placeholder being read out loud.
//

import Foundation

public struct Readback: Equatable, Sendable {

    /// False for entries like "No pilot readback normally required."
    public let isRequired: Bool

    /// The phrase to speak.
    public let primary: Phrase

    /// The "If not:" / "If incorrect:" branch, when the phraseology offers one.
    public let alternate: Phrase?

    /// The "Later:" branch — a report the pilot makes once the condition occurs,
    /// not part of the immediate reply.
    public let deferred: Phrase?

    public init(isRequired: Bool,
                primary: Phrase,
                alternate: Phrase? = nil,
                deferred: Phrase? = nil) {
        self.isRequired = isRequired
        self.primary = primary
        self.alternate = alternate
        self.deferred = deferred
    }

    /// TTS-ready text, or nil when required values are still missing.
    /// The common case is non-nil; that is the whole point of the shortcut.
    public var text: String? { isRequired ? primary.spoken : nil }

    public static let notRequired = Readback(isRequired: false, primary: .empty)
}

// MARK: - Phrase

public struct Phrase: Equatable, Sendable {

    /// Fixed runs and slots in order, so a caller can re-render after supplying
    /// the values the parser could not.
    public let segments: [Segment]

    /// Every slot still without a value.
    public let unresolvedSlots: [String]

    public init(segments: [Segment], unresolvedSlots: [String]) {
        self.segments = segments
        self.unresolvedSlots = unresolvedSlots
    }

    public static let empty = Phrase(segments: [], unresolvedSlots: [])

    public var isEmpty: Bool { segments.isEmpty }

    /// Speakable text, or nil while any slot is unresolved.
    public var spoken: String? {
        guard unresolvedSlots.isEmpty else { return nil }
        return render { $0.spoken ?? "" }
    }

    /// Speakable text with the caller's values substituted for the slots the
    /// parser could not fill. Unsupplied slots keep their placeholder.
    public func spoken(filling values: [String: String]) -> String {
        render { segment in
            if let spoken = segment.spoken { return spoken }
            if let supplied = values[segment.name ?? ""] { return supplied }
            return "[\(segment.name ?? "")]"
        }
    }

    /// Display form: values where known, placeholders where not.
    public var text: String {
        render { $0.spoken ?? "[\($0.name ?? "")]" }
    }

    private func render(_ value: (Segment) -> String) -> String {
        var output = ""
        for segment in segments {
            switch segment {
            case .literal(let run): output += run
            case .slot:             output += value(segment)
            }
        }
        return output
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: " ,", with: ",")
            .replacingOccurrences(of: " .", with: ".")
            .trimmingCharacters(in: .whitespaces)
    }
}

// MARK: - Segment

public enum Segment: Equatable, Sendable {
    /// Verbatim run of template text, casing and punctuation intact.
    case literal(String)
    /// A slot, with its spoken form when the parser could supply one.
    case slot(name: String, kind: SlotKind, spoken: String?)

    public var name: String? {
        if case .slot(let name, _, _) = self { return name }
        return nil
    }

    public var spoken: String? {
        switch self {
        case .literal(let run):            return run
        case .slot(_, _, let spoken):      return spoken
        }
    }
}
