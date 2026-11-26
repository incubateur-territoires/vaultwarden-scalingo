#!/usr/bin/env bash
# Rules that tie .github/workflows/release.yml to scripts/package-release.sh.
# The rule function is proven on the fixtures in tests/fixtures/release, then
# run on the real files. (The fixture scripts are .txt: they are not linted.)

# check_release WORKFLOW SCRIPT:
#  - the pull_request paths filter lists VERSIONS, the workflow, and every
#    scripts/*.sh that either file names (a change to one must run the build);
#  - the asset name is the same in the workflow's env.ASSET, in every dist/*.tar.gz
#    path of the workflow (upload-artifact cannot read env.ASSET) and in the
#    script's ASSET_NAME.
check_release() {
  local workflow="$1" script="$2" paths wanted want asset script_asset literal
  paths="$(ruby -ryaml -e '
    doc = YAML.safe_load(File.read(ARGV[0]), aliases: true)
    on = doc["on"] || doc[true] || {}
    puts Array((on["pull_request"] || {})["paths"])
  ' "$workflow" 2> /dev/null)"
  wanted="$(
    echo VERSIONS
    echo .github/workflows/release.yml
    grep -ohE 'scripts/[A-Za-z0-9_./-]+\.sh' "$workflow" "$script"
  )"
  while IFS= read -r want; do
    if ! printf '%s\n' "$paths" | grep -qxF -- "$want"; then
      problem "$workflow" "the pull_request paths filter must list $want"
    fi
  done <<EOF
$(printf '%s\n' "$wanted" | sort -u)
EOF

  asset="$(sed -n 's/^  ASSET: *//p' "$workflow")"
  script_asset="$(sed -n 's/^ASSET_NAME=//p' "$script")"
  if [ -z "$asset" ]; then
    problem "$workflow" "env ASSET is missing"
  elif [ "$asset" != "$script_asset" ]; then
    problem "$workflow" "env ASSET ($asset) must be the ASSET_NAME of the packaging script (${script_asset:-none})"
  fi
  while IFS= read -r literal; do
    [ -n "$literal" ] || continue
    [ "$literal" = "dist/$asset" ] || problem "$workflow" "$literal must be dist/$asset (the env ASSET)"
  done <<EOF
$(grep -ohE 'dist/[A-Za-z0-9_.-]+\.tar\.gz' "$workflow")
EOF
}

release_fixture() {
  check_release "tests/fixtures/release/$1/release.yml" "tests/fixtures/release/$1/package-release.txt"
}

expect_no_problem release_fixture ok
expect_problem "paths filter must list scripts/lib/kv.sh" release_fixture no-kv-path
expect_problem "paths filter must list scripts/package-release.sh" release_fixture no-script-path
expect_problem "paths filter must list VERSIONS" release_fixture no-versions-path
expect_problem "paths filter must list .github/workflows/release.yml" release_fixture no-workflow-path
expect_problem "must be the ASSET_NAME of the packaging script" release_fixture script-asset-differs
expect_problem "dist/other-name.tar.gz must be dist/asset.tar.gz" release_fixture upload-path-differs
expect_problem "env ASSET is missing" release_fixture no-asset-env

if [ -f .github/workflows/release.yml ]; then
  check_release .github/workflows/release.yml scripts/package-release.sh
fi
