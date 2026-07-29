# Contributing to ATCParserKit

Thanks for your interest! ATCParserKit keeps its parsing logic in **one place —
the Swift core** (`Sources/ATCParserKit`). Every platform wrapper (React Native,
Unity) is a thin bridge over that core. Please preserve that invariant: **no
parsing logic in JavaScript or C#.**

## Repository layout

| Path | What |
|---|---|
| `Sources/ATCParserKit` | The parser core (public API + internal implementation) |
| `Sources/ATCParserFFI` | C ABI (`@_cdecl`) over the core, for Unity |
| `Tests/ATCParserKitTests` | Core tests + JSON wire-contract tests |
| `platforms/react-native` | `@ishant89/atc-parser-kit` (RCT module + TS wrapper) |
| `platforms/unity` | `com.ishantve.atcparserkit` (C# wrapper + xcframework) |
| `scripts/` | `build-xcframework.sh`, `release.sh` |

## Development

```sh
swift build          # build core + FFI
swift test           # run the suite
```

React Native wrapper:
```sh
cd platforms/react-native && npm install && npm run typecheck
```

Unity plugin binary:
```sh
scripts/build-xcframework.sh
```

## Changing the JSON contract

`ParserResult` / `ParsedCommand` / `CommandType` **are the public contract** for
the RN and Unity edges. If you change a field name or shape:

1. Update the Swift models, the TS types (`platforms/react-native/src/types.ts`),
   and the C# models (`platforms/unity/Runtime/Parser.cs`) together.
2. Add/adjust the JSON snapshot test.
3. Treat it as a **major** version bump (JS/C# decoders are string-keyed).

## Pull requests

- Keep the public API minimal; hide new implementation as `internal`.
- Add tests for new parse behaviour.
- CI (`.github/workflows/ci.yml`) must be green: Swift build/test, podspec lint,
  xcframework build, RN typecheck.

## Releasing (maintainers)

```sh
scripts/release.sh 1.2.0
git push origin main && git push origin 1.2.0
```

The tag triggers `release.yml`, which publishes CocoaPods + npm and creates a
GitHub Release with the xcframework. Requires `COCOAPODS_TRUNK_TOKEN` and
`NPM_TOKEN` repository secrets.
