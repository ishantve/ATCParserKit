//
//  TemplateSet.swift
//  ATCParserKit
//
//  The decoded, sanitised phraseology vocabulary — the parser's source of
//  truth. Templates come from the backend, so this type assumes the data is
//  imperfect and reports what it had to work around rather than silently
//  papering over it.
//
//  Decoding never throws on bad *content*, only on unreadable JSON. A malformed
//  entry is kept (so the vocabulary stays complete) and recorded in
//  `diagnostics`, which doubles as the list of fixes to request from the backend.
//

import Foundation

public struct TemplateSet: Equatable, Sendable {

    /// Every template, ordered by category (alphabetical) then payload order.
    /// Dictionary iteration order is unstable, so ordering is imposed here to
    /// keep matching and snapshot tests deterministic.
    public let templates: [CommandTemplate]

    /// Data-quality findings from decoding. Empty means the payload was clean.
    public let diagnostics: [Diagnostic]

    // MARK: - Init

    /// Decode the backend payload: `{ "<category>": [ {…}, … ], … }`.
    public init(data: Data) throws {
        let raw = try JSONDecoder().decode([String: [RawCommandTemplate]].self, from: data)
        self.init(raw: raw)
    }

    init(raw: [String: [RawCommandTemplate]]) {
        var templates: [CommandTemplate] = []
        var diagnostics: [Diagnostic] = []

        for category in raw.keys.sorted() {
            for (index, entry) in (raw[category] ?? []).enumerated() {
                let code = entry.abbreviationCode?.trimmingCharacters(in: .whitespaces)
                let hasCode = !(code ?? "").isEmpty
                let id = hasCode ? code! : "\(category)#\(index)"

                let pattern = TemplatePattern(entry.icaoTemplate ?? "")
                let readback = TemplatePattern(entry.readBackText ?? "")

                if !hasCode {
                    diagnostics.append(.missingCode(id: id, category: category))
                }
                if pattern.isEmpty {
                    diagnostics.append(.emptyTemplate(id: id))
                }
                if readback.isEmpty {
                    diagnostics.append(.emptyReadback(id: id))
                }
                diagnostics.append(contentsOf: Self.sanitisationDiagnostics(
                    id: id, pattern: pattern, readback: readback, entry: entry))
                diagnostics.append(contentsOf: Self.slotDiagnostics(
                    id: id, pattern: pattern, readback: readback))

                templates.append(CommandTemplate(
                    id: id,
                    code: hasCode ? code : nil,
                    category: category,
                    pattern: pattern,
                    readback: readback,
                    speaker: entry.speaker ?? "",
                    keyboardShortcut: entry.keyboardShortCut.flatMap(Self.blankToNil),
                    comments: entry.comments.flatMap(Self.blankToNil),
                    isEnabled: (entry.show ?? 1) != 0))
            }
        }

        diagnostics.append(contentsOf: Self.duplicateCodeDiagnostics(in: templates))
        diagnostics.append(contentsOf: Self.indistinguishableDiagnostics(in: templates))

        self.templates = templates
        self.diagnostics = diagnostics
    }

    // MARK: - Corrections

    /// A replacement for one template's text.
    ///
    /// The payload contains mistakes that cannot be worked around by sanitising —
    /// code 320's readback names a placeholder its own request never supplies, so
    /// the reply can never be spoken. Waiting for the backend means the phrase
    /// stays broken; editing the bundled copy means the fix disappears the moment
    /// the payload is fetched for real. So corrections are applied here, and the
    /// diagnostics still report the underlying problem.
    ///
    /// Which templates need correcting is deployment knowledge, not parser
    /// knowledge: the list lives with the caller, only the mechanism lives here.
    public struct Correction: Equatable, Sendable {
        public let id: String
        public let template: String?
        public let readback: String?

        public init(id: String, template: String? = nil, readback: String? = nil) {
            self.id = id
            self.template = template
            self.readback = readback
        }
    }

