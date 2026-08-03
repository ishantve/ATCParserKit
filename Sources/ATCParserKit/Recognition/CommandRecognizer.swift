//
//  CommandRecognizer.swift
//  ATCParserKit
//
//  Turns one transcript into every instruction it contains.
//
//  Selection is a left-to-right sweep. At each position the best match is taken,
//  the cursor jumps past it, and the sweep continues — so instructions come out
//  in the order they were spoken, and no two claim the same words. Anything the
//  sweep steps over is reported as unrecognised rather than discarded.
//
//  Two things keep the sweep honest:
//
//    • The matcher's coverage rule stops a template reaching across the whole
//      transmission to collect its literals.
//    • Punctuation, where present, caps the search window. Speech has no commas,
//      but typed and simulated input does, and a comma is the strongest
//      available hint that one instruction ended.
//
//  Callsigns carry forward. A controller says the callsign once — "Air India 123,
//  climb to FL260, increase speed to 300 knots" — so a command without one
//  inherits from the most recent command that had one. A new callsign starts a
//  new aircraft, which is what makes several aircraft in one transmission work.
//
//  Templates are injected, never fetched: this type stays free of networking so
//  the same logic serves native, React Native and Unity callers.
//

import Foundation

public struct CommandRecognizer: Sendable {

    public let matcher: TemplateMatcher
    public let normalizer: TranscriptNormalizer
    public let renderer: ReadbackRenderer

    /// Reply spoken when a recognised instruction is switched off for this
    /// deployment (`show == 0`).
    ///
    /// Injected rather than hard-coded: the whole design puts phraseology in the
    /// payload, and one sentence baked into the kit could never be changed per
    /// setup or language. Ideally the backend ships this alongside the templates;
    /// the default keeps things working until it does. "UNABLE" is the ICAO
    /// wording for "cannot comply" — "NEGATIVE" would claim the controller was
    /// misheard, which is a different thing.
    public let disabledReadback: String

    public init(templates: TemplateSet,
                registry: SlotRegistry = .default,
                lexicon: Lexicon = .default,
                minimumScore: Double = 0.5,
                minimumCoverage: Double = 0.6,
                disabledReadback: String = "UNABLE, [CALLSIGN].") {
        self.matcher = TemplateMatcher(templates: templates,
                                       registry: registry,
                                       minimumScore: minimumScore,
                                       minimumCoverage: minimumCoverage)
        self.normalizer = TranscriptNormalizer(lexicon: lexicon)
        self.renderer = ReadbackRenderer(registry: registry)
        self.disabledReadback = disabledReadback
    }

    public init(matcher: TemplateMatcher,
                normalizer: TranscriptNormalizer = .init(),
                renderer: ReadbackRenderer = .init(),
                disabledReadback: String = "UNABLE, [CALLSIGN].") {
        self.matcher = matcher
        self.normalizer = normalizer
        self.renderer = renderer
        self.disabledReadback = disabledReadback
    }

    // MARK: - Entry point

    public func recognize(_ transcript: String) -> RecognitionResult {
        let normalized = normalizer.normalize(transcript)
        let tokens = normalized.tokens
        guard !tokens.isEmpty else {
            return RecognitionResult(commands: [], normalized: "", unrecognized: [])
        }

        let (matches, gaps) = select(in: tokens, boundaries: normalized.boundaries)

        return RecognitionResult(
            commands: build(from: matches, tokens: tokens),
            normalized: normalized.text,
            unrecognized: gaps.map { tokens[$0].joined(separator: " ") })
    }

    // MARK: - Non-overlapping selection

    private func select(in tokens: [String],
                        boundaries: Set<Int>) -> ([TemplateMatch], [Range<Int>]) {
        var matches: [TemplateMatch] = []
        var gaps: [Range<Int>] = []
        var cursor = 0

        while cursor < tokens.count {
            guard let match = nextMatch(in: tokens, from: cursor, boundaries: boundaries) else {
                // Nothing starts here. Grow the current gap and step on.
                appendGap(cursor..<(cursor + 1), to: &gaps)
                cursor += 1
                continue
            }
            // Words skipped before the match belong to nobody.
            if match.range.lowerBound > cursor {
                appendGap(cursor..<match.range.lowerBound, to: &gaps)
            }
            matches.append(match)
            cursor = max(match.range.upperBound, cursor + 1)
        }
        return (matches, gaps)
    }

    /// Best match at or after `cursor`, preferring one that stays inside the
    /// current punctuated clause before falling back to the rest of the
    /// transmission.
    private func nextMatch(in tokens: [String],
                           from cursor: Int,
                           boundaries: Set<Int>) -> TemplateMatch? {
        if let clauseEnd = boundaries.filter({ $0 >= cursor }).min(),
           clauseEnd + 1 < tokens.count,
           let inClause = matcher.earliestMatch(in: tokens, range: cursor..<(clauseEnd + 1)) {
            return inClause
        }
        return matcher.earliestMatch(in: tokens, range: cursor..<tokens.count)
    }

    /// Merges a gap into the previous one when they touch, so "climb and" is
    /// reported as one fragment rather than two words.
    private func appendGap(_ range: Range<Int>, to gaps: inout [Range<Int>]) {
        if let last = gaps.last, last.upperBound == range.lowerBound {
            gaps[gaps.count - 1] = last.lowerBound..<range.upperBound
        } else {
            gaps.append(range)
        }
    }

    // MARK: - Assembly

    private func build(from matches: [TemplateMatch], tokens: [String]) -> [RecognizedCommand] {
        var carried: String?

        return matches.map { match in
            let spoken = match.slot(named: "CALLSIGN")?.value
            if case .text(let callsign) = spoken, !callsign.isEmpty {
                carried = callsign
            }

            // A disabled instruction is answered, not obeyed — so it gets the
            // refusal in place of the template's own reply, letting a caller speak
            // `readback` without branching.
            let readback = match.template.isEnabled
                ? renderer.render(match.template, slots: match.slots, callsign: carried)
                : renderer.render(text: disabledReadback, callsign: carried)

            return RecognizedCommand(
                callsign: carried,
                category: match.template.category,
                code: match.template.id,
                backendCode: match.template.code,
                slots: match.slots,
                isEnabled: match.template.isEnabled,
                outcome: Self.outcome(for: match),
                readback: readback,
                matchedText: tokens[match.range].joined(separator: " "),
                tiedWith: match.tiedWith,
                score: match.score,
                coverage: match.coverage)
        }
    }

    /// An illegal value outranks a disabled template: telling the controller the
    /// heading was 450 is more use than telling them the phrase is switched off.
    private static func outcome(for match: TemplateMatch) -> RecognizedCommand.Outcome {
        if let invalid = match.invalidSlot, let value = invalid.value {
            return .invalidValue(slot: invalid.name, value: value)
        }
        return match.template.isEnabled ? .ok : .disabled
    }
}
