//
//  Recognizer.cs
//  ATCParserKit — Unity iOS plugin
//
//  C# wrapper over the native template-driven recognizer.
//
//  Unlike Parser.Parse, this holds native state: the phraseology payload is decoded once and
//  reused for every transmission, so a Recognizer owns a native handle and must be disposed.
//  It implements IDisposable — use `using`, or call Dispose() when the scene tears down.
//  Leaking one leaks the decoded payload for the life of the process.
//
//  All recognition logic runs in Swift. Nothing here interprets phraseology; it marshals a
//  transcript in and JSON out.
//

using System;
using System.Runtime.InteropServices;
using UnityEngine;

namespace ATCParserKit
{
    /// <summary>One value pulled from the transcript.</summary>
    [Serializable]
    public class RecognizedSlot
    {
        /// <summary>Placeholder name as written in the template — "LEVEL", "THREE DIGITS".</summary>
        public string name;
        /// <summary>Resolved slot kind — "flightLevel", "runway", "fix", "freeText"…</summary>
        public string kind;
        /// <summary>Text form of the value, for every kind: "260", "27L", "PJ", "121.5".</summary>
        public string value;
        /// <summary>Which case produced <see cref="value"/>: "integer", "runway", "fix", "frequency", "text".</summary>
        public string valueKind;
        /// <summary>Numeric value when <see cref="hasIntValue"/>; otherwise 0.</summary>
        public int intValue;
        /// <summary>Check this rather than <c>intValue != 0</c> — a heading of zero is a real heading.</summary>
        public bool hasIntValue;
        /// <summary>Transcript tokens this slot claimed. Useful when diagnosing a mis-parse.</summary>
        public string[] tokens;
        /// <summary>False when the slot did not parse, or parsed outside the phraseology's limits.</summary>
        public bool isValid;
        /// <summary>True when the value should come from aircraft state, not speech.</summary>
        public bool isStateDerived;
    }

    /// <summary>One recognised instruction.</summary>
    [Serializable]
    public class RecognizedCommand
    {
        /// <summary>Empty when no callsign was spoken and none could be carried forward.</summary>
        public string callsign;
        /// <summary>Payload category key. A presentational grouping — do not switch behaviour on it.</summary>
        public string category;
        /// <summary>Stable template identifier. This is the key to act on.</summary>
        public string code;
        /// <summary>Empty when the payload shipped no code, in which case <see cref="code"/> is synthesised.</summary>
        public string backendCode;

        /// <summary>"ok", "disabled" or "invalidValue".</summary>
        public string outcome;
        /// <summary>True only when <see cref="outcome"/> is "ok". The one condition for acting.</summary>
        public bool isActionable;
        /// <summary>Whether this deployment permits the instruction at all.</summary>
        public bool isEnabled;
        /// <summary>The offending slot when the outcome is "invalidValue"; otherwise empty.</summary>
        public string invalidSlot;

        /// <summary>
        /// What the pilot says back, ready for a synthesiser. Already the refusal for a disabled
        /// instruction, so it can be spoken unconditionally — <see cref="outcome"/> decides only
        /// whether to act.
        /// </summary>
        public string readback;
        /// <summary>
        /// The reply when a confirmation's honest answer is "negative". Empty when the template
        /// has no such branch. Speaking <see cref="readback"/> where this applies makes an
        /// aircraft answer "affirm" to a question whose true answer is "negative".
        /// </summary>
        public string readbackAlternate;
        /// <summary>The report the pilot owes later, once a condition is met. Empty when none.</summary>
        public string readbackDeferred;
        /// <summary>Slots still unfilled in <see cref="readback"/> — do not speak it while non-empty.</summary>
        public string[] unresolvedSlots;

        /// <summary>Values from the transcript, in template order. Repeated placeholders repeat.</summary>
        public RecognizedSlot[] slots;
        /// <summary>The transcript text this command was recognised from.</summary>
        public string matchedText;
        /// <summary>Templates that matched equally well — the payload's wording cannot separate them.</summary>
        public string[] tiedWith;
        public double score;
        public double coverage;
    }

    /// <summary>One spoken reply, for one aircraft.</summary>
    [Serializable]
    public class ComposedReadback
    {
        /// <summary>Empty when the transmission named no aircraft.</summary>
        public string callsign;
        public string spoken;
    }

    /// <summary>Everything recognised in one transmission.</summary>
    [Serializable]
    public class RecognitionResult
    {
        /// <summary>The whole transcript after normalisation.</summary>
        public string normalized;
        /// <summary>Instructions in the order they were spoken.</summary>
        public RecognizedCommand[] commands;
        /// <summary>
        /// Speech no template accounted for. Report it — silence about it looks to a trainee
        /// like the instruction was accepted.
        /// </summary>
        public string[] unrecognized;
        /// <summary>
        /// One reply per aircraft, already grouped: a pilot given three instructions answers
        /// once. Grouping happens in Swift so it is not reimplemented here.
        /// </summary>
        public ComposedReadback[] readbacks;
    }

    /// <summary>Problems found in the payload when it was decoded.</summary>
    [Serializable]
    public class PayloadDiagnostics
    {
        /// <summary>One line per problem. Empty when the payload is clean.</summary>
        public string[] issues;
        public int templateCount;
        public int enabledCount;
    }