    /// A copy with the given replacements applied. Corrections naming a template
    /// that is not present are ignored, so a stale list cannot break loading.
    public func applying(_ corrections: [Correction]) -> TemplateSet {
        guard !corrections.isEmpty else { return self }
        let byID = Dictionary(corrections.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        let corrected = templates.map { template -> CommandTemplate in
            guard let correction = byID[template.id] else { return template }
            return CommandTemplate(
                id: template.id,
                code: template.code,
                category: template.category,
                pattern: correction.template.map(TemplatePattern.init) ?? template.pattern,
                readback: correction.readback.map(TemplatePattern.init) ?? template.readback,
                speaker: template.speaker,
                keyboardShortcut: template.keyboardShortcut,
                comments: template.comments,
                isEnabled: template.isEnabled)
        }
        return TemplateSet(templates: corrected, diagnostics: diagnostics)
    }

    init(templates: [CommandTemplate], diagnostics: [Diagnostic]) {
        self.templates = templates
        self.diagnostics = diagnostics
    }

    // MARK: - Lookup

    /// Category keys in the order used by `templates`.
    public var categories: [String] {
        var seen = Set<String>()
        return templates.compactMap { seen.insert($0.category).inserted ? $0.category : nil }
    }

    public func templates(in category: String) -> [CommandTemplate] {
        templates.filter { $0.category == category }
    }

    public func template(id: String) -> CommandTemplate? {
        templates.first { $0.id == id }
    }

    /// Templates the current deployment allows to be acted on.
    public var enabled: [CommandTemplate] { templates.filter(\.isEnabled) }

    /// Templates that parse but must not execute.
    public var disabled: [CommandTemplate] { templates.filter { !$0.isEnabled } }

    // MARK: - Diagnostics helpers

    private static func blankToNil(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Flags entries whose text had to be cleaned up — the concrete list to send
    /// back to the backend (double spaces, `[TIME ]`, `[WAYPOINT/FIX/]`).
    private static func sanitisationDiagnostics(id: String,
                                                pattern: TemplatePattern,
                                                readback: TemplatePattern,
                                                entry: RawCommandTemplate) -> [Diagnostic] {
        var found: [Diagnostic] = []
        if let original = entry.icaoTemplate,
           original.trimmingCharacters(in: .whitespaces) != pattern.text {
            found.append(.sanitised(id: id, field: .template, from: original, to: pattern.text))
        }
        if let original = entry.readBackText,
           original.trimmingCharacters(in: .whitespaces) != readback.text {
            found.append(.sanitised(id: id, field: .readback, from: original, to: readback.text))
        }
        // "If not: …" appearing twice is duplicated text, not two branches.
        let clauses = readback.raw.lowercased().components(separatedBy: "if not:").count - 1
        if clauses > 1 {
            found.append(.repeatedReadbackClause(id: id, clause: "If not:", count: clauses))
        }
        return found
    }

    /// Compares the slots a controller phrase offers against the slots its
    /// readback needs. A readback-only slot is legitimate (`[ACTUAL LEVEL]`
    /// comes from aircraft state), so both directions are reported separately
    /// rather than as one "mismatch".
    private static func slotDiagnostics(id: String,
                                        pattern: TemplatePattern,
                                        readback: TemplatePattern) -> [Diagnostic] {
        let inTemplate = Set(pattern.slotNames)
        let inReadback = Set(readback.slotNames)
        var found: [Diagnostic] = []
        let templateOnly = inTemplate.subtracting(inReadback).sorted()
        let readbackOnly = inReadback.subtracting(inTemplate).sorted()
        if !templateOnly.isEmpty {
            found.append(.slotsMissingFromReadback(id: id, slots: templateOnly))
        }
        if !readbackOnly.isEmpty {
            found.append(.slotsNotInTemplate(id: id, slots: readbackOnly))
        }
        return found
    }

    /// Templates whose fixed words are word-for-word identical, differing only
    /// in which placeholder ends the phrase. Nothing in the spoken words can
    /// tell them apart, so the matcher reports the tie instead of guessing.
    private static func indistinguishableDiagnostics(in templates: [CommandTemplate]) -> [Diagnostic] {
        Dictionary(grouping: templates) { $0.pattern.literals.joined(separator: " ") }
            .filter { $0.value.count > 1 && !$0.key.isEmpty }
            .sorted { $0.key < $1.key }
            .map { .indistinguishable(ids: $0.value.map(\.id).sorted(),
                                      literals: $0.key) }
    }

    private static func duplicateCodeDiagnostics(in templates: [CommandTemplate]) -> [Diagnostic] {
        var byCode: [String: [String]] = [:]
        for template in templates {
            guard let code = template.code else { continue }
            byCode[code, default: []].append(template.category)
        }
        return byCode
            .filter { $0.value.count > 1 }
            .sorted { $0.key < $1.key }
            .map { .duplicateCode(code: $0.key, categories: $0.value.sorted()) }
    }
}

// MARK: - Diagnostic

extension TemplateSet {

    public enum Field: String, Equatable, Sendable {
        case template
        case readback
    }

    /// A data-quality finding. Not an error — decoding succeeds regardless.
    public enum Diagnostic: Equatable, Sendable {
        /// `abbreviationCode` was blank; `id` is a synthesised fallback.
        case missingCode(id: String, category: String)
        /// The same `abbreviationCode` appears under more than one category.
        case duplicateCode(code: String, categories: [String])
        /// `icaoTemplate` was blank or contained no usable tokens.
        case emptyTemplate(id: String)
        /// `readBackText` was blank or contained no usable tokens.
        case emptyReadback(id: String)
        /// Text needed cleanup before use (whitespace, slot-name typos).
        case sanitised(id: String, field: Field, from: String, to: String)
        /// A readback needs slots the controller phrase never supplies. Expected
        /// for state-derived values; suspicious otherwise.
        case slotsNotInTemplate(id: String, slots: [String])
        /// The controller phrase carries slots the readback never echoes.
        case slotsMissingFromReadback(id: String, slots: [String])
        /// A conditional clause is repeated verbatim in one readback.
        case repeatedReadbackClause(id: String, clause: String, count: Int)
        /// Two or more templates share an identical literal sequence and cannot
        /// be distinguished by the words a controller speaks.
        case indistinguishable(ids: [String], literals: String)
    }
}

extension TemplateSet.Diagnostic: CustomStringConvertible {
    public var description: String {
        switch self {
        case .missingCode(let id, let category):
            return "[\(id)] missing abbreviationCode in category '\(category)'"
        case .duplicateCode(let code, let categories):
            return "[\(code)] duplicate abbreviationCode across \(categories.joined(separator: ", "))"
        case .emptyTemplate(let id):
            return "[\(id)] empty icaoTemplate"
        case .emptyReadback(let id):
            return "[\(id)] empty readBackText"
        case .sanitised(let id, let field, let from, let to):
            return "[\(id)] \(field.rawValue) cleaned: \"\(from)\" → \"\(to)\""
        case .slotsNotInTemplate(let id, let slots):
            return "[\(id)] readback needs slots absent from template: \(slots.joined(separator: ", "))"
        case .slotsMissingFromReadback(let id, let slots):
            return "[\(id)] template slots not echoed in readback: \(slots.joined(separator: ", "))"
        case .repeatedReadbackClause(let id, let clause, let count):
            return "[\(id)] readback repeats \"\(clause)\" \(count)×"
        case .indistinguishable(let ids, let literals):
            return "[\(ids.joined(separator: ", "))] identical wording: \"\(literals)\""
        }
    }
}
