//
//  RecognitionWire.swift
//  ATCParserKit
//
//  JSON wire format for template-driven recognition — the one serialisation point the
//  React Native and Unity wrappers cross.
//
//  The domain types (`RecognitionResult`, `RecognizedCommand`, `SlotValue`, `Readback`) are
//  not themselves `Codable`, on purpose. They carry sum types with payloads, a `Range<Int>`,
//  and a segmented phrase tree — all natural in Swift and all things the consumers cannot
//  express. Unity's `JsonUtility` in particular has no dictionaries, no polymorphism, and no
//  nullable primitives, and it is the *tightest* constraint, so it sets the shape:
//
//    • flat objects, no unions — a sum type becomes a `kind` string plus its fields
//    • no nulls: an absent string is `""`, an absent number is `0` beside a `has…` flag
//    • arrays only inside an object, never at the top level
//
//  Widening this format is a breaking change for JS and C# callers even when Swift compiles,
//  so fields are added, never renamed or repurposed.
//

import Foundation

// MARK: - Public entry points

extension RecognitionResult {

    /// This result as wire DTOs.
    public var wire: WireRecognitionResult { WireRecognitionResult(self) }

    /// This result as a JSON string, with sorted keys so output is deterministic.
    public func toJSON() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return String(decoding: try encoder.encode(wire), as: UTF8.self)
    }
}

// MARK: - Result

public struct WireRecognitionResult: Codable, Equatable, Sendable {

    /// The whole transcript after normalisation.
    public let normalized: String

    /// Instructions in the order they were spoken.
    public let commands: [WireRecognizedCommand]

    /// Stretches of speech no template accounted for. Never omitted — a caller that
    /// cannot see these cannot tell "understood nothing" from "understood everything".
    public let unrecognized: [String]

    /// One spoken reply per aircraft, already grouped.
    ///
    /// Precomputed rather than left to the wrapper: grouping by callsign and composing one
    /// utterance per aircraft is phraseology, not presentation, and reimplementing it in
    /// TypeScript and again in C# is exactly the duplicated logic this package exists to
    /// avoid.
    public let readbacks: [WireReadback]

    public init(_ result: RecognitionResult) {
        normalized = result.normalized
        commands = result.commands.map(WireRecognizedCommand.init)
        unrecognized = result.unrecognized
        readbacks = result.composedReadbacks().map {
            WireReadback(callsign: $0.callsign ?? "", spoken: $0.spoken)
        }
    }
}

public struct WireReadback: Codable, Equatable, Sendable {
    /// Empty when the transmission named no aircraft.
    public let callsign: String
    public let spoken: String

    public init(callsign: String, spoken: String) {
        self.callsign = callsign
        self.spoken = spoken
    }
}

// MARK: - Command

public struct WireRecognizedCommand: Codable, Equatable, Sendable {

    /// Empty when no callsign was spoken and none could be carried forward.
    public let callsign: String
    public let category: String
    public let code: String
    /// Empty when the payload shipped this entry without a code, in which case `code` is a
    /// synthesised fallback and must not be treated as a backend key.
    public let backendCode: String

    /// `"ok"`, `"disabled"` or `"invalidValue"`.
    ///
    /// A string rather than a boolean because there are genuinely three answers, and the
    /// middle one — understood, replied to, must not be executed — is the one a boolean
    /// loses. `isActionable` is provided so the common check cannot be got wrong, but the
    /// distinction stays visible.
    public let outcome: String

    /// True only for `outcome == "ok"`. The single condition for acting on a command.
    public let isActionable: Bool

    /// Whether this deployment allows the instruction at all (the payload's `show`).
    public let isEnabled: Bool

    /// The offending slot when `outcome == "invalidValue"`, otherwise empty.
    public let invalidSlot: String

    /// What the pilot says back, ready for a synthesiser. Empty when no reply is required.
    ///
    /// For a disabled instruction this is already the refusal, not the template's own reply,
    /// so it can be spoken unconditionally; `outcome` decides only whether to act.
    public let readback: String

    /// The reply when a confirmation's honest answer is "negative" (`If not:` in the
    /// template). Empty when the template has no such branch.
    ///
    /// Speaking `readback` where this one applies makes an aircraft answer "affirm" to a
    /// question whose truthful answer is "negative", so both are on the wire and the caller
    /// picks.
    public let readbackAlternate: String

    /// The report the pilot owes later, once a condition is met (`Later:` in the template).
    /// Empty when the template has no such branch.
    public let readbackDeferred: String

    /// Slot names still unfilled in `readback`. Non-empty means the sentence has a hole in
    /// it and the caller must fill those before speaking it.
    public let unresolvedSlots: [String]

