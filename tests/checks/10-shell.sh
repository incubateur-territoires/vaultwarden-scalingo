#!/usr/bin/env bash
# Lint every shell file of the repository with the shellcheck tool.

optional_tool_selftest shellcheck

# Fixtures are only shell when executable; everything else is by name.
shell_files() {
  local dir
  for dir in scripts bin tests; do
    [ -d "$dir" ] || continue
    find "$dir" -type f \( -name '*.sh' -o -path 'bin/*' -o \
      \( -path 'tests/fixtures/*' -perm -u+x \) \)
  done
}

if optional_tool shellcheck; then
  while IFS= read -r file; do
    if ! out="$(shellcheck -x "$file" 2>&1)"; then
      problem "$file" "shellcheck: $(strip_leading_blank_lines "$out")"
    fi
  done <<EOF
$(shell_files | sort)
EOF
fi
