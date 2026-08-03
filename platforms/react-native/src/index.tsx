import { NativeModules, Platform } from 'react-native';
import type { ParserResult } from './types';

export * from './types';
export { Recognizer } from './recognizer';

const LINKING_ERROR =
  `The package '@ishant89/atc-parser-kit' doesn't seem to be linked. Make sure:\n\n` +
  '- You rebuilt the app after installing the package\n' +
  "- You ran `pod install` in the ios/ directory\n" +
  '- You are not using Expo Go (this package has native iOS code)\n';

const ATCParserModule = NativeModules.ATCParserModule
  ? NativeModules.ATCParserModule
  : new Proxy(
      {},
      {
        get() {
          throw new Error(LINKING_ERROR);
        },
      }
    );

/**
 * Parse an ATC voice-command transcript into a structured result.
 *
 * The parsing logic runs natively in Swift (ATCParserKit) — this is a thin
 * wrapper that returns the parsed JSON as a typed object.
 *
 * iOS only. On other platforms this rejects.
 */
export async function parse(command: string): Promise<ParserResult> {
  if (Platform.OS !== 'ios') {
    throw new Error('@ishant89/atc-parser-kit currently supports iOS only.');
  }
  const json: string = await ATCParserModule.parse(command);
  return JSON.parse(json) as ParserResult;
}

import { Recognizer } from './recognizer';

export default { parse, Recognizer };
