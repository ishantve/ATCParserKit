//
//  TurnDirection.swift
//  ATCParserKit
//
//  Direction of a commanded turn. Encodes to "left" / "right" in JSON.
//

import Foundation

public enum TurnDirection: String, Codable, Equatable, Sendable {
    case left
    case right
}
