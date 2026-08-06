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

    /// Applies the replacement rules, preserving case. Feed this to the parser /
    /// recognizer (which lowercases internally). Returns "" for empty input.
    public static func clean(_ raw: String) -> String {
        guard !raw.isEmpty else { return "" }
        return wordReplacements.reduce(raw) { apply($0, $1) }
    }

    /// Cleaned transcript, uppercased for display in a text field.
    public static func displayText(_ raw: String) -> String {
        let cleaned = clean(raw)
        return cleaned.isEmpty ? "" : cleaned.uppercased()
    }

    /// One whole-word (`\bfrom\b`), case-insensitive replacement.
    private static func apply(_ text: String, _ rule: Replacement) -> String {
        let pattern = "\\b\(NSRegularExpression.escapedPattern(for: rule.from))\\b"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return text
        }
        let range = NSRange(text.startIndex..., in: text)
        let template = NSRegularExpression.escapedTemplate(for: rule.to)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: template)
    }
}
