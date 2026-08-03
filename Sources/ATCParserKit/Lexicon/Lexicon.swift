//
//  Lexicon.swift
//  ATCParserKit
//
//  Vocabulary that bridges what a controller says to what a template contains.
//  Templates are exact ICAO text ("FLIGHT LEVEL"), speech is not ("FL"), so
//  without this layer a template-driven matcher would reject phrasings the old
//  hand-written parser accepted.
//
//  Four rules, applied in order:
//
//    1. spellings     — "localiser" → "localizer", "centre" → "center"
//    2. splitting     — "fl260" → "fl" "260"        (letters glued to digits)
//    3. abbreviations — "fl" → "flight" "level"     (one token → many)
//    4. contractions  — "take" "off" → "takeoff"    (many tokens → one)
//
//  Splitting runs before abbreviation so "fl260" and "fl 260" converge, and
//  contraction runs last so it sees the fully expanded stream.
//
//  Phonetics are here rather than in the parser because they serve both
//  directions: folding spoken words into a fix code while parsing, and spelling
//  a code back out for readback.
//

import Foundation

public struct Lexicon: Equatable, Sendable {

    /// Alternative spellings of the same word.
    public var spellings: [String: String]

    /// Abbreviation → the template words it stands for.
    public var abbreviations: [String: [String]]

    /// Word sequences spoken apart that templates write as one token.
    public var contractions: [Contraction]

    public struct Contraction: Equatable, Sendable {
        public let spoken: [String]
        public let template: String
        public init(spoken: [String], template: String) {
            self.spoken = spoken
            self.template = template
        }
    }

    public init(spellings: [String: String],
                abbreviations: [String: [String]],
                contractions: [Contraction]) {
        self.spellings = spellings
        self.abbreviations = abbreviations
        self.contractions = contractions
    }

    // MARK: - Default

    public static let `default` = Lexicon(
        spellings: [
            "localiser": "localizer",
            "centre": "center",
            "metre": "meter",
            "metres": "meters",
            "squark": "squawk",
        ],
        abbreviations: [
            "fl": ["flight", "level"],
            "hdg": ["heading"],
            "rwy": ["runway"],
            "kts": ["knots"],
            "kt": ["knots"],
            "loc": ["localizer"],
        ],
        // Only where the template writes one token and speech gives two.
        // "GO AROUND" is two tokens in template 327, so contracting it would
        // stop it matching — the direction of these rules matters.
        contractions: [
            Contraction(spoken: ["take", "off"], template: "takeoff"),
            Contraction(spoken: ["stand", "by"], template: "standby"),
        ])

    // MARK: - Normalisation

    /// Applies every rule to an already lowercased, punctuation-free token list.
    public func normalize(_ tokens: [String]) -> [String] {
        contract(expandAbbreviations(split(respell(tokens))))
    }

    private func respell(_ tokens: [String]) -> [String] {
        tokens.map { spellings[$0] ?? $0 }
    }

    /// Separates a known abbreviation glued to its value: "fl260" → "fl" "260".
    /// Only known abbreviations are split, so a callsign like "aca125" is left
    /// alone for the callsign slot to claim.
    private func split(_ tokens: [String]) -> [String] {
        tokens.flatMap { token -> [String] in
            let letters = String(token.prefix(while: \.isLetter))
            guard !letters.isEmpty, abbreviations[letters] != nil else { return [token] }
            let rest = String(token.dropFirst(letters.count))
            guard !rest.isEmpty, rest.allSatisfy(\.isNumber) else { return [token] }
            return [letters, rest]
        }
    }

    private func expandAbbreviations(_ tokens: [String]) -> [String] {
        tokens.flatMap { abbreviations[$0] ?? [$0] }
    }

    /// Longest-first so a two-word contraction is never shadowed by a shorter
    /// overlapping one.
    private func contract(_ tokens: [String]) -> [String] {
        guard !contractions.isEmpty else { return tokens }
        let ordered = contractions.sorted { $0.spoken.count > $1.spoken.count }
        var output: [String] = []
        var index = 0
        outer: while index < tokens.count {
            for rule in ordered where index + rule.spoken.count <= tokens.count {
                if Array(tokens[index..<(index + rule.spoken.count)]) == rule.spoken {
                    output.append(rule.template)
                    index += rule.spoken.count
                    continue outer
                }
            }
            output.append(tokens[index])
            index += 1
        }
        return output
    }

    // MARK: - Phonetic alphabet

    /// ICAO phonetic word → letter. Used to fold a spoken fix into its code.
    public static let phoneticToLetter: [String: String] = [
        "alpha": "A", "alfa": "A", "bravo": "B", "charlie": "C", "delta": "D",
        "echo": "E", "foxtrot": "F", "golf": "G", "hotel": "H", "india": "I",
        "juliet": "J", "juliett": "J", "kilo": "K", "lima": "L", "mike": "M",
        "november": "N", "oscar": "O", "papa": "P", "quebec": "Q", "romeo": "R",
        "sierra": "S", "tango": "T", "uniform": "U", "victor": "V",
        "whiskey": "W", "xray": "X", "yankee": "Y", "zulu": "Z",
    ]

    /// Letter → ICAO phonetic word, for spelling a code out in a readback.
    public static let letterToPhonetic: [Character: String] = {
        var map: [Character: String] = [:]
        // Reverse the canonical spellings only, so "alfa"/"juliett" variants
        // don't fight over the same letter.
        for (word, letter) in phoneticToLetter
        where !["alfa", "juliett"].contains(word) {
            map[Character(letter)] = word
        }
        return map
    }()

    /// Words the recogniser may emit in place of a digit. Deliberately not part
    /// of `normalize` — expanding them everywhere would corrupt "cleared **for**
    /// takeoff" and "descend **to**". Fixed-width slots use this as a last
    /// resort when they come up a digit short.
    public static let homophoneDigits: [String: String] = NumberWords.homophones
}
