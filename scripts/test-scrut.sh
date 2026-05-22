#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if ! command -v scrut >/dev/null 2>&1; then
  echo "scrut is not installed. Install it from https://github.com/facebookincubator/scrut." >&2
  exit 127
fi

if [ "$#" -eq 0 ]; then
  set -- "$ROOT/tests/scrut"
fi

scrut test "$@"
