#!/usr/bin/env bash
# Builds Kitbag in Release and packages release/Kitbag-<version>.dmg.
# Env: SIGN_IDENTITY (default "-" = ad-hoc), NOTARIZE=1 + NOTARY_PROFILE (notarytool keychain profile),
#      ARCHS (default "arm64 x86_64").
set -euo pipefail
cd "$(dirname "$0")/.."

APP=Kitbag
PLIST=App/Resources/Info.plist
ENTITLEMENTS=App/Resources/Kitbag.entitlements
# Default: the local certificate from scripts/setup-signing.sh if it exists (keeps macOS permissions
# across rebuilds), otherwise ad-hoc.
LOCAL_ID="Kitbag Local Signing"
if [[ -z "${SIGN_IDENTITY:-}" ]]; then
  if security find-certificate -c "$LOCAL_ID" >/dev/null 2>&1; then SIGN_IDENTITY="$LOCAL_ID"; else SIGN_IDENTITY="-"; fi
fi
NOTARIZE="${NOTARIZE:-0}"
ARCHS="${ARCHS:-arm64 x86_64}"
BUILD=build
RELEASE=release

log() { printf '\033[1m==> %s\033[0m\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }
trap 'die "build failed at line $LINENO"' ERR

for tool in swift codesign hdiutil iconutil sips qlmanage /usr/libexec/PlistBuddy; do
  command -v "$tool" >/dev/null || die "missing required tool: $tool"
done
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST") || die "cannot read version from $PLIST"
DMG="$RELEASE/$APP-$VERSION.dmg"
if [[ "$NOTARIZE" == 1 ]]; then
  [[ "$SIGN_IDENTITY" != "-" && "$SIGN_IDENTITY" != "$LOCAL_ID" ]] || die "NOTARIZE=1 needs SIGN_IDENTITY (a Developer ID Application identity)"
  [[ -n "${NOTARY_PROFILE:-}" ]] || die "NOTARIZE=1 needs NOTARY_PROFILE (see 'xcrun notarytool store-credentials')"
fi

log "Cleaning old output"
rm -rf "$BUILD" "$DMG"
mkdir -p "$BUILD" "$RELEASE"

log "Building $APP $VERSION (Release, $ARCHS)"
ARCH_FLAGS=()
for a in $ARCHS; do ARCH_FLAGS+=(--arch "$a"); done
swift build -c release --scratch-path "$BUILD/swift" "${ARCH_FLAGS[@]}"
BIN="$(swift build -c release --scratch-path "$BUILD/swift" "${ARCH_FLAGS[@]}" --show-bin-path)/$APP"
[[ -f "$BIN" ]] || die "binary not found at $BIN"

log "Preparing app icon from assets/logo (originals are not modified)"
ICNS="$BUILD/AppIcon.icns"
if ls assets/logo/*.icns >/dev/null 2>&1; then
  cp assets/logo/*.icns "$ICNS"  # shortcut: assumes a single .icns
else
  SRC=""
  for f in assets/logo/kitbagLogo.png assets/logo/kitbagLogo.svg; do
    if [[ -f "$f" ]]; then SRC="$f"; break; fi
  done
  [[ -n "$SRC" ]] || die "no .icns, .png or kitbagLogo.svg in assets/logo"
  MASTER="$BUILD/icon-1024.png"
  if [[ "$SRC" == *.svg ]]; then
    swift scripts/render-svg.swift "$SRC" "$MASTER" 1024  # transparent background, unlike Quick Look
  else
    sips -z 1024 1024 "$SRC" --out "$MASTER" >/dev/null
  fi
  SET="$BUILD/AppIcon.iconset"
  mkdir -p "$SET"
  for s in 16 32 128 256 512; do
    sips -z $s $s "$MASTER" --out "$SET/icon_${s}x${s}.png" >/dev/null
    sips -z $((s * 2)) $((s * 2)) "$MASTER" --out "$SET/icon_${s}x${s}@2x.png" >/dev/null
  done
  iconutil -c icns "$SET" -o "$ICNS"
fi

# Light and dark icon artwork. The app draws the matching one on its Dock tile while running
# (a plain .icns cannot carry appearance variants).
if [[ -f assets/logo/kitbagLogo.svg ]]; then
  sed 's/#5BB0FF/#171E23/; s/#2440D6/#171E23/; s/#0B1E8F/#000000/g; s/#0A1B6B/#000000/g; s/stop-opacity="0.38"/stop-opacity="0"/; s/stop-opacity="0.35"/stop-opacity="0"/' \
    assets/logo/kitbagLogo.svg > "$BUILD/kitbagLogoDark.svg"
  swift scripts/render-svg.swift "$BUILD/kitbagLogoDark.svg" "$BUILD/AppIconDark.png" 512
  swift scripts/render-svg.swift assets/logo/kitbagLogo.svg "$BUILD/AppIconLight.png" 512
fi

log "Assembling $APP.app"
APPDIR="$BUILD/$APP.app"
mkdir -p "$APPDIR/Contents/MacOS" "$APPDIR/Contents/Resources"
cp "$BIN" "$APPDIR/Contents/MacOS/$APP"
cp "$PLIST" "$APPDIR/Contents/Info.plist"
cp "$ICNS" "$APPDIR/Contents/Resources/AppIcon.icns"
for v in Dark Light; do
  [[ ! -f "$BUILD/AppIcon$v.png" ]] || cp "$BUILD/AppIcon$v.png" "$APPDIR/Contents/Resources/AppIcon$v.png"
done
cp assets/logo/kitbagMenuLogo.svg "$APPDIR/Contents/Resources/MenuIcon.svg"  # AppKit renders SVG natively

log "Code signing (identity: $SIGN_IDENTITY)"
SIGN_OPTS=(--force --options runtime --entitlements "$ENTITLEMENTS" --sign "$SIGN_IDENTITY")
[[ "$SIGN_IDENTITY" == "-" || "$SIGN_IDENTITY" == "$LOCAL_ID" ]] || SIGN_OPTS+=(--timestamp)
codesign "${SIGN_OPTS[@]}" "$APPDIR"
codesign --verify --strict "$APPDIR"

log "Creating DMG"
STAGE="$BUILD/dmg"
mkdir -p "$STAGE"
cp -R "$APPDIR" "$STAGE/"
if command -v create-dmg >/dev/null; then
  create-dmg --volname "$APP" --volicon "$ICNS" --window-size 540 360 --icon-size 96 \
    --icon "$APP.app" 140 170 --app-drop-link 400 170 "$DMG" "$STAGE"
else
  echo "create-dmg not found; using hdiutil"
  ln -s /Applications "$STAGE/Applications"
  cp "$ICNS" "$STAGE/.VolumeIcon.icns"
  RW="$BUILD/rw.dmg"
  MNT="$BUILD/mnt"
  hdiutil create -volname "$APP" -srcfolder "$STAGE" -fs HFS+ -format UDRW -ov "$RW" >/dev/null
  mkdir -p "$MNT"
  hdiutil attach "$RW" -nobrowse -readwrite -mountpoint "$MNT" >/dev/null
  # Set the "custom icon" Finder flag so the volume shows .VolumeIcon.icns.
  xattr -wx com.apple.FinderInfo "00 00 00 00 00 00 00 00 04 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00" "$MNT"
  hdiutil detach "$MNT" >/dev/null
  hdiutil convert "$RW" -format UDZO -o "$DMG" >/dev/null
fi
if [[ "$SIGN_IDENTITY" != "-" && "$SIGN_IDENTITY" != "$LOCAL_ID" ]]; then codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG"; fi

if [[ "$NOTARIZE" == 1 ]]; then
  log "Notarizing (this can take a few minutes)"
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG"
fi

SIZE=$(du -h "$DMG" | cut -f1)
log "Done: $PWD/$DMG ($SIZE)"
