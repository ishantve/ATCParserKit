//
//  ParserResult.swift
//  ATCParserKit
//
//  The public, platform-independent output of a parse. Serialises to the JSON
//  contract consumed by Swift, React Native, and Unity.
//

import Foundation

public struct ParserResult: Codable, Equatable, Sendable {

    /// The callsign prefix, if one was detected (e.g. "air canada 125").
    /// `nil` for a plain command with no callsign.
    public let callsign: String?

    /// The recognised instructions, in the order they were parsed.
    public let commands: [ParsedCommand]

    /// The normalised transcript the parse ran on (lowercased, punctuation
    /// stripped, spoken digits expanded). Useful for debugging and telemetry.
    public let normalized: String

    public init(callsign: String?, commands: [ParsedCommand], normalized: String) {
        self.callsign = callsign
        self.commands = commands
        self.normalized = normalized
    }
}
