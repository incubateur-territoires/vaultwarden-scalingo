#!/usr/bin/env bash
# Unit tests of scripts/lib/kv.sh read_kv, on tests/fixtures/kv/*.

# shellcheck source=scripts/lib/kv.sh
. scripts/lib/kv.sh

# kv_expect DESCRIPTION FIXTURE KEY EXPECTED_RC EXPECTED_OUTPUT
kv_expect() {
  local desc="$1" file="$2" key="$3" want_rc="$4" want_out="$5" out rc
  out="$(read_kv "$file" "$key" 2> /dev/null)"
  rc=$?
  if [ "$rc" -ne "$want_rc" ] || [ "$out" != "$want_out" ]; then
    problem "$file" "read_kv: $desc (got rc=$rc out='$out', want rc=$want_rc out='$want_out')"
  fi
}

kv_expect "prints the value" tests/fixtures/kv/ok.env FIRST 0 one
kv_expect "keeps '=' inside the value" tests/fixtures/kv/ok.env SECOND 0 "a=b"
kv_expect "empty value" tests/fixtures/kv/ok.env EMPTY 0 ""
kv_expect "missing key returns 1" tests/fixtures/kv/ok.env MISSING 1 ""
kv_expect "commented key is missing" tests/fixtures/kv/ok.env COMMENTED 1 ""
kv_expect "duplicate key is an error" tests/fixtures/kv/duplicate.env KEY 2 ""
kv_expect "other keys of a file with a duplicate still read" tests/fixtures/kv/duplicate.env OTHER 0 x
kv_expect "unreadable file is an error" tests/fixtures/kv/absent.env KEY 2 ""
kv_expect "a comment line is never a key" tests/fixtures/kv/ok.env "# COMMENTED" 1 ""
kv_expect "a directory is an error" tests/fixtures/kv KEY 2 ""

# kv_expect_err DESCRIPTION FILE KEY EXPECTED_RC STDERR_SUBSTRING [AWK_EXIT]:
# check the reason read_kv gives on stderr. With AWK_EXIT, `awk` is replaced
# by one that fails with that status.
kv_expect_err() {
  local desc="$1" file="$2" key="$3" want_rc="$4" want_err="$5" awk_exit="${6:-}"
  local fake err rc
  fake="$(mktemp -d)"
  if [ -n "$awk_exit" ]; then
    printf '#!/bin/sh\nexit %s\n' "$awk_exit" > "$fake/awk"
    chmod +x "$fake/awk"
  fi
  err="$(PATH="$fake:$PATH" read_kv "$file" "$key" 2>&1 > /dev/null)"
  rc=$?
  rm -rf "$fake"
  case "$err" in
    *"$want_err"*) ;;
    *) rc="stderr='$err' lacks '$want_err'" ;;
  esac
  if [ "$rc" != "$want_rc" ]; then
    problem "$file" "read_kv: $desc (got rc=$rc, want rc=$want_rc)"
  fi
}

kv_expect_err "a duplicate is reported as such" tests/fixtures/kv/duplicate.env KEY 2 "defined more than once"
kv_expect_err "an awk failure is not reported as a duplicate" tests/fixtures/kv/ok.env FIRST 2 "cannot read" 2
