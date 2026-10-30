#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root_dir"

flutter test --enable-flutter-gpu --enable-impeller "$@"

if [[ $# -eq 0 ]]; then
  cd example
  flutter test --enable-flutter-gpu --enable-impeller
fi
