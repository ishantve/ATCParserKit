//
//  TemplateMatcher.swift
//  ATCParserKit
//
//  Aligns a normalised transcript against the template vocabulary.
//
//  Templates are exact ICAO text; controllers are not. "RADAR" gets dropped,
//  "TO" gets swallowed, filler creeps in. So matching is by **literal
//  subsequence**: a template's fixed words must appear in the transcript in
//  order, but not necessarily adjacently, and not necessarily all of them.
//  Whatever sits between two matched literals is the slot value.
//
//  Ranking, in order:
//
//    1. score            matched literals ÷ template literals
//    2. matched literals absolute count — breaks the tie between
//                        "MAINTAIN [N] KNOTS" (2/2) and
//                        "MAINTAIN [N] KNOTS OR GREATER" (4/4) in favour of
//                        the more specific phrase actually spoken
//    3. clean slots      a candidate whose values are all in range beats one
//                        that only fits by accepting an illegal value
//
//  A candidate is discarded outright when a *required* slot cannot be parsed —
//  that is what stops "SQUAWK [CODE]" claiming "squawk charlie". Callsign and
//  free-text slots are optional, because a plain command has no callsign and a
//  controller may omit a reason.
//
//  Spans are tracked precisely rather than "start of transcript to last matched
//  word", because selecting several non-overlapping matches from one transcript
//  depends on knowing exactly which tokens a match consumed.
//

import Foundation

public struct TemplateMatcher: Sendable {

    public let templates: TemplateSet
    public let registry: SlotRegistry
    /// Minimum share of a template's literals that must be present.
    public let minimumScore: Double

    /// Least share of a match's own span that it must actually explain.
    ///
    /// Subsequence matching has no sense of distance on its own: given a whole
    /// utterance, "TURN RIGHT HEADING [x]" happily finds "turn", "right" and
    /// "heading" scattered across eighteen tokens and claims all of them.
    /// Requiring a match to account for most of the words it covers keeps
    /// matches local, which is what makes picking several of them out of one
    /// transcript possible.
    public let minimumCoverage: Double

    /// How many words a literal may be searched past when no slot is waiting to
    /// absorb them.
    ///
    /// Subsequence matching is otherwise happy to satisfy a literal from far
    /// away, which quietly wrecks the alignment that follows it. Given
    /// "climb and maintain flight level 260 increase speed to 300 knots",
    /// "CLIMB **TO** FLIGHT LEVEL" matched its "to" against the one in "speed to
    /// 300" eight words later, then failed to find "flight" and "level" after it —
    /// so the template that fitted best was "STOP CLIMB AT FLIGHT LEVEL". With a
    /// gap limit, the distant "to" is simply treated as not spoken.
    ///
    /// When a slot *is* pending the gap is unrestricted, because the slot is what
    /// those words belong to.
    public let maximumLiteralGap: Int

    /// Literals that controllers routinely omit. When absent they drop out of
    /// the score's denominator instead of counting as a miss.
    ///
    /// "RADAR" prefixes most of the payload and is almost never spoken, so
    /// charging templates for it squeezed real phrasings down to the threshold —
    /// "turn left heading 270" scored exactly 0.50 against
    /// "RADAR TURN LEFT HEADING [THREE DIGITS]", one dropped word from failing.
    public let optionalLiterals: Set<String>

    /// Slots resolved once per template, cached alongside the literal list.
    private let compiled: [Compiled]
    /// literal → indices into `compiled`, so a transcript only scores the
    /// templates it shares vocabulary with rather than all of them.
    private let literalIndex: [String: [Int]]

    public init(templates: TemplateSet,
                registry: SlotRegistry = .default,
                minimumScore: Double = 0.5,
                minimumCoverage: Double = 0.6,
                maximumLiteralGap: Int = 2,
                optionalLiterals: Set<String> = ["radar", "the"]) {
        self.templates = templates
        self.registry = registry
        self.minimumScore = minimumScore
        self.minimumCoverage = minimumCoverage
        self.maximumLiteralGap = maximumLiteralGap
        self.optionalLiterals = optionalLiterals

        let compiled = templates.templates.map { template in
            Compiled(template: template,
                     slots: registry.resolve(template.pattern),
                     literals: template.pattern.literals)
        }
        self.compiled = compiled

        var index: [String: [Int]] = [:]
        for (position, entry) in compiled.enumerated() {
            for literal in Set(entry.literals) {
                index[literal, default: []].append(position)
            }
        }
        self.literalIndex = index
        self.vocabulary = Set(index.keys)
    }

