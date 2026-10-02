#!/usr/bin/env bash
# Builds a Release ToastNote.app and packs it into build/ToastNote-<version>.dmg.
#
# Environment (all optional):
#   VERSION              marketing version, e.g. v1.2.0 or 1.2.0 (default: MARKETING_VERSION from project.yml)
#   BUILD_NUMBER         CFBundleVersion (default: 1)
#   CODE_SIGN_IDENTITY   e.g. "Developer ID Application: Name (TEAMID)"; default is an ad-hoc signature
#   GITHUB_REPOSITORY    owner/repo for the Sparkle feed URL (set automatically in GitHub Actions)
#   SPARKLE_PUBLIC_KEY   EdDSA public key from Sparkle's generate_keys; empty builds without updates
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${VERSION:-$(sed -n 's/.*MARKETING_VERSION: "\(.*\)".*/\1/p' project.yml | head -1)}"
VERSION="${VERSION#v}"
IDENTITY="${CODE_SIGN_IDENTITY:--}"
DERIVED="build/Release"
APP="$DERIVED/Build/Products/Release/ToastNote.app"
DMG="build/ToastNote-$VERSION.dmg"

settings=("MARKETING_VERSION=$VERSION" "CURRENT_PROJECT_VERSION=${BUILD_NUMBER:-1}" "CODE_SIGN_IDENTITY=$IDENTITY")
[ -n "${GITHUB_REPOSITORY:-}" ] && settings+=("GITHUB_REPOSITORY=$GITHUB_REPOSITORY")
[ -n "${SPARKLE_PUBLIC_KEY:-}" ] && settings+=("SPARKLE_PUBLIC_KEY=$SPARKLE_PUBLIC_KEY")
# An ad-hoc build must not demand a development team.
[ "$IDENTITY" = "-" ] && settings+=("CODE_SIGN_STYLE=Manual" "DEVELOPMENT_TEAM=")

echo "==> Generating project"
xcodegen generate

echo "==> Building ToastNote $VERSION (Release, signing identity: $IDENTITY)"
xcodebuild -project ToastNote.xcodeproj -scheme ToastNote -configuration Release \
  -destination 'platform=macOS' -derivedDataPath "$DERIVED" "${settings[@]}" build 2>&1 | tail -5

[ -d "$APP" ] || { echo "error: $APP was not built" >&2; exit 1; }

if [ "$IDENTITY" = "-" ]; then
  # An ad-hoc app has no team ID, so the hardened runtime's library validation refuses to load the embedded
  # frameworks (Sparkle). Sign everything ad hoc and opt out of library validation for this build only;
  # Developer ID builds are signed with a team and keep it on.
  echo "==> Re-signing ad hoc (app and embedded frameworks, library validation off)"
  ENTITLEMENTS="$(mktemp -t toastnote-entitlements).plist"
  cp App/ToastNote.entitlements "$ENTITLEMENTS"
  /usr/libexec/PlistBuddy -c "Add :com.apple.security.cs.disable-library-validation bool true" "$ENTITLEMENTS"
  codesign --force --deep --options runtime --entitlements "$ENTITLEMENTS" --sign - "$APP"
  rm -f "$ENTITLEMENTS"
fi

echo "==> Creating $DMG"
STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
rm -f "$DMG"
hdiutil create -volname "ToastNote" -srcfolder "$STAGING" -ov -format UDZO "$DMG" >/dev/null

echo "==> Sizes (budget: DMG < 15 MB, app < 30 MB)"
ls -lh "$DMG" | awk '{print "DMG:", $5}'
du -sh "$APP" | awk '{print "App:", $1}'
echo "$DMG"
