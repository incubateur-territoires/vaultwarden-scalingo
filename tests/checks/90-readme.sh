#!/usr/bin/env bash
# Rules for README.md. check_readme is proven on tests/fixtures/readme/* and on
# copies of the real README with one line removed, then run on README.md.

README_TITLE="# Deploy Vaultwarden on Scalingo"
README_BUTTON="https://my.scalingo.com/deploy?source=https://github.com/incubateur-territoires/vaultwarden-scalingo"
README_BADGE="https://cdn.scalingo.com/deploy/button.svg"
README_SENTENCE="Vaultwarden is an unofficial, lightweight server compatible with Bitwarden clients."
README_SECURITY="Keep this instance up to date: Vaultwarden publishes security fixes regularly."
# One heading per line, in the order the README must have them.
README_HEADINGS="Before you deploy
One-click deployment
Storage
First admin and users
Connect a Bitwarden client
Upgrade
Backups
Optional settings
Troubleshooting
Security"
README_OPTIONAL="SMTP_HOST SMTP_FROM SMTP_PORT SMTP_USERNAME SMTP_PASSWORD DATABASE_MAX_CONNS"
# Each symptom is the start of the first cell of a row of the Troubleshooting table.
README_SYMPTOMS="Bucket unreachable
Wrong credentials
Wrong endpoint
NO DATABASE_URL FOUND
DOMAIN
VERSIONS pins no release yet
Could not download
Checksum mismatch
The Vaultwarden binary does not run on stack"
# What the Upgrade section must give, in this order: the backup, the deploy, the rollback.
README_BACKUP_CMD="backups-create"
README_DEPLOY_CMD="archive/refs/heads/main.tar.gz"
README_ROLLBACK_CMD="archive/<previous-commit>.tar.gz"
# How the operator learns whether a migration ran, and which commit to roll back to.
README_MIGRATION_QUERY="SELECT count(*) FROM __diesel_schema_migrations;"
README_PREVIOUS_COMMIT="--grep='chore(release): deploy'"

# readme_section FILE HEADING: the lines under "## HEADING", up to the next "## ".
readme_section() {
  awk -v want="## $2" '
    /^## / { inside = ($0 == want); next }
    inside { print }
  ' "$1"
}

# check_readme FILE: report each rule the README breaks.
check_readme() {
  local file="$1" heading name symptom present="" found="" section backup_at deploy_at
  if [ ! -f "$file" ]; then
    problem "$file" "file is missing"
    return
  fi
  if [ "$(head -n 1 "$file")" != "$README_TITLE" ]; then
    problem "$file" "first line must be '$README_TITLE'"
  fi
  grep -qF -- "($README_BADGE)]($README_BUTTON)" "$file" ||
    problem "$file" "deploy button must link to $README_BUTTON, with the badge image $README_BADGE"
  grep -qF -- "$README_SENTENCE" "$file" ||
    problem "$file" "sentence missing: $README_SENTENCE"
  case "$(readme_section "$file" "Security")" in
    *"$README_SECURITY"*) ;;
    *) problem "$file" "security sentence missing under ## Security: $README_SECURITY" ;;
  esac

  # The required headings the file has, in the required order.
  while IFS= read -r heading; do
    if grep -qxF -- "## $heading" "$file"; then
      present="${present:+$present, }$heading"
    else
      problem "$file" "missing heading: ## $heading"
    fi
  done <<EOF
$README_HEADINGS
EOF
  # The same headings, in the order the file has them.
  while IFS= read -r heading; do
    case ", $present, " in
      *", ${heading#"## "}, "*) found="${found:+$found, }${heading#"## "}" ;;
    esac
  done <<EOF
