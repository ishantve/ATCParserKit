//
//  CommandType.swift
//  ATCParserKit
//
//  Discriminator for a parsed command. The JSON `type` field. Each case pairs
//  with a specific subset of ParsedCommand's fields (see ParsedCommand).
//

import Foundation

public enum CommandType: String, Codable, Equatable, Sendable {
    case heading             // absolute heading, shortest turn      → heading
    case headingTurn         // absolute heading, forced direction   → heading, direction
    case relativeTurn        // turn N degrees left / right          → degrees, direction
    case presentHeading      // stop the turn, hold current heading  → (no fields)
    case flightLevel         // climb / descend / maintain a FL      → flightLevel
    case altitudeBlock       // maintain a block of flight levels    → altitudeLow, altitudeHigh
    case speed               // maintain an exact speed              → speed
    case minSpeed            // speed floor ("or greater")           → speed
    case maxSpeed            // speed ceiling ("do not exceed")      → speed
    case hold                // proceed direct and hold at a fix     → fix
    case interceptLocalizer  // intercept a runway localizer         → runway
}
