//
//  NumberWords.swift
//  ATCParserKit
//
//  Numbers in both directions: spoken words → digits for parsing, digits →
//  spoken words for readback. The recogniser is inconsistent about which form
//  it emits, so all three of "260", "two six zero" and "2 6 0" must land on the
//  same value.
//
//  ── Words → digits ──────────────────────────────────────────────────────────
//  ATC phraseology is digit-by-digit, so expansion is **literal concatenation,
//  never arithmetic**: every number word becomes its own digit string and
//  neighbours join up.
//
//      "two six zero"   → 2 · 6 · 0    → "260"
//      "two seventy"    → 2 · 70       → "270"
//      "eight thousand" → 8 · 000      → "8000"
//
//  One ordering exception: a tens word *followed by* a unit word is addition,
//  not concatenation — otherwise "runway twenty seven" would read as 207.
//
//      "twenty seven"   → 20 + 7       → "27"
//      "one twenty"     → 1 · 20       → "120"
//
//  Merging is deliberately not unconditional: two multi-digit numerals that the
//  recogniser produced itself stay apart, so a flight number never fuses into
//  the value beside it ("125" "250" is not "125250").
//
//  ── Digits → words ─────────────────────────────────────────────────────────
//  Levels, headings, speeds and codes are read digit-by-digit ("260" →
//  "two six zero"). Altitudes are read by magnitude ("8500" → "eight thousand
//  five hundred"). Reading an altitude digit-by-digit, or a level by magnitude,
//  both sound wrong to a controller — hence two separate styles.
//

import Foundation

enum NumberWords {

    // MARK: - Vocabulary

    /// Number word → the literal digits it contributes.
    /// `hundred`/`thousand` fall out of the same concatenation rule.
    static let digitWords: [String: String] = [
        "zero": "0", "oh": "0",
        "one": "1", "two": "2", "three": "3", "four": "4", "five": "5",
        "six": "6", "seven": "7", "eight": "8", "nine": "9", "niner": "9",
        "ten": "10", "eleven": "11", "twelve": "12", "thirteen": "13",
        "fourteen": "14", "fifteen": "15", "sixteen": "16", "seventeen": "17",
        "eighteen": "18", "nineteen": "19",
        "twenty": "20", "thirty": "30", "forty": "40", "fourty": "40",
        "fifty": "50", "sixty": "60", "seventy": "70", "eighty": "80",
        "ninety": "90",
        "hundred": "00", "thousand": "000",
    ]

    private static let tensWords: Set<String> = [
        "twenty", "thirty", "forty", "fourty", "fifty", "sixty", "seventy",
        "eighty", "ninety",
    ]

    private static let unitWords: Set<String> = [
        "one", "two", "three", "four", "five", "six", "seven", "eight",
        "nine", "niner",
    ]

    /// Words the recogniser substitutes for digits ("for" for four, "to" for
    /// two). Never expanded during normalisation — "cleared for takeoff" and
    /// "descend to" would break. Slot parsing consults this only when a
    /// fixed-width value came up short. See `Lexicon.homophoneDigits`.
    static let homophones: [String: String] = [
        "to": "2", "too": "2", "tree": "3", "for": "4", "fore": "4",
        "fife": "5", "won": "1", "ate": "8",
    ]

    // MARK: - Words → digits

    /// One token after expansion, carrying enough provenance to decide merging.
    struct Token: Equatable {
        var text: String
        var isNumeric: Bool
        /// True when this token came from a spoken word rather than the
        /// recogniser's own numerals.
        var fromWord: Bool
    }

    /// Expands number words and fuses adjacent numeric tokens.
    /// Input must already be lowercased and punctuation-free.
    static func expand(_ tokens: [String]) -> [Token] {
        var expanded: [Token] = []
        var index = 0

        while index < tokens.count {
            let token = tokens[index]

            if let digits = digitWords[token] {
                var value = digits
                // "twenty seven" → 27, but "twenty zero" is not a thing.
                if tensWords.contains(token),
                   index + 1 < tokens.count,
                   unitWords.contains(tokens[index + 1]),
                   let tens = Int(digits),
                   let unit = Int(digitWords[tokens[index + 1]] ?? "") {
                    value = String(tens + unit)
                    index += 1
                }
                expanded.append(Token(text: value, isNumeric: true, fromWord: true))
            } else if !token.isEmpty, token.allSatisfy(\.isNumber) {
                expanded.append(Token(text: token, isNumeric: true, fromWord: false))
            } else {
                expanded.append(Token(text: token, isNumeric: false, fromWord: false))
            }
            index += 1
        }

        return merge(expanded)
    }

