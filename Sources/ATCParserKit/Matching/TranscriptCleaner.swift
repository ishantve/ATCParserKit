//
//  TranscriptCleaner.swift
//  ATCParserKit
//
//  Post-processes a raw speech transcript before it is displayed or matched,
//  fixing known recognizer quirks: hyphen folding, ICAO spellings, and stray
//  tokens ("[unk]", stray commas). Shared so every consumer — native, React
//  Native, Unity — cleans transcripts identically instead of each app carrying
//  its own copy.
//
//  Each rule is a { from → to } whole-word, case-insensitive replacement applied
//  in order. `clean` preserves case (it feeds the matcher, which lowercases);
//  `displayText` uppercases for on-screen display.
//

import Foundation

public enum TranscriptCleaner {

    private struct Replacement { let from: String; let to: String }

    private static let wordReplacements: [Replacement] = [
        .init(from: "juliet", to: "juliett"),
        .init(from: "x-ray", to: "xray"),
        .init(from: "ads-b", to: "adsb"),
        .init(from: "anti-icing", to: "antiicing"),
        .init(from: "take-off", to: "takeoff"),
        .init(from: "de-ice", to: "deice"),
        .init(from: "de-icing", to: "deicing"),
        .init(from: "air-taxiing", to: "airtaxiing"),
        .init(from: "low-altitude", to: "low altitude"),
        .init(from: "non-precision", to: "non precision"),
        .init(from: "non-surveillance", to: "non surveillance"),
        .init(from: "re-enter", to: "reenter"),
        .init(from: "straight-in", to: "straightin"),
        .init(from: "three", to: "tree"),
        .init(from: "air taxi", to: "airtaxi"),
        .init(from: "alpha", to: "alfa"),
        .init(from: "[unk]", to: ""),   // recognizer's unknown-word token
        .init(from: ",", to: ""),
    ]

    /// Applies the replacement rules + folds a phonetically-spelled leading
    /// callsign, preserving case. Feed this to the parser / recognizer (which
    /// lowercases internally). Returns "" for empty input.
    public static func clean(_ raw: String) -> String {
        guard !raw.isEmpty else { return "" }
        let replaced = wordReplacements.reduce(raw) { apply($0, $1) }
        let folded = foldLeadingCallsign(replaced)
        // Collapse whitespace left behind by removals ("[unk]", stray commas) and trim.
        return folded
            .replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    /// Folds a LEADING run of two or more ICAO phonetic words into a letter code —
    /// "echo tango delta 615 …" → "ETD 615 …" — so a phonetically-spelled callsign
    /// matches its aircraft (e.g. ETD615) and displays as the code. Only the
    /// leading run (the callsign position) and only ≥2 words, so a lone "delta" /
    /// "victor" (an airline name or a plain word) is left alone; mid-command fixes
    /// fold through the parser's own fix handling instead.
    private static func foldLeadingCallsign(_ text: String) -> String {
        let tokens = text.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        var code = ""
        var index = 0
        while index < tokens.count, let letter = Lexicon.phoneticToLetter[tokens[index].lowercased()] {
            code += letter
            index += 1
        }
        guard code.count >= 2 else { return text }
        let rest = tokens[index...].joined(separator: " ")
        return rest.isEmpty ? code : code + " " + rest
    }

    /// Cleaned transcript, uppercased for display in a text field.
    public static func displayText(_ raw: String) -> String {
        let cleaned = clean(raw)
        return cleaned.isEmpty ? "" : cleaned.uppercased()
    }

    /// Case-insensitive replacement. A `\b` word boundary is added only where the
    /// rule's edge is a word character — so tokens that start/end with punctuation
    /// ("[unk]", ",") still match (a `\b[unk]\b` would never fire, because `[` is
    /// not a word character).
    private static func apply(_ text: String, _ rule: Replacement) -> String {
        let escaped = NSRegularExpression.escapedPattern(for: rule.from)
        let left  = (rule.from.first.map(isWordCharacter) ?? false) ? "\\b" : ""
        let right = (rule.from.last.map(isWordCharacter) ?? false) ? "\\b" : ""
        guard let regex = try? NSRegularExpression(pattern: left + escaped + right,
                                                   options: [.caseInsensitive]) else {
            return text
        }
        let range = NSRange(text.startIndex..., in: text)
        let template = NSRegularExpression.escapedTemplate(for: rule.to)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: template)
    }

    private static func isWordCharacter(_ c: Character) -> Bool {
        c.isLetter || c.isNumber || c == "_"
    }
}
