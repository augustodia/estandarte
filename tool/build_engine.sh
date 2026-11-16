#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PARENT="$(cd "$ROOT/.." && pwd)"
if [ -f "$PARENT/estandarte-engine/go.mod" ]; then
  ENGINE_DIR="$PARENT/estandarte-engine"
elif [ -f "$ROOT/engine/go.mod" ]; then
  ENGINE_DIR="$ROOT/engine"
else
  echo "Erro: motor Go não encontrado em $PARENT/estandarte-engine nem em $ROOT/engine" >&2
  exit 1
fi
cd "$ENGINE_DIR"

GOOS=js GOARCH=wasm go build -ldflags="-s -w" -o "$ROOT/web/engine/estandarte.wasm" ./cmd/wasm
GOROOT="$(go env GOROOT)"
WASM_EXEC="$GOROOT/lib/wasm/wasm_exec.js"
[ -f "$WASM_EXEC" ] || WASM_EXEC="$GOROOT/misc/wasm/wasm_exec.js"
cp "$WASM_EXEC" "$ROOT/web/engine/wasm_exec.js"

echo "Built web/engine/estandarte.wasm and copied wasm_exec.js"
if [ "${1:-}" = "--native" ]; then
  mkdir -p "$ROOT/build/native"
  case "$(uname -s)" in
    Linux*)  CGO_ENABLED=1 go build -buildmode=c-shared -o "$ROOT/build/native/libestandarte_engine.so" ./cmd/ffi ;;
    Darwin*) CGO_ENABLED=1 go build -buildmode=c-shared -o "$ROOT/build/native/libestandarte_engine.dylib" ./cmd/ffi ;;
  esac
  echo "Built native shared library in build/native/"
fi
