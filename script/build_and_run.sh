#!/usr/bin/env bash
set -euo pipefail
MODE="${1:-run}"
export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUNDLE="$PROJECT_DIR/dist/公众号文章下载器.app"
if [[ "$MODE" != "--build-only" ]] && pgrep -x MPArchive >/dev/null; then
  # The app's backend watches its parent and restores the proxy when it exits.
  pkill -TERM -x MPArchive
  for i in {1..80}; do pgrep -x MPArchive >/dev/null || break; sleep 0.1; done
fi
"$PROJECT_DIR/build.sh"
swift build --package-path "$PROJECT_DIR/macos"
BUILD_DIR="$(swift build --package-path "$PROJECT_DIR/macos" --show-bin-path)"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"
cp "$BUILD_DIR/MPArchive" "$BUNDLE/Contents/MacOS/MPArchive.new"
mv -f "$BUNDLE/Contents/MacOS/MPArchive.new" "$BUNDLE/Contents/MacOS/MPArchive"
cp "$PROJECT_DIR/mp_article_downloader_src/mp_article_batch_downloader" "$BUNDLE/Contents/Resources/mp_article_batch_downloader"
cp "$PROJECT_DIR/LICENSE" "$BUNDLE/Contents/Resources/LICENSE"
if [[ -f "$PROJECT_DIR/macos/AppIcon.icns" ]]; then cp "$PROJECT_DIR/macos/AppIcon.icns" "$BUNDLE/Contents/Resources/AppIcon.icns"; fi
cat > "$BUNDLE/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>MPArchive</string>
<key>CFBundleIdentifier</key><string>com.baiyalab.mp-article-downloader</string>
<key>CFBundleName</key><string>公众号文章下载器</string>
<key>CFBundleDisplayName</key><string>公众号文章下载器</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.0.3</string>
<key>CFBundleVersion</key><string>5</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>NSHighResolutionCapable</key><true/>
<key>CFBundleDevelopmentRegion</key><string>zh_CN</string>
<key>CFBundleLocalizations</key><array><string>zh_CN</string></array>
</dict></plist>
PLIST
# A stable signing identity keeps macOS Files & Folders permissions attached to
# the app across local rebuilds. Fall back to ad-hoc signing on machines without
# an installed development identity.
SIGN_IDENTITY="${CODESIGN_IDENTITY:-}"
if [[ -z "$SIGN_IDENTITY" ]]; then
  SIGN_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | sed -n 's/.*"\(Apple Development:[^"]*\)".*/\1/p' | head -n 1)"
fi
[[ -n "$SIGN_IDENTITY" ]] || SIGN_IDENTITY="-"
codesign --force --sign "$SIGN_IDENTITY" "$BUNDLE/Contents/Resources/mp_article_batch_downloader"
codesign --force --sign "$SIGN_IDENTITY" "$BUNDLE"
case "$MODE" in
 --build-only) ;;
 --install)
  python3 "$PROJECT_DIR/script/migrate_legacy.py"
  mkdir -p "$HOME/Applications"
  ditto "$BUNDLE" "$HOME/Applications/公众号文章下载器.app"
  /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$HOME/Applications/公众号文章下载器.app"
  open "$HOME/Applications/公众号文章下载器.app"
  ;;
 --verify|run) open "$BUNDLE"; sleep 1; pgrep -x MPArchive >/dev/null ;;
 --logs) open "$BUNDLE"; /usr/bin/log stream --info --predicate 'process == "MPArchive"' ;;
 --debug) lldb -- "$BUNDLE/Contents/MacOS/MPArchive" ;;
 *) echo "usage: $0 [--build-only|--install|--verify|--logs|--debug]" >&2; exit 2 ;;
esac
