# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.0.0/) and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- **Core (Phase 1):** pure-Swift `ATCParser` facade with `parse(_:)` and
  `parseToJSON(_:)`.
- Public wire models: `ParserResult`, `ParsedCommand`, `CommandType`,
  `TurnDirection` (all `Codable`, `Sendable`).
- Typed discriminated JSON contract; nil fields omitted; deterministic
  (sorted-key) output.
- Test suite covering parse semantics and the JSON wire contract.

_Not yet released. Core is complete; SPM/CocoaPods publish, React Native (iOS),
and Unity (iOS) wrappers follow in subsequent phases._
