//
//  ATCRecognizerFFI.swift
//  ATCParserKit
//
//  C ABI over template-driven recognition, for consumers that call across a C boundary
//  (Unity via P/Invoke).
//
//  `atc_parser_parse` is one function because parsing built-in commands is one pure
//  string-to-string call. Template recognition is not: the payload is decoded once and reused
//  for every transmission, so it has a lifetime, and the boundary has to be
//  create / use / release. Re-decoding a 75-template payload per utterance would be wasteful
//  and would throw away the diagnostics, which are only produced at decode time.
//
//  Ownership rules, and they are the whole contract:
//    • every returned `char *` is heap-allocated and MUST be freed with `atc_parser_free`
//    • a handle from `atc_recognizer_create` MUST be released with `atc_recognizer_release`
//    • a released handle must never be used again
//

import Foundation
import ATCParserKit

/// What a handle points at.
///
/// A class, so the pointer can be an unmanaged reference with a retain we control. The
/// diagnostics are captured at creation because that is the only moment they exist.
private final class RecognizerBox {
    let recognizer: CommandRecognizer
    let diagnosticsJSON: String

    init(recognizer: CommandRecognizer, diagnosticsJSON: String) {
        self.recognizer = recognizer
        self.diagnosticsJSON = diagnosticsJSON
    }
}

/// Build a recognizer from a phraseology payload (the JSON your backend serves).
///
/// Returns an opaque handle, or NULL on failure. On failure, when `error_json` is non-NULL a
/// JSON error envelope is written to `*error_json` and must be freed with `atc_parser_free`;
/// the reason is reported rather than collapsed into NULL, because "your payload did not
/// decode" and "you passed a null pointer" need different fixes.
///
/// The handle is not thread-safe. Recognition itself is pure, but create/release are not:
/// use one handle per thread, or serialise access.
@_cdecl("atc_recognizer_create")
func atc_recognizer_create(_ templatesJSON: UnsafePointer<CChar>?,
                           _ errorJSON: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?)
    -> UnsafeMutableRawPointer? {

    func fail(_ reason: String, _ detail: String) -> UnsafeMutableRawPointer? {
        if let errorJSON {
            let escaped = detail.replacingOccurrences(of: "\\", with: "\\\\")
                                .replacingOccurrences(of: "\"", with: "\\\"")
            errorJSON.pointee = strdup(#"{"error":"\#(reason)","detail":"\#(escaped)"}"#)
        }
        return nil
    }

    guard let templatesJSON else { return fail("null_input", "templates_json was NULL") }

    do {
        let set = try TemplateSet(data: Data(String(cString: templatesJSON).utf8))
        let box = RecognizerBox(recognizer: CommandRecognizer(templates: set),
                               diagnosticsJSON: try set.diagnosticsJSON())
        return Unmanaged.passRetained(box).toOpaque()
    } catch {
        return fail("decode_failed", String(describing: error))
    }
}

/// Problems found in the payload while it was decoded, plus the template counts, as JSON.
///
/// Exposed across the bridge deliberately: a broken template otherwise fails silently as
/// commands that never match, and this is the only place that is visible.
///
/// Returns NULL for a NULL handle. Otherwise caller-frees with `atc_parser_free`.
@_cdecl("atc_recognizer_diagnostics")
func atc_recognizer_diagnostics(_ handle: UnsafeMutableRawPointer?)
    -> UnsafeMutablePointer<CChar>? {
    guard let handle else { return nil }
    return strdup(Unmanaged<RecognizerBox>.fromOpaque(handle).takeUnretainedValue()
        .diagnosticsJSON)
}

/// Recognise a transcript. Returns the result as a JSON C string; caller-frees with
/// `atc_parser_free`.
///
/// Returns NULL only for a NULL handle. An unrecognised transcript is not an error — it comes
/// back as a valid result with no commands and the text under `unrecognized`.
@_cdecl("atc_recognizer_recognize")
func atc_recognizer_recognize(_ handle: UnsafeMutableRawPointer?,
                              _ transcript: UnsafePointer<CChar>?)
    -> UnsafeMutablePointer<CChar>? {
    guard let handle else { return nil }
    let box = Unmanaged<RecognizerBox>.fromOpaque(handle).takeUnretainedValue()
    let input = transcript.map { String(cString: $0) } ?? ""
    do {
        return strdup(try box.recognizer.recognize(input).toJSON())
    } catch {
        return strdup(#"{"error":"encode_failed"}"#)
    }
}

/// Release a handle from `atc_recognizer_create`. Safe to call with NULL; never call twice
/// with the same handle.
@_cdecl("atc_recognizer_release")
func atc_recognizer_release(_ handle: UnsafeMutableRawPointer?) {
    guard let handle else { return }
    Unmanaged<RecognizerBox>.fromOpaque(handle).release()
}
