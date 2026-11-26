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