    /// Every fixed word used anywhere in the vocabulary. A callsign candidate may
    /// not be built from these — without that guard "turn left heading 270" fits
    /// the callsign shape (three words then a number) perfectly.
    private let vocabulary: Set<String>

    private struct Compiled {
        let template: CommandTemplate
        let slots: [ResolvedSlot]
        let literals: [String]
    }

    private struct Capture {
        let slot: ResolvedSlot
        let range: Range<Int>
    }

    // MARK: - Matching

    /// Best template for the whole token run, or nil if nothing clears the bar.
    public func bestMatch(in tokens: [String]) -> TemplateMatch? {
        allMatches(in: tokens).first
    }

    /// Best template for a sub-range of the transcript. Used when selecting
    /// several matches from one utterance.
    public func bestMatch(in tokens: [String], range: Range<Int>) -> TemplateMatch? {
        allMatches(in: tokens, range: range).first
    }

    /// Candidates within a sub-range, re-anchored onto the full transcript.
    public func allMatches(in tokens: [String], range: Range<Int>) -> [TemplateMatch] {
        guard !range.isEmpty else { return [] }
        return allMatches(in: Array(tokens[range])).map { $0.shifted(by: range.lowerBound) }
    }

    /// The instruction spoken *first* in `range`.
    ///
    /// Ranking by quality alone is wrong for a left-to-right sweep: a strong
    /// match later in the transmission would beat the instruction actually at the
    /// cursor and swallow it. So the earliest start wins, and quality only breaks
    /// ties between matches that begin at the same word.
    public func earliestMatch(in tokens: [String], range: Range<Int>) -> TemplateMatch? {
        allMatches(in: tokens, range: range).min { lhs, rhs in
            if lhs.range.lowerBound != rhs.range.lowerBound {
                return lhs.range.lowerBound < rhs.range.lowerBound
            }
            return TemplateMatch.isBetter(lhs, rhs)
        }
    }

    /// Every viable candidate, best first. Useful for diagnosing why one
    /// template beat another.
    public func allMatches(in tokens: [String]) -> [TemplateMatch] {
        let ranked = candidates(for: tokens)
            .compactMap { align(compiled[$0], to: tokens) }
            .sorted(by: TemplateMatch.isBetter)
        guard let best = ranked.first else { return [] }

        let tied = ranked.dropFirst()
            .filter { TemplateMatch.isTie(best, $0) }
            .map(\.template.id)
        guard !tied.isEmpty else { return ranked }
        return [best.reporting(tiedWith: tied)] + ranked.dropFirst()
    }

    /// Templates sharing at least one literal with the transcript.
    private func candidates(for tokens: [String]) -> [Int] {
        var seen = Set<Int>()
        for token in tokens {
            for position in literalIndex[token] ?? [] { seen.insert(position) }
        }
        return seen.sorted()
    }

    // MARK: - Alignment

