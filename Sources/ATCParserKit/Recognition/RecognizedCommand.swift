//
//  RecognizedCommand.swift
//  ATCParserKit
//
//  The parser's output: a flat, ordered list of instructions, each carrying its
//  own callsign.
//
//  It is a list rather than a single object because one transmission genuinely
//  holds several instructions, and sometimes several aircraft. Each command
//  carrying its own callsign — rather than grouping commands under a
//  transmission — keeps the shape flat and lets a caller group by callsign when
//  it wants to.
//
//  `outcome` is an enum rather than a success flag on purpose. "Did it work" has
//  more than two answers here: a phrase can be understood but disabled for this
//  deployment, or understood with a value outside legal limits. Collapsing those
//  into `false` leaves the caller with nothing to say beyond "not recognised",
//  which is exactly the unhelpful feedback this rewrite exists to replace.
//
//  Two things this deliberately does not carry: whether the named aircraft is on
//  frequency, and what the command does to an aircraft. The parser cannot know
//  either — the first is caller state, the second is simulator behaviour. Both
//  are decided downstream from `code`.
//

import Foundation

public struct RecognizedCommand: Equatable, Sendable {

    /// Callsign as spoken, carried forward from an earlier command in the same
    /// transmission when this one did not repeat it. Nil when none was given.
    public let callsign: String?

    /// Payload category key — "vectoring", "climb", "speedcontrol"…
    /// A presentational grouping; do not switch behaviour on it.
    public let category: String

    /// Stable template identifier — the backend `abbreviationCode` where
    /// present. This is the key downstream layers act on.
    public let code: String

    /// Nil when the backend shipped this entry without an `abbreviationCode`,
    /// in which case `code` is a synthesised fallback.
    public let backendCode: String?

    /// Values pulled from the transcript, in template order. A repeated
    /// placeholder appears more than once, so this is a list.
    public let slots: [FilledSlot]

    /// Whether this deployment allows the instruction to be acted on (`show`).
    public let isEnabled: Bool

    public let outcome: Outcome

    /// What the pilot says back, ready for a synthesiser. For a disabled
    /// instruction this is the refusal, not the template's own reply, so a caller
    /// speaks `readback` unconditionally and consults `outcome` only to decide
    /// whether to act.
    public let readback: Readback

    /// The transcript text this command was recognised from.
    public let matchedText: String

    /// Templates that were equally good matches. Non-empty only where the
    /// payload's wording cannot distinguish them; the caller resolves using
    /// data the parser does not have.
    public let tiedWith: [String]

    /// How much of the template's wording was actually present, and how much of
    /// the matched span it explained. Exposed for telemetry and threshold
    /// tuning against real transcripts.
    public let score: Double
    public let coverage: Double

    public init(callsign: String?,
                category: String,
                code: String,
                backendCode: String?,
                slots: [FilledSlot],
                isEnabled: Bool,
                outcome: Outcome,
                readback: Readback,
                matchedText: String,
                tiedWith: [String],
                score: Double,
                coverage: Double) {
        self.callsign = callsign
        self.category = category
        self.code = code
        self.backendCode = backendCode
        self.slots = slots
        self.isEnabled = isEnabled
        self.outcome = outcome
        self.readback = readback
        self.matchedText = matchedText
        self.tiedWith = tiedWith
        self.score = score
        self.coverage = coverage
    }

    public enum Outcome: Equatable, Sendable {
        /// Understood, legal, and permitted — act on it.
        case ok
        /// Understood, but `show == 0`: answer, do not act.
        case disabled
        /// Understood, but a value falls outside the phraseology's limits.
        case invalidValue(slot: String, value: SlotValue)
    }

    public func slot(named name: String) -> FilledSlot? {
        slots.first { $0.name == name }
    }

    /// Convenience for the common branch: is this one to execute?
    public var isActionable: Bool { outcome == .ok }
}

// MARK: - Result

public struct RecognitionResult: Equatable, Sendable {

    /// Instructions in the order they were spoken.
    public let commands: [RecognizedCommand]

    /// The whole transcript after normalisation — useful for logs and telemetry.
    public let normalized: String

    /// Stretches of speech no template accounted for.
    ///
    /// Reported rather than dropped: in a training simulator "I did not
    /// understand *climb and*" teaches something, while silence looks like the
    /// instruction was accepted.
    public let unrecognized: [String]

    public init(commands: [RecognizedCommand],
                normalized: String,
                unrecognized: [String]) {
        self.commands = commands
        self.normalized = normalized
        self.unrecognized = unrecognized
    }

    public var isEmpty: Bool { commands.isEmpty }

    /// Commands grouped by the aircraft they address, in first-mention order.
    public func groupedByCallsign() -> [(callsign: String?, commands: [RecognizedCommand])] {
        var order: [String] = []
        var grouped: [String: [RecognizedCommand]] = [:]
        for command in commands {
            let key = command.callsign ?? ""
            if grouped[key] == nil { order.append(key) }
            grouped[key, default: []].append(command)
        }
        return order.map { (callsign: $0.isEmpty ? nil : $0, commands: grouped[$0] ?? []) }
    }

    /// One spoken reply per aircraft.
    ///
    /// A pilot given three instructions answers once — every instruction, then the
    /// callsign at the end — rather than three separate readbacks with the
    /// callsign each time. Speaking them individually also gets them cut off, one
    /// utterance interrupting the last.
    public func composedReadbacks() -> [(callsign: String?, spoken: String)] {
        groupedByCallsign().compactMap { group in
            guard let spoken = ReadbackComposer.compose(group.commands,
                                                        callsign: group.callsign)
            else { return nil }
            return (callsign: group.callsign, spoken: spoken)
        }
    }
}
