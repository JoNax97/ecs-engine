#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"

scratch="$(mktemp /tmp/loomscript-try.XXXXXX.lms)"
trap 'rm -f "$scratch"' EXIT

"${EDITOR:-nano}" "$scratch"
"$repo_root/bin/loomscript" "$scratch"
