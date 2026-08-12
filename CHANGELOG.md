# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.0.0/) and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.4.0] - 2026-08-12

One shared transcript cleanup for the parser and the screen. **Additive** — nothing in 1.x,
1.2.0 or 1.3.0 changed. Full notes: [docs/releases/1.4.0.md](docs/releases/1.4.0.md).

### Added
- **`TranscriptCleaner`** (`Sources/ATCParserKit/Matching/TranscriptCleaner.swift`) — the
  recognizer-quirk fixups every consumer was doing itself: hyphen folding (`take-off` →
  `takeoff`), ICAO spellings (`juliet` → `juliett`, `alpha` → `alfa`, `three` → `tree`), and
  removal of `[unk]` and stray commas. `clean` preserves case for the parser (the matcher
  lowercases internally); `displayText` uppercases for a text field. Whole-word,
  case-insensitive, applied in order — and the `\b` boundary is added only where the rule's
  own edge is a word character, so `[unk]` actually matches while `threefold` stays intact.
- **`TranscriptNormalizer` runs `clean` as step 0**, so the recognition path and the display
  share one cleanup instead of drifting apart.
- **Leading phonetic callsign folds to a code** — `"echo tango delta 615"` → `"ETD 615"`, so a
  spelled-out callsign matches its aircraft. Leading run only (the callsign position) and two
  or more words only, so a lone `delta` (an airline, a plain word) is left alone.
- **ICAO digit spellings in spoken output** — `spokenDigits` reads 3/4/5/9 as
  `tree` / `fower` / `fife` / `niner`, matching how a controller reads a heading, level,
  squawk or callsign aloud.
- **`NumberWords.spokenFragment`** (and `NumberWords` is now `public`) — renders an arbitrary
  fragment for speech with digit runs read digit-by-digit: `"emirates 22 5"` →
  `"emirates two two fife"`. For the "say again" case, where handing `22` to a synthesiser
  would otherwise produce "twenty two".
- **`displayText` on every platform** — C ABI `atc_display_text` (free with
  `atc_parser_free`), React Native `displayText(transcript)`, Unity `Parser.DisplayText`.
  String in, string out, so it needs no handle.
- Tests: **177**, up from 170.

### Fixed
- The stray-comma rule ran inside `clean`, which `TranscriptNormalizer` calls *before* it
  looks for clause punctuation — so a two-aircraft transmission
  (`"… report passing PJ, speedbird 45 …"`) lost its split and produced one readback instead
  of two. Commas are now dropped in `displayText` only: the screen has none, the matcher still
  sees where a clause ended.

### Changed
- CI verifies **seven** exported C symbols in both xcframework slices, up from six.

## [1.3.0] - 2026-08-03

The template API reaches React Native and Unity. **Additive** — nothing in 1.x or 1.2.0
changed. Full notes: [docs/releases/1.3.0.md](docs/releases/1.3.0.md).

### Added
- **Handle-based C ABI** (`ATCParserFFI`): `atc_recognizer_create`,
  `atc_recognizer_recognize`, `atc_recognizer_diagnostics`, `atc_recognizer_release`.
  Create/use/release rather than one call, because the payload is decoded once and reused —
  re-decoding per utterance would be wasteful and would discard the diagnostics, which only
  exist at decode time. A NULL handle returns NULL instead of trapping; a failed create
  reports its reason (`decode_failed` vs `null_input`) in a JSON envelope.
- **Unity:** `Recognizer : IDisposable` with `Create` / `Recognize` / `Diagnostics` /
  `Dispose`, plus `[Serializable]` result types. The finalizer is a backstop, not the plan.
- **React Native:** `Recognizer` class (`create` / `recognize` / `diagnostics` / `dispose`)
  over a new `ATCRecognizerModule`. The handle is an `Int` into a native table, not a pointer:
  the bridge carries only JSON values, and a stale number must not become a wild pointer, so a
  released handle gives a reported `atc_invalid_handle` error rather than a crash.
- **Wire format** (`Sources/ATCParserKit/Wire/RecognitionWire.swift`) for recognition results
  and payload diagnostics. Shaped by Unity's `JsonUtility`, the tightest consumer: flat
  objects, no sum types, **no nulls** (absent string → `""`, absent number → `0` beside a
  `has…` flag), no top-level arrays. `readbacks` arrive already grouped per aircraft,
  `isActionable` is precomputed, and integer slots carry both `value` and `intValue` — so
  neither TypeScript nor C# reimplements phraseology or re-parses numbers.
- Tests: **170**, up from 151 — the new ones drive the C ABI as Unity does (handle lifecycle,
  two independent handles, NULL safety, failure reporting) and pin the wire shape (no nulls for
  any input, every key always present, `outcome` one of three known strings, `isActionable`
  always agreeing with it, and deterministic output).

### Changed
- CI verifies all **six** exported C symbols in **both** xcframework slices, rather than two
  symbols in one.

### Notes
- 1.2.0 stamped the npm and UPM packages to `1.2.0` while their code still exposed the 1.1.1
  API. Those channels were never published at 1.2.0 for that reason; 1.3.0 is the first
  version where every platform means the same thing.
- Still iOS-only for React Native and Unity: they bridge a compiled Swift binary, and Android
  would mean a second implementation of the parser.

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
