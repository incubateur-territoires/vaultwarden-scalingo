#!/usr/bin/env bash
# Tests of the buildpack contract (bin/detect, bin/compile, bin/release) and of
# scripts/compile.sh. Offline: the release asset is built by
# scripts/package-release.sh from a fake binary and served with file://.

# shellcheck source=scripts/lib/kv.sh
. scripts/lib/kv.sh

COMPILE_PFX=" !     "
COMPILE_ASSET=vaultwarden-scalingo-x86_64-linux.tar.gz
COMPILE_TAG=v9.9.9
COMPILE_ZERO=0000000000000000000000000000000000000000000000000000000000000000

# compile_package DIR BODY: package a fake binary whose script is BODY into
# DIR/out. Sets COMPILE_URL (file:// URL of the asset) and COMPILE_PIN (its sha256).
compile_package() {
  local dir="$1" body="$2"
  mkdir -p "$dir/src/web-vault"
  printf '%s\n' "$body" > "$dir/vaultwarden"
  chmod +x "$dir/vaultwarden"
  echo "<html></html>" > "$dir/src/web-vault/index.html"
  tar -czf "$dir/web.tar.gz" -C "$dir/src" web-vault
  GITHUB_SHA=0123456789abcdef0123456789abcdef01234567 \
    bash scripts/package-release.sh "$dir/vaultwarden" "$dir/web.tar.gz" "$dir/out" > /dev/null 2>&1
  COMPILE_URL="file://$dir/out/$COMPILE_ASSET"
  COMPILE_PIN="$(sha256_of "$dir/out/$COMPILE_ASSET")"
}

# compile_run LABEL WORK TAG PIN URL [STACK]: run bin/compile on a copy of the
# scripts and a VERSIONS that pins TAG and PIN (an empty TAG or PIN leaves that
# key empty; the word "omit" drops the key). The cache is WORK/cache and
# survives between runs. Sets COMPILE_RC, COMPILE_OUT, COMPILE_ERR, COMPILE_BUILD.
compile_run() {
  local label="$1" work="$2" tag="$3" pin="$4" url="$5" stack="${6:-}"
  local build="$work/build-$label" envs=()
  rm -rf "$build"
  mkdir -p "$build" "$work/cache" "$work/env"
  cp -R scripts "$build/scripts"
  grep -v '^RELEASE_TAG=\|^RELEASE_ASSET_SHA256=' VERSIONS > "$build/VERSIONS"
  [ "$tag" = omit ] || echo "RELEASE_TAG=$tag" >> "$build/VERSIONS"
  [ "$pin" = omit ] || echo "RELEASE_ASSET_SHA256=$pin" >> "$build/VERSIONS"
  [ -z "$url" ] || envs[0]="VAULTWARDEN_RELEASE_URL=$url"
  [ -z "$stack" ] || envs[${#envs[@]}]="STACK=$stack"
  env -i PATH="${COMPILE_PATH:-$PATH}" ${envs[@]+"${envs[@]}"} \
    bin/compile "$build" "$work/cache" "$work/env" > "$work/run.out" 2> "$work/run.err"
  COMPILE_RC=$?
  COMPILE_OUT="$(cat "$work/run.out")"
  COMPILE_ERR="$(cat "$work/run.err")"
  COMPILE_BUILD="$build"
}

# compile_expect_failure LABEL MESSAGE: the last run exited 1 with MESSAGE on
# stderr, and installed nothing.
compile_expect_failure() {
  if [ "$COMPILE_RC" -ne 1 ]; then
    problem scripts/compile.sh "$1: must exit 1 (got $COMPILE_RC)"
  fi
  case "$COMPILE_ERR" in
    *"$COMPILE_PFX$2"*) ;;
    *) problem scripts/compile.sh "$1: must print \"$2\" (got: $COMPILE_ERR)" ;;
  esac
}

