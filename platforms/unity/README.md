# ATCParserKit — Unity (iOS)

Parse ATC voice-command transcripts in Unity on **iOS**. The parsing logic runs
natively in Swift (bundled as a static `xcframework`); C# calls it through a
minimal C interface and gets a structured result.

> **iOS only.** The plugin is an iOS `xcframework`. Calls throw
> `NotSupportedException` in the Editor and on other platforms.

## Install (UPM)

Add to your project's `Packages/manifest.json`:

```json
{
  "dependencies": {
    "com.ishantve.atcparserkit": "https://github.com/ishantve/ATCParserKit.git?path=platforms/unity#1.3.0"
  }
}
```

…or **Window → Package Manager → + → Add package from git URL**:

```
https://github.com/ishantve/ATCParserKit.git?path=platforms/unity#1.3.0
```

## Usage

```csharp
using ATCParserKit;

var result = Parser.Parse("air canada 125 climb flight level 250 turn left heading 270");

Debug.Log(result.callsign);          // "air canada 125"
foreach (var c in result.commands)
{
    switch (c.type)
    {
        case "headingTurn": Debug.Log($"heading {c.heading} {c.direction}"); break;
        case "flightLevel": Debug.Log($"FL {c.flightLevel}"); break;
    }
}
```

`ParserResult` / `ParsedCommand` mirror the JSON contract; each command carries
only the fields relevant to its `type`.

## Your own phraseology

`Parser.Parse` knows eleven built-in commands. To recognise **your own ICAO phraseology**,
give `Recognizer` your template payload.

Unlike `Parser`, a `Recognizer` owns native state — the payload is decoded once and reused —
so it implements `IDisposable`. Use `using`, or dispose it when the scene tears down; leaking
one keeps the decoded payload resident for the life of the process.

```csharp
using ATCParserKit;

using (var recognizer = Recognizer.Create(payloadJson))
{
    // Log these at startup: a broken template otherwise fails silently, as an
    // instruction that never matches.
    foreach (var issue in recognizer.Diagnostics().issues) Debug.LogWarning(issue);

    var result = recognizer.Recognize(
        "air india 123 climb to flight level 260, speed 300 knots");

    // One reply per aircraft, however many instructions it was given.
    foreach (var reply in result.readbacks) Speak(reply.spoken);

    // Act only on isActionable. A "disabled" command was understood and gets a
    // reply, but this deployment does not permit it — it must not execute.
    foreach (var command in result.commands)
    {
        if (command.isActionable) Apply(command.code, command.slots);
    }

    // Never silent about what it could not place.
    foreach (var leftover in result.unrecognized)
        Debug.LogWarning($"not understood: {leftover}");
}
```

The wire format is shaped for `JsonUtility`, which is the tightest constraint in the
project: no dictionaries, no sum types, no nullable primitives. So an absent string is `""`
and an absent number is `0` beside a `has…` flag, and a slot's value arrives as text plus a
`valueKind` — check `hasIntValue` rather than `intValue != 0`, since a heading of zero is a
real heading.

## How it works

```
C# Parser.Parse(cmd)
  → atc_parser_parse(cmd)     [DllImport("__Internal")]  (C ABI, ATCParserFFI)
  → ATCParser().parseToJSON   (Swift, ATCParserKit)
  → JSON C string → JsonUtility.FromJson<ParserResult>
  → atc_parser_free(ptr)      (no leak)

C# Recognizer.Create(payload)
  → atc_recognizer_create(payload, out error)  → opaque handle (retained in Swift)

C# recognizer.Recognize(transcript)
  → atc_recognizer_recognize(handle, transcript)
  → CommandRecognizer.recognize(_:).toJSON()   (Swift, ATCParserKit)
  → JSON C string → JsonUtility.FromJson<RecognitionResult>
  → atc_parser_free(ptr)

C# recognizer.Dispose()
  → atc_recognizer_release(handle)             (releases the decoded payload)
```

Recognition is create/use/release rather than one call because the payload has a lifetime:
decoding it per utterance would be wasteful and would throw away the diagnostics, which only
exist at decode time.

No parsing logic exists in C# — it is delegated entirely to Swift.

## Building the plugin binary

The prebuilt `Runtime/Plugins/iOS/ATCParserFFI.xcframework` ships with the
package. To rebuild it from source (device + simulator slices):

```sh
scripts/build-xcframework.sh   # from the repo root
```

## iOS build notes

- The `xcframework` is static; `[DllImport("__Internal")]` resolves the symbols
  once Unity's generated Xcode project links it into the app.
- If **Strip Engine Code** / aggressive stripping removes the symbols, add
  `atc_parser_parse` / `atc_parser_free` to a `link.xml` or reference them so
  the linker keeps them.

## License

MIT
