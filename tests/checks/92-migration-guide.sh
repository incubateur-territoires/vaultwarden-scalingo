#!/usr/bin/env bash
# Rules for docs/migrate-existing-instance.md. check_guide is proven on
# tests/fixtures/migration-guide/* and on copies of the real guide with one
# line removed or changed, then run on the guide itself. Bash 3.2, no network.
#
# Each data table below has one entry per line, and the lines of one heading are
# kept together (a section is read once per run, not once per line). The
# separator between a heading and its text is "@@": it cannot occur in either.

GUIDE=docs/migrate-existing-instance.md
GUIDE_TITLE="# Migrate an existing instance to Scalingo"
GUIDE_ASK="## What to ask your hosting provider"
# One heading per line, in the order the guide must have them (title first). A
# task requires only the headings it writes. "###" headings not listed are allowed.
GUIDE_HEADINGS="# Migrate an existing instance to Scalingo
## Before you start
## What to ask your hosting provider
## If the provider gives you nothing
## Check the versions"

# "heading@@text": the section must contain the text, as a fixed string.
read -r -d "" GUIDE_NEEDLES <<'EOF'
## Before you start@@accounts, vaults, organisations, attachments, Sends and two-factor setups
## Before you start@@the `DOMAIN` setting, the signing key `rsa_key.pem`, and the data
## Before you start@@has not been robustly tested
## Before you start@@are your acts
## Before you start@@(#check-the-versions)
## What to ask your hosting provider@@A new signing key is created silently at the first start. Every device and web session is logged out once, and open invitations stop working. The data is intact.
## What to ask your hosting provider@@Send nothing by email unencrypted
## What to ask your hosting provider@@The database copy and `rsa_key.pem` are secrets
## What to ask your hosting provider@@Delete these copies after the cutover.
## What to ask your hosting provider@@`icon_cache/`: cached site icons
## What to ask your hosting provider@@`tmp/`: Vaultwarden's temporary files
## What to ask your hosting provider@@`db.sqlite3-shm`: the wiki says
## What to ask your hosting provider@@The source's `ADMIN_TOKEN`
## What to ask your hosting provider@@https://github.com/dani-garcia/vaultwarden/wiki/Backing-up-your-vault
## What to ask your hosting provider@@https://www.sqlite.org/cli.html
## What to ask your hosting provider@@https://www.postgresql.org/docs/current/app-pgdump.html
## What to ask your hosting provider@@https://mariadb.com/kb/en/mysqldump/
## What to ask your hosting provider@@https://github.com/dani-garcia/vaultwarden/blob/1.37.5/src/auth.rs
## What to ask your hosting provider@@https://github.com/dani-garcia/vaultwarden/blob/1.37.5/src/config.rs
## What to ask your hosting provider@@it is ignored with `--format=custom`
## What to ask your hosting provider@@do not rehearse or cut over until the provider gives the version
## What to ask your hosting provider@@Missing: nothing can be migrated
## If the provider gives you nothing@@https://bitwarden.com/help/export-your-data/
## If the provider gives you nothing@@password protected
## If the provider gives you nothing@@delete it immediately after use
## If the provider gives you nothing@@.zip (with attachments)
## If the provider gives you nothing@@Each organisation owner exports the organisation separately
## If the provider gives you nothing@@does not promise that an attachments zip imports
## If the provider gives you nothing@@Sends and the trash
## If the provider gives you nothing@@The structure of an organisation
## If the provider gives you nothing@@Attachments, unless the zip format is used
## If the provider gives you nothing@@Two-factor setups
## If the provider gives you nothing@@Logged-in devices
## If the provider gives you nothing@@Account recovery and emergency access
## Check the versions@@The target must not be older than the source.
## Check the versions@@the `VAULTWARDEN_VERSION` line of
## Check the versions@@the line `Starting Vaultwarden <version>` in your app's logs is the one that counts
## Check the versions@@Do not edit `VERSIONS` yourself.
## Check the versions@@Same version: go on.
## Check the versions@@The target is newer: for a PostgreSQL source this is fine
## Check the versions@@Version unknown, or newer than the target: stop.
## Check the versions@@The rule is derived from that: upstream does not state it.
## Check the versions@@that is our inference, not stated upstream
EOF

