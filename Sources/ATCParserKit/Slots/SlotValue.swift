//
//  SlotValue.swift
//  ATCParserKit
//
//  A filled slot: parsing a token run into a typed value, and rendering that
//  value back into speakable words.
//
//  Parsing numeric slots is two-pass. The strict pass accepts only digits. If a
//  fixed-width slot comes up short, a relaxed pass allows recogniser homophones
//  ("to" for two, "for" for four) — so "heading to seven zero" recovers 270
//  instead of quietly accepting 70 and turning the aircraft the wrong way.
//  Homophones are never trusted outside that shortfall, because "cleared for
//  takeoff" and "descend to" contain the same words legitimately.
//
//  Out-of-range values are reported, not discarded: a rejected value tells the
//  controller what went wrong, whereas a dropped one looks like silence.
//

import Foundation

public enum SlotValue: Equatable, Sendable {
    case integer(Int)
    /// Runway designator including any L/R/C suffix — "27L".
    case runway(String)
    /// Fix identifier folded from phonetics — "PJ", "RE01".
    case fix(String)
    /// Frequency as written — "121.5".
    case frequency(String)
    /// Verbatim text for slots with no structure.
    case text(String)
}

extension SlotValue {

    public enum Outcome: Equatable, Sendable {
        case ok(SlotValue)
        /// Parsed cleanly but outside the phraseology's legal range.
        case outOfRange(SlotValue)
        /// Nothing usable in the token run.
        case unparsed
    }

    // MARK: - Parsing

    public static func parse(_ tokens: [String], as kind: SlotKind) -> Outcome {
        let tokens = tokens.filter { !$0.isEmpty }
        guard !tokens.isEmpty else { return .unparsed }

        switch kind {
        case .callsign, .freeText:
            return .ok(.text(tokens.joined(separator: " ")))
        case .fix:
            return .ok(.fix(foldFix(tokens)))
        case .frequency:
            return parseFrequency(tokens)
        case .runway:
            return parseRunway(tokens)
        case .squawk:
            return parseSquawk(tokens)
        default:
            return parseInteger(tokens, as: kind)
        }
    }

    // MARK: Numeric

    private static func parseInteger(_ tokens: [String], as kind: SlotKind) -> Outcome {
        guard let digits = digits(from: tokens, width: kind.digitWidth),
              let value = Int(digits) else { return .unparsed }
        guard let range = kind.range else { return .ok(.integer(value)) }
        return range.contains(value) ? .ok(.integer(value)) : .outOfRange(.integer(value))
    }

    private static func parseSquawk(_ tokens: [String]) -> Outcome {
        guard let digits = digits(from: tokens, width: 4),
              let value = Int(digits) else { return .unparsed }
        // A squawk is four octal digits — 4580 is not a code, it is a mistake.
        let isOctal = digits.count == 4 && digits.allSatisfy { ("0"..."7").contains($0) }
        return isOctal ? .ok(.integer(value)) : .outOfRange(.integer(value))
    }

    private static func parseRunway(_ tokens: [String]) -> Outcome {
        guard let digits = digits(from: tokens, width: nil),
              let number = Int(digits) else { return .unparsed }

        let suffix: String
        if tokens.contains("left")                              { suffix = "L" }
        else if tokens.contains("right")                        { suffix = "R" }
        else if tokens.contains("center") || tokens.contains("centre") { suffix = "C" }
        else                                                    { suffix = "" }

        // Runway numbers are always two digits in phraseology: 7 is "07".
        let designator = String(format: "%02d", number) + suffix
        guard let range = SlotKind.runway.range, range.contains(number) else {
            return .outOfRange(.runway(designator))
        }
        return .ok(.runway(designator))
    }

