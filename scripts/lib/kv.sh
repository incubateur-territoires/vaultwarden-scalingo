#!/usr/bin/env bash
# read_kv FILE KEY: print the value of the line KEY=value in FILE.
# The only parser of KEY=VALUE files: never `source` or `eval` them.
# Blank lines and lines starting with # (optionally indented) are ignored; the
# value is everything after the first '=', verbatim.
# Lines are matched byte for byte, so these are NOT recognised:
#   - an indented key or spaces around '=' (`  KEY=v`, `KEY = v`): the key is
#     read as absent (return 1);
#   - CRLF line ends: the value keeps its trailing carriage return.
# Returns 0 and prints the value; 1 when KEY is absent; 2 on error, with the
# reason on stderr: FILE is not a readable regular file, awk failed, or KEY is
# defined more than once.
read_kv() {
  local file="$1" key="$2" out rc
  if [ ! -f "$file" ] || [ ! -r "$file" ]; then
    echo "read_kv: cannot read $file" >&2
    return 2
  fi
  out="$(awk -v key="$key" '
    /^[[:space:]]*(#|$)/ { next }
    {
      i = index($0, "=")
      if (i > 0 && substr($0, 1, i - 1) == key) { n++; value = substr($0, i + 1) }
    }
    END {
      if (n == 0) exit 1
      if (n > 1) exit 3
      print value
    }' "$file")"
  rc=$?
  case "$rc" in
    0) printf '%s\n' "$out" ;;
    1) return 1 ;;
    3)
      echo "read_kv: $key is defined more than once in $file" >&2
      return 2
      ;;
    *)
      echo "read_kv: cannot read $file (awk failed with status $rc)" >&2
      return 2
      ;;
  esac
}
