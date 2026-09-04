#!/usr/bin/env bash
set -euo pipefail

# Resolve paths relative to this script's own location, not the caller's cwd,
# so `./scripts/build.sh` works the same from the repo root, from scripts/,
# or from anywhere else.
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"

src="$repo_root/src"
test_dir="$repo_root/src/loomscript/test"
out="$repo_root/bin/loomscript"

echo "-- check --"
odin check "$src/loomscript" -no-entry-point

echo "-- test --"
odin test "$test_dir" -define:ODIN_TEST_LOG_LEVEL=warning

echo "-- build --"
mkdir -p "$repo_root/bin"
odin build "$src" -out:"$out"

echo "-- done: $out --"
