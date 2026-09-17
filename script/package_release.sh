#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_APP="${PACKAGE_SOURCE_APP:-$PROJECT_DIR/dist/公众号文章下载器.app}"
ASSET="${PACKAGE_ASSET:-$PROJECT_DIR/release/MPArticleDownloader-macOS-arm64.zip}"
OUTPUT_DIR="$(dirname "$ASSET")"

if [[ ! -d "$SOURCE_APP" ]]; then
  echo "未找到应用包，请先运行 ./script/build_and_run.sh --build-only" >&2
  exit 1
fi

mkdir -p "$OUTPUT_DIR"
STAGE="$(mktemp -d "${TMPDIR:-/tmp}/mp-article-release.XXXXXX")"
cleanup() { python3 - "$STAGE" <<'PY'
import shutil, sys
shutil.rmtree(sys.argv[1], ignore_errors=True)
PY
}
trap cleanup EXIT

APP="$STAGE/公众号文章下载器.app"
ditto "$SOURCE_APP" "$APP"

# 公共下载包使用可移植的 ad-hoc 签名，不携带开发者个人证书。
codesign --force --sign - "$APP/Contents/Resources/mp_article_batch_downloader"
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP"

python3 - "$ASSET" <<'PY'
from pathlib import Path
import sys
for suffix in ("", ".sha256"):
    path = Path(sys.argv[1] + suffix)
    if path.exists():
        path.unlink()
PY

ditto -c -k --sequesterRsrc --keepParent "$APP" "$ASSET"
(
  cd "$OUTPUT_DIR"
  shasum -a 256 "$(basename "$ASSET")" > "$(basename "$ASSET").sha256"
)

VERIFY="$STAGE/verify"
mkdir -p "$VERIFY"
ditto -x -k "$ASSET" "$VERIFY"
codesign --verify --deep --strict "$VERIFY/公众号文章下载器.app"
python3 "$PROJECT_DIR/script/verify_certificate_precedence.py" \
  "$VERIFY/公众号文章下载器.app/Contents/Resources/mp_article_batch_downloader"

ls -lh "$ASSET" "$ASSET.sha256"
cat "$ASSET.sha256"
