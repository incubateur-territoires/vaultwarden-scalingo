#!/usr/bin/env bash
# scripts/pin-release.sh on temp copies of VERSIONS fixtures. Offline.
# `refuses` comes from 35-set-version.sh (the modules share one shell).

# shellcheck source=scripts/lib/kv.sh
. scripts/lib/kv.sh

pin_release_check() {
  local script=scripts/pin-release.sh work file sums sha newer repo out before
  sha=0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
  newer=fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210
  repo=incubateur-territoires/vaultwarden-scalingo
  work="$(mktemp -d)"
  file="$work/VERSIONS"
  sums="$work/SHA256SUMS"
  cp tests/fixtures/versions/ok-unpinned.env "$file"
  printf '%s  vaultwarden-scalingo-x86_64-linux.tar.gz\n' "$sha" > "$sums"

  # The pin: both keys are set, the checksum is printed, the result passes the
  # VERSIONS rules.
  if ! out="$(bash "$script" "$file" v1.2.3 "$sums" "$repo" 2> /dev/null)"; then
    problem "$script" "exits non-zero when it pins a release"
  fi
  [ "$out" = "$sha" ] || problem "$script" "must print the checksum it pinned (got: $out)"
  [ "$(read_kv "$file" RELEASE_TAG 2> /dev/null)" = "v1.2.3" ] || problem "$script" "must set RELEASE_TAG"
  [ "$(read_kv "$file" RELEASE_ASSET_SHA256 2> /dev/null)" = "$sha" ] || problem "$script" "must set RELEASE_ASSET_SHA256"
  expect_no_problem check_versions "$file"

  # A newer release replaces the pin of an older one.
  printf '%s  vaultwarden-scalingo-x86_64-linux.tar.gz\n' "$newer" > "$sums"
  if ! bash "$script" "$file" v1.2.4 "$sums" "$repo" > /dev/null 2>&1; then
    problem "$script" "must replace the pin of an older release"
  fi
  [ "$(read_kv "$file" RELEASE_TAG 2> /dev/null)" = "v1.2.4" ] || problem "$script" "must replace RELEASE_TAG"
  [ "$(read_kv "$file" RELEASE_ASSET_SHA256 2> /dev/null)" = "$newer" ] || problem "$script" "must replace RELEASE_ASSET_SHA256"

  # Refusals: non-zero, a reason on stderr, the file untouched.
  printf '%s  vaultwarden-scalingo-x86_64-linux.tar.gz\n' "$sha" > "$sums"
  cp tests/fixtures/versions/ok-unpinned.env "$file"
  before="$(cat "$file")"
  refuses "$script" "usage" "$file" v1.2.3 "$sums"
  refuses "$script" "not a plain tag name" "$file" '-n v1' "$sums" "$repo"
  refuses "$script" "not a plain tag name" "$file" '' "$sums" "$repo"
  refuses "$script" "cannot read" "$file" v1.2.3 "$work/absent" "$repo"
  refuses "$script" "does not start with a sha256" "$file" v1.2.3 tests/fixtures/versions/ok-unpinned.env "$repo"
  # The fork case: the workflow runs in a repository VERSIONS does not name.
  refuses "$script" "RELEASE_REPOSITORY is $repo but this workflow runs in someone/fork" "$file" v1.2.3 "$sums" someone/fork
  refuses "$script" "RELEASE_REPOSITORY" "$file" v1.2.3 "$sums" ""
  refuses "$script" "cannot read" "$work/absent-versions" v1.2.3 "$sums" "$repo"
  [ "$(cat "$file")" = "$before" ] || problem "$script" "a refused call must leave the file untouched"

  # A re-run after the pin pull request was merged has nothing to change: say
  # so (git commit would only say "nothing to commit").
  bash "$script" "$file" v1.2.3 "$sums" "$repo" > /dev/null 2>&1
  before="$(cat "$file")"
  refuses "$script" "already pins v1.2.3" "$file" v1.2.3 "$sums" "$repo"
  [ "$(cat "$file")" = "$before" ] || problem "$script" "a call with nothing to change must leave the file untouched"
  rm -rf "$work"
}

pin_release_check
