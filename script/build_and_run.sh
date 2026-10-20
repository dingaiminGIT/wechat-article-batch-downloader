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
NATIVE_SOURCE="${NATIVE_RUNTIME_SOURCE:-$PROJECT_DIR/../wechat-unfollow-bridge/dist/批量取关公众号.app/Contents/Resources}"
if [[ ! -x "$NATIVE_SOURCE/node" || ! -f "$NATIVE_SOURCE/debugger/build/index.js" ]]; then
 echo "缺少已验证的原生运行时，请设置 NATIVE_RUNTIME_SOURCE（含 node 和 debugger）" >&2
 exit 1
fi
mkdir -p "$BUNDLE/Contents/Resources/native"
cp "$NATIVE_SOURCE/node" "$BUNDLE/Contents/Resources/native/node.new"
mv -f "$BUNDLE/Contents/Resources/native/node.new" "$BUNDLE/Contents/Resources/native/node"
ditto "$NATIVE_SOURCE/debugger" "$BUNDLE/Contents/Resources/native/debugger"
cp "$PROJECT_DIR/native/bridge.mjs" "$PROJECT_DIR/native/compatibility.json" "$PROJECT_DIR/native/THIRD_PARTY.md" "$BUNDLE/Contents/Resources/native/"
NATIVE_NODE_LICENSE="${NATIVE_NODE_LICENSE:-$PROJECT_DIR/../wechat-unfollow-bridge/Licenses/Node-v23.6.0-LICENSE.txt}"
if [[ ! -s "$NATIVE_NODE_LICENSE" ]]; then echo "缺少 Node 运行时许可证，停止打包" >&2; exit 1; fi
cp "$NATIVE_NODE_LICENSE" "$BUNDLE/Contents/Resources/native/NODE-LICENSE.txt"
cp "$PROJECT_DIR/docs/native-batch-implementation.md" "$BUNDLE/Contents/Resources/实现原理与使用说明.md"
NATIVE_SOURCE_CODE="${NATIVE_SOURCE_CODE:-$PROJECT_DIR/../wechat-unfollow-bridge/third_party/WMPFDebugger}"
if [[ ! -f "$NATIVE_SOURCE_CODE/LICENSE" ]]; then echo "缺少原生组件源代码及许可证，停止打包" >&2;exit 1;fi
ditto "$NATIVE_SOURCE_CODE" "$BUNDLE/Contents/Resources/native/third-party-source/WMPFDebugger"
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
<key>CFBundleShortVersionString</key><string>1.1.0</string>
<key>CFBundleVersion</key><string>12</string>
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
codesign --force --sign "$SIGN_IDENTITY" "$BUNDLE/Contents/Resources/native/node"
codesign --force --sign "$SIGN_IDENTITY" "$BUNDLE"
case "$MODE" in
 --build-only) ;;
 --install)
  # Updates preserve the existing account store; migrate only on first install.
  if [[ ! -f "$HOME/Library/Application Support/MPArticleDownloader/mp.json" ]]; then
    python3 "$PROJECT_DIR/script/migrate_legacy.py"
  fi
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
