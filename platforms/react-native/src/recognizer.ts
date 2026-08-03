import { NativeModules, Platform } from 'react-native';
import type { PayloadDiagnostics, RecognitionResult } from './types';

const LINKING_ERROR =
  `The package '@ishant89/atc-parser-kit' doesn't seem to be linked. Make sure:\n\n` +
  '- You rebuilt the app after installing the package\n' +
  '- You ran `pod install` in the ios/ directory\n' +
  '- You are not using Expo Go (this package has native iOS code)\n';

const ATCRecognizerModule = NativeModules.ATCRecognizerModule
  ? NativeModules.ATCRecognizerModule
  : new Proxy(
      {},
      {
        get() {
          throw new Error(LINKING_ERROR);
        },
      }
    );

/**
 * Recognises transcripts against your own ICAO phraseology payload.
 *
 * Unlike `parse`, this owns native state: the payload is decoded once and reused for every
 * transmission. So it is a class with a lifetime rather than a function — create one per
 * payload, keep it, and `dispose()` it when you are done (a component's unmount, or the end of
 * a session). Recreating one per utterance re-decodes the whole payload and throws away the
 * diagnostics.
 *
 * iOS only.
 *
 * @example
 * ```ts
 * const recognizer = await Recognizer.create(payloadJson);
 * for (const issue of (await recognizer.diagnostics()).issues) console.warn(issue);
 *
 * const result = await recognizer.recognize('air india 123 climb to flight level 260');
 * for (const reply of result.readbacks) speak(reply.spoken);
 * for (const command of result.commands) if (command.isActionable) apply(command);
 *
 * recognizer.dispose();
 * ```
 */
export class Recognizer {
  private handle: number | null;

  private constructor(handle: number) {
    this.handle = handle;
  }

  /**
   * Decode a phraseology payload and build a recognizer.
   *
   * @param templatesJson The payload as served by your backend, as a JSON string.
   * @throws If the payload cannot be decoded — the message carries the decoder's own reason,
   *         since "malformed JSON" and "wrong type in a field" need different fixes.
   */
  static async create(templatesJson: string): Promise<Recognizer> {
    if (Platform.OS !== 'ios') {
      throw new Error('@ishant89/atc-parser-kit currently supports iOS only.');
    }
    const handle: number = await ATCRecognizerModule.createRecognizer(templatesJson);
    return new Recognizer(handle);
  }

  /**
   * Recognise one transmission. Several instructions and several aircraft may appear in it.
   *
   * An unrecognised transcript is not an error: the result simply has no commands and the text
   * under `unrecognized`.
   */
  async recognize(transcript: string): Promise<RecognitionResult> {
    const json: string = await ATCRecognizerModule.recognize(
      this.requireHandle(),
      transcript
    );
    return JSON.parse(json) as RecognitionResult;
  }

  /**
   * Problems found in the payload when it was decoded, plus the template counts.
   *
   * Worth logging at startup: a broken template otherwise fails silently, as an instruction
   * that never matches.
   */
  async diagnostics(): Promise<PayloadDiagnostics> {
    const json: string = await ATCRecognizerModule.diagnostics(this.requireHandle());
    return JSON.parse(json) as PayloadDiagnostics;
  }

  /**
   * Release the native payload. Safe to call more than once; calling `recognize` afterwards
   * rejects rather than reaching a freed payload.
   */
  dispose(): void {
    if (this.handle === null) {
      return;
    }
    const handle = this.handle;
    this.handle = null;
    // Fire and forget: the native side treats an unknown handle as a no-op, so nothing here
    // needs to be awaited on an unmount path.
    void ATCRecognizerModule.releaseRecognizer(handle);
  }

  /** True until `dispose()` is called. */
  get isDisposed(): boolean {
    return this.handle === null;
  }

  private requireHandle(): number {
    if (this.handle === null) {
      throw new Error(
        'This Recognizer has been disposed. Create a new one from the payload.'
      );
    }
    return this.handle;
  }
}
