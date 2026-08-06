//
//  ATCParserFFI.swift
//  ATCParserKit
//
//  Minimal C ABI over the Swift parser core, for consumers that call across a
//  C boundary (e.g. Unity via P/Invoke). Two symbols only: parse + free.
//  Everything returns a JSON C string; ownership is caller-frees.
//

import Foundation
import ATCParserKit

/// Parse an ATC command transcript and return the result as a JSON C string.
///
/// The returned pointer is heap-allocated (strdup) and MUST be released by the
/// caller with `atc_parser_free`. On failure a JSON error envelope is returned
/// (never NULL for a valid input pointer).
@_cdecl("atc_parser_parse")
func atc_parser_parse(_ command: UnsafePointer<CChar>?) -> UnsafeMutablePointer<CChar>? {
    let input = command.map { String(cString: $0) } ?? ""
    let json: String
    do {
        json = try ATCParser().parseToJSON(input)
    } catch {
        json = #"{"error":"parse_failed"}"#
    }
    return strdup(json)
}

/// Clean a raw transcript for display: recogniser-quirk fixups + ICAO spellings,
/// uppercased (see TranscriptCleaner). Returned pointer is strdup'd — free it with
/// `atc_parser_free`.
@_cdecl("atc_display_text")
func atc_display_text(_ transcript: UnsafePointer<CChar>?) -> UnsafeMutablePointer<CChar>? {
    let input = transcript.map { String(cString: $0) } ?? ""
    return strdup(TranscriptCleaner.displayText(input))
}

/// Free a string previously returned by `atc_parser_parse` / `atc_display_text`.
@_cdecl("atc_parser_free")
func atc_parser_free(_ pointer: UnsafeMutablePointer<CChar>?) {
    free(pointer)
}
