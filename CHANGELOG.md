# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.0.0/) and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.1.1] - 2026-07-29

### Fixed
- React Native: `ATCParserModule.swift` used `RCTPromiseResolveBlock` /
  `RCTPromiseRejectBlock` without `import React`, so the native module failed to
  compile in consumer apps. Added `import React`.

## [1.1.0] - 2026-07-29

### Added
- **CI/CD** (`.github/workflows`): `ci.yml` (Swift build/test, podspec lint,
  xcframework build + symbol check, RN typecheck) and `release.yml` (tag-driven
  CocoaPods + npm publish and a GitHub Release with the xcframework).
- `scripts/release.sh` — stamps one version across SPM/CocoaPods/npm/Unity.
- `CONTRIBUTING.md` and a multi-platform top-level README.
- **React Native (iOS) wrapper** under `platforms/react-native`
  (`@ishant89/atc-parser-kit`): RCT native module bridging the Swift core, a
  typed TypeScript API (`parse` + wire types), podspec, and a usage example.
  No parsing logic in JavaScript — fully delegated to Swift.
- **Unity (iOS) native plugin** under `platforms/unity`
  (`com.ishantve.atcparserkit`): a new `ATCParserFFI` C-ABI target (`@_cdecl`
  `atc_parser_parse` / `atc_parser_free`), a static `xcframework` built via
  `scripts/build-xcframework.sh`, and a C# `Parser.Parse` wrapper
  (`DllImport("__Internal")` → JSON → `JsonUtility`). No parsing logic in C#.

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
