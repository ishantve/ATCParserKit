# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.0.0/) and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- **React Native (iOS) wrapper** under `platforms/react-native`
  (`@ishant89/atc-parser-kit`): RCT native module bridging the Swift core, a
  typed TypeScript API (`parse` + wire types), podspec, and a usage example.
  No parsing logic in JavaScript — fully delegated to Swift.

## [1.0.0] - 2026-07-29

### Added
- **Core:** pure-Swift `ATCParser` facade with `parse(_:)` and `parseToJSON(_:)`.
- Public wire models: `ParserResult`, `ParsedCommand`, `CommandType`,
  `TurnDirection` (all `Codable`, `Sendable`).
- Typed discriminated JSON contract; nil fields omitted; deterministic
  (sorted-key) output.
- Test suite covering parse semantics and the JSON wire contract.
- Swift Package Manager and CocoaPods distribution.

_React Native (iOS) and Unity (iOS) wrappers follow in subsequent releases._
