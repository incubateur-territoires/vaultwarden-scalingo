#!/usr/bin/env bash
# A `gh workflow run NAME --ref REF` of release.yml runs after a pull request
# is open: when it fails, the job must say how to start the checks by hand.

# check_dispatch_guard WORKFLOW: each call of `gh workflow run NAME` (not the
# command quoted in a message or a comment) is the condition of an `if !`, and
# the workflow has an ::error:: line that gives the command
# `gh workflow run NAME --ref` to run by hand.
check_dispatch_guard() {
  local workflow="$1" name line
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    if ! printf '%s\n' "$line" | grep -qE "^[[:space:]]*if ! gh workflow run +[A-Za-z0-9_.-]+( |;|\$)"; then
      problem "$workflow" "gh workflow run must be the condition of an 'if !' that reports its failure (got: $line)"
    fi
  done <<EOT
$(grep -E 'gh workflow run +[A-Za-z0-9_.-]+' "$workflow" | grep -vE '^[[:space:]]*#|::error::')
EOT
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    if ! grep -qE "::error::.*gh workflow run $name --ref" "$workflow"; then
      problem "$workflow" "gh workflow run $name: the ::error:: message must give the command 'gh workflow run $name --ref <branch>' to run by hand"
    fi
  done <<EOT
$(grep -ohE 'gh workflow run +[A-Za-z0-9_.-]+' "$workflow" | awk '{ print $4 }' | sort -u)
EOT
}

expect_no_problem check_dispatch_guard tests/fixtures/dispatch-guard/ok/release.yml
expect_problem "must be the condition of an 'if !'" check_dispatch_guard tests/fixtures/dispatch-guard/unguarded/release.yml
expect_problem "must be the condition of an 'if !'" check_dispatch_guard tests/fixtures/dispatch-guard/one-unguarded/release.yml
expect_problem "the ::error:: message must give the command" check_dispatch_guard tests/fixtures/dispatch-guard/no-hint/release.yml

if [ -f .github/workflows/release.yml ]; then
  check_dispatch_guard .github/workflows/release.yml
fi
