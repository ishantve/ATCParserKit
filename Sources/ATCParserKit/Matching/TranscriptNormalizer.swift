//
//  TranscriptNormalizer.swift
//  ATCParserKit
//
//  Raw transcript → tokens a template can be matched against.
//
//  Order is load-bearing:
//
//    1. lowercase + strip punctuation   "Climb, FL260."  → climb fl260
//    2. lexicon                          fl260           → flight level 260
//    3. numbers                          two six zero    → 260
//
//  Step 2 must precede step 3 so "fl260" is split before number expansion sees
//  it; reversed, the digits would fuse with whatever came before.
//
//  Punctuation is dropped for matching but the boundary it marked is kept —
//  speech has no commas, yet typed and simulated input does, and a comma is the
//  strongest hint that one instruction ended and another began. The boundary
//  indices are handed to the caller rather than embedded as a token, so they
//  stay advisory.
//

import Foundation

public struct TranscriptNormalizer: Equatable, Sendable {

    public var lexicon: Lexicon

    public init(lexicon: Lexicon = .default) {
        self.lexicon = lexicon
    }

    public struct Output: Equatable, Sendable {
        /// Tokens ready for matching.
        public let tokens: [String]
        /// Token indices where the speaker punctuated — advisory split hints.
        public let boundaries: Set<Int>
        /// Cleaned, human-readable form of the whole transcript.
        public let text: String
    }

    public func normalize(_ raw: String) -> Output {
        // Split on whitespace, remembering which words ended a clause.
        var words: [String] = []
        var punctuatedWordIndices = Set<Int>()

        for chunk in raw.lowercased().split(whereSeparator: \.isWhitespace) {
            let endsClause = chunk.contains { ",;:.".contains($0) }
            let cleaned = String(chunk.unicodeScalars.filter {
                CharacterSet.alphanumerics.contains($0)
            })
            guard !cleaned.isEmpty else { continue }
            words.append(cleaned)
            if endsClause { punctuatedWordIndices.insert(words.count - 1) }
        }

        // The lexicon and number expansion both change token counts, so the
        // boundary hints are re-derived by expanding each word on its own and
        // tracking how far the output grew.
        var tokens: [String] = []
        var boundaries = Set<Int>()
        for (index, word) in words.enumerated() {
            tokens.append(contentsOf: lexicon.normalize([word]))
            if punctuatedWordIndices.contains(index) {
                boundaries.insert(tokens.count - 1)
            }
        }

        // Number expansion merges tokens, so map the boundaries through it.
        let expanded = NumberWords.expand(tokens)
        let mapped = Self.remapBoundaries(boundaries, from: tokens, to: expanded)

        return Output(tokens: expanded.map(\.text),
                      boundaries: mapped,
                      text: expanded.map(\.text).joined(separator: " "))
    }

    /// Convenience for callers that don't care about clause hints.
    public func tokens(_ raw: String) -> [String] {
        normalize(raw).tokens
    }

    /// Walks the pre- and post-expansion streams in step, moving each boundary
    /// onto the token that absorbed it.
    private static func remapBoundaries(_ boundaries: Set<Int>,
                                        from before: [String],
                                        to after: [NumberWords.Token]) -> Set<Int> {
        guard !boundaries.isEmpty else { return [] }
        var mapped = Set<Int>()
        var beforeIndex = 0
        for (afterIndex, token) in after.enumerated() {
            // How many input tokens folded into this output token.
            var consumed = 0
            var rebuilt = ""
            while beforeIndex + consumed < before.count, rebuilt.count < token.text.count {
                let source = before[beforeIndex + consumed]
                rebuilt += NumberWords.digitWords[source] ?? source
                consumed += 1
            }
            consumed = max(consumed, 1)
            for offset in 0..<consumed where boundaries.contains(beforeIndex + offset) {
                mapped.insert(afterIndex)
            }
            beforeIndex += consumed
        }
        return mapped
    }
}
