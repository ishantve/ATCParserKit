//
//  SlotKind.swift
//  ATCParserKit
//
//  What a `[PLACEHOLDER]` actually holds. The backend only gives placeholders a
//  name, so every value rule — range, digit width, how it is read aloud — lives
//  here.
//
//  Digit width is not decoration: `[THREE DIGITS]` says a heading is exactly
//  three digits, which is what lets "heading to seven zero" be recovered as 270
//  rather than accepted as 70.
//

import Foundation

public enum SlotKind: String, Equatable, Sendable, CaseIterable {

    /// Aircraft identity — "air india 123".
    case callsign
    /// Flight level — `[LEVEL]`, `[ACTUAL LEVEL]`.
    case flightLevel
    /// Altitude in feet — `[ALTITUDE]`. Read by magnitude, not digit-by-digit.
    case altitudeFeet
    /// Magnetic heading — `[THREE DIGITS]`. Exactly three digits.
    case heading
    /// Airspeed — `[NUMBER]` beside "knots".
    case speedKnots
    /// Relative turn amount — `[NUMBER OF DEGREES]`.
    case degrees
    /// Runway designator with optional L/R/C — `[NUMBER]` beside "runway".
    case runway
    /// Transponder code — `[CODE]`, `[ACTUAL CODE]`. Four octal digits.
    case squawk
    /// QNH — `[VALUE]`.
    case pressure
    /// Distance in nautical miles — `[DISTANCE]`.
    case distance
    /// Clock time — `[TIME]`. Four digits, HHMM. Typed rather than left as free
    /// text because it is the only thing separating template 122 from 123, whose
    /// literals are word-for-word identical.
    case time
    /// Radio frequency — `[FREQUENCY]`.
    case frequency
    /// A named point: fix, waypoint, VOR, DME station, holding fix.
    case fix
    /// Anything the parser cannot give structure to — reasons, intentions,
    /// times, unit names. Captured verbatim.
    case freeText
    /// `[NUMBER]` with no disambiguating context.
    case integer

    // MARK: - Value rules

    /// Accepted numeric range, or nil for non-numeric kinds.
    public var range: ClosedRange<Int>? {
        switch self {
        case .flightLevel:   return 10...600
        case .altitudeFeet:  return 0...60_000
        case .heading:       return 0...360
        case .speedKnots:    return 60...600
        case .degrees:       return 1...180
        case .runway:        return 1...36
        case .squawk:        return 0...7777
        case .pressure:      return 800...1100
        case .distance:      return 1...999
        case .time:          return 0...2359
        case .integer:       return 0...9999
        case .callsign, .frequency, .fix, .freeText:
            return nil
        }
    }

    /// Exact digit count when the phraseology fixes one, else nil.
    public var digitWidth: Int? {
        switch self {
        case .heading: return 3
        case .squawk:  return 4
        case .time:    return 4
        default:       return nil
        }
    }

    /// How the value is read back aloud.
    public var spokenStyle: SpokenStyle {
        switch self {
        case .altitudeFeet:            return .magnitude
        case .fix:                     return .phonetic
        case .callsign:                return .callsign
        case .freeText:                return .verbatim
        case .frequency:               return .digitsWithDecimal
        case .flightLevel, .heading, .speedKnots, .degrees, .runway,
             .squawk, .pressure, .distance, .time, .integer:
            return .digitByDigit
        }
    }

    public enum SpokenStyle: String, Equatable, Sendable {
        /// "260" → "two six zero"
        case digitByDigit
        /// "8500" → "eight thousand five hundred"
        case magnitude
        /// "121.5" → "one two one decimal five"
        case digitsWithDecimal
        /// "PJ" → "papa juliet"
        case phonetic
        /// "air india 123" → "air india one two three" — words as spoken, but the
        /// flight number digit by digit, never "one hundred twenty three".
        case callsign
        /// spoken as written
        case verbatim
    }

    /// True when the value comes from aircraft state rather than the transcript.
    /// Set by the registry for `[ACTUAL …]` placeholders, not by the kind itself.
    public var isNumeric: Bool { range != nil }
}
