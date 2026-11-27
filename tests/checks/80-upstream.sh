#!/usr/bin/env bash
# scripts/upstream-web-vault.sh (the readers of what upstream publishes) on the
# fixtures in tests/fixtures/upstream, and the rules of the update workflow.
# Offline: the workflow does the downloads, the script only reads files.

# says SCRIPT_ARGS...: run the script; print its stdout, keep stderr for reason.
# upstream_fails REASON ARGS...: the script must fail and say REASON.
upstream_fails() {
  local reason="$1" err
  shift
  if err="$(bash scripts/upstream-web-vault.sh "$@" 2>&1 > /dev/null)"; then
    problem scripts/upstream-web-vault.sh "must refuse ($reason): $*"
  elif ! printf '%s' "$err" | grep -qF -- "$reason"; then
    problem scripts/upstream-web-vault.sh "must say \"$reason\" (got: $err)"
  fi
}

# upstream_says WANT ARGS...: the script must succeed and print exactly WANT.
upstream_says() {
  local want="$1" got
  shift
  if ! got="$(bash scripts/upstream-web-vault.sh "$@" 2> /dev/null)"; then
    problem scripts/upstream-web-vault.sh "must succeed: $*"
  elif [ "$got" != "$want" ]; then
    problem scripts/upstream-web-vault.sh "$* must print $want (got: $got)"
  fi
}

upstream_check() {
  local work sum
  work="$(mktemp -d)"
  sum=354de9056c871e48db84975985e7d57c111ac6537bd4e4720488019e8638060f

  # The shapes upstream publishes today (copied from 1.37.5 and v2026.10.1).
  upstream_says "v2026.10.1" vault-version tests/fixtures/upstream/DockerSettings.yaml
  upstream_says "$sum" sha256-of tests/fixtures/upstream/sha256sums.txt bw_web_v2026.10.1.tar.gz
  # A name is matched whole: the signature file next to it is another line.
  upstream_says "652581efc0cb38acd5a0078915a8be7791a8b02d53fe2f49b9969312fe96130c" \
    sha256-of tests/fixtures/upstream/sha256sums.txt bw_web_v2026.10.1.tar.gz.asc

  # vault_version: quotes or none, a trailing comment; a commented or indented line is not the key.
  printf '# vault_version: "v2000.1.1"\nvault_version: v2026.10.1 # pinned\n  vault_version: "v2000.2.2"\n' > "$work/plain.yaml"
  upstream_says "v2026.10.1" vault-version "$work/plain.yaml"
  printf "vault_version: 'v2026.10.1'\n" > "$work/single.yaml"
  upstream_says "v2026.10.1" vault-version "$work/single.yaml"

  # Anything else is refused with a reason, and nothing is printed.
  printf 'debian_version: trixie\n' > "$work/none.yaml"
  upstream_fails "no vault_version" vault-version "$work/none.yaml"
  printf 'vault_version: "v2026.10.1"\nvault_version: "v2026.11.0"\n' > "$work/twice.yaml"
  upstream_fails "more than once" vault-version "$work/twice.yaml"
  printf 'vault_version: "latest"\n' > "$work/latest.yaml"
  upstream_fails "not a web vault version" vault-version "$work/latest.yaml"
  printf 'vault_version: ""\n' > "$work/empty.yaml"
  upstream_fails "not a web vault version" vault-version "$work/empty.yaml"
  printf 'vault_version: "v2026.10.1/../x"\n' > "$work/path.yaml"
  upstream_fails "not a web vault version" vault-version "$work/path.yaml"
  upstream_fails "cannot read" vault-version "$work/absent.yaml"

  upstream_fails "no checksum for bw_web_v2026.11.0.tar.gz" sha256-of tests/fixtures/upstream/sha256sums.txt bw_web_v2026.11.0.tar.gz
  upstream_fails "no checksum for bw_web_v2026.10.1" sha256-of tests/fixtures/upstream/sha256sums.txt bw_web_v2026.10.1
  printf '%s  a.tar.gz\n%s  a.tar.gz\n' "$sum" "$sum" > "$work/dup.txt"
  upstream_fails "more than once" sha256-of "$work/dup.txt" a.tar.gz
  printf '%s  a.tar.gz\n' "${sum%?}" > "$work/short.txt"
  upstream_fails "not a sha256" sha256-of "$work/short.txt" a.tar.gz
  printf '%s  a.tar.gz\n' "$(printf '%s' "$sum" | tr a-f A-F)" > "$work/upper.txt"
  upstream_fails "not a sha256" sha256-of "$work/upper.txt" a.tar.gz
  : > "$work/empty.txt"
  upstream_fails "no checksum for a.tar.gz" sha256-of "$work/empty.txt" a.tar.gz
  upstream_fails "cannot read" sha256-of "$work/absent.txt" a.tar.gz

  upstream_fails "usage" vault-version
  upstream_fails "usage" sha256-of tests/fixtures/upstream/sha256sums.txt
  upstream_fails "usage" nothing-like-this x

  # commit-of: the commit that `git archive` writes in the header of a tar,
  # read from a gzip like the ones GitHub serves. A tar without it is refused.
  local repo commit
  repo="$work/repo"
  mkdir "$repo"
  (
    cd "$repo" || exit 1
    git init -q .
    echo hello > file
    git add file
    git -c user.name=t -c user.email=t@example.com -c commit.gpgsign=false commit -q -m one
    git archive --format=tar HEAD | gzip -n > "$work/with-commit.tar.gz"
    git rev-parse HEAD > "$work/commit.txt"
  ) > /dev/null 2>&1
  commit="$(cat "$work/commit.txt" 2> /dev/null)"
  if [[ ! $commit =~ ^[0-9a-f]{40}$ ]]; then
    problem scripts/upstream-web-vault.sh "the test could not make a git archive"
  else
    upstream_says "$commit" commit-of "$work/with-commit.tar.gz"
  fi
  tar -cf - -C "$repo" file | gzip -n > "$work/no-commit.tar.gz"
  upstream_fails "no commit id" commit-of "$work/no-commit.tar.gz"
  printf 'not a tar' | gzip -n > "$work/not-tar.tar.gz"
  upstream_fails "no commit id" commit-of "$work/not-tar.tar.gz"
  upstream_fails "cannot read" commit-of "$work/absent.tar.gz"

  rm -rf "$work"
}

