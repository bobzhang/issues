#!/usr/bin/env bash
set -euo pipefail

export REPO_ROOT
REPO_ROOT="$(cd "$TESTDIR/../.." && pwd)"

export ISSUES_DB="$TMPDIR/issues.db"

moon -C "$REPO_ROOT" build --target native cmd/main >/dev/null

export ISSUES_BIN="$REPO_ROOT/_build/native/debug/build/cmd/main/main.exe"

issues() {
  "$ISSUES_BIN" --db "$ISSUES_DB" "$@"
}
