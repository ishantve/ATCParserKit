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
    "com.ishantve.atcparserkit": "https://github.com/ishantve/ATCParserKit.git?path=platforms/unity#1.1.0"
  }
}
```

…or **Window → Package Manager → + → Add package from git URL**:

```
https://github.com/ishantve/ATCParserKit.git?path=platforms/unity#1.1.0
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

## How it works

```
C# Parser.Parse(cmd)
  → atc_parser_parse(cmd)     [DllImport("__Internal")]  (C ABI, ATCParserFFI)
  → ATCParser().parseToJSON   (Swift, ATCParserKit)
  → JSON C string → JsonUtility.FromJson<ParserResult>
  → atc_parser_free(ptr)      (no leak)
```

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
