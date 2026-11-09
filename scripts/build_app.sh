#!/bin/bash
# Compile le widget et l'emballe dans dist/DeskWidgets.app (sans Xcode).
# Analogie: swift build fabrique le moteur, ce script lui construit la carrosserie (le .app).
set -euo pipefail

cd "$(dirname "$0")/.."

# Il faut au moins les outils en ligne de commande d'Apple
if ! command -v swift >/dev/null 2>&1; then
  echo "swift est introuvable. Installe les outils en ligne de commande: xcode-select --install" >&2
  exit 1
fi

echo "Compilation..."
swift build -c release

APP="dist/DeskWidgets.app"
BIN="$(swift build -c release --show-bin-path)/DeskWidgets"

# Structure d'une app macOS: Contents/MacOS (le programme) et Info.plist (sa carte d'identité)
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/DeskWidgets"

# LSUIElement: pas d'icône dans le Dock, l'app vit uniquement sur le bureau
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>DeskWidgets</string>
  <key>CFBundleIdentifier</key><string>com.noham.deskwidgets</string>
  <key>CFBundleName</key><string>DeskWidgets</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

# Signature locale "ad hoc": suffit pour lancer l'app sur ton propre Mac
codesign --force --deep --sign - "$APP"

echo "Prêt: $APP"
echo "Lancer: open $APP"
