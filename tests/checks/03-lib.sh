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

# The shellcheck tool starts its report with an empty line: the module that runs
# it (10-shell.sh) must not leave a gap after the tool's name ("shellcheck:  |
# In ..."). Run that module itself, in a throwaway repository, with a fake
# tool that prints such a report, so a change to the module is caught.
lib_dir="$(mktemp -d)"
mkdir "$lib_dir/fake" "$lib_dir/scripts"
: > "$lib_dir/scripts/some.sh"
cat > "$lib_dir/fake/shellcheck" <<'FAKE'
#!/bin/sh
if [ "$1" = "--version" ]; then
  printf 'ShellCheck - shell script analysis tool\nversion: 9.8.7\nlicense: GNU General Public License, version 3\n'
  exit 0
fi
printf '\nIn %s line 3:\necho $x\n     ^-- SC2086: Double quote.\n' "$2"
exit 1
FAKE
chmod +x "$lib_dir/fake/shellcheck"
lib_all="$(
  cd "$lib_dir" || exit 1
  PATH="$lib_dir/fake:$PATH"
  export CHECK_LOG="$lib_dir/log"
  # shellcheck source=/dev/null
  . "$ROOT/tests/checks/10-shell.sh"
)"
lib_out="$(printf '%s\n' "$lib_all" | grep '^check: scripts/')"
# shellcheck disable=SC2016 # the expected report holds a literal $x
if [ "$lib_out" != 'check: scripts/some.sh: shellcheck: In scripts/some.sh line 3: | echo $x |      ^-- SC2086: Double quote.' ]; then
  problem tests/checks/10-shell.sh "a tool's leading empty line must not show in the problem (got '$lib_out')"
fi
# The run says which shellcheck it used, so a CI log shows the pinned one.
if ! printf '%s\n' "$lib_all" | grep -qx 'check: shellcheck 9.8.7'; then
  problem tests/checks/10-shell.sh "the run must print the shellcheck version it used (got '$lib_all')"
fi
rm -rf "$lib_dir"
unset lib_dir lib_out lib_all