    private func align(_ entry: Compiled, to tokens: [String]) -> TemplateMatch? {
        var cursor = 0
        var matchedLiterals = 0
        /// Denominator: every literal that was found, plus every absent literal
        /// the controller was not entitled to drop.
        var requiredLiterals = 0
        var literalHits: [Int] = []
        var pending: [ResolvedSlot] = []
        var captures: [Capture] = []

        func flush(_ span: Range<Int>) {
            guard !pending.isEmpty else { return }
            captures.append(contentsOf: assign(span, to: pending, in: tokens))
            pending.removeAll()
        }

        for token in entry.template.pattern.tokens {
            switch token {
            case .slot:
                // Resolved slots are positional; consume them in order.
                let next = captures.count + pending.count
                guard next < entry.slots.count else { continue }
                pending.append(entry.slots[next])

            case .literal(let word):
                // A pending slot owns whatever lies ahead, so the search is
                // unbounded; otherwise the literal must be close by.
                let limit = pending.isEmpty
                    ? min(tokens.count, cursor + 1 + maximumLiteralGap)
                    : tokens.count
                guard let hit = tokens[cursor..<limit].firstIndex(of: word) else {
                    // Literal absent. A routinely-omitted word costs nothing;
                    // anything else counts against the score.
                    if !optionalLiterals.contains(word) { requiredLiterals += 1 }
                    continue
                }
                flush(cursor..<hit)
                matchedLiterals += 1
                requiredLiterals += 1
                literalHits.append(hit)
                cursor = hit + 1
            }
        }
        flush(cursor..<tokens.count)

        guard let firstHit = literalHits.first else { return nil }
        // One matched word is not evidence. "GO TO [WAYPOINT/FIX]" would
        // otherwise claim "increase speed **to** 300 knots" on the strength of
        // "to" alone, with "300knots" as the fix. Templates that genuinely have
        // a single literal ("[CALLSIGN] ROGER") are still allowed one.
        guard matchedLiterals >= min(2, entry.literals.count) else { return nil }

        let score = requiredLiterals == 0
            ? 1.0
            : Double(matchedLiterals) / Double(requiredLiterals)
        guard score >= minimumScore else { return nil }

        var filled: [FilledSlot] = []
        for capture in captures {
            let span = Array(tokens[capture.range])
            let outcome = SlotValue.parse(span, as: capture.slot.kind)
            if case .unparsed = outcome, Self.isRequired(capture.slot.kind) {
                return nil    // e.g. "squawk charlie" is not "SQUAWK [CODE]"
            }
            filled.append(FilledSlot(name: capture.slot.name,
                                     kind: capture.slot.kind,
                                     tokens: span,
                                     range: capture.range,
                                     outcome: outcome,
                                     isStateDerived: capture.slot.isStateDerived))
        }

        let filledRanges = filled.filter { !$0.range.isEmpty }.map(\.range)
        let start = min(firstHit, filledRanges.map(\.lowerBound).min() ?? firstHit)
        let end = max(literalHits.last! + 1, filledRanges.map(\.upperBound).max() ?? 0)
        let range = start..<end

        // Words inside the span that neither a literal nor a slot accounts for.
        var explained = Set(literalHits)
        for slotRange in filledRanges { explained.formUnion(slotRange) }
        let coverage = range.isEmpty
            ? 0.0
            : Double(explained.count) / Double(range.count)
        guard coverage >= minimumCoverage else { return nil }

        return TemplateMatch(template: entry.template,
                             score: score,
                             matchedLiterals: matchedLiterals,
                             coverage: coverage,
                             slots: filled,
                             range: range,
                             tiedWith: [])
    }

    // MARK: - Slot capture

    /// Hands a span of transcript tokens to the slots waiting for it.
    ///
    /// A structured slot (level, speed, code…) claims only the run of digits it
    /// needs, so a trailing slot doesn't swallow the rest of the utterance —
    /// which matters once one transcript carries several instructions. Free-text
    /// and fix slots have no recognisable shape, so they take the whole span.
    ///
    /// Several slots sharing one span happens only in
    /// "CONTACT [UNIT CALL SIGN] [FREQUENCY] NOW": the structured slot takes the
    /// trailing numeric run and the free-text slot keeps the remainder.
    private func assign(_ span: Range<Int>,
                        to pending: [ResolvedSlot],
                        in tokens: [String]) -> [Capture] {
        guard !pending.isEmpty else { return [] }

        if pending.count == 1 {
            let slot = pending[0]
            let range: Range<Int>
            switch slot.kind {
            case .callsign:            range = callsignRun(in: span, of: tokens)
            case _ where Self.isStructured(slot.kind):
                                       range = Self.valueRun(in: span, of: tokens)
            default:                   range = span
            }
            return [Capture(slot: slot, range: range)]
        }

        var remaining = span
        var claimed: [Int: Range<Int>] = [:]
        for (offset, slot) in pending.enumerated().reversed()
        where Self.isStructured(slot.kind) {
            let run = Self.trailingValueRun(in: remaining, of: tokens)
            guard !run.isEmpty else { continue }
            claimed[offset] = run
            remaining = remaining.lowerBound..<run.lowerBound
        }

        return pending.enumerated().map { offset, slot in
            if let range = claimed[offset] { return Capture(slot: slot, range: range) }
            if !remaining.isEmpty {
                let range = remaining
                remaining = range.upperBound..<range.upperBound
                return Capture(slot: slot, range: range)
            }
            return Capture(slot: slot, range: span.lowerBound..<span.lowerBound)
        }
    }

