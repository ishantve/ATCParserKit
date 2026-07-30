//
//  CommandTemplate.swift
//  ATCParserKit
//
//  One backend phraseology entry, compiled and sanitised.
//
//  `id` vs `code`: `abbreviationCode` is the backend's identifier and is what
//  downstream layers key their behaviour off. It is *not* guaranteed present —
//  the payload ships entries with an empty code — so `id` is always usable
//  while `code` stays honest about what the backend actually sent.
//

import Foundation

public struct CommandTemplate: Equatable, Sendable {

    /// Stable identifier. The backend `abbreviationCode` when present,
    /// otherwise a synthesised `"<category>#<index>"` fallback.
    public let id: String

    /// The backend `abbreviationCode`, or nil when it was blank.
    public let code: String?

    /// The payload key this template was listed under ("vectoring", "climb"…).
    /// A presentational grouping, not a behavioural one — two categories can
    /// hold semantically identical phraseology.
    public let category: String

    /// What the controller says.
    public let pattern: TemplatePattern

    /// What the pilot says back. Note this may contain prose rather than pure
    /// phraseology ("Later: …", "If not: …"); splitting that is a later concern.
    public let readback: TemplatePattern

    /// Who utters `pattern` — "ATC" throughout the current payload.
    public let speaker: String

    /// Optional UI shortcut, blank values normalised to nil.
    public let keyboardShortcut: String?

    /// Free-text note from the backend, blank values normalised to nil.
    public let comments: String?

    /// Backend `show` flag. A disabled template still parses — it just must not
    /// be executed, and answers with a different readback.
    public let isEnabled: Bool

    public init(id: String,
                code: String?,
                category: String,
                pattern: TemplatePattern,
                readback: TemplatePattern,
                speaker: String,
                keyboardShortcut: String?,
                comments: String?,
                isEnabled: Bool) {
        self.id = id
        self.code = code
        self.category = category
        self.pattern = pattern
        self.readback = readback
        self.speaker = speaker
        self.keyboardShortcut = keyboardShortcut
        self.comments = comments
        self.isEnabled = isEnabled
    }
}

// MARK: - Wire model

/// Verbatim shape of one entry in the backend payload. Kept separate from
/// `CommandTemplate` so decoding stays dumb and all cleanup is explicit.
struct RawCommandTemplate: Decodable, Equatable {
    let icaoTemplate: String?
    let abbreviationCode: String?
    let readBackText: String?
    let speaker: String?
    let keyboardShortCut: String?
    let comments: String?
    let show: Int?
}
