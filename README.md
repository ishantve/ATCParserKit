# ATCParserKit

[![CI](https://github.com/ishantve/ATCParserKit/actions/workflows/ci.yml/badge.svg)](https://github.com/ishantve/ATCParserKit/actions/workflows/ci.yml)
[![CocoaPods](https://img.shields.io/cocoapods/v/ATCParserKit.svg)](https://cocoapods.org/pods/ATCParserKit)
[![Swift](https://img.shields.io/badge/Swift-5.9%2B-orange.svg)](https://swift.org)
[![Platforms](https://img.shields.io/badge/platforms-iOS%2015%2B%20%7C%20macOS%2012%2B-blue.svg)](#requirements)
[![SPM](https://img.shields.io/badge/SwiftPM-compatible-brightgreen.svg)](https://swift.org/package-manager)
[![License](https://img.shields.io/badge/license-MIT-lightgrey.svg)](LICENSE)

A dependency-free **ATC voice-command parser** written in Swift. It turns an
air-traffic-control transcript (e.g. _"air canada 125 climb flight level 250
turn left heading 270"_) into a structured, JSON-ready result — a callsign plus
a typed list of commands (heading, flight level, altitude block, speed
floor/ceiling, hold, localizer intercept). The parsing logic lives **once, in
Swift**, and every other platform — Swift Package Manager, CocoaPods, React
Native, Unity — is a thin wrapper over that same core, so there is a single
source of truth and no duplicated logic.

**Current release: `1.1.1`.** Available on Swift Package Manager and Unity (git)
today; CocoaPods and npm serve the latest published version (see each section).

```swift
import ATCParserKit

let result = try ATCParser().parse("air canada 125 climb flight level 250 turn left heading 270")
// result.callsign == "air canada 125"
// result.commands == [
//   ParsedCommand(type: .headingTurn, heading: 270, direction: .left),
//   ParsedCommand(type: .flightLevel, flightLevel: 250),
// ]
```

> **Scope:** the parser core is pure `Foundation` and runs anywhere Swift runs.
> The React Native and Unity wrappers are **iOS-only** (they bridge the compiled
> Swift binary); Android / desktop / WebGL are not supported in v1.

## Features

- Callsign extraction (airline-agnostic, no lookup table).
- Commands: heading, forced-direction turn, present heading, flight level,
  altitude block, speed / speed floor / speed ceiling, hold, localizer intercept.
- Spoken-digit expansion (`"two seven zero"` → `270`) and ICAO phonetics
  (`"papa juliet"` → `PJ`).
- Typed, lossless JSON contract — trivial to consume from JS and C#.

## Installation

### Swift Package Manager

```swift
dependencies: [
    .package(url: "https://github.com/ishantve/ATCParserKit.git", from: "1.1.1")
]
```

### CocoaPods

```ruby
pod 'ATCParserKit', '~> 1.0'
```

### React Native (iOS)

```sh
npm install @ishant89/atc-parser-kit && cd ios && pod install
```

```ts
import { parse } from '@ishant89/atc-parser-kit';
const result = await parse('aca 29 speed 280');
```

See [platforms/react-native](platforms/react-native/README.md).

### Unity (iOS)

Add via **Package Manager → Add package from git URL**:

```
https://github.com/ishantve/ATCParserKit.git?path=platforms/unity#1.1.1
```

```csharp
using ATCParserKit;
var result = Parser.Parse("aca 29 speed 280");
```

See [platforms/unity](platforms/unity/README.md).

## Usage

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

## JSON contract

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

## Contributing

Issues and PRs welcome. The golden rule: **parsing logic stays in the Swift
core only** — wrappers are thin bridges. See [CONTRIBUTING.md](CONTRIBUTING.md)
for the layout, dev workflow, JSON-contract policy, and release process.

## License

ATCParserKit is available under the MIT license. See [LICENSE](LICENSE).
