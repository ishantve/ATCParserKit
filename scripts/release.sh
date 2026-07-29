#!/usr/bin/env bash
#
# release.sh <version>
#
# Stamps one version across every artifact (SPM tag, CocoaPods podspec, npm RN
# package, Unity UPM package + install docs), commits, and tags. Push the tag to
# trigger .github/workflows/release.yml, which publishes each channel.
#
# Usage:  scripts/release.sh 1.1.0
#
set -euo pipefail

VERSION="${1:-}"
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "usage: scripts/release.sh <major.minor.patch>" >&2
  exit 1
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "▸ Stamping version $VERSION"

# CocoaPods (core)
sed -i '' "s/s.version[[:space:]]*=.*/s.version          = '$VERSION'/" ATCParserKit.podspec

# npm (React Native)
node -e "const f='platforms/react-native/package.json',p=require('./'+f);p.version='$VERSION';require('fs').writeFileSync(f,JSON.stringify(p,null,2)+'\n')"

# Unity UPM
node -e "const f='platforms/unity/package.json',p=require('./'+f);p.version='$VERSION';require('fs').writeFileSync(f,JSON.stringify(p,null,2)+'\n')"

# Unity install doc pin
sed -i '' -E "s|(path=platforms/unity#)[^ )\"']*|\1$VERSION|g" platforms/unity/README.md

echo "▸ Committing + tagging"
git add ATCParserKit.podspec platforms/react-native/package.json platforms/unity/package.json platforms/unity/README.md
git commit -m "release: $VERSION"
git tag "$VERSION"

echo "✅ Tagged $VERSION."
echo "   Push to publish:  git push origin main && git push origin $VERSION"
