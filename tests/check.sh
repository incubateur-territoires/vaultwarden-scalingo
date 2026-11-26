#!/usr/bin/env bash
# Runs every check module in tests/checks/ and reports. No `set -e`: a failing
# check records a problem and the run goes on, so one run lists everything.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 1

CHECK_LOG="$(mktemp)"
export CHECK_LOG
trap 'rm -f "$CHECK_LOG"' EXIT

# shellcheck source=tests/lib.sh
. tests/lib.sh

for module in tests/checks/*.sh; do
  # shellcheck source=/dev/null
  . "$module"
done

count="$(wc -l < "$CHECK_LOG" | tr -d ' ')"
if [ "$count" -eq 0 ]; then
  echo "check: all passed"
  exit 0
fi
echo "check: $count problem(s) found"
exit 1
