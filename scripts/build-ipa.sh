#!/usr/bin/env bash
# Builds an unsigned AniWorld.ipa. Requires macOS + Xcode + xcodegen (brew install xcodegen).
# Used by .github/workflows/build.yml and runnable locally on a Mac.
#
# Env:
#   VERSION   optional marketing version (e.g. 1.2.3) -> CFBundleShortVersionString
#   BUILD_NR  optional build number                   -> CFBundleVersion
#   OUT_DIR   output directory (default: ./build)
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"
OUT_DIR="${OUT_DIR:-$ROOT/build}"
DERIVED="$OUT_DIR/DerivedData"
SPM_DIR="$OUT_DIR/SourcePackages"
mkdir -p "$OUT_DIR"

EXTRA=()
[[ -n "${VERSION:-}"  ]] && EXTRA+=("MARKETING_VERSION=$VERSION")
[[ -n "${BUILD_NR:-}" ]] && EXTRA+=("CURRENT_PROJECT_VERSION=$BUILD_NR")

echo "==> xcodegen generate"
xcodegen generate

echo "==> resolve packages"
xcodebuild -resolvePackageDependencies \
  -project AniworldIOS.xcodeproj -scheme AniworldIOS \
  -clonedSourcePackagesDirPath "$SPM_DIR"

echo "==> xcodebuild (Release, unsigned)"
if command -v xcbeautify >/dev/null 2>&1; then
  PRETTY=(xcbeautify --renderer github-actions)
  # fall back to the default renderer if the flag is unsupported
  xcbeautify --help 2>&1 | grep -q -- '--renderer' || PRETTY=(xcbeautify)
else
  PRETTY=(cat)
fi
# pipefail makes the step fail when xcodebuild fails, even though output goes through a pipe.
xcodebuild \
  -project AniworldIOS.xcodeproj -scheme AniworldIOS \
  -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' \
  -derivedDataPath "$DERIVED" \
  -clonedSourcePackagesDirPath "$SPM_DIR" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
  ${EXTRA[@]+"${EXTRA[@]}"} \
  build 2>&1 | "${PRETTY[@]}"

APP="$DERIVED/Build/Products/Release-iphoneos/AniWorld.app"
[[ -d "$APP" ]] || { echo "error: $APP not found" >&2; exit 1; }

# Ad-hoc signature with entitlements: the build itself stays unsigned, but the App Group
# (shared data for the widgets) must be embedded so sideloading tools (AltStore, SideStore,
# Sideloadly, Impactor) carry it over when they re-sign with the user's own certificate.
# Order matters: nested code first (frameworks, widget extension), the app last.
echo "==> ad-hoc sign with entitlements"
if [[ -d "$APP/Frameworks" ]]; then
  find "$APP/Frameworks" -maxdepth 1 \( -name '*.framework' -o -name '*.dylib' \) -print0 |
    while IFS= read -r -d '' fw; do
      codesign --force --sign - --timestamp=none "$fw"
    done
fi
WIDGET="$APP/PlugIns/AniWorldWidgets.appex"
[[ -d "$WIDGET" ]] || { echo "error: $WIDGET not found" >&2; exit 1; }
codesign --force --sign - --timestamp=none \
  --entitlements "$ROOT/Widgets/AniWorldWidgets.entitlements" "$WIDGET"
codesign --force --sign - --timestamp=none \
  --entitlements "$ROOT/App/AniWorld.entitlements" "$APP"
# Read the entitlements as XML (":-") into a variable first: piping into `grep -q` can end in
# SIGPIPE, which pipefail would turn into a spurious failure.
for bundle in "$WIDGET" "$APP"; do
  ents="$(codesign -d --entitlements :- "$bundle" 2>/dev/null || true)"
  if [[ "$ents" != *"<string>group.com.aniworldios.app</string>"* ]]; then
    echo "error: App Group missing in signature of $bundle" >&2
    exit 1
  fi
done

echo "==> package IPA"
STAGE="$OUT_DIR/ipa-stage"
rm -rf "$STAGE" "$OUT_DIR/AniWorld.ipa"
mkdir -p "$STAGE/Payload"
cp -R "$APP" "$STAGE/Payload/AniWorld.app"
( cd "$STAGE" && zip -qry "$OUT_DIR/AniWorld.ipa" Payload )
rm -rf "$STAGE"

ls -lh "$OUT_DIR/AniWorld.ipa"
echo "IPA: $OUT_DIR/AniWorld.ipa"
