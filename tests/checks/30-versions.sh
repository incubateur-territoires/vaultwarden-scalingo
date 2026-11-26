#!/usr/bin/env bash
# Rules for VERSIONS, the single pin file. The rule function is proven on the
# fixtures in tests/fixtures/versions, then run on the real file.

# shellcheck source=scripts/lib/kv.sh
. scripts/lib/kv.sh

VERSIONS_KEYS="VAULTWARDEN_VERSION VAULTWARDEN_SOURCE_SHA256 WEB_VAULT_VERSION WEB_VAULT_SHA256 RELEASE_REPOSITORY RELEASE_TAG RELEASE_ASSET_SHA256"

# check_versions FILE: every key present exactly once, no unknown key, each
# value in its format, the release pin set or empty as a whole, no `latest`.
check_versions() {
  local file="$1" key value rc name
  local version_re='^[0-9]+(\.[0-9]+)*$'
  local web_re='^v?[0-9]{4}\.[0-9]+\.[0-9]+$'
  local sha_re='^[0-9a-f]{64}$'
  local repo_re='^[A-Za-z0-9-]+/[A-Za-z0-9._-]+$'
  local tag_re='^[A-Za-z0-9][A-Za-z0-9._-]*$'

  # Unknown keys: every non-blank, non-comment line must be KEY=value, KEY known.
  while IFS= read -r name; do
    case " $VERSIONS_KEYS " in
      *" $name "*) ;;
      *) problem "$file" "unknown key: $name" ;;
    esac
  done <<EOF
$(awk '/^[[:space:]]*(#|$)/ { next } { i = index($0, "="); print (i > 0 ? substr($0, 1, i - 1) : $0) }' "$file")
EOF

  # Presence and uniqueness, then the value of each key.
  for key in $VERSIONS_KEYS; do
    value="$(read_kv "$file" "$key" 2> /dev/null)"
    rc=$?
    if [ "$rc" -eq 1 ]; then
      problem "$file" "missing key: $key"
      continue
    elif [ "$rc" -ne 0 ]; then
      problem "$file" "$key is defined more than once (or the file is unreadable)"
      continue
    fi
    if [ "$value" = "latest" ]; then
      problem "$file" "$key must not be latest"
      continue
    fi
    case "$key" in
      VAULTWARDEN_VERSION)
        [[ $value =~ $version_re ]] || problem "$file" "$key must look like 1.2.3 (got: $value)"
        ;;
      WEB_VAULT_VERSION)
        [[ $value =~ $web_re ]] || problem "$file" "$key must look like v2026.10.1 (got: $value)"
        ;;
      VAULTWARDEN_SOURCE_SHA256 | WEB_VAULT_SHA256)
        [[ $value =~ $sha_re ]] || problem "$file" "$key must be 64 lowercase hex characters (got: $value)"
        ;;
      RELEASE_ASSET_SHA256)
        if [ -n "$value" ]; then
          [[ $value =~ $sha_re ]] || problem "$file" "$key must be 64 lowercase hex characters (got: $value)"
        fi
        ;;
      RELEASE_REPOSITORY)
        [[ $value =~ $repo_re ]] || problem "$file" "$key must look like owner/name (got: $value)"
        ;;
      RELEASE_TAG)
        if [ -n "$value" ]; then
          [[ $value =~ $tag_re ]] || problem "$file" "$key is not a plain tag name (got: $value)"
          case "$value" in
            main | master | HEAD | stable) problem "$file" "$key must be a fixed tag, not $value" ;;
          esac
        fi
        ;;
    esac
  done

  # The release pin is all or nothing.
  local tag sha
  tag="$(read_kv "$file" RELEASE_TAG 2> /dev/null)"
  sha="$(read_kv "$file" RELEASE_ASSET_SHA256 2> /dev/null)"
  if [ -n "$tag" ] && [ -z "$sha" ]; then
    problem "$file" "RELEASE_TAG is set but RELEASE_ASSET_SHA256 is empty"
  elif [ -z "$tag" ] && [ -n "$sha" ]; then
    problem "$file" "RELEASE_ASSET_SHA256 is set but RELEASE_TAG is empty"
  fi
}

expect_problem "VAULTWARDEN_VERSION must look like" check_versions tests/fixtures/versions/bad-version.env
expect_problem "WEB_VAULT_VERSION must not be latest" check_versions tests/fixtures/versions/latest.env
expect_problem "WEB_VAULT_SHA256 must be 64 lowercase hex" check_versions tests/fixtures/versions/short-checksum.env
expect_problem "RELEASE_TAG is set but RELEASE_ASSET_SHA256 is empty" check_versions tests/fixtures/versions/tag-without-checksum.env
expect_problem "RELEASE_ASSET_SHA256 is set but RELEASE_TAG is empty" check_versions tests/fixtures/versions/checksum-without-tag.env
expect_problem "RELEASE_TAG must be a fixed tag, not main" check_versions tests/fixtures/versions/tag-main.env
expect_problem "unknown key: EXTRA_KEY" check_versions tests/fixtures/versions/unknown-key.env
expect_problem "missing key: WEB_VAULT_SHA256" check_versions tests/fixtures/versions/missing-key.env
expect_problem "WEB_VAULT_VERSION is defined more than once" check_versions tests/fixtures/versions/duplicate-key.env
expect_no_problem check_versions tests/fixtures/versions/ok-unpinned.env
expect_no_problem check_versions tests/fixtures/versions/ok-pinned.env

if [ -f VERSIONS ]; then
  check_versions VERSIONS
else
  problem VERSIONS "file is missing"
fi
