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

## Your own phraseology

`parse` knows eleven built-in commands. To recognise **your own ICAO phraseology** instead,
give `Recognizer` your template payload — it matches whatever that payload defines, handles
several instructions and several aircraft in one transmission, and returns the readback to
speak back.

```ts
import { Recognizer } from '@ishant89/atc-parser-kit';

// Create one per payload and keep it — creating one per utterance re-decodes the
// whole payload and discards the diagnostics.
const recognizer = await Recognizer.create(payloadJson);

// Log these at startup: a broken template otherwise fails silently, as an
// instruction that never matches.
for (const issue of (await recognizer.diagnostics()).issues) console.warn(issue);

const result = await recognizer.recognize(
  'air india 123 climb to flight level 260, speed 300 knots'
);

// One reply per aircraft, however many instructions it was given.
for (const reply of result.readbacks) speak(reply.spoken);

// Act only on `isActionable`. A `disabled` command was understood and gets a
// reply, but this deployment does not permit it — it must not execute.
for (const command of result.commands) {
  if (command.isActionable) apply(command.code, command.slots);
}

// Never silent about what it could not place.
for (const leftover of result.unrecognized) console.warn('not understood:', leftover);

recognizer.dispose();   // e.g. on unmount
```

## API

### `parse(command: string): Promise<ParserResult>`

Parses `command` against the built-in commands and resolves with the structured result.
Rejects on empty input or on non-iOS platforms.

### `Recognizer`

Recognises transcripts against a phraseology payload. Owns native state, so it has a
lifetime — dispose it.

| | |
|---|---|
| `Recognizer.create(templatesJson)` | Decodes the payload; rejects with the decoder's reason if it cannot. |
| `recognize(transcript)` | One transmission → `RecognitionResult`. An unrecognised transcript is not an error. |
| `diagnostics()` | Payload problems found at decode time, plus template counts. |
| `dispose()` | Releases the native payload. Safe to call twice. |
| `isDisposed` | |

Types are in [`src/types.ts`](src/types.ts). Note that the recognition types have almost no
optional fields: the Swift wire layer emits no nulls and omits no keys, so an absent string is
`''` and an absent number is `0` beside a `has…` flag.

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
