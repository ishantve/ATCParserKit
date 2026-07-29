//
//  ATCParserModule.swift
//  @ishant89/atc-parser-kit
//
//  React Native (old-bridge) native module. A thin wrapper that hands the
//  transcript to the shared ATCParserKit Swift core and returns the parsed
//  result as a JSON string; the JS side JSON.parses it into a typed object.
//

import Foundation
import React
import ATCParserKit

@objc(ATCParserModule)
final class ATCParserModule: NSObject {

  @objc(parse:resolver:rejecter:)
  func parse(_ command: String,
             resolver resolve: @escaping RCTPromiseResolveBlock,
             rejecter reject: @escaping RCTPromiseRejectBlock) {
    do {
      let json = try ATCParser().parseToJSON(command)
      resolve(json)
    } catch {
      reject("atc_parse_error", "ATCParserKit could not parse the command", error)
    }
  }

  @objc static func requiresMainQueueSetup() -> Bool { false }
}