# Only the quoted lines (">") of the ask section: what the operator sends. One
# fixed string per line: the items of the message and of its "not needed" line.
read -r -d "" GUIDE_MESSAGE_NEEDLES <<'EOF'
The Vaultwarden version we run
SQLite, PostgreSQL or MySQL/MariaDB, with the database server version
sqlite3 <database file> ".backup '<new file>'"
pg_dump --format=custom --no-privileges <database>
`mysqldump`
every file whose name starts with `rsa_key`
the folder `attachments/`
the folder `sends/`
the file `config.json`, if it exists
`RSA_KEY_FILENAME`, `ATTACHMENTS_FOLDER` or `SENDS_FOLDER`: their values
S3 bucket (then the bucket name and the prefix)
the `DOMAIN` setting
mail server (host, port, sender; not the password)
signups, invitations, emergency access, push notifications, Duo or Yubico
stop it, do not delete it
at least 30 days
the folders `icon_cache/` and `tmp/`
the file `db.sqlite3-shm`
the admin token
EOF

# "heading@@cell": the section must have a table row whose first cell is the cell.
read -r -d "" GUIDE_ROWS <<'EOF'
## What to ask your hosting provider@@Database copy
## What to ask your hosting provider@@rsa_key files
## What to ask your hosting provider@@attachments/
## What to ask your hosting provider@@sends/
## What to ask your hosting provider@@config.json
## What to ask your hosting provider@@Vaultwarden version
## What to ask your hosting provider@@Same DOMAIN
EOF

# guide_section FILE HEADING: the lines under HEADING (the whole line, "## X" or
# "### X"). A "##" section runs to the next "## "; a "###" section to the next
# "## " or "### ".
guide_section() {
  awk -v want="$2" '
    $0 == want { inside = 1; next }
    /^## / { inside = 0 }
    /^### / && want ~ /^### / { inside = 0 }
    inside { print }
  ' "$1"
}

# guide_table_rule FILE KIND TABLE: apply one rule to each "heading@@text" line
# of TABLE. KIND is "contains" (a fixed string anywhere in the section) or "row"
# (a table row whose first cell is the text). The section, and for "row" its
# first cells, are read once per heading, not once per line.
guide_table_rule() {
  local file="$1" kind="$2" line heading text last="" section="" cells="" nl
  nl="
"
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    heading="${line%%@@*}"
    text="${line#*@@}"
    if [ "$heading" != "$last" ]; then
      section="$(guide_section "$file" "$heading")"
      last="$heading"
      if [ "$kind" = "row" ]; then
        cells="$(printf '%s\n' "$section" | awk -F'|' '
          /^\|/ { c = $2; gsub(/^ +| +$/, "", c); print c }
        ')"
      fi
    fi
    if [ "$kind" = "row" ]; then
      case "$nl$cells$nl" in
        *"$nl$text$nl"*) ;;
        *) problem "$file" "$heading needs a table row starting with '$text'" ;;
      esac
    else
      case "$section" in
        *"$text"*) ;;
        *) problem "$file" "$heading must contain: $text" ;;
      esac
    fi
  done <<EOF
$3
EOF
}

# guide_message_rule FILE TABLE: each line of TABLE must be in the quoted lines
# (">") of the ask section: what the operator sends.
guide_message_rule() {
  local message line
  message="$(guide_section "$1" "$GUIDE_ASK" | grep '^>')"
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    case "$message" in
      *"$line"*) ;;
      *) problem "$1" "the quoted message in $GUIDE_ASK must contain: $line" ;;
    esac
  done <<EOF
$2
EOF
}

