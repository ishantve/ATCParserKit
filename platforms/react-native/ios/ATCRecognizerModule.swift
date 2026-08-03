//
//  ATCRecognizerModule.swift
//  @ishant89/atc-parser-kit
//
//  React Native (old-bridge) native module for template-driven recognition.
//
//  Unlike `parse`, this holds state: the phraseology payload is decoded once and reused for
//  every transmission, so the JS side gets a handle and must release it.
//
//  The handle is an `Int`, not a pointer. The bridge can only carry JSON-compatible values, and
//  handing JavaScript a raw address would let a stale number become a wild pointer. An integer
//  into a table we own means a stale handle is a clean, reported error instead of a crash.
//

import Foundation
import React
import ATCParserKit

@objc(ATCRecognizerModule)
final class ATCRecognizerModule: NSObject {

  /// Live recognizers, and the diagnostics captured when each payload was decoded — that is
  /// the only moment they exist.
  private var recognizers: [Int: (recognizer: CommandRecognizer, diagnostics: String)] = [:]
  private var nextHandle = 1

  /// React Native calls a module's methods on one queue, but that is a framework detail rather
  /// than a guarantee this table should rely on, so it takes a lock.
  private let lock = NSLock()

  // MARK: - Lifecycle

  /// Decode a phraseology payload and return a handle to keep.
  ///
  /// Rejects with the decoder's own reason rather than a generic failure: "your payload is
  /// malformed" and "that field is the wrong type" need different fixes, and a JS caller has no
  /// other way to see which it was.
  @objc(createRecognizer:resolver:rejecter:)
  func createRecognizer(_ templatesJSON: String,
                        resolver resolve: @escaping RCTPromiseResolveBlock,
                        rejecter reject: @escaping RCTPromiseRejectBlock) {
    do {
      let set = try TemplateSet(data: Data(templatesJSON.utf8))
      let entry = (recognizer: CommandRecognizer(templates: set),
                   diagnostics: try set.diagnosticsJSON())
      lock.lock()
      let handle = nextHandle
      nextHandle += 1
      recognizers[handle] = entry
      lock.unlock()
      resolve(handle)
    } catch {
      reject("atc_payload_error",
             "ATCParserKit could not decode the phraseology payload: \(error)", error)
    }
  }

  /// Release a handle. Releasing an unknown handle is not an error — a double dispose is
  /// harmless and should not crash a React component's unmount path.
  @objc(releaseRecognizer:resolver:rejecter:)
  func releaseRecognizer(_ handle: NSNumber,
                         resolver resolve: @escaping RCTPromiseResolveBlock,
                         rejecter reject: @escaping RCTPromiseRejectBlock) {
    lock.lock()
    recognizers[handle.intValue] = nil
    lock.unlock()
    resolve(nil)
  }

  // MARK: - Use

  /// Recognise one transmission. Several instructions and several aircraft may appear in it.
  @objc(recognize:transcript:resolver:rejecter:)
  func recognize(_ handle: NSNumber,
                 transcript: String,
                 resolver resolve: @escaping RCTPromiseResolveBlock,
                 rejecter reject: @escaping RCTPromiseRejectBlock) {
    guard let entry = entry(for: handle) else {
      return rejectStaleHandle(handle, reject)
    }
    do {
      resolve(try entry.recognizer.recognize(transcript).toJSON())
    } catch {
      reject("atc_encode_error", "ATCParserKit could not encode the result", error)
    }
  }

  /// Problems found in the payload when it was decoded, plus the template counts.
  @objc(diagnostics:resolver:rejecter:)
  func diagnostics(_ handle: NSNumber,
                   resolver resolve: @escaping RCTPromiseResolveBlock,
                   rejecter reject: @escaping RCTPromiseRejectBlock) {
    guard let entry = entry(for: handle) else {
      return rejectStaleHandle(handle, reject)
    }
    resolve(entry.diagnostics)
  }

  // MARK: - Private

  private func entry(for handle: NSNumber)
    -> (recognizer: CommandRecognizer, diagnostics: String)? {
    lock.lock()
    defer { lock.unlock() }
    return recognizers[handle.intValue]
  }

  private func rejectStaleHandle(_ handle: NSNumber,
                                 _ reject: @escaping RCTPromiseRejectBlock) {
    reject("atc_invalid_handle",
           "Recognizer \(handle) has been released, or was never created. "
             + "Create one per phraseology payload and dispose it when done.",
           nil)
  }

  @objc static func requiresMainQueueSetup() -> Bool { false }
}
