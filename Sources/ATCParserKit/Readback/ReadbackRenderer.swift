//
//  ReadbackRenderer.swift
//  ATCParserKit
//
//  Builds a speakable readback from a template's `readBackText` and the values a
//  match extracted.
//
//  Three jobs:
//
//    1. Split the prose. "Later:" and "If not:" mark branches, not speech.
//    2. Fill the slots. By position, not by name — a block clearance echoes
//       [LEVEL] twice, and matching on name alone would put the lower level in
//       both places.
//    3. Speak the numbers properly. "260" is "two six zero", never "two hundred
//       sixty"; an altitude is the other way round.
//
//  Rendering works on the template text rather than its tokens, so casing and
//  punctuation survive: "ILS" stays upper case for the synthesiser to spell out,
//  and the commas are what give the phrase its pauses.
//

import Foundation

public struct ReadbackRenderer: Sendable {

    public var registry: SlotRegistry

    public init(registry: SlotRegistry = .default) {
        self.registry = registry
    }

    /// Markers the backend uses for conditional and deferred branches. Matched
    /// case-insensitively; the payload is inconsistent about the punctuation
    /// before them (code 409 uses a comma where the others use a full stop).
    private static let alternateMarkers = ["if not:", "if incorrect:"]
    private static let deferredMarkers = ["later:"]

    /// Sentinel for entries that are a note rather than a phrase.
    private static let noReadbackSentinel = "no pilot readback"

    // MARK: - Entry points

    /// Readback for a matched command. `callsign` is passed separately because it
    /// may have been carried forward from an earlier instruction in the same
    /// transmission rather than spoken again in this one.
    public func render(_ template: CommandTemplate,
                       slots: [FilledSlot],
                       callsign: String?) -> Readback {
        render(pattern: template.readback,
               values: Self.values(from: slots),
               callsign: callsign)
    }

    /// Extracted values keyed by name, keeping repeats in the order they appeared.
    private static func values(from slots: [FilledSlot]) -> [String: [SlotValue]] {
        var values: [String: [SlotValue]] = [:]
        for slot in slots where slot.value != nil {
            values[slot.name, default: []].append(slot.value!)
        }
        return values
    }

    /// Readback for a phrase supplied by the caller rather than the payload —
    /// used for the reply to a disabled instruction.
    public func render(text: String, callsign: String?) -> Readback {
        render(pattern: TemplatePattern(text), values: [:], callsign: callsign)
    }

    /// Readback for a command assembled from values rather than recognised from
    /// speech.
    ///
    /// A command keyboard picks the template outright and collects its values on a
    /// keypad, so there is no transcript and no match — but the reply should be the
    /// same ICAO phraseology a spoken instruction gets. Values are listed per name
    /// because a placeholder can repeat.
    public func render(_ template: CommandTemplate,
                       values: [String: [SlotValue]],
                       callsign: String?) -> Readback {
        render(pattern: template.readback, values: values, callsign: callsign)
    }

    // MARK: - Building

    private func render(pattern: TemplatePattern,
                        values: [String: [SlotValue]],
                        callsign: String?) -> Readback {
        let text = pattern.text
        guard !text.isEmpty else { return .notRequired }
        if text.lowercased().contains(Self.noReadbackSentinel) { return .notRequired }

        let split = Self.split(text)
        // Slots are consumed left to right across the whole readback, so the
        // second [LEVEL] of a block clearance gets the second value.
        var queue = SlotQueue(values: values, callsign: callsign)

        return Readback(
            isRequired: true,
            primary: phrase(from: split.primary, queue: &queue),
            alternate: split.alternate.map { phrase(from: $0, queue: &queue) },
            deferred: split.deferred.map { phrase(from: $0, queue: &queue) })
    }

    private func phrase(from text: String, queue: inout SlotQueue) -> Phrase {
        let pattern = TemplatePattern(text)
        var segments: [Segment] = []
        var unresolved: [String] = []
        var slotIndex = 0

        for part in pattern.parts {
            switch part {
            case .text(let run):
                segments.append(.literal(String(run)))
            case .slot(let name):
                let kind = registry.kind(at: slotTokenIndex(slotIndex, in: pattern),
                                         in: pattern)
                slotIndex += 1
                let spoken = queue.next(name: name, kind: kind)
                if spoken == nil { unresolved.append(name) }
                segments.append(.slot(name: name, kind: kind, spoken: spoken))
            }
        }
        return Phrase(segments: segments, unresolvedSlots: unresolved)
    }

    /// Position of the nth slot within a pattern's token list, which is what the
    /// registry needs to read the literals either side of it.
    private func slotTokenIndex(_ ordinal: Int, in pattern: TemplatePattern) -> Int {
        var seen = 0
        for (index, token) in pattern.tokens.enumerated() {
            if case .slot = token {
                if seen == ordinal { return index }
                seen += 1
            }
        }
        return 0
    }

    // MARK: - Prose splitting

    struct Split: Equatable {
        var primary: String
        var alternate: String?
        var deferred: String?
    }

    /// Cuts the readback at its branch markers. A marker appearing twice — code
    /// 411 repeats "If not:" — yields one branch, not two.
    static func split(_ text: String) -> Split {
        var cuts: [(index: String.Index, marker: String, isDeferred: Bool)] = []
        let lowered = text.lowercased()

        for marker in alternateMarkers + deferredMarkers {
            var searchFrom = lowered.startIndex
            while let found = lowered.range(of: marker, range: searchFrom..<lowered.endIndex) {
                cuts.append((found.lowerBound, marker,
                             deferredMarkers.contains(marker)))
                searchFrom = found.upperBound
            }
        }
        // With no branch to cut away, the closing full stop is the phrase's own
        // punctuation and stays. Trimming is only for the punctuation left
        // dangling where a marker was removed.
        guard !cuts.isEmpty else {
            return Split(primary: text.trimmingCharacters(in: .whitespaces))
        }
        cuts.sort { $0.index < $1.index }

        var split = Split(primary: trim(String(text[text.startIndex..<cuts[0].index])))
        for (position, cut) in cuts.enumerated() {
            let start = text.index(cut.index, offsetBy: cut.marker.count)
            let end = position + 1 < cuts.count ? cuts[position + 1].index : text.endIndex
            let body = trim(String(text[start..<end]))
            guard !body.isEmpty else { continue }
            if cut.isDeferred {
                if split.deferred == nil { split.deferred = body }
            } else if split.alternate == nil {
                split.alternate = body
            }
        }
        return split
    }

    /// Drops the punctuation left dangling where a branch was cut away.
    private static func trim(_ text: String) -> String {
        text.trimmingCharacters(in: CharacterSet(charactersIn: " ,.;:"))
    }
}

// MARK: - Slot queue

/// Hands out extracted values in template order.
///
/// Matching by name alone breaks on repeated placeholders, and a readback may ask
/// for values that were never spoken — the aircraft's *actual* level, a radial to
/// be computed from its position. Those come back nil so they can be reported as
/// unresolved rather than silently rendered as a placeholder.
private struct SlotQueue {

    private var byName: [String: [SlotValue]]
    private let callsign: String?

    init(values: [String: [SlotValue]], callsign: String?) {
        self.byName = values
        self.callsign = callsign
    }

    mutating func next(name: String, kind: SlotKind) -> String? {
        if name == "CALLSIGN" {
            guard let callsign, !callsign.isEmpty else { return nil }
            return SlotValue.text(callsign).spoken(as: .callsign)
        }
        guard var queued = byName[name], let value = queued.first else { return nil }
        queued.removeFirst()
        byName[name] = queued
        return value.spoken(as: kind)
    }
}
