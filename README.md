# ATCParserKit

[![CI](https://github.com/ishantve/ATCParserKit/actions/workflows/ci.yml/badge.svg)](https://github.com/ishantve/ATCParserKit/actions/workflows/ci.yml)
[![CocoaPods](https://img.shields.io/cocoapods/v/ATCParserKit.svg)](https://cocoapods.org/pods/ATCParserKit)
[![Swift](https://img.shields.io/badge/Swift-5.9%2B-orange.svg)](https://swift.org)
[![Platforms](https://img.shields.io/badge/platforms-iOS%2015%2B%20%7C%20macOS%2012%2B-blue.svg)](#requirements)
[![SPM](https://img.shields.io/badge/SwiftPM-compatible-brightgreen.svg)](https://swift.org/package-manager)
[![License](https://img.shields.io/badge/license-MIT-lightgrey.svg)](LICENSE)

A dependency-free **ATC voice-command parser** written in Swift. It turns an
air-traffic-control transcript into a structured, JSON-ready result. The parsing logic lives
**once, in Swift**, and every other platform — Swift Package Manager, CocoaPods, React
Native, Unity — is a thin wrapper over that same core, so there is a single source of truth
and no duplicated logic.

**Current release: `1.3.0`** ([release notes](docs/releases/1.3.0.md)). Available on Swift
Package Manager and Unity (git) today; CocoaPods and npm serve the latest published version
(see each section).

There are **two ways to use it**, and they coexist. Both are available on **every** platform —
Swift, React Native and Unity.

### 1. Built-in commands — one call, no setup

```swift
let result = try ATCParser().parse("air canada 125 climb flight level 250 turn left heading 270")
// result.callsign == "air canada 125"
// result.commands == [
//   ParsedCommand(type: .headingTurn, heading: 270, direction: .left),
//   ParsedCommand(type: .flightLevel, flightLevel: 250),
// ]
```

Eleven command types, compiled in. This is also the API the React Native and Unity wrappers
expose.

### 2. Your own phraseology — templates as input

```swift
let templates = try TemplateSet(data: payloadJSON)     // your ICAO wording, your codes
let recognizer = CommandRecognizer(templates: templates)

let result = recognizer.recognize("air india 123 climb and maintain FL260, speed 300 knots")
// two commands, each with its category, backend code, filled slots and readback
for (callsign, spoken) in result.composedReadbacks() { speak(spoken) }
```

Recognises whatever the payload defines — several instructions and several aircraft in one
transmission, with the readback to speak back.

The same thing from TypeScript and C#. Both hold a payload, so both have a lifetime:

```ts
const recognizer = await Recognizer.create(payloadJson);   // React Native
const result = await recognizer.recognize(transcript);
recognizer.dispose();
```
```csharp
using (var recognizer = Recognizer.Create(payloadJson))    // Unity
{
    var result = recognizer.Recognize(transcript);
}
```

> **Scope:** the parser core is pure `Foundation` and runs anywhere Swift runs.
> The React Native and Unity wrappers are **iOS-only** (they bridge the compiled
> Swift binary); Android / desktop / WebGL are not supported in v1.

## Features

**Both APIs**

- Callsign extraction (airline-agnostic, no lookup table).
- Spoken-digit expansion (`"two seven zero"` → `270`), tens words (`"seventy"` → `70`) and
  ICAO phonetics (`"papa juliet"` → `PJ`) — speech transcripts arrive as words,
  inconsistently, and all forms parse to the same value.

**Built-in commands (`ATCParser`)**

- Heading, forced-direction turn, relative turn, present heading, flight level, altitude
  block, speed / floor / ceiling, hold, localizer intercept.
- Typed, lossless JSON contract — trivial to consume from JS and C#.

**Template-driven (`CommandRecognizer`)**

- Your phraseology payload is the vocabulary; the library is not recompiled to add a command.
- Several commands, and several aircraft, in one transmission.
- Readbacks rendered from the template — including the `Later:` report a pilot owes and the
  `If not:` answer to a confirmation.
- Typed slots with contextual resolution and separate parse / spoken digit widths (FL090 is
  read "zero nine zero").
- Payload diagnostics, so a broken template is reported rather than silently mis-parsed.
- Available from Swift, TypeScript and C# — one implementation, three bindings.

## Installation

### Swift Package Manager

```swift
dependencies: [
    .package(url: "https://github.com/ishantve/ATCParserKit.git", from: "1.3.0")
]
```

### CocoaPods

```ruby
pod 'ATCParserKit', '~> 1.3'
```

### React Native (iOS)

```sh
npm install @ishant89/atc-parser-kit && cd ios && pod install
```

```ts
import { parse, Recognizer } from '@ishant89/atc-parser-kit';
const result = await parse('aca 29 speed 280');
```

See [platforms/react-native](platforms/react-native/README.md).

### Unity (iOS)

Add via **Package Manager → Add package from git URL**:

```
https://github.com/ishantve/ATCParserKit.git?path=platforms/unity#1.3.0
```

```csharp
using ATCParserKit;
var result = Parser.Parse("aca 29 speed 280");
```

See [platforms/unity](platforms/unity/README.md).

## Usage

### Built-in commands

```swift
import ATCParserKit

let parser = ATCParser()

// Typed result
let result = try parser.parse("indigo 2341 intercept the localizer runway 27 left")
for command in result.commands {
    switch command.type {
    case .interceptLocalizer: print("ILS runway", command.runway ?? "")
    case .flightLevel:        print("FL", command.flightLevel ?? 0)
    default:                  break
    }
}

// JSON (the boundary used by React Native & Unity)
let json = try parser.parseToJSON("aca 29 speed 280")
```

### Template-driven

```swift
// Load the payload once and keep the recognizer; it is a value type and cheap to hold.
let templates = try TemplateSet(data: try Data(contentsOf: payloadURL))
for issue in templates.diagnostics { print("payload issue:", issue) }

let recognizer = CommandRecognizer(templates: templates)
let result = recognizer.recognize(transcript)

// One reply per aircraft, however many instructions it was given.
for (callsign, spoken) in result.composedReadbacks() { speak(spoken) }

// Only .ok may be acted on — .disabled parsed but is not available, and
// .invalidValue parsed but the value is out of range. Both still get a reply.
for command in result.commands where command.isActionable {
    apply(command.code, command.slots)
}

// Never silent about what it could not place.
for leftover in result.unrecognized { log("not understood:", leftover) }
```

## JSON contract

This is the wire format of `parseToJSON` — the built-in-command API. The template API has its
own, documented in
[`Sources/ATCParserKit/Wire/RecognitionWire.swift`](Sources/ATCParserKit/Wire/RecognitionWire.swift);
both are the boundary the React Native and Unity wrappers cross.

```json
{
  "callsign": "air canada 125",
  "normalized": "air canada 125 climb flight level 250 turn left heading 270",
  "commands": [
    { "type": "headingTurn", "heading": 270, "direction": "left" },
    { "type": "flightLevel", "flightLevel": 250 }
  ]
}
```

Each command carries only the fields relevant to its `type`; unused fields are
omitted. `type` is one of: `heading`, `headingTurn`, `relativeTurn`,
`presentHeading`, `flightLevel`, `altitudeBlock`, `speed`, `minSpeed`,
`maxSpeed`, `hold`, `interceptLocalizer`.

| Field | Present for |
|---|---|
| `heading` | `heading`, `headingTurn` |
| `degrees` | `relativeTurn` |
| `direction` (`left`/`right`) | `headingTurn`, `relativeTurn` |
| `flightLevel` | `flightLevel` |
| `altitudeLow`, `altitudeHigh` | `altitudeBlock` |
| `speed` | `speed`, `minSpeed`, `maxSpeed` |
| `fix` | `hold` |
| `runway` | `interceptLocalizer` |

## Requirements

| | |
|---|---|
| Swift | 5.9+ |
| Platforms | iOS 15+, macOS 12+ (core); iOS only for RN / Unity wrappers |
| Dependencies | none (Foundation) |

## Roadmap

- [x] **Phase 1** — pure-Swift core + public API + JSON contract + tests
- [x] **Phase 2** — SPM + CocoaPods publish (`v1.0.0`)
- [x] **Phase 3** — React Native (iOS) wrapper ([`@ishant89/atc-parser-kit`](platforms/react-native))
- [x] **Phase 4** — Unity (iOS) native plugin ([`com.ishantve.atcparserkit`](platforms/unity))
- [x] **Phase 5** — CI/CD ([Actions](.github/workflows)) + multi-platform docs
- [x] **1.2.0** — template-driven recognition, multi-command, readbacks ([notes](docs/releases/1.2.0.md))
- [x] **1.3.0** — the template API on React Native and Unity too, over a handle-based
      bridge ([notes](docs/releases/1.3.0.md))
- [ ] **Later** — Android / desktop support (would mean a second implementation; not planned
      while Swift is the single source of truth)

## Contributing

Issues and PRs welcome. The golden rule: **parsing logic stays in the Swift
core only** — wrappers are thin bridges. See [CONTRIBUTING.md](CONTRIBUTING.md)
for the layout, dev workflow, JSON-contract policy, and release process.

## License

ATCParserKit is available under the MIT license. See [LICENSE](LICENSE).
