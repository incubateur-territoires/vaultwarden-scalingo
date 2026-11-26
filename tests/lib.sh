#!/usr/bin/env bash
# Helpers shared by the check modules. Sourced, never executed.
# Needs CHECK_LOG: a file that gets one line per problem.

# problem FILE RULE: print "check: FILE: RULE" and count it. One problem is one
# line: the lines of a multi-line RULE (a tool's report) are joined with " | ".
problem() {
  local msg="" line
  # Pure bash: the self-tests call this with an empty PATH.
  while IFS= read -r line; do
    [ -n "${line//[[:space:]]/}" ] && msg="${msg:+$msg | }$line"
  done <<EOF
$2
EOF
  echo "check: $1: $msg"
  echo "check: $1: $msg" >> "$CHECK_LOG"
}

# strip_leading_blank_lines TEXT: print TEXT without its leading empty lines
# (shellcheck starts its report with one), so a label put in front of it, as in
# "shellcheck: TEXT", is followed by the report's first line, not by a gap.
strip_leading_blank_lines() {
  local line started=""
  while IFS= read -r line; do
    if [ -z "$started" ] && [ -z "${line//[[:space:]]/}" ]; then
      continue
    fi
    started=1
    printf '%s\n' "$line"
  done <<EOF
$1
EOF
}

# warn MSG: print "check: MSG"; does not count as a problem.
warn() {
  echo "check: $*"
}

# require_tool NAME: a problem when NAME is not installed.
require_tool() {
  if command -v "$1" > /dev/null 2>&1; then
    return 0
  fi
  problem "$1" "not installed (required by make check)"
  return 1
}

# optional_tool NAME: true when installed. When missing, a warning locally and
# a problem when CI=true. Returns false either way.
optional_tool() {
  if command -v "$1" > /dev/null 2>&1; then
    return 0
  fi
  if [ "${CI:-}" = "true" ]; then
    problem "$1" "not installed (required in CI)"
  else
    warn "$1 not installed, skipping (CI runs it)"
  fi
  return 1
}

# optional_tool_selftest NAME: prove optional_tool for a tool that is not on
# PATH: only a warning outside CI, a problem when CI=true.
optional_tool_selftest() {
  local name="$1" empty log out
  empty="$(mktemp -d)"
  log="$(mktemp)"
  out="$(PATH="$empty" CHECK_LOG="$log" CI='' optional_tool "$name")"
  if [ "$out" != "check: $name not installed, skipping (CI runs it)" ] || [ -s "$log" ]; then
    problem "$name" "a missing tool must only warn outside CI"
  fi
  PATH="$empty" CHECK_LOG="$log" CI=true optional_tool "$name" > /dev/null
  if [ ! -s "$log" ]; then
    problem "$name" "a missing tool must be a problem when CI=true"
  fi
  rm -rf "$empty" "$log"
}

# expect_problem RULE_SUBSTRING CMD...: run CMD (its last argument names the
# fixture) and record a problem unless it reported RULE_SUBSTRING. What CMD
# reports is kept out of the real log and the output.
expect_problem() {
  local rule="$1" outer_log="$CHECK_LOG" inner_log fixture
  shift
  for fixture; do :; done
  inner_log="$(mktemp)"
  CHECK_LOG="$inner_log"
  "$@" > /dev/null 2>&1
  CHECK_LOG="$outer_log"
  if ! grep -qF -- "$rule" "$inner_log"; then
    problem "$fixture" "expected \"$rule\" to be reported"
  fi
  rm -f "$inner_log"
}

# expect_no_problem CMD...: run CMD (its last argument names the fixture) and
# record a problem when it reported anything. Same isolation as expect_problem.
expect_no_problem() {
  local outer_log="$CHECK_LOG" inner_log fixture reported
  for fixture; do :; done
  inner_log="$(mktemp)"
  CHECK_LOG="$inner_log"
  "$@" > /dev/null 2>&1
  CHECK_LOG="$outer_log"
  if [ -s "$inner_log" ]; then
    reported="$(head -n 1 "$inner_log")"
    problem "$fixture" "expected no problem, got: ${reported#check: }"
  fi
  rm -f "$inner_log"
}

# sha256_of FILE: print the hex sha256 of FILE.
sha256_of() {
  if command -v sha256sum > /dev/null 2>&1; then
    sha256sum "$1" | cut -d ' ' -f 1
  else
    shasum -a 256 "$1" | cut -d ' ' -f 1
  fi
}
