//
//  ParsedCommand.swift
//  ATCParserKit
//
//  Public, platform-independent representation of one parsed instruction.
//  A flat, decode-friendly struct: only the fields relevant to `type` are
//  populated; the rest stay nil and are omitted from JSON. This keeps the wire
//  format trivial to consume from JavaScript (React Native) and C# (Unity).
//

import Foundation

public struct ParsedCommand: Codable, Equatable, Sendable {

    /// Which instruction this is. Selects which fields below are populated.
    public let type: CommandType

    /// Absolute heading in degrees — `heading`, `headingTurn`.
    public let heading: Double?
    /// Relative turn amount in degrees — `relativeTurn`.
    public let degrees: Double?
    /// Turn direction — `headingTurn`, `relativeTurn`.
    public let direction: TurnDirection?
    /// Flight level — `flightLevel`.
    public let flightLevel: Int?
    /// Lower bound of an altitude block — `altitudeBlock`.
    public let altitudeLow: Int?
    /// Upper bound of an altitude block — `altitudeBlock`.
    public let altitudeHigh: Int?
    /// Speed in knots — `speed`, `minSpeed`, `maxSpeed`.
    public let speed: Double?
    /// Holding fix identifier — `hold`.
    public let fix: String?
    /// Runway designator — `interceptLocalizer`.
    public let runway: String?

    public init(type: CommandType,
                heading: Double? = nil,
                degrees: Double? = nil,
                direction: TurnDirection? = nil,
                flightLevel: Int? = nil,
                altitudeLow: Int? = nil,
                altitudeHigh: Int? = nil,
                speed: Double? = nil,
                fix: String? = nil,
                runway: String? = nil) {
        self.type = type
        self.heading = heading
        self.degrees = degrees
        self.direction = direction
        self.flightLevel = flightLevel
        self.altitudeLow = altitudeLow
        self.altitudeHigh = altitudeHigh
        self.speed = speed
        self.fix = fix
        self.runway = runway
    }
}

// MARK: - Mapping from the internal domain model

extension ParsedCommand {
    /// Translate an internal `AircraftCommand` into the public wire model.
    init(_ command: AircraftCommand) {
        switch command {
        case .heading(let h):
            self.init(type: .heading, heading: h)
        case .headingTurn(let h, let d):
            self.init(type: .headingTurn, heading: h, direction: d)
        case .relativeTurn(let deg, let d):
            self.init(type: .relativeTurn, degrees: deg, direction: d)
        case .presentHeading:
            self.init(type: .presentHeading)
        case .flightLevel(let fl):
            self.init(type: .flightLevel, flightLevel: fl)
        case .altitudeBlock(let low, let high):
            self.init(type: .altitudeBlock, altitudeLow: low, altitudeHigh: high)
        case .speed(let kt):
            self.init(type: .speed, speed: kt)
        case .minSpeed(let kt):
            self.init(type: .minSpeed, speed: kt)
        case .maxSpeed(let kt):
            self.init(type: .maxSpeed, speed: kt)
        case .hold(let fix):
            self.init(type: .hold, fix: fix)
        case .interceptLocalizer(let runway):
            self.init(type: .interceptLocalizer, runway: runway)
        }
    }
}