# check_guide FILE: report each rule the guide breaks.
check_guide() {
  local file="$1" heading present="" found="" nl line target
  nl="
"
  if [ ! -f "$file" ]; then
    problem "$file" "file is missing"
    return
  fi
  if [ "$(head -n 1 "$file")" != "$GUIDE_TITLE" ]; then
    problem "$file" "first line must be '$GUIDE_TITLE'"
  fi

  # The required headings the file has, in the required order.
  while IFS= read -r heading; do
    if grep -qxF -- "$heading" "$file"; then
      present="${present:+$present$nl}$heading"
    else
      problem "$file" "missing heading: $heading"
    fi
  done <<EOF
$GUIDE_HEADINGS
EOF
  # The same headings, in the order the file has them.
  while IFS= read -r heading; do
    case "$nl$present$nl" in
      *"$nl$heading$nl"*) found="${found:+$found$nl}$heading" ;;
    esac
  done <<EOF
$(grep -E '^#{1,3} ' "$file")
EOF
  if [ "$found" != "$present" ]; then
    problem "$file" "headings out of order: expected ${present//$nl/, }"
  fi

  guide_table_rule "$file" contains "$GUIDE_NEEDLES"
  guide_table_rule "$file" row "$GUIDE_ROWS"
  guide_message_rule "$file" "$GUIDE_MESSAGE_NEEDLES"

  # Relative links must name a file that exists, relative to the guide.
  while IFS= read -r line; do
    target="${line#\](}"
    target="${target%)}"
    case "$target" in
      http://* | https://* | mailto:* | "#"*) continue ;;
    esac
    target="${target%%#*}"
    if [ ! -e "$(dirname "$file")/$target" ]; then
      problem "$file" "relative link does not resolve: $target"
    fi
  done <<EOF
$(grep -o '](\([^)]*\))' "$file")
EOF
}

expect_problem "file is missing" check_guide tests/fixtures/migration-guide/missing.md
expect_problem "headings out of order" check_guide tests/fixtures/migration-guide/wrong-order.md
expect_problem "relative link does not resolve" check_guide tests/fixtures/migration-guide/dangling-link.md

