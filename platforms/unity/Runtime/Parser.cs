//
//  Parser.cs
//  ATCParserKit — Unity iOS plugin
//
//  C# wrapper over the native ATCParserFFI C interface. The parsing logic runs
//  natively in Swift; this marshals the transcript in and the JSON result out.
//

using System;
using System.Runtime.InteropServices;
using UnityEngine;

namespace ATCParserKit
{
    /// <summary>One parsed instruction. Only the fields relevant to <see cref="type"/> are set.</summary>
    [Serializable]
    public class ParsedCommand
    {
        public string type;          // heading, headingTurn, relativeTurn, presentHeading,
                                     // flightLevel, altitudeBlock, speed, minSpeed, maxSpeed,
                                     // hold, interceptLocalizer
        public double heading;       // heading, headingTurn
        public double degrees;       // relativeTurn
        public string direction;     // "left" / "right" — headingTurn, relativeTurn
        public int flightLevel;      // flightLevel
        public int altitudeLow;      // altitudeBlock
        public int altitudeHigh;     // altitudeBlock
        public double speed;         // speed, minSpeed, maxSpeed
        public string fix;           // hold
        public string runway;        // interceptLocalizer
    }

    /// <summary>The full parse result: callsign (if any) + commands + normalized transcript.</summary>
    [Serializable]
    public class ParserResult
    {
        public string callsign;
        public ParsedCommand[] commands;
        public string normalized;
    }

    /// <summary>Parses ATC voice-command transcripts. iOS device/simulator only.</summary>
    public static class Parser
    {
#if UNITY_IOS && !UNITY_EDITOR
        [DllImport("__Internal")]
        private static extern IntPtr atc_parser_parse(string command);

        [DllImport("__Internal")]
        private static extern void atc_parser_free(IntPtr pointer);

        [DllImport("__Internal")]
        private static extern IntPtr atc_display_text(string transcript);
#endif

        /// <summary>
        /// Parse <paramref name="command"/> into a structured result.
        /// Runs the shared Swift parser natively. Throws on non-iOS targets.
        /// </summary>
        public static ParserResult Parse(string command)
        {
#if UNITY_IOS && !UNITY_EDITOR
            IntPtr pointer = atc_parser_parse(command);
            if (pointer == IntPtr.Zero) { return null; }
            string json = Marshal.PtrToStringAnsi(pointer);
            atc_parser_free(pointer);
            return JsonUtility.FromJson<ParserResult>(json);
#else
            throw new NotSupportedException(
                "ATCParserKit runs natively on iOS device/simulator builds only.");
#endif
        }

        /// <summary>
        /// Clean a raw transcript for display: recogniser-quirk fixups + ICAO
        /// spellings, uppercased (see TranscriptCleaner). Throws on non-iOS targets.
        /// </summary>
        public static string DisplayText(string transcript)
        {
#if UNITY_IOS && !UNITY_EDITOR
            IntPtr pointer = atc_display_text(transcript);
            if (pointer == IntPtr.Zero) { return ""; }
            string text = Marshal.PtrToStringAnsi(pointer);
            atc_parser_free(pointer);
            return text;
#else
            throw new NotSupportedException(
                "ATCParserKit runs natively on iOS device/simulator builds only.");
#endif
        }
    }
}
