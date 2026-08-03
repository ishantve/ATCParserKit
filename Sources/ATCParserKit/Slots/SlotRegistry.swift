//
//  SlotRegistry.swift
//  ATCParserKit
//
//  Resolves a placeholder name to the kind of value it holds.
//
//  A plain name → kind table is not enough, because the payload overloads one
//  placeholder across incompatible meanings:
//
//      "RADAR MAINTAIN [NUMBER] KNOTS"                → a speed,  60…600
//      "RADAR INTERCEPT THE LOCALIZER RUNWAY [NUMBER]" → a runway, 1…36
//
//  Same name, ranges that barely overlap. So resolution is contextual: the
//  literals sitting either side of the slot in its own template decide. Context
//  rules are consulted first, the name table second.
//
//  Unknown placeholders resolve to `.freeText` rather than failing — a new
//  backend placeholder should degrade to captured text, not break the parse.
//  `TemplateSetTests.testSlotVocabulary` is what makes sure a new one gets
//  noticed and given a real kind.
//

import Foundation

public struct SlotRegistry: Equatable, Sendable {

    /// Placeholder name → kind, used when no context rule applies.
    public var kinds: [String: SlotKind]

    /// Placeholder names whose value comes from aircraft state rather than the
    /// controller's words. The parser cannot fill these; it reports them so the
    /// app can supply the value before speaking.
    public var stateDerived: Set<String>

    /// Context rules, evaluated in order.
    public var contextRules: [ContextRule]

    public struct ContextRule: Equatable, Sendable {
        /// Placeholder this rule applies to.
        public let slot: String
        /// Literal that must appear immediately before the slot.
        public let precededBy: String?
        /// Literal that must appear immediately after the slot.
        public let followedBy: String?
        public let kind: SlotKind

        public init(slot: String, precededBy: String? = nil,
                    followedBy: String? = nil, kind: SlotKind) {
            self.slot = slot
            self.precededBy = precededBy
            self.followedBy = followedBy
            self.kind = kind
        }
    }

    public init(kinds: [String: SlotKind],
                stateDerived: Set<String>,
                contextRules: [ContextRule]) {
        self.kinds = kinds
        self.stateDerived = stateDerived
        self.contextRules = contextRules
    }

    // MARK: - Default

    public static let `default` = SlotRegistry(
        kinds: [
            "CALLSIGN": .callsign,
            "LEVEL": .flightLevel,
            "ACTUAL LEVEL": .flightLevel,
            "ALTITUDE": .altitudeFeet,
            "THREE DIGITS": .heading,
            "NUMBER OF DEGREES": .degrees,
            "CODE": .squawk,
            "ACTUAL CODE": .squawk,
            "VALUE": .pressure,
            "DISTANCE": .distance,
            "FREQUENCY": .frequency,
            "SIGNIFICANT POINT": .fix,
            "DME STATION": .fix,
            "HOLDING FIX": .fix,
            "WAYPOINT/FIX": .fix,
            // A station's name, spoken as a name. Not `.fix`: that spells a code out
            // phonetically, which is right for "PJ" and wrong for "DELHI". It appears
            // only in a readback, never in a request, so nothing validates against it.
            "VOR NAME": .freeText,
            "POSITION": .freeText,
            "REASON": .freeText,
            "INTENTIONS": .freeText,
            "TIME": .time,
            "UNIT NAME": .freeText,
            "UNIT CALL SIGN": .freeText,
            "TYPE OF APPROACH": .freeText,
            "STANDARD DEPARTURE NAME AND NUMBER": .freeText,
            // No context rule matched — treat as a bare integer.
            "NUMBER": .integer,
        ],
        stateDerived: [
            "ACTUAL LEVEL",   // 430 — the aircraft's real level
            "ACTUAL CODE",    // 216 — the aircraft's real squawk
            "INTENTIONS",     // 442 — the pilot's answer
        ],
        contextRules: [
            .init(slot: "NUMBER", precededBy: "runway", kind: .runway),
            .init(slot: "NUMBER", followedBy: "knots", kind: .speedKnots),
        ])

    // MARK: - Resolution

    /// Kind for the slot at `index` in `pattern`, using its neighbours to
    /// disambiguate overloaded names.
    public func kind(at index: Int, in pattern: TemplatePattern) -> SlotKind {
        guard case .slot(let name) = pattern.tokens[index] else { return .freeText }

        let previous = literal(before: index, in: pattern)
        let next = literal(after: index, in: pattern)

        for rule in contextRules where rule.slot == name {
            if let required = rule.precededBy, required != previous { continue }
            if let required = rule.followedBy, required != next { continue }
            return rule.kind
        }
        return kinds[name] ?? .freeText
    }

    /// Kind for a name with no template context. Overloaded names fall back to
    /// their table entry, so prefer `kind(at:in:)` where a pattern is available.
    public func kind(for name: String) -> SlotKind {
        kinds[name] ?? .freeText
    }

    public func isStateDerived(_ name: String) -> Bool {
        stateDerived.contains(name)
    }

    /// Every slot in a pattern, resolved in order of appearance.
    public func resolve(_ pattern: TemplatePattern) -> [ResolvedSlot] {
        pattern.tokens.enumerated().compactMap { index, token in
            guard case .slot(let name) = token else { return nil }
            return ResolvedSlot(name: name,
                                kind: kind(at: index, in: pattern),
                                tokenIndex: index,
                                isStateDerived: isStateDerived(name))
        }
    }

    private func literal(before index: Int, in pattern: TemplatePattern) -> String? {
        guard index > 0, case .literal(let word) = pattern.tokens[index - 1] else { return nil }
        return word
    }

    private func literal(after index: Int, in pattern: TemplatePattern) -> String? {
        let next = index + 1
        guard next < pattern.tokens.count,
              case .literal(let word) = pattern.tokens[next] else { return nil }
        return word
    }
}

// MARK: - ResolvedSlot

public struct ResolvedSlot: Equatable, Sendable {
    public let name: String
    public let kind: SlotKind
    /// Position within the pattern's token list — slots repeat, so identity is
    /// positional rather than by name.
    public let tokenIndex: Int
    public let isStateDerived: Bool

    public init(name: String, kind: SlotKind, tokenIndex: Int, isStateDerived: Bool) {
        self.name = name
        self.kind = kind
        self.tokenIndex = tokenIndex
        self.isStateDerived = isStateDerived
    }
}