# The mutants are the real guide edited, in a scratch tree that holds links to
# the repository's files and its own docs/. A relative link of the real guide
# then resolves in an unmodified copy, so only the edit can make a rule report.
MUT_ROOT=""
MUT_GUIDE=""
make_mutant_tree() {
  local entry
  MUT_ROOT="$(mktemp -d)"
  for entry in ./*; do
    if [ -e "$entry" ] && [ "$entry" != ./docs ]; then
      ln -s "$PWD/${entry#./}" "$MUT_ROOT/${entry#./}"
    fi
  done
  mkdir "$MUT_ROOT/docs"
  for entry in docs/*; do
    if [ -e "$entry" ]; then
      ln -s "$PWD/$entry" "$MUT_ROOT/$entry"
    fi
  done
  rm -f "$MUT_ROOT/$GUIDE"
  MUT_GUIDE="$MUT_ROOT/$GUIDE"
}

# expect_guide_mutant RULE SED_SCRIPT: the real guide, edited by SED_SCRIPT,
# must report RULE.
expect_guide_mutant() {
  sed -e "$2" "$GUIDE" > "$MUT_GUIDE"
  expect_problem "$1" check_guide "$MUT_GUIDE"
}

# guide_entry KIND LINE FILE: one entry of a table, alone (KIND: contains, row
# or message), so that a mutant per entry runs one rule, not the whole guide.
guide_entry() {
  case "$1" in
    message) guide_message_rule "$3" "$2" ;;
    *) guide_table_rule "$3" "$1" "$2" ;;
  esac
}

# guide_mutant_each KIND TABLE SCOPE: every entry of TABLE is enforced: the real
# guide with that text replaced (SCOPE "quoted": on the quoted lines only;
# "row": on the table lines only; "": everywhere) must report the entry. The
# wiring of each table into check_guide is proven by the named mutants above it.
guide_mutant_each() {
  local kind="$1" table="$2" scope="$3" line text
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    text="${line#*@@}"
    awk -v n="$text" -v scope="$scope" '
      scope == "" || (scope == "quoted" && /^>/) || (scope == "row" && /^\|/) {
        out = ""
        while ((i = index($0, n)) > 0) {
          out = out substr($0, 1, i - 1) "@@GONE@@"
          $0 = substr($0, i + length(n))
        }
        $0 = out $0
      }
      { print }
    ' "$GUIDE" > "$MUT_GUIDE"
    if [ "$kind" = "row" ]; then
      expect_problem "needs a table row starting with '$text'" guide_entry "$kind" "$line" "$MUT_GUIDE"
    else
      expect_problem "must contain: $text" guide_entry "$kind" "$line" "$MUT_GUIDE"
    fi
  done <<EOF
$table
EOF
}

if [ -f "$GUIDE" ]; then
  make_mutant_tree
  # The tree itself: an unmodified copy reports nothing. Without this, every
  # mutant below could pass on a broken link of the copy, whatever its edit.
  cp "$GUIDE" "$MUT_GUIDE"
  expect_no_problem check_guide "$MUT_GUIDE"

  expect_guide_mutant "first line must be" '\%^# Migrate an existing instance to Scalingo$%d'
  expect_guide_mutant "missing heading: ## If the provider gives you nothing" '\%^## If the provider gives you nothing$%d'
  expect_guide_mutant "missing heading: ## Check the versions" '\%^## Check the versions$%d'
  expect_guide_mutant "## Before you start must contain: has not been robustly tested" 's/has not been robustly tested/is not robustly tested/'
  expect_guide_mutant "must contain: The database copy and \`rsa_key.pem\` are secrets" '\%The database copy and .rsa_key.pem. are secrets%d'
  expect_guide_mutant "must contain: Send nothing by email unencrypted" '\%Send nothing by email unencrypted%d'
  expect_guide_mutant "must contain: Delete these copies after the cutover." '\%Delete these copies after the cutover%d'
  expect_guide_mutant "must contain: The source's \`ADMIN_TOKEN\`" '\%^- The source.s .ADMIN_TOKEN.%d'
  expect_guide_mutant "must contain: A new signing key is created silently" 's/created silently/created/'
  expect_guide_mutant "must contain: https://www.sqlite.org/cli.html" 's%https://www.sqlite.org/cli.html%https://example.org/cli.html%'
  expect_guide_mutant "## If the provider gives you nothing must contain: Sends and the trash" '\%^- Sends and the trash%d'
  expect_guide_mutant "must contain: Two-factor setups" '\%^- Two-factor setups%d'
  expect_guide_mutant "## Check the versions must contain: Same version: go on." '\%^- Same version: go on%d'
  expect_guide_mutant "must contain: the line \`Starting Vaultwarden <version>\` in your app's logs" 's/Starting Vaultwarden <version>/Starting Vaultwarden/'
  # A needle of the message, deleted from the quote; and the same text left
  # outside the quote, which must still report: only quoted lines are read.
  expect_guide_mutant "must contain: the folder \`sends/\`" '\%^> .*the folder .sends/.%d'
  expect_guide_mutant "must contain: the folder \`sends/\`" 's%^> \(.*the folder .sends/.\)%\1%'
  expect_guide_mutant "must contain: pg_dump --format=custom" '\%^> .*pg_dump --format=custom%d'
  expect_guide_mutant "must contain: the admin token" 's/, the admin token//'
  expect_guide_mutant "needs a table row starting with 'sends/'" '\%^| sends/ |%d'
  expect_guide_mutant "needs a table row starting with 'Same DOMAIN'" '\%^| Same DOMAIN |%d'
  # The rule on a missing version is STOP, not "the rehearsal is the only check".
  expect_guide_mutant "must contain: do not rehearse or cut over until the provider gives the version" 's/do not rehearse or cut over/the rehearsal is then the only check/'
  # The mutants above live in a tree where ../README.md exists: this one breaks it.
  expect_guide_mutant "relative link does not resolve" 's%(\.\./README\.md#upgrade)%(../NO-SUCH-FILE.md#upgrade)%'

  guide_mutant_each contains "$GUIDE_NEEDLES" ""
  guide_mutant_each message "$GUIDE_MESSAGE_NEEDLES" "quoted"
  guide_mutant_each row "$GUIDE_ROWS" "row"

  if [ -n "$MUT_ROOT" ]; then
    rm -rf "$MUT_ROOT"
  fi
fi
check_guide "$GUIDE"
