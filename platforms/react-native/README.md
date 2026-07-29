# @ishant89/atc-parser-kit

React Native (iOS) wrapper for [ATCParserKit](https://github.com/ishantve/ATCParserKit).
Parses ATC voice-command transcripts into structured, typed results. **The
parsing logic runs natively in Swift** — this package is a thin bridge, so JS
and native share one implementation.

> **iOS only.** The wrapper bridges the compiled Swift core; Android is not
> supported in this version.

## Installation

```sh
npm install @ishant89/atc-parser-kit
cd ios && pod install
```

Autolinking pulls in the native module and the `ATCParserKit` Swift core pod.

## Usage

```ts
import { parse } from '@ishant89/atc-parser-kit';

const result = await parse('air canada 125 climb flight level 250 turn left heading 270');
// {
//   callsign: 'air canada 125',
//   normalized: 'air canada 125 climb flight level 250 turn left heading 270',
//   commands: [
//     { type: 'headingTurn', heading: 270, direction: 'left' },
//     { type: 'flightLevel', flightLevel: 250 },
//   ],
// }
```

### Types

```ts
import type { ParserResult, ParsedCommand, CommandType, TurnDirection } from '@ishant89/atc-parser-kit';
```

`CommandType` is one of: `heading`, `headingTurn`, `relativeTurn`,
`presentHeading`, `flightLevel`, `altitudeBlock`, `speed`, `minSpeed`,
`maxSpeed`, `hold`, `interceptLocalizer`. Each `ParsedCommand` carries only the
fields relevant to its `type` (see [`src/types.ts`](src/types.ts)).

## API

### `parse(command: string): Promise<ParserResult>`

Parses `command` and resolves with the structured result. Rejects on empty
input or on non-iOS platforms.

## How it works

```
JS parse(str)
  → NativeModules.ATCParserModule.parse   (RCT bridge)
  → ATCParser().parseToJSON               (Swift, ATCParserKit)
  → JSON string
  → JSON.parse                            (typed ParserResult)
```

No parsing logic exists in JavaScript — it is entirely delegated to Swift.

## License

MIT
