//
//  ATCParser.swift
//  ATCParserKit
//
//  Public facade — the single entry point. Parsing is context-free and pure
//  (Foundation only), so the same logic drives every platform (native Swift,
//  React Native, Unity) via `parse` or its JSON convenience `parseToJSON`.
//

import Foundation

public final class ATCParser {

    public init() {}

    /// Parse an ATC transcript into a structured result.
    ///
    /// Parsing is lenient: unrecognised text simply yields an empty `commands`
    /// array rather than an error. `throws` is reserved for genuinely unusable
    /// input (empty / whitespace-only).
    public func parse(_ command: String) throws -> ParserResult {
        let normalized = CommandParser.normalize(command)
        guard !normalized.isEmpty else { throw ATCParserError.emptyInput }

        // Split off a callsign prefix so flight-number digits can't collide with
        // command values; parse the remainder (or the whole string if none).
        let extracted = CommandParser.extractCallsign(from: normalized)
        let commandText = extracted?.commandText ?? normalized

        let commands = CommandParser.parse(commandText).map(ParsedCommand.init)
        return ParserResult(callsign: extracted?.callsign,
                            commands: commands,
                            normalized: normalized)
    }

    /// Same as `parse`, encoded as a JSON string. This is the boundary used by
    /// the React Native bridge and the Unity C interface — the one and only
    /// serialisation point. Keys are sorted for deterministic output.
    public func parseToJSON(_ command: String) throws -> String {
        let result = try parse(command)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(result)
        return String(decoding: data, as: UTF8.self)
    }
}

/// Errors thrown by `ATCParser`.
public enum ATCParserError: Error, Equatable, Sendable {
    /// The input was empty or contained nothing parseable after normalisation.
    case emptyInput
}