    /// Convenience: expanded tokens as a normalised string.
    static func expandToString(_ tokens: [String]) -> String {
        expand(tokens).map(\.text).joined(separator: " ")
    }

    /// Joins neighbouring numeric tokens, except two multi-digit numerals the
    /// recogniser produced itself — those are separate values, not one number.
    private static func merge(_ tokens: [Token]) -> [Token] {
        var merged: [Token] = []
        for token in tokens {
            guard token.isNumeric,
                  let previous = merged.last,
                  previous.isNumeric else {
                merged.append(token)
                continue
            }
            let bothStandaloneNumerals =
                previous.text.count > 1 && token.text.count > 1
                && !previous.fromWord && !token.fromWord
            if bothStandaloneNumerals {
                merged.append(token)
            } else {
                merged[merged.count - 1] = Token(
                    text: previous.text + token.text,
                    isNumeric: true,
                    fromWord: previous.fromWord || token.fromWord)
            }
        }
        return merged
    }

    // MARK: - Digits → words

    // ICAO radiotelephony digit spellings — headings, levels, callsigns, codes
    // are all read this way ("tree", "fower", "fife", "niner"); the rest match
    // plain English. Keeps readback consistent with how the recognizer hears them.
    private static let spokenDigit: [Character: String] = [
        "0": "zero", "1": "one", "2": "two", "3": "tree", "4": "fower",
        "5": "fife", "6": "six", "7": "seven", "8": "eight", "9": "niner",
    ]

    /// "260" → "two six zero". Used for levels, headings, speeds, codes —
    /// anything ATC reads one digit at a time.
    static func spokenDigits(_ text: String) -> String {
        text.compactMap { spokenDigit[$0] ?? (($0 == ".") ? "decimal" : nil) }
            .joined(separator: " ")
    }

    /// Renders an arbitrary transcript fragment for speech: numeric runs read
    /// digit-by-digit (via spokenDigits), other words spoken as they are. e.g.
    /// "emirates 22 5" → "emirates two two fife". Use before handing a raw
    /// fragment (e.g. an unrecognised "say again" phrase) to a synthesiser, so it
    /// doesn't read "22" as "twenty two". (Does not change spokenDigits — wraps it.)
    public static func spokenFragment(_ text: String) -> String {
        text.split(separator: " ").flatMap { token -> [String] in
            if token.allSatisfy(\.isNumber) { return [spokenDigits(String(token))] }
            let letters = String(token.prefix(while: \.isLetter))
            let digits = String(token.dropFirst(letters.count))
            guard !letters.isEmpty, !digits.isEmpty, digits.allSatisfy(\.isNumber) else {
                return [String(token)]
            }
            return [letters, spokenDigits(digits)]
        }.joined(separator: " ")
    }

    static func spokenDigits(_ value: Int, padTo width: Int = 0) -> String {
        var text = String(value)
        if text.count < width {
            text = String(repeating: "0", count: width - text.count) + text
        }
        return spokenDigits(text)
    }

    /// "8500" → "eight thousand five hundred", "12000" → "one two thousand".
    /// The thousands part is still spoken digit-by-digit, per ICAO.
    static func spokenMagnitude(_ value: Int) -> String {
        guard value > 0 else { return "zero" }
        var parts: [String] = []
        let thousands = value / 1000
        let hundreds = (value % 1000) / 100
        let remainder = value % 100

        if thousands > 0 {
            parts.append(spokenDigits(thousands))
            parts.append("thousand")
        }
        if hundreds > 0 {
            parts.append(spokenDigit[Character(String(hundreds))] ?? String(hundreds))
            parts.append("hundred")
        }
        // Non-round altitudes are rare; fall back to digits rather than invent
        // English ("eight thousand fifty" is not phraseology).
        if remainder > 0 {
            parts.append(spokenDigits(remainder))
        }
        return parts.joined(separator: " ")
    }
}