    /// Callsign-shaped run inside `span`: one to three non-vocabulary words
    /// followed by a flight number, or a single glued token like "aca125".
    ///
    /// Bounding this matters because `[CALLSIGN]` leads every template, so an
    /// unbounded capture absorbs whatever preceded the first matched literal —
    /// turning "air india 123 climb and maintain flight level 260" into a
    /// callsign. Excluding template vocabulary matters just as much: "turn left
    /// heading 270" is three words and a number, which is exactly the shape of a
    /// callsign, and was being read as one.
    ///
    /// A callsign without a flight number is not recognised at all. That is
    /// deliberate — reporting no callsign is recoverable, reporting the wrong one
    /// sends the instruction to the wrong aircraft.
    ///
    /// The run must also sit just before the instruction, with only filler in
    /// between. A controller names an aircraft once at the top of a transmission,
    /// so without this the *second* instruction's callsign slot reaches back over
    /// the first instruction and grabs the same callsign — which made every match
    /// appear to start at word zero and broke picking instructions in order.
    /// Filler is allowed ("air india 123 good morning turn right…"); another
    /// instruction is not.
    private func callsignRun(in span: Range<Int>, of tokens: [String]) -> Range<Int> {
        let empty = span.lowerBound..<span.lowerBound
        guard !span.isEmpty else { return empty }

        func isAirlineWord(_ token: String) -> Bool {
            token.allSatisfy(\.isLetter) && !vocabulary.contains(token)
        }

        /// Nothing between the callsign and the instruction may be phraseology.
        func onlyFillerFollows(_ end: Int) -> Bool {
            !(end..<span.upperBound).contains { vocabulary.contains(tokens[$0]) }
        }

        // Scanned from the right: with "…123 turn right heading 250 reduce speed",
        // the callsign nearest the instruction is the one that belongs to it. The
        // run is then grown leftwards so "air india 123" comes back whole rather
        // than as "india 123".
        for index in span.reversed() {
            let token = tokens[index]
            guard onlyFillerFollows(index + 1) else { continue }

            // "aca125" — airline and flight number in one token.
            if token.contains(where: \.isLetter), token.contains(where: \.isNumber),
               !vocabulary.contains(token) {
                return index..<(index + 1)
            }

            // "air india 123" — the flight number, preceded by up to three words.
            guard !token.isEmpty, token.allSatisfy(\.isNumber) else { continue }
            var start = index
            while start > span.lowerBound, index - start < 3,
                  isAirlineWord(tokens[start - 1]) { start -= 1 }
            if start < index { return start..<(index + 1) }
        }
        return empty
    }

    /// First run of value-shaped tokens inside `span`, skipping any filler
    /// before it ("to and maintain block 260" → just "260").
    private static func valueRun(in span: Range<Int>, of tokens: [String]) -> Range<Int> {
        guard let start = span.first(where: { isValueToken(tokens[$0]) }) else {
            return span.lowerBound..<span.lowerBound
        }
        var end = start
        while end < span.upperBound, isValueToken(tokens[end]) { end += 1 }
        return start..<end
    }

    /// Value-shaped tokens at the end of `span`.
    private static func trailingValueRun(in span: Range<Int>, of tokens: [String]) -> Range<Int> {
        var start = span.upperBound
        while start > span.lowerBound, isValueToken(tokens[start - 1]) { start -= 1 }
        return start..<span.upperBound
    }

    private static func isValueToken(_ token: String) -> Bool {
        (!token.isEmpty && token.allSatisfy(\.isNumber))
            || ["decimal", "point", "left", "right", "center", "centre"].contains(token)
            || Lexicon.homophoneDigits[token] != nil
    }

    private static func isStructured(_ kind: SlotKind) -> Bool {
        switch kind {
        case .callsign, .freeText, .fix: return false
        default:                         return true
        }
    }

    /// Optional slots are the ones a controller genuinely omits: no callsign on
    /// a plain command, no spoken reason on a terminated service.
    private static func isRequired(_ kind: SlotKind) -> Bool {
        switch kind {
        case .callsign, .freeText: return false
        default:                   return true
        }
    }
}

// MARK: - Results