    /// <summary>
    /// Recognises transcripts against your own ICAO phraseology payload.
    /// iOS device/simulator only. Owns native state — dispose it.
    /// </summary>
    /// <example>
    /// <code>
    /// using (var recognizer = Recognizer.Create(payloadJson))
    /// {
    ///     foreach (var issue in recognizer.Diagnostics().issues) Debug.LogWarning(issue);
    ///
    ///     var result = recognizer.Recognize("air india 123 climb to flight level 260");
    ///     foreach (var reply in result.readbacks) Speak(reply.spoken);
    ///     foreach (var command in result.commands)
    ///         if (command.isActionable) Apply(command);
    /// }
    /// </code>
    /// </example>
    public sealed class Recognizer : IDisposable
    {
#if UNITY_IOS && !UNITY_EDITOR
        [DllImport("__Internal")]
        private static extern IntPtr atc_recognizer_create(string templatesJson, out IntPtr errorJson);

        [DllImport("__Internal")]
        private static extern IntPtr atc_recognizer_recognize(IntPtr handle, string transcript);

        [DllImport("__Internal")]
        private static extern IntPtr atc_recognizer_diagnostics(IntPtr handle);

        [DllImport("__Internal")]
        private static extern void atc_recognizer_release(IntPtr handle);

        [DllImport("__Internal")]
        private static extern void atc_parser_free(IntPtr pointer);
#endif

        private IntPtr handle;

        private Recognizer(IntPtr handle)
        {
            this.handle = handle;
        }

        /// <summary>
        /// Decode a phraseology payload and build a recognizer. Keep the instance and reuse it;
        /// decoding is the expensive part, and the diagnostics only exist at decode time.
        /// </summary>
        /// <param name="templatesJson">The phraseology payload, as served by your backend.</param>
        /// <exception cref="ArgumentException">The payload could not be decoded — the message says why.</exception>
        /// <exception cref="NotSupportedException">Not an iOS device/simulator build.</exception>
        public static Recognizer Create(string templatesJson)
        {
#if UNITY_IOS && !UNITY_EDITOR
            IntPtr error;
            IntPtr created = atc_recognizer_create(templatesJson, out error);
            if (created == IntPtr.Zero)
            {
                // The native side says why rather than just failing, because "your payload is
                // malformed" and "you passed null" need different fixes.
                string detail = "unknown error";
                if (error != IntPtr.Zero)
                {
                    detail = Marshal.PtrToStringAnsi(error);
                    atc_parser_free(error);
                }
                throw new ArgumentException("ATCParserKit could not decode the payload: " + detail);
            }
            return new Recognizer(created);
#else
            throw new NotSupportedException(
                "ATCParserKit runs natively on iOS device/simulator builds only.");
#endif
        }

        /// <summary>
        /// Recognise one transmission. Several instructions and several aircraft may appear in it.
        /// An unrecognised transcript is not an error: the result simply has no commands and the
        /// text under <see cref="RecognitionResult.unrecognized"/>.
        /// </summary>
        public RecognitionResult Recognize(string transcript)
        {
#if UNITY_IOS && !UNITY_EDITOR
            ThrowIfDisposed();
            IntPtr pointer = atc_recognizer_recognize(handle, transcript);
            if (pointer == IntPtr.Zero) { return null; }
            string json = Marshal.PtrToStringAnsi(pointer);
            atc_parser_free(pointer);
            return JsonUtility.FromJson<RecognitionResult>(json);
#else
            throw new NotSupportedException(
                "ATCParserKit runs natively on iOS device/simulator builds only.");
#endif
        }

        /// <summary>
        /// Problems found in the payload when it was decoded, plus the template counts.
        /// Worth logging at startup: a broken template otherwise fails silently, as an
        /// instruction that never matches.
        /// </summary>
        public PayloadDiagnostics Diagnostics()
        {
#if UNITY_IOS && !UNITY_EDITOR
            ThrowIfDisposed();
            IntPtr pointer = atc_recognizer_diagnostics(handle);
            if (pointer == IntPtr.Zero) { return null; }
            string json = Marshal.PtrToStringAnsi(pointer);
            atc_parser_free(pointer);
            return JsonUtility.FromJson<PayloadDiagnostics>(json);
#else
            throw new NotSupportedException(
                "ATCParserKit runs natively on iOS device/simulator builds only.");
#endif
        }

        /// <summary>Release the native payload. Safe to call more than once.</summary>
        public void Dispose()
        {
#if UNITY_IOS && !UNITY_EDITOR
            if (handle != IntPtr.Zero)
            {
                atc_recognizer_release(handle);
                handle = IntPtr.Zero;   // so a second Dispose, or the finalizer, is a no-op
            }
            GC.SuppressFinalize(this);
#endif
        }

        /// <summary>
        /// Backstop for a caller that forgets to dispose. It is a backstop, not the plan: the
        /// finalizer runs on the GC thread at an unpredictable time, and until it does the
        /// decoded payload stays resident.
        /// </summary>
        ~Recognizer()
        {
            Dispose();
        }

        private void ThrowIfDisposed()
        {
            if (handle == IntPtr.Zero)
            {
                throw new ObjectDisposedException(nameof(Recognizer));
            }
        }
    }
}