upstream_check

# check_update_workflow FILE: the update workflow runs weekly and by hand, and
# every script it names exists (a renamed script must not leave it broken until
# the next upstream release).
check_update_workflow() {
  local file="$1" script report line
  report="$(ruby -ryaml -e '
    doc = YAML.safe_load(File.read(ARGV[0]), aliases: true)
    on = doc["on"] || doc[true] || {}
    puts "must run on a schedule" unless on.is_a?(Hash) && on.key?("schedule")
    puts "must have a workflow_dispatch trigger" unless on.is_a?(Hash) && on.key?("workflow_dispatch")
  ' "$file" 2>&1)"
  while IFS= read -r line; do
    [ -n "$line" ] && problem "$file" "$line"
  done <<EOF
$report
EOF
  while IFS= read -r script; do
    [ -n "$script" ] || continue
    [ -f "$script" ] || problem "$file" "names $script, which does not exist"
  done <<EOF
$(grep -ohE 'scripts/[A-Za-z0-9_./-]+\.sh' "$file" | sort -u)
EOF
}

expect_problem "must run on a schedule" check_update_workflow tests/fixtures/upstream/update-no-schedule.yml
expect_problem "must have a workflow_dispatch trigger" check_update_workflow tests/fixtures/upstream/update-no-dispatch.yml
expect_problem "scripts/absent.sh, which does not exist" check_update_workflow tests/fixtures/upstream/update-missing-script.yml

if [ -f .github/workflows/update.yml ]; then
  check_update_workflow .github/workflows/update.yml
  check_dispatch_targets .github/workflows/update.yml
else
  problem .github/workflows/update.yml "file is missing"
fi