compile_check() {
  local work vw_version web_version line want

  vw_version="$(read_kv VERSIONS VAULTWARDEN_VERSION)"
  web_version="$(read_kv VERSIONS WEB_VAULT_VERSION)"
  work="$(mktemp -d)"
  compile_package "$work" "#!/bin/sh
echo \"Vaultwarden $vw_version\"
echo \"Web-Vault $web_version\""
  if [ ! -f "$work/out/$COMPILE_ASSET" ]; then
    problem scripts/package-release.sh "cannot build the fake asset for the compile tests"
    rm -rf "$work"
    return
  fi

  # Good asset: installed, success line, then reused from the cache.
  compile_run good "$work" "$COMPILE_TAG" "$COMPILE_PIN" "$COMPILE_URL" scalingo-24
  want="-----> Installed Vaultwarden $vw_version with web vault $web_version from release $COMPILE_TAG"
  if [ "$COMPILE_RC" -ne 0 ]; then
    problem scripts/compile.sh "a good asset must exit 0 (got $COMPILE_RC: $COMPILE_ERR)"
  fi
  case "$COMPILE_OUT" in
    *"$want"*) ;;
    *) problem scripts/compile.sh "a good asset must print \"$want\" (got: $COMPILE_OUT)" ;;
  esac
  [ -x "$COMPILE_BUILD/vaultwarden/vaultwarden" ] || problem scripts/compile.sh "BUILD_DIR/vaultwarden/vaultwarden must be installed and executable"
  [ -f "$COMPILE_BUILD/vaultwarden/web-vault/index.html" ] || problem scripts/compile.sh "BUILD_DIR/vaultwarden/web-vault must be installed"
  [ -f "$COMPILE_BUILD/vaultwarden/manifest" ] || problem scripts/compile.sh "BUILD_DIR/vaultwarden/manifest must be installed"
  [ -f "$work/cache/$COMPILE_PIN.tar.gz" ] || problem scripts/compile.sh "a verified asset must be kept in CACHE_DIR as <sha256>.tar.gz"

  echo stale > "$work/cache/${COMPILE_ZERO}.tar.gz"
  compile_run cached "$work" "$COMPILE_TAG" "$COMPILE_PIN" "file://$work/missing.tar.gz" scalingo-24
  if [ "$COMPILE_RC" -ne 0 ]; then
    problem scripts/compile.sh "a cached asset must be reused without the URL (got $COMPILE_RC: $COMPILE_ERR)"
  fi
  case "$COMPILE_OUT" in
    *"$want"*) ;;
    *) problem scripts/compile.sh "a cached asset must print \"$want\" (got: $COMPILE_OUT)" ;;
  esac
  [ ! -e "$work/cache/${COMPILE_ZERO}.tar.gz" ] || problem scripts/compile.sh "the cache must drop the asset of an earlier pin"

  # A cached file that does not match the pin is not trusted.
  echo corrupt > "$work/cache/$COMPILE_PIN.tar.gz"
  compile_run corrupt-cache "$work" "$COMPILE_TAG" "$COMPILE_PIN" "$COMPILE_URL" scalingo-24
  if [ "$COMPILE_RC" -ne 0 ]; then
    problem scripts/compile.sh "a corrupt cached asset must be downloaded again (got $COMPILE_RC: $COMPILE_ERR)"
  fi
  rm -rf "$work/cache"

  # Wrong checksum: refused, nothing extracted, nothing cached.
  compile_run mismatch "$work" "$COMPILE_TAG" "$COMPILE_ZERO" "$COMPILE_URL" scalingo-24
  compile_expect_failure "a wrong checksum" "Checksum mismatch for $COMPILE_ASSET: expected $COMPILE_ZERO, got $(sha256_of "$work/out/$COMPILE_ASSET"). Refusing to install."
  if [ -e "$COMPILE_BUILD/vaultwarden" ]; then
    problem scripts/compile.sh "a wrong checksum must extract nothing into BUILD_DIR"
  fi
  if [ -n "$(ls -A "$work/cache")" ]; then
    problem scripts/compile.sh "a wrong checksum must keep nothing in CACHE_DIR"
  fi

  # No release pinned yet (the state of VERSIONS today).
  compile_run no-tag "$work" "" "" "$COMPILE_URL"
  compile_expect_failure "an empty pin" "VERSIONS pins no release yet (RELEASE_TAG is empty). Publish a release of this repository, then merge the pull request that pins it."
  compile_run no-sha "$work" "$COMPILE_TAG" "" "$COMPILE_URL"
  compile_expect_failure "a tag without checksum" "VERSIONS sets RELEASE_TAG but RELEASE_ASSET_SHA256 is empty. Refusing to install a release that is not verified."
  compile_run omitted-tag "$work" omit "$COMPILE_PIN" "$COMPILE_URL"
  compile_expect_failure "a VERSIONS without RELEASE_TAG" "Cannot read RELEASE_TAG from VERSIONS."
  compile_run omitted-sha "$work" "$COMPILE_TAG" omit "$COMPILE_URL"
  compile_expect_failure "a VERSIONS without RELEASE_ASSET_SHA256" "Cannot read RELEASE_ASSET_SHA256 from VERSIONS."

  # Unreachable: a missing file, and an https address nobody listens on.
  for want in "file://$work/missing.tar.gz" "https://localhost:1/missing.tar.gz"; do
    compile_run unreachable "$work" "$COMPILE_TAG" "$COMPILE_PIN" "$want"
    compile_expect_failure "an unreachable URL ($want)" "Could not download $want. Check that release $COMPILE_TAG exists and has its assets."
  done
  # Without an override, curl gets the pinned release of the pinned repository,
  # over https only (a fake curl records its arguments and fails).
  mkdir -p "$work/fakebin"
  printf '#!/bin/sh\nprintf "%%s\\n" "$@" > "%s/curl.args"\nexit 22\n' "$work" > "$work/fakebin/curl"
  chmod +x "$work/fakebin/curl"
  want="https://github.com/$(read_kv VERSIONS RELEASE_REPOSITORY)/releases/download/$COMPILE_TAG/$COMPILE_ASSET"
  COMPILE_PATH="$work/fakebin:$PATH"
  compile_run default-url "$work" "$COMPILE_TAG" "$COMPILE_PIN" ""
  COMPILE_PATH="$PATH"
  compile_expect_failure "a failed download" "Could not download $want. Check that release $COMPILE_TAG exists and has its assets."
  if ! grep -qx -- "$want" "$work/curl.args" 2> /dev/null; then
    problem scripts/compile.sh "curl must be given the URL $want"
  fi
  if ! grep -qx -- "=https" "$work/curl.args" 2> /dev/null; then
    problem scripts/compile.sh "curl must be restricted with --proto '=https'"
  fi

  # A binary that does not run: the stack message, with the stack when known.
  compile_package "$work/broken" '#!/bin/sh
