//
//  TemplatePattern.swift
//  ATCParserKit
//
//  A backend phraseology string ("[CALLSIGN] RADAR TURN LEFT HEADING
//  [THREE DIGITS]") compiled into an ordered token sequence of literals and
//  slots. This is the single place that understands the `[PLACEHOLDER]` syntax.
//
//  Two views of the same pattern, deliberately kept separate:
//
//    • `tokens` — matching view. Literals are lowercased and stripped of
//      punctuation so they line up with a normalised transcript.
//    • `text`   — rendering view. Original casing and punctuation are kept
//      (commas drive TTS prosody); only whitespace and slot names are cleaned.
//
//  Sanitisation applied to slot names, because the payload is inconsistent:
//    "[TIME ]"           → "TIME"            (inner whitespace)
//    "[WAYPOINT/FIX/]"   → "WAYPOINT/FIX"    (trailing separator)
//    "[significant point]" → "SIGNIFICANT POINT"
//

import Foundation

public struct TemplatePattern: Equatable, Sendable {

    public enum Token: Equatable, Sendable {
        /// A fixed word, lowercased and stripped of punctuation.
        case literal(String)
        /// A placeholder, upper-cased and whitespace-normalised.
        case slot(String)
    }

    /// Literals and slots in the order they appear.
    public let tokens: [Token]

    /// Display/render form: punctuation preserved, whitespace collapsed,
    /// slot names normalised.
    public let text: String

    /// The untouched string this pattern was compiled from.
    public let raw: String

    public init(_ raw: String) {
        self.raw = raw
        self.tokens = Self.tokenize(raw)
        self.text = Self.renderText(raw)
    }

    // MARK: - Derived

    /// Slot names in order of appearance. A name may repeat — several templates
    /// use `[LEVEL]` twice (e.g. block clearances), so this is a list, not a set.
    public var slotNames: [String] {
        tokens.compactMap { if case .slot(let name) = $0 { return name } else { return nil } }
    }

    /// Fixed words available for matching. The matcher's score denominator.
    public var literals: [String] {
        tokens.compactMap { if case .literal(let word) = $0 { return word } else { return nil } }
    }

    public var isEmpty: Bool { tokens.isEmpty }

    // MARK: - Compilation

    private static func tokenize(_ raw: String) -> [Token] {
        var tokens: [Token] = []
        forEachPart(in: raw) { part in
            switch part {
            case .slot(let name):
                tokens.append(.slot(name))
            case .text(let run):
                for word in run.split(whereSeparator: \.isWhitespace) {
                    let cleaned = String(word.unicodeScalars.filter {
                        CharacterSet.alphanumerics.contains($0)
                    })
                    guard !cleaned.isEmpty else { continue }
                    tokens.append(.literal(cleaned.lowercased()))
                }
            }
        }
        return tokens
    }

    private static func renderText(_ raw: String) -> String {
        var pieces: [String] = []
        forEachPart(in: raw) { part in
            switch part {
            case .slot(let name):
                pieces.append("[\(name)]")
            case .text(let run):
                pieces.append(contentsOf: run.split(whereSeparator: \.isWhitespace).map(String.init))
            }
        }
        // Re-join with single spaces, then pull punctuation back onto the previous
        // word so "[CALLSIGN] ," never happens.
        return pieces.joined(separator: " ")
            .replacingOccurrences(of: " ,", with: ",")
            .replacingOccurrences(of: " .", with: ".")
            .trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Bracket scanning

    /// A run of fixed text, or a slot. Readback rendering walks these rather than
    /// `tokens`, because it needs the original casing and punctuation: "ILS" must
    /// stay upper case for the synthesiser to spell it out, and the commas are
    /// what give a spoken readback its pauses.
    enum Part {
        case text(Substring)
        case slot(String)
    }

    /// Text runs and slots of the sanitised pattern, in order.
    var parts: [Part] {
        var parts: [Part] = []
        Self.forEachPart(in: text) { parts.append($0) }
        return parts
    }

    /// Walks `raw` once, handing out alternating text runs and slots.
    /// An unterminated `[` is treated as ordinary text rather than an error —
    /// a malformed template should degrade, not crash the whole template set.
    static func forEachPart(in raw: String, _ body: (Part) -> Void) {
        var index = raw.startIndex
        while index < raw.endIndex {
            guard let open = raw[index...].firstIndex(of: "[") else {
                body(.text(raw[index...]))
                return
            }
            if open > index { body(.text(raw[index..<open])) }

            guard let close = raw[open...].firstIndex(of: "]") else {
                body(.text(raw[open...]))
                return
            }
            let name = normalizeSlotName(raw[raw.index(after: open)..<close])
            if name.isEmpty {
                body(.text(raw[open...close]))   // "[]" — keep it visible
            } else {
                body(.slot(name))
            }
            index = raw.index(after: close)
        }
    }

    /// Upper-case, collapse inner whitespace, and drop stray separators the
    /// payload leaves behind (`[WAYPOINT/FIX/]`).
    static func normalizeSlotName(_ inner: Substring) -> String {
        inner
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/-_ "))
            .uppercased()
    }
}
