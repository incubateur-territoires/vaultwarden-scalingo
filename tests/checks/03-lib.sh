#!/usr/bin/env bash
# Unit tests of tests/lib.sh: the log the run counts holds one line per problem.

# A tool such as shellcheck prints several lines for one finding; `problem`
# must still write, and count, exactly one line starting with "check: FILE:".
lib_log="$(mktemp)"
lib_out="$(CHECK_LOG="$lib_log" problem some/file.sh $'shellcheck: In some/file.sh line 3:\n\necho $x\n     ^-- SC2086: Double quote.\n')"
lib_lines="$(wc -l < "$lib_log" | tr -d ' ')"
lib_out_lines="$(printf '%s\n' "$lib_out" | wc -l | tr -d ' ')"
case "$lib_out" in
  "check: some/file.sh: shellcheck: "*) ;;
  *) problem tests/lib.sh "problem must start with 'check: FILE: RULE' (got '$lib_out')" ;;
esac
if [ "$lib_lines" -ne 1 ] || [ "$lib_out_lines" -ne 1 ]; then
  problem tests/lib.sh "a multi-line message must be one problem line (log=$lib_lines, output=$lib_out_lines)"
fi
rm -f "$lib_log"
unset lib_log lib_out lib_lines lib_out_lines