public struct FilledSlot: Equatable, Sendable {
    public let name: String
    public let kind: SlotKind
    /// The transcript tokens this slot claimed.
    public let tokens: [String]
    /// Where those tokens sat in the transcript.
    public let range: Range<Int>
    public let outcome: SlotValue.Outcome
    /// True when the value should have come from aircraft state, not speech.
    public let isStateDerived: Bool

    public var value: SlotValue? {
        switch outcome {
        case .ok(let value), .outOfRange(let value): return value
        case .unparsed:                              return nil
        }
    }

    public var isValid: Bool {
        if case .ok = outcome { return true }
        return false
    }

    func shifted(by offset: Int) -> FilledSlot {
        FilledSlot(name: name, kind: kind, tokens: tokens,
                   range: (range.lowerBound + offset)..<(range.upperBound + offset),
                   outcome: outcome, isStateDerived: isStateDerived)
    }
}

public struct TemplateMatch: Equatable, Sendable {
    public let template: CommandTemplate
    /// Share of the template's literals found in the transcript.
    public let score: Double
    public let matchedLiterals: Int
    /// Share of this match's own span that its literals and slots account for.
    public let coverage: Double
    public let slots: [FilledSlot]
    /// Token span of the transcript this match consumed.
    public let range: Range<Int>

    /// Templates that tied with this one on every ranking criterion.
    ///
    /// Some payload entries are word-for-word identical and differ only in the
    /// *type* of their final argument — a DME station versus a significant
    /// point, for instance. No lexical rule can separate those, because both are
    /// just names. Rather than pick silently, the tie is reported so a caller
    /// holding navigation data can decide which one was meant.
    public let tiedWith: [String]

    /// The first slot whose value is out of range, if any.
    public var invalidSlot: FilledSlot? {
        slots.first { if case .outOfRange = $0.outcome { return true } else { return false } }
    }

    public func slot(named name: String) -> FilledSlot? {
        slots.first { $0.name == name }
    }

    /// How many slots carry a value with real structure — a time or a level
    /// rather than an unconstrained name. Breaks ties between templates whose
    /// literals match equally well but whose arguments do not.
    var specificity: Int {
        slots.filter { slot in
            guard slot.isValid else { return false }
            switch slot.kind {
            case .callsign, .freeText, .fix: return false
            default:                         return true
            }
        }.count
    }

    /// Re-anchors a match found in a slice back onto the full transcript.
    func shifted(by offset: Int) -> TemplateMatch {
        guard offset != 0 else { return self }
        return TemplateMatch(template: template,
                             score: score,
                             matchedLiterals: matchedLiterals,
                             coverage: coverage,
                             slots: slots.map { $0.shifted(by: offset) },
                             range: (range.lowerBound + offset)..<(range.upperBound + offset),
                             tiedWith: tiedWith)
    }

    func reporting(tiedWith ids: [String]) -> TemplateMatch {
        TemplateMatch(template: template,
                      score: score,
                      matchedLiterals: matchedLiterals,
                      coverage: coverage,
                      slots: slots,
                      range: range,
                      tiedWith: ids)
    }

    /// Ranking: literal coverage, then phrase specificity, then argument
    /// specificity, then legal values.
    static func isBetter(_ lhs: TemplateMatch, _ rhs: TemplateMatch) -> Bool {
        if lhs.score != rhs.score { return lhs.score > rhs.score }
        if lhs.matchedLiterals != rhs.matchedLiterals {
            return lhs.matchedLiterals > rhs.matchedLiterals
        }
        if lhs.specificity != rhs.specificity { return lhs.specificity > rhs.specificity }
        let lhsClean = lhs.invalidSlot == nil
        let rhsClean = rhs.invalidSlot == nil
        if lhsClean != rhsClean { return lhsClean }
        if lhs.coverage != rhs.coverage { return lhs.coverage > rhs.coverage }
        return lhs.template.id < rhs.template.id   // stable
    }

    /// True when two candidates are separated by nothing but the stable
    /// id fallback — i.e. genuinely indistinguishable from the words alone.
    static func isTie(_ lhs: TemplateMatch, _ rhs: TemplateMatch) -> Bool {
        lhs.score == rhs.score
            && lhs.matchedLiterals == rhs.matchedLiterals
            && lhs.specificity == rhs.specificity
            && (lhs.invalidSlot == nil) == (rhs.invalidSlot == nil)
            && lhs.coverage == rhs.coverage
    }
}