    private static func parseFrequency(_ tokens: [String]) -> Outcome {
        var parts: [String] = []
        var sawSeparator = false
        for token in tokens {
            if token == "decimal" || token == "point" || token == "comma" {
                guard !sawSeparator, !parts.isEmpty else { continue }
                sawSeparator = true
                parts.append(".")
            } else if token.allSatisfy(\.isNumber) {
                parts.append(token)
            } else if token.contains(".") {
                parts.append(token)
                sawSeparator = true
            }
        }
        let text = parts.joined()
        guard !text.isEmpty, text.contains(where: \.isNumber) else { return .unparsed }
        return .ok(.frequency(text))
    }

    /// Concatenates the digits in a run. Strict first; if a fixed-width slot is
    /// short, retry allowing homophones.
    private static func digits(from tokens: [String], width: Int?) -> String? {
        let strict = tokens
            .filter { !$0.isEmpty && $0.allSatisfy(\.isNumber) }
            .joined()

        guard let width else { return strict.isEmpty ? nil : strict }
        if strict.count == width { return strict }

        let relaxed = tokens.compactMap { token -> String? in
            if !token.isEmpty, token.allSatisfy(\.isNumber) { return token }
            return Lexicon.homophoneDigits[token]
        }.joined()

        if relaxed.count == width { return relaxed }
        return strict.isEmpty ? (relaxed.isEmpty ? nil : relaxed) : strict
    }

    // MARK: Fix names

    /// "papa juliet" → "PJ", "romeo echo 01" → "RE01", "clink" → "CLINK".
    /// Mixed input keeps the words joined rather than half-folding them.
    private static func foldFix(_ tokens: [String]) -> String {
        let foldable = tokens.allSatisfy {
            Lexicon.phoneticToLetter[$0] != nil || $0.allSatisfy(\.isNumber)
        }
        guard foldable else { return tokens.joined().uppercased() }
        return tokens.map { Lexicon.phoneticToLetter[$0] ?? $0 }.joined().uppercased()
    }

    // MARK: - Rendering

    /// Speakable form for a readback, following the kind's style.
    public func spoken(as kind: SlotKind) -> String {
        switch (self, kind.spokenStyle) {
        case (.integer(let value), .magnitude):
            return NumberWords.spokenMagnitude(value)
        case (.integer(let value), _):
            return NumberWords.spokenDigits(value, padTo: kind.digitWidth ?? 0)
        case (.runway(let designator), _):
            return spokenRunway(designator)
        case (.fix(let code), .phonetic):
            return spelledOut(code)
        case (.fix(let code), _):
            return code
        case (.frequency(let text), _):
            return NumberWords.spokenDigits(text)
        case (.text(let text), .callsign):
            return spokenCallsign(text)
        case (.text(let text), _):
            return text
        }
    }

    /// "air india 123" → "air india one two three". A flight number read as a
    /// quantity ("one hundred twenty three") is not a callsign.
    private func spokenCallsign(_ text: String) -> String {
        text.split(separator: " ").flatMap { token -> [String] in
            if token.allSatisfy(\.isNumber) { return [NumberWords.spokenDigits(String(token))] }
            // "aca125" — say the prefix, then the digits one at a time.
            let letters = String(token.prefix(while: \.isLetter))
            let digits = String(token.dropFirst(letters.count))
            guard !letters.isEmpty, !digits.isEmpty, digits.allSatisfy(\.isNumber) else {
                return [String(token)]
            }
            return [letters, NumberWords.spokenDigits(digits)]
        }.joined(separator: " ")
    }

    private func spokenRunway(_ designator: String) -> String {
        let digits = designator.filter(\.isNumber)
        var words = [NumberWords.spokenDigits(digits)]
        switch designator.last {
        case "L": words.append("left")
        case "R": words.append("right")
        case "C": words.append("center")
        default:  break
        }
        return words.joined(separator: " ")
    }

    /// "RE01" → "romeo echo zero one".
    private func spelledOut(_ code: String) -> String {
        code.uppercased().compactMap { character -> String? in
            if character.isNumber { return NumberWords.spokenDigits(String(character)) }
            return Lexicon.letterToPhonetic[character]
        }.joined(separator: " ")
    }
}
