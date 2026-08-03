# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.0.0/) and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.2.0] - 2026-08-03

Template-driven recognition. **Additive — nothing in 1.x changed**, so every existing
Swift, React Native and Unity caller keeps working untouched. Full notes:
[docs/releases/1.2.0.md](docs/releases/1.2.0.md).

### Added
- **Templates as input.** `TemplateSet(data:)` decodes a phraseology payload into
  `CommandTemplate`s grouped by category; `CommandRecognizer(templates:).recognize(_:)`
  recognises whatever that payload defines instead of a fixed set compiled into the library.
  `TemplatePattern` keeps a lowercased form for matching and the original casing for speech.
- **Payload diagnostics.** `TemplateSet.diagnostics` reports what is wrong with a payload —
  a readback naming a placeholder its instruction never supplies, a missing code, two
  templates with identical literal words — instead of silently doing its best.
  `TemplateSet.Correction` + `applying(_:)` let a deployment fix a known-bad entry at load
  time without forking the payload.
- **Multiple commands and multiple aircraft in one transmission.** Matches are selected
  non-overlapping in spoken order; each command carries its own callsign (carried forward
  from the last one spoken), and `groupedByCallsign()` splits them.
- **`TemplateMatcher`** — literal-subsequence alignment with tunable `minimumScore` (0.5),
  `minimumCoverage` (0.6), `maximumLiteralGap` (2) and `optionalLiterals`
  (`["radar", "the"]`); bounded callsign runs; `tiedWith` surfaces equally good matches
  rather than hiding the ambiguity.
- **Slots.** `SlotKind` (15 kinds, each with a range and digit width), `SlotValue`,
  `SlotRegistry` with contextual resolution — a bare `[NUMBER]` is a runway next to
  "runway" and a speed next to "knots". Parse width and *spoken* width are separate, so
  FL090 reads "zero nine zero" and squawk 2000 reads digit by digit.
- **Number words both directions.** `NumberWords` parses "two six zero" and "seventy"
  (spoken back as "seven zero") and renders values as spoken digits; `Lexicon` holds
  spellings, abbreviations (`fl` → `flight level`), the two safe contractions, and ICAO
  phonetics. Homophone repair ("for" → 4, "to" → 2) applies only inside fixed-width slots,
  never globally.
- **Readbacks.** `Readback` splits a reply into its immediate part, a `Later:` part the
  pilot owes once a condition is met, and an `If not:` / `If incorrect:` alternative;
  `ReadbackRenderer` fills and renders each branch; `ReadbackComposer` joins several
  readbacks for one aircraft into a single utterance. `unresolvedSlots` prevents speaking a
  sentence with a hole in it.
- **`RecognizedCommand.outcome`** — `.ok` / `.disabled` / `.invalidValue`. A
  recognised-but-unavailable command is neither an error nor a success: it parses, gets its
  own reply, and must not execute. `RecognitionResult.unrecognized` reports what nothing
  matched.
- Tests: **151**, up from 13.

### Notes
- The template API is **Swift-only** in this release. The React Native and Unity wrappers
  still expose 1.x `parse` / `parseToJSON`: the 1.x call is a pure string-to-string function
  that suits a C ABI, whereas template recognition needs a payload held across calls, making
  the bridge create/recognise/release. That is the next release rather than a half-done part
  of this one.

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
