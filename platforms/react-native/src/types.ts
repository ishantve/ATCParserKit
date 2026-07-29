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
