#!/bin/bash
# Pack the Swift-built CelistDB binary into a proper macOS .app bundle.
#
# Usage:
#   ./Scripts/make_app.sh                    # release build → dist/celist.db.app
#   ./Scripts/make_app.sh --debug            # use existing debug build
#
# Optional (for a signed + notarized app):
#   ./Scripts/make_app.sh --sign "Developer ID Application: Your Name (XXXX)"
#
# After this you can drag celist.db.app to Applications, or zip it to share.

set -euo pipefail

cd "$(dirname "$0")/.."
APP_NAME="celist.db"
BIN_NAME="CelistDB"
DIST_DIR="$PWD/dist"
APP="$DIST_DIR/$APP_NAME.app"
CONTENT="$APP/Contents"
MACOS="$CONTENT/MacOS"
RES="$CONTENT/Resources"
BUILD_MODE="release"
SIGN_IDENTITY=""

# --- Args -------------------------------------------------------------
for arg in "$@"; do
  case "$arg" in
    --debug) BUILD_MODE="debug" ;;
    --sign=*) SIGN_IDENTITY="${arg#--sign=}" ;;
    --sign) : ;; # handled via the next arg later; see below
  esac
done

# Allow `--sign "Developer ID Application: ..."` (two-arg form).
if [[ -n "${2:-}" && "$1" == "--sign" ]]; then
  SIGN_IDENTITY="$2"
fi

# --- Build ------------------------------------------------------------
echo "==> Building…"
if [[ "$BUILD_MODE" == "release" ]]; then
  swift build -c release
  BIN=".build/release/$BIN_NAME"
else
  swift build
  BIN=".build/debug/$BIN_NAME"
fi

if [[ ! -f "$BIN" ]]; then
  echo "ERROR: binary not found at $BIN — did the build fail?" >&2
  exit 1
fi

# --- Assemble bundle --------------------------------------------------
echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$MACOS" "$RES"

cp "$BIN" "$MACOS/$BIN_NAME"

# --- App icon ---------------------------------------------------------
if [[ -f "Scripts/AppIcon.icns" ]]; then
  cp "Scripts/AppIcon.icns" "$RES/AppIcon.icns"
  echo "==> Bundled app icon"
else
  echo "!! No Scripts/AppIcon.icns found — run Scripts/make_icns.sh first"
fi

cat > "$CONTENT/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleDisplayName</key>
  <string>$APP_NAME</string>
  <key>CFBundleExecutable</key>
  <string>$BIN_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>com.celist.db</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>LSApplicationCategoryType</key>
  <string>public.app-category.productivity</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
</dict>
</plist>
PLIST

# --- Include bundled GRDB framework if the build produced one ----------
if [[ "$BUILD_MODE" == "release" ]] && [[ -d ".build/release/GRDB" ]]; then
  cp -R ".build/release/GRDB" "$CONTENT/Frameworks/" 2>/dev/null || true
fi

# --- Code signing ------------------------------------------------------
if [[ -n "$SIGN_IDENTITY" ]]; then
  echo "==> Signing with $SIGN_IDENTITY"
  codesign --force --deep --sign "$SIGN_IDENTITY" "$APP"
else
  echo "==> Not signing (skip with --sign to codesign)"
  codesign --force --deep --sign - "$APP" 2>/dev/null || true
fi

echo ""
echo "✅ Done: $APP"
echo ""

# --- Package the shareable zip (app + README) --------------------------
if [[ -f "Scripts/README.txt" ]]; then
  cp "Scripts/README.txt" "$DIST_DIR/README.txt"
fi
rm -f "$DIST_DIR/$APP_NAME.zip"
pushd "$DIST_DIR" >/dev/null
zip -r "$APP_NAME.zip" "$APP_NAME.app" README.txt -x "*.DS_Store" >/dev/null
popd >/dev/null
echo "📦 Packaged: $DIST_DIR/$APP_NAME.zip"
echo ""
echo "Share dist/$APP_NAME.zip. Recipients unzip, drag $APP_NAME.app to"
echo "Applications, and right-click→Open on first launch (Gatekeeper)."
echo ""
echo "For Gatekeeper-friendly installs you still need to notarize:"
echo "  xcrun notarytool submit dist/$APP_NAME.zip --keychain-profile \"notary\" --wait"
echo "  xcrun stapler staple $APP"
