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
  local work sum got
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

  # tree-of: the git tree of the files inside a source archive, read from a gzip
  # like the ones GitHub serves (one top-level directory, `git archive` layout).
  # The workflow compares it with the tree of the commit that the API names for
  # the tag: that is what ties the files to the commit, not the header of the tar.
  local repo tree
  repo="$work/repo"
  mkdir "$repo"
  (
    cd "$repo" || exit 1
    git init -q .
    mkdir src
    echo hello > src/main.rs
    printf '#!/bin/sh\n' > run.sh
    chmod +x run.sh
    ln -s src/main.rs link
    printf 'ignored.txt\n' > .gitignore
    echo kept > ignored.txt
    git add --force .
    git -c user.name=t -c user.email=t@example.com -c commit.gpgsign=false commit -q -m one
    git archive --format=tar --prefix=project-1.0/ HEAD > "$work/genuine.tar"
    gzip -n < "$work/genuine.tar" > "$work/genuine.tar.gz"
    git rev-parse 'HEAD^{tree}' > "$work/tree.txt"
  ) > /dev/null 2>&1
  tree="$(cat "$work/tree.txt" 2> /dev/null)"
  if [[ ! $tree =~ ^[0-9a-f]{40}$ ]]; then
    problem scripts/upstream-web-vault.sh "the test could not make a git archive"
  else
    # Executable bit, symlink and a file that .gitignore names all count.
    upstream_says "$tree" tree-of "$work/genuine.tar.gz"
    # A tar whose header names the genuine commit but whose files are others:
    # `git get-tar-commit-id` accepts it, the tree must not match.
    mkdir "$work/evil" "$work/evil/project-1.0" "$work/evil/project-1.0/src"
    echo 'fn main() { evil() }' > "$work/evil/project-1.0/src/main.rs"
    { head -c 1024 "$work/genuine.tar"; tar -cf - -C "$work/evil" project-1.0; } | gzip -n > "$work/lying.tar.gz"
    if [ -z "$(gzip -dc "$work/lying.tar.gz" | git get-tar-commit-id 2> /dev/null)" ]; then
      problem scripts/upstream-web-vault.sh "the test could not make a tar that lies about its commit"
    else
      got="$(bash scripts/upstream-web-vault.sh tree-of "$work/lying.tar.gz" 2> /dev/null || true)"
      if [ -z "$got" ] || [ "$got" = "$tree" ]; then
        problem scripts/upstream-web-vault.sh "tree-of must give another tree for a tar that lies about its commit (got: ${got:-nothing})"
      fi
    fi
  fi
  printf 'not a tar' | gzip -n > "$work/not-tar.tar.gz"
  upstream_fails "not an archive" tree-of "$work/not-tar.tar.gz"
  upstream_fails "cannot read" tree-of "$work/absent.tar.gz"
  upstream_fails "usage" tree-of

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
    jobs = (doc["jobs"] || {}).values.select { |j| j.is_a?(Hash) }
    puts "must not run twice at once (no concurrency group)" unless doc.key?("concurrency") || jobs.any? { |j| j.key?("concurrency") }
    jobs.flat_map { |j| j["steps"] || [] }.each do |step|
      next unless step.is_a?(Hash) && step["uses"].to_s.start_with?("actions/checkout@")
      puts "must not keep the token in .git/config (checkout needs persist-credentials: false)" unless (step["with"] || {})["persist-credentials"] == false
    end
  ' "$file" 2>&1)"
  while IFS= read -r line; do
    [ -n "$line" ] && problem "$file" "$line"
  done <<EOF
$report
EOF
  if grep -qE 'commits/[$]' "$file"; then
    problem "$file" "asks the API for a commit by a bare name: use commits/refs/tags/NAME (a branch of the same name answers too)"
  fi
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

expect_problem "no concurrency group" check_update_workflow tests/fixtures/upstream/update-no-concurrency.yml
expect_problem "persist-credentials: false" check_update_workflow tests/fixtures/upstream/update-persists-credentials.yml
expect_problem "by a bare name" check_update_workflow tests/fixtures/upstream/update-bare-tag.yml

if [ -f .github/workflows/update.yml ]; then
  check_update_workflow .github/workflows/update.yml
  check_dispatch_targets .github/workflows/update.yml
else
  problem .github/workflows/update.yml "file is missing"
fi
