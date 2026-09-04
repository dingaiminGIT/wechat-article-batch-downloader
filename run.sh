#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN="$ROOT_DIR/mp_article_downloader_src/mp_article_batch_downloader"

if [[ ! -x "$BIN" ]]; then
  echo "未找到可执行文件：$BIN"
  echo "请先运行：$ROOT_DIR/build.sh"
  exit 1
fi

exec sudo "$BIN" --config "$ROOT_DIR/config.yaml"
