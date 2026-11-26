#!/usr/bin/env bash
# scripts/package-release.sh on a fake binary and a tiny web vault tarball
# built in a temp dir. Offline: no build, no download.

# shellcheck source=scripts/lib/kv.sh
. scripts/lib/kv.sh

package_check() {
  local script=scripts/package-release.sh work out asset_name want got entries
  asset_name=vaultwarden-scalingo-x86_64-linux.tar.gz
  work="$(mktemp -d)"
  out="$work/out"

  printf '#!/bin/sh\necho "Vaultwarden 1.37.5"\n' > "$work/vaultwarden"
  chmod +x "$work/vaultwarden"
  mkdir -p "$work/src/web-vault/assets"
  echo "<html></html>" > "$work/src/web-vault/index.html"
  echo "body {}" > "$work/src/web-vault/assets/app.css"
  tar -czf "$work/web.tar.gz" -C "$work/src" web-vault

  # Layout and exit code.
  if ! GITHUB_SHA=0123456789abcdef0123456789abcdef01234567 \
    bash "$script" "$work/vaultwarden" "$work/web.tar.gz" "$out" > /dev/null 2>&1; then
    problem "$script" "exits non-zero on a binary and a web vault tarball"
    rm -rf "$work"
    return
  fi
  if [ ! -f "$out/$asset_name" ] || [ ! -f "$out/SHA256SUMS" ]; then
    problem "$script" "must write $asset_name and SHA256SUMS in OUT_DIR"
    rm -rf "$work"
    return
  fi
  entries="$(tar -tzf "$out/$asset_name" | sed 's#^\./##' | cut -d / -f 1 | sort -u)"
  if [ "$entries" != "vaultwarden" ]; then
    problem "$script" "the asset must have one top directory, vaultwarden/ (got: $entries)"
  fi
  mkdir "$work/extract"
  tar -xzf "$out/$asset_name" -C "$work/extract"
  for want in vaultwarden/vaultwarden vaultwarden/manifest \
    vaultwarden/web-vault/index.html vaultwarden/web-vault/assets/app.css; do
    [ -f "$work/extract/$want" ] || problem "$script" "the asset lacks $want"
  done
  [ -x "$work/extract/vaultwarden/vaultwarden" ] || problem "$script" "vaultwarden/vaultwarden must be executable"
  if [ "$("$work/extract/vaultwarden/vaultwarden")" != "Vaultwarden 1.37.5" ]; then
    problem "$script" "the binary must be copied unchanged"
  fi

  # Manifest: versions from VERSIONS, commit from GITHUB_SHA.
  for want in "VAULTWARDEN_VERSION:$(read_kv VERSIONS VAULTWARDEN_VERSION)" \
    "WEB_VAULT_VERSION:$(read_kv VERSIONS WEB_VAULT_VERSION)" \
    "SOURCE_COMMIT:0123456789abcdef0123456789abcdef01234567"; do
    got="$(read_kv "$work/extract/vaultwarden/manifest" "${want%%:*}" 2> /dev/null)"
    [ "$got" = "${want#*:}" ] || problem "$script" "manifest ${want%%:*} must be ${want#*:} (got: $got)"
  done
  if [ "$(wc -l < "$work/extract/vaultwarden/manifest" | tr -d ' ')" -ne 3 ]; then
    problem "$script" "manifest must hold exactly 3 keys"
  fi

  # SHA256SUMS: one line, sha256sum format, matching the asset.
  want="$(sha256_of "$out/$asset_name")  $asset_name"
  got="$(cat "$out/SHA256SUMS")"
  [ "$got" = "$want" ] || problem "$script" "SHA256SUMS must be '$want' (got: '$got')"

  # Without GITHUB_SHA the commit comes from git.
  rm -rf "$out"
  (unset GITHUB_SHA; bash "$script" "$work/vaultwarden" "$work/web.tar.gz" "$out" > /dev/null 2>&1)
  tar -xzf "$out/$asset_name" -C "$work/extract"
  want="$(git rev-parse HEAD)"
  got="$(read_kv "$work/extract/vaultwarden/manifest" SOURCE_COMMIT 2> /dev/null)"
  [ "$got" = "$want" ] || problem "$script" "without GITHUB_SHA, SOURCE_COMMIT must be git HEAD (got: $got)"

  # Refusals: nothing written on bad input.
  rm -rf "$out"
  if bash "$script" "$work/absent" "$work/web.tar.gz" "$out" > /dev/null 2>&1; then
    problem "$script" "must fail when the binary does not exist"
  fi
  if bash "$script" "$work/vaultwarden" "$work/absent.tar.gz" "$out" > /dev/null 2>&1; then
    problem "$script" "must fail when the web vault tarball does not exist"
  fi
  mkdir -p "$work/wrong/other"
  tar -czf "$work/wrong.tar.gz" -C "$work/wrong" other
  if bash "$script" "$work/vaultwarden" "$work/wrong.tar.gz" "$out" > /dev/null 2>&1; then
    problem "$script" "must fail when the tarball has no web-vault/ directory"
  fi
  if bash "$script" "$work/vaultwarden" > /dev/null 2>&1; then
    problem "$script" "must fail without its three arguments"
  fi
  [ ! -e "$out/$asset_name" ] || problem "$script" "must not leave an asset behind after a refusal"
  rm -rf "$work"
}

package_check
