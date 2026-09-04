#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="$ROOT_DIR/mp_article_downloader_src"
BIN_NAME="mp_article_batch_downloader"

cd "$SRC_DIR"
GO_BIN="${GO_BIN:-}"
if [[ -z "$GO_BIN" && -x /opt/homebrew/bin/go ]]; then
  GO_BIN=/opt/homebrew/bin/go
fi
if [[ -z "$GO_BIN" ]]; then
  GO_BIN=go
fi

"$GO_BIN" version
DOWNLOAD_GOPROXY="${DOWNLOAD_GOPROXY:-https://goproxy.cn,direct}"
GO_ROOT="${GO_ROOT:-}"
if [[ -z "$GO_ROOT" && "$GO_BIN" == "/opt/homebrew/bin/go" ]]; then
  GO_ROOT="/opt/homebrew/opt/go/libexec"
fi

if [[ -n "$GO_ROOT" ]]; then
  GOPROXY="$DOWNLOAD_GOPROXY" GOSUMDB=off GOROOT="$GO_ROOT" "$GO_BIN" build -o "$BIN_NAME" .
else
  GOPROXY="$DOWNLOAD_GOPROXY" GOSUMDB=off GOROOT= "$GO_BIN" build -o "$BIN_NAME" .
fi
chmod +x "$BIN_NAME"

echo "构建完成：$SRC_DIR/$BIN_NAME"
