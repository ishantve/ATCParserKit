// Minimal ambient declarations of the React Native surface this package uses.
// Used ONLY for type-checking the wrapper in isolation (CI + local), so we don't
// have to install the full react-native toolchain. NOT published — `files` in
// package.json ships only src/ios/podspec/README, so consumers resolve the real
// react-native types from their own project.

declare module 'react-native' {
  export const NativeModules: { [name: string]: any };
  export const Platform: { OS: 'ios' | 'android' | 'macos' | 'windows' | 'web' | string };
}