    /// Values pulled from the transcript, in template order. A repeated placeholder appears
    /// more than once, so this is a list rather than a map — which also suits `JsonUtility`,
    /// as it cannot decode dictionaries.
    public let slots: [WireSlot]

    /// The transcript text this command was recognised from.
    public let matchedText: String

    /// Templates that matched equally well. Non-empty only where the payload's own wording
    /// cannot tell them apart; surfaced rather than silently resolved.
    public let tiedWith: [String]

    public let score: Double
    public let coverage: Double

    public init(_ command: RecognizedCommand) {
        callsign = command.callsign ?? ""
        category = command.category
        code = command.code
        backendCode = command.backendCode ?? ""
        isEnabled = command.isEnabled
        isActionable = command.isActionable
        matchedText = command.matchedText
        tiedWith = command.tiedWith
        score = command.score
        coverage = command.coverage
        slots = command.slots.map(WireSlot.init)

        switch command.outcome {
        case .ok:
            outcome = "ok"
            invalidSlot = ""
        case .disabled:
            outcome = "disabled"
            invalidSlot = ""
        case .invalidValue(let slot, _):
            outcome = "invalidValue"
            invalidSlot = slot
        }

        readback = command.readback.primary.spoken ?? ""
        readbackAlternate = command.readback.alternate?.spoken ?? ""
        readbackDeferred = command.readback.deferred?.spoken ?? ""
        unresolvedSlots = command.readback.primary.unresolvedSlots
    }
}

// MARK: - Slot

public struct WireSlot: Codable, Equatable, Sendable {

    /// Placeholder name as it appears in the template — "LEVEL", "THREE DIGITS".
    public let name: String

    /// The resolved `SlotKind` — "flightLevel", "runway", "fix"…
    public let kind: String

    /// The value in text form: `"260"`, `"27L"`, `"PJ"`, `"121.5"`.
    ///
    /// One string for every kind, since the consumers cannot express a sum type. `valueKind`
    /// says which case it came from, so nothing is lost.
    public let value: String

    /// Which `SlotValue` case produced `value`: "integer", "runway", "fix", "frequency",
    /// "text". Empty when the slot did not parse.
    public let valueKind: String

    /// The numeric value when `valueKind == "integer"`, else `0`.
    ///
    /// Carried alongside the string so a caller does not re-parse it. Guard on
    /// `hasIntValue`, not on `intValue != 0` — a heading of zero is a real heading.
    public let intValue: Int
    public let hasIntValue: Bool

    /// The transcript tokens this slot claimed. Kept for diagnosing a mis-parse against a
    /// real transcript.
    public let tokens: [String]

    /// False when the slot did not parse, or parsed outside the phraseology's legal range.
    public let isValid: Bool

    /// True when the value should have come from aircraft state rather than speech — the
    /// caller supplies it, the parser cannot.
    public let isStateDerived: Bool

    public init(_ slot: FilledSlot) {
        name = slot.name
        kind = slot.kind.rawValue
        tokens = slot.tokens
        isValid = slot.isValid
        isStateDerived = slot.isStateDerived

        switch slot.value {
        case .integer(let number):
            value = String(number); valueKind = "integer"
            intValue = number;      hasIntValue = true
        case .runway(let text):
            value = text; valueKind = "runway";    intValue = 0; hasIntValue = false
        case .fix(let text):
            value = text; valueKind = "fix";       intValue = 0; hasIntValue = false
        case .frequency(let text):
            value = text; valueKind = "frequency"; intValue = 0; hasIntValue = false
        case .text(let text):
            value = text; valueKind = "text";      intValue = 0; hasIntValue = false
        case nil:
            value = ""; valueKind = ""; intValue = 0; hasIntValue = false
        }
    }
}

// MARK: - Payload diagnostics

extension TemplateSet {

    /// Payload problems found while decoding, as a JSON object of strings.
    ///
    /// An object rather than a bare array because `JsonUtility` cannot decode a top-level
    /// array, and this has to be readable from C# without a third-party JSON library.
    public func diagnosticsJSON() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let wire = WireDiagnostics(issues: diagnostics.map(\.description),
                                  templateCount: templates.count,
                                  enabledCount: enabled.count)
        return String(decoding: try encoder.encode(wire), as: UTF8.self)
    }
}

public struct WireDiagnostics: Codable, Equatable, Sendable {
    /// One human-readable line per problem. Empty when the payload is clean.
    public let issues: [String]
    public let templateCount: Int
    public let enabledCount: Int

    public init(issues: [String], templateCount: Int, enabledCount: Int) {
        self.issues = issues
        self.templateCount = templateCount
        self.enabledCount = enabledCount
    }
}