exit 127'
  compile_run broken "$work" "$COMPILE_TAG" "$COMPILE_PIN" "$COMPILE_URL" scalingo-24
  compile_expect_failure "a binary that fails --version" "The Vaultwarden binary does not run on stack scalingo-24. Supported stacks: scalingo-24, scalingo-26."
  rm -rf "$work/cache"
  compile_run broken-unknown "$work" "$COMPILE_TAG" "$COMPILE_PIN" "$COMPILE_URL"
  compile_expect_failure "a binary that fails --version, stack unknown" "The Vaultwarden binary does not run on stack unknown. Supported stacks: scalingo-24, scalingo-26."

  # bin/compile hands its three arguments to the deployed scripts/compile.sh.
  mkdir -p "$work/tramp/scripts"
  printf '#!/bin/sh\nprintf "%%s\\n" "$@" > "%s/args"\n' "$work" > "$work/tramp/scripts/compile.sh"
  chmod +x "$work/tramp/scripts/compile.sh"
  bin/compile "$work/tramp" cache-dir env-dir > /dev/null 2>&1
  if [ "$(cat "$work/args" 2> /dev/null)" != "$work/tramp
cache-dir
env-dir" ]; then
    problem bin/compile "must run \$1/scripts/compile.sh with BUILD_DIR CACHE_DIR ENV_DIR"
  fi

  # bin/detect: a Vaultwarden app has a VERSIONS file.
  mkdir -p "$work/app" "$work/other"
  : > "$work/app/VERSIONS"
  if ! line="$(bin/detect "$work/app" 2> /dev/null)" || [ "$line" != "Vaultwarden" ]; then
    problem bin/detect "must print Vaultwarden and exit 0 when VERSIONS exists"
  fi
  if bin/detect "$work/other" > /dev/null 2>&1; then
    problem bin/detect "must exit 1 when VERSIONS is absent"
  fi

  # bin/release: the Procfile defines the process.
  if [ "$(bin/release "$work/app" 2> /dev/null)" != "--- {}" ]; then
    problem bin/release "must print --- {}"
  fi

  rm -rf "$work"
}

compile_check

for compile_file in .buildpacks bin/detect bin/compile bin/release scripts/compile.sh; do
  [ -f "$compile_file" ] || problem "$compile_file" "is missing"
done
for compile_file in bin/detect bin/compile bin/release scripts/compile.sh; do
  [ -x "$compile_file" ] || problem "$compile_file" "must be executable"
done
# D3: this repository's own main is the buildpack.
if [ "$(cat .buildpacks 2> /dev/null)" != "https://github.com/incubateur-territoires/vaultwarden-scalingo.git#main" ]; then
  problem .buildpacks "must be the single line https://github.com/incubateur-territoires/vaultwarden-scalingo.git#main"
fi
