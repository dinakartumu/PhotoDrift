#!/bin/bash
#
# Builds, signs, notarizes and packages PhotoDrift for direct distribution.
#
#   Tools/release.sh                 # full run, including notarization
#   Tools/release.sh --skip-notarize # build + sign + DMG only, no Apple round trip
#
# One-time setup — stores an App Store Connect credential in your login keychain so
# this script never handles a password directly:
#
#   xcrun notarytool store-credentials PhotoDrift \
#     --apple-id "you@example.com" \
#     --team-id FU4YK33ZPJ \
#     --password "app-specific-password"
#
# Override the profile name with NOTARY_PROFILE if you called it something else.

set -euo pipefail

cd "$(dirname "$0")/.."

SCHEME="PhotoDrift"
PROJECT="PhotoDrift.xcodeproj"
TEAM_ID="FU4YK33ZPJ"
NOTARY_PROFILE="${NOTARY_PROFILE:-PhotoDrift}"
BUILD_DIR="build/release"
ARCHIVE="$BUILD_DIR/PhotoDrift.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
APP="$EXPORT_DIR/PhotoDrift.app"
STAGE="$BUILD_DIR/dmg"
# Where xcodebuild clones Swift packages for this run; Sparkle's appcast tooling ships
# inside its package artifact, so resolving here makes the tools a build product.
PACKAGES="$BUILD_DIR/packages"
GENERATE_APPCAST="$PACKAGES/artifacts/sparkle/Sparkle/bin/generate_appcast"
APPCAST="appcast.xml"
DOWNLOAD_BASE="https://github.com/dinakartumu/PhotoDrift/releases/download"
PRODUCT_PAGE="https://dinakartumu.com/photodrift"
RELEASES_PAGE="https://github.com/dinakartumu/PhotoDrift/releases"

SKIP_NOTARIZE=0
[[ "${1:-}" == "--skip-notarize" ]] && SKIP_NOTARIZE=1

step() { printf '\n\033[1m==> %s\033[0m\n' "$1"; }
fail() { printf '\033[31merror: %s\033[0m\n' "$1" >&2; exit 1; }

step "Cleaning $BUILD_DIR"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

step "Archiving"
xcodebuild archive \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath "$ARCHIVE" \
  -clonedSourcePackagesDirPath "$PACKAGES" \
  | grep -E '^\*\*|error:' || true
[[ -d "$ARCHIVE" ]] || fail "archive not produced"
[[ -x "$GENERATE_APPCAST" ]] || fail "Sparkle tools not found at $GENERATE_APPCAST"

step "Exporting with Developer ID"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportOptionsPlist Tools/ExportOptions.plist \
  -exportPath "$EXPORT_DIR" \
  | grep -E '^\*\*|error:' || true
[[ -d "$APP" ]] || fail "export did not produce $APP"

step "Verifying signature"
codesign --verify --deep --strict --verbose=2 "$APP"
# Capture once rather than piping into `grep -q`: grep exits on first match, codesign
# takes SIGPIPE, and under `set -o pipefail` that would fail an otherwise good check.
SIGNATURE=$(codesign -dv --verbose=4 "$APP" 2>&1)
grep -q 'flags=.*runtime' <<<"$SIGNATURE" \
  || fail "hardened runtime is not enabled — notarization will be rejected"
grep -q 'Authority=Developer ID Application' <<<"$SIGNATURE" \
  || fail "not signed with a Developer ID Application certificate"
printf 'Developer ID signature with hardened runtime confirmed.\n'

VERSION=$(defaults read "$PWD/$APP/Contents/Info.plist" CFBundleShortVersionString)
DMG="$BUILD_DIR/PhotoDrift-$VERSION.dmg"

step "Building $DMG"
rm -rf "$STAGE"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create \
  -volname "PhotoDrift" \
  -srcfolder "$STAGE" \
  -ov -format UDZO \
  "$DMG" >/dev/null
[[ -f "$DMG" ]] || fail "DMG not produced"

step "Signing DMG"
# Resolve the certificate by its hash: this keychain holds more than one
# "Developer ID Application" identity, and the plain name is ambiguous.
IDENTITY=$(security find-identity -v -p codesigning \
  | grep 'Developer ID Application' \
  | grep "$TEAM_ID" \
  | head -1 \
  | awk '{print $2}')
[[ -n "$IDENTITY" ]] || fail "no Developer ID Application certificate for team $TEAM_ID"
codesign --sign "$IDENTITY" --timestamp "$DMG"
codesign --verify --verbose=2 "$DMG"

if [[ "$SKIP_NOTARIZE" == "1" ]]; then
  printf '\n\033[33mSkipped notarization. %s is signed but NOT stapled —\n' "$DMG"
  printf 'Gatekeeper will still block it on other Macs.\033[0m\n'
  exit 0
fi

step "Notarizing (this waits on Apple, usually a few minutes)"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait \
  || fail "notarization failed — run 'xcrun notarytool log <id> --keychain-profile $NOTARY_PROFILE' for details"

step "Stapling"
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG" || fail "staple validation failed"

step "Verifying Gatekeeper acceptance"
spctl -a -t open --context context:primary-signature -v "$DMG"

# The EdDSA signature must cover the final bytes, so this runs after stapling. The
# existing appcast is copied alongside the DMG so generate_appcast merges rather than
# starts over; entries for archives that are no longer on disk are preserved as-is.
step "Updating $APPCAST"
APPCAST_DIR="$BUILD_DIR/appcast"
mkdir -p "$APPCAST_DIR"
cp "$DMG" "$APPCAST_DIR/"
[[ -f "$APPCAST" ]] && cp "$APPCAST" "$APPCAST_DIR/$APPCAST"
"$GENERATE_APPCAST" \
  --download-url-prefix "$DOWNLOAD_BASE/v$VERSION/" \
  --link "$PRODUCT_PAGE" \
  --full-release-notes-url "$RELEASES_PAGE" \
  --maximum-versions 5 \
  -o "$APPCAST" \
  "$APPCAST_DIR"
grep -q "PhotoDrift-$VERSION.dmg" "$APPCAST" || fail "$APPCAST does not list PhotoDrift-$VERSION.dmg"

printf '\n\033[32mDone: %s\033[0m\n' "$DMG"
printf 'Notarized and stapled. This will launch on a Mac that has never seen it before.\n'
printf 'Next: upload the DMG to the v%s GitHub release, then commit and push %s so\n' "$VERSION" "$APPCAST"
printf 'installed copies see the update.\n'