$(grep '^## ' "$file")
EOF
  if [ "$found" != "$present" ]; then
    problem "$file" "headings out of order: expected $present"
  fi

  section="$(readme_section "$file" "Optional settings")"
  for name in $README_OPTIONAL; do
    case "$section" in
      *"$name"*) ;;
      *) problem "$file" "Optional settings must name $name" ;;
    esac
  done

  section="$(readme_section "$file" "Upgrade")"
  backup_at="$(printf '%s\n' "$section" | grep -nF -- "$README_BACKUP_CMD" | head -n 1 | cut -d : -f 1)"
  deploy_at="$(printf '%s\n' "$section" | grep -nF -- "$README_DEPLOY_CMD" | head -n 1 | cut -d : -f 1)"
  if [ -z "$backup_at" ]; then
    problem "$file" "Upgrade must give the backup command ($README_BACKUP_CMD)"
  fi
  if [ -z "$deploy_at" ]; then
    problem "$file" "Upgrade must give the deploy command (a URL ending $README_DEPLOY_CMD)"
  fi
  if [ -n "$backup_at" ] && [ -n "$deploy_at" ] && [ "$backup_at" -gt "$deploy_at" ]; then
    problem "$file" "Upgrade must give the backup command before the deploy command"
  fi
  case "$section" in
    *"$README_ROLLBACK_CMD"*) ;;
    *) problem "$file" "Upgrade must give the rollback command (a URL ending $README_ROLLBACK_CMD)" ;;
  esac
  case "$section" in
    *"$README_MIGRATION_QUERY"*) ;;
    *) problem "$file" "Upgrade must give the migration count query ($README_MIGRATION_QUERY)" ;;
  esac
  case "$section" in
    *"$README_PREVIOUS_COMMIT"*) ;;
    *) problem "$file" "Upgrade must say how to find the previous commit ($README_PREVIOUS_COMMIT)" ;;
  esac

  section="$(readme_section "$file" "Troubleshooting")"
  while IFS= read -r symptom; do
    if ! printf '%s\n' "$section" | grep -qE "^\\| *$symptom"; then
      problem "$file" "Troubleshooting needs a table row starting with '$symptom'"
    fi
  done <<EOF
$README_SYMPTOMS
EOF
}

expect_problem "missing heading: ## Backups" check_readme tests/fixtures/readme/missing-heading.md
expect_problem "headings out of order" check_readme tests/fixtures/readme/wrong-order.md
expect_problem "deploy button must link to" check_readme tests/fixtures/readme/missing-button.md
expect_problem "deploy button must link to" check_readme tests/fixtures/readme/button-without-badge.md
expect_problem "security sentence missing" check_readme tests/fixtures/readme/misplaced-security.md
expect_problem "Upgrade must give the backup command" check_readme tests/fixtures/readme/upgrade-without-backup.md
expect_problem "before the deploy command" check_readme tests/fixtures/readme/upgrade-backup-after-deploy.md

# expect_mutant_problem RULE PATTERN: README.md without the lines matching
# PATTERN (sed syntax, no %) must report RULE.
expect_mutant_problem() {
  local copy
  copy="$(mktemp)"
  sed "\\%$2%d" README.md > "$copy"
  expect_problem "$1" check_readme "$copy"
  rm -f "$copy"
}

if [ -f README.md ]; then
  expect_mutant_problem "first line must be" '^# Deploy Vaultwarden on Scalingo$'
  expect_mutant_problem "sentence missing: Vaultwarden is" 'unofficial, lightweight server'
  expect_mutant_problem "security sentence missing" 'Keep this instance up to date'
  expect_mutant_problem "Optional settings must name SMTP_PORT" 'SMTP_PORT'
  expect_mutant_problem "starting with 'Wrong credentials'" '^| *Wrong credentials'
  expect_mutant_problem "starting with 'DOMAIN'" '^| *DOMAIN'
  expect_mutant_problem "Upgrade must give the backup command" 'backups-create'
  expect_mutant_problem "Upgrade must give the deploy command" 'archive/refs/heads/main'
  expect_mutant_problem "Upgrade must give the rollback command" 'archive/<previous-commit>'
  expect_mutant_problem "Upgrade must give the migration count query" 'SELECT count'
  expect_mutant_problem "Upgrade must say how to find the previous commit" "grep='chore(release): deploy'"
  expect_mutant_problem "deploy button must link to" 'cdn.scalingo.com/deploy/button.svg'
fi
check_readme README.md
