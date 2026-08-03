// Wire types mirroring ATCParserKit's Swift Codable models. Keep in lockstep
// with Sources/ATCParserKit/Models/*.swift — this is the JSON contract.

export type CommandType =
  | 'heading'
  | 'headingTurn'
  | 'relativeTurn'
  | 'presentHeading'
  | 'flightLevel'
  | 'altitudeBlock'
  | 'speed'
  | 'minSpeed'
  | 'maxSpeed'
  | 'hold'
  | 'interceptLocalizer';

export type TurnDirection = 'left' | 'right';

/** One parsed instruction. Only the fields relevant to `type` are present. */
export interface ParsedCommand {
  type: CommandType;
  /** heading, headingTurn */
  heading?: number;
  /** relativeTurn */
  degrees?: number;
  /** headingTurn, relativeTurn */
  direction?: TurnDirection;
  /** flightLevel */
  flightLevel?: number;
  /** altitudeBlock */
  altitudeLow?: number;
  /** altitudeBlock */
  altitudeHigh?: number;
  /** speed, minSpeed, maxSpeed */
  speed?: number;
  /** hold */
  fix?: string;
  /** interceptLocalizer */
  runway?: string;
}

/** The full parse result: callsign (if any) + commands + normalized transcript. */
export interface ParserResult {
  callsign?: string;
  commands: ParsedCommand[];
  normalized: string;
}

// ---------------------------------------------------------------------------
// Template-driven recognition
//
// Mirrors Sources/ATCParserKit/Wire/RecognitionWire.swift. That file is the
// contract; keep these in lockstep with it.
//
// Note the absence of `?` on almost everything: the Swift wire layer emits no
// nulls and omits no keys, so an absent string is `''` and an absent number is
// `0` beside a `has…` flag. That is a constraint Unity's JsonUtility imposes,
// and TypeScript gets the benefit — no optional-chaining on every field.
// ---------------------------------------------------------------------------

/**
 * Whether an instruction may be acted on.
 *
 * Three values, not two. `disabled` means the payload defined the instruction
 * but this deployment does not permit it: it was understood, it gets a reply,
 * and it must not execute. A boolean loses exactly that case.
 */
export type Outcome = 'ok' | 'disabled' | 'invalidValue';

/** Which `SlotValue` case produced a slot's text. Empty when it did not parse. */
export type SlotValueKind = '' | 'integer' | 'runway' | 'fix' | 'frequency' | 'text';

/** One value pulled from the transcript. */
export interface RecognizedSlot {
  /** Placeholder name as written in the template — 'LEVEL', 'THREE DIGITS'. */
  name: string;
  /** Resolved slot kind — 'flightLevel', 'runway', 'fix', 'freeText'… */
  kind: string;
  /** Text form of the value, for every kind: '260', '27L', 'PJ', '121.5'. */
  value: string;
  valueKind: SlotValueKind;
  /** Numeric value when `hasIntValue`; otherwise 0. */
  intValue: number;
  /** Check this, not `intValue !== 0` — a heading of zero is a real heading. */
  hasIntValue: boolean;
  /** Transcript tokens this slot claimed. Useful when diagnosing a mis-parse. */
  tokens: string[];
  /** False when the slot did not parse, or parsed outside the phraseology's limits. */
  isValid: boolean;
  /** True when the value should come from aircraft state rather than speech. */
  isStateDerived: boolean;
}

/** One recognised instruction. */
export interface RecognizedCommand {
  /** Empty when no callsign was spoken and none could be carried forward. */
  callsign: string;
  /** Payload category key. Presentational grouping — do not switch behaviour on it. */
  category: string;
  /** Stable template identifier. This is the key to act on. */
  code: string;
  /** Empty when the payload shipped no code, in which case `code` is synthesised. */
  backendCode: string;

  outcome: Outcome;
  /** True only when `outcome === 'ok'`. The one condition for acting. */
  isActionable: boolean;
  /** Whether this deployment permits the instruction at all. */
  isEnabled: boolean;
  /** The offending slot when `outcome === 'invalidValue'`; otherwise empty. */
  invalidSlot: string;

  /**
   * What the pilot says back, ready for a synthesiser. Already the refusal for a
   * disabled instruction, so it can be spoken unconditionally — `outcome`
   * decides only whether to act.
   */
  readback: string;
  /**
   * The reply when a confirmation's honest answer is 'negative' (`If not:` in
   * the template). Empty when the template has no such branch. Speaking
   * `readback` where this applies makes an aircraft answer 'affirm' to a
   * question whose true answer is 'negative'.
   */
  readbackAlternate: string;
  /** The report the pilot owes later, once a condition is met. Empty when none. */
  readbackDeferred: string;
  /** Slots still unfilled in `readback` — do not speak it while this is non-empty. */
  unresolvedSlots: string[];

  /** Values from the transcript, in template order. Repeated placeholders repeat. */
  slots: RecognizedSlot[];
  /** The transcript text this command was recognised from. */
  matchedText: string;
  /** Templates that matched equally well — the payload's wording cannot separate them. */
  tiedWith: string[];
  score: number;
  coverage: number;
}

/** One spoken reply, for one aircraft. */
export interface ComposedReadback {
  /** Empty when the transmission named no aircraft. */
  callsign: string;
  spoken: string;
}

/** Everything recognised in one transmission. */
export interface RecognitionResult {
  /** The whole transcript after normalisation. */
  normalized: string;
  /** Instructions in the order they were spoken. */
  commands: RecognizedCommand[];
  /**
   * Speech no template accounted for. Report it — silence about it looks to a
   * trainee like the instruction was accepted.
   */
  unrecognized: string[];
  /**
   * One reply per aircraft, already grouped: a pilot given three instructions
   * answers once. Grouped in Swift so it is not reimplemented here.
   */
  readbacks: ComposedReadback[];
}

/** Problems found in the payload when it was decoded. */
export interface PayloadDiagnostics {
  /** One line per problem. Empty when the payload is clean. */
  issues: string[];
  templateCount: number;
  enabledCount: number;
}
