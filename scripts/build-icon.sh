#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="${TMPDIR:-/tmp}/codex-harem-clang-cache"
mkdir -p .build
swift scripts/build-icon.swift assets/app-icon.png .build/AppIcon.iconset
