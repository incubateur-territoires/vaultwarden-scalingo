#!/usr/bin/env bash
# read_kv FILE KEY: print the value of the line KEY=value in FILE.
# The only parser of KEY=VALUE files: never `source` or `eval` them.
# Blank lines and lines starting with # are ignored; the value is everything
# after the first '=', verbatim.
# Returns 0 and prints the value; 1 when KEY is absent; 2 on error (FILE
# unreadable, or KEY defined more than once), with the reason on stderr.
read_kv() {
  local file="$1" key="$2" out rc
  if [ ! -r "$file" ]; then
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
      if (n > 1) exit 2
      print value
    }' "$file")"
  rc=$?
  case "$rc" in
    0) printf '%s\n' "$out" ;;
    1) return 1 ;;
    *)
      echo "read_kv: $key is defined more than once in $file" >&2
      return 2
      ;;
  esac
}
