#!/usr/bin/env bash
# Tests of scripts/start.sh: the real script runs under `env -i` against a fake
# binary (tests/fixtures/start/home/vaultwarden) that records its environment.

START_HOME="$PWD/tests/fixtures/start/home"
START_DB='postgres://user:fixtureDbPass%21@db.example.com:5432/vw?sslmode=prefer&x=1'
START_KEY='AKIAFIXTUREKEY123'
START_SECRET='fixture/Secret+Key9'
START_ADMIN='fixtureAdminToken'
START_SECRETS="fixtureDbPass% $START_KEY $START_SECRET $START_ADMIN"
START_BASE="PORT=8080
DATABASE_URL=$START_DB
DOMAIN=https://vault.example.com
S3_BUCKET=my-bucket
S3_ENDPOINT=https://s3.fr-par.scw.cloud
S3_REGION=fr-par
AWS_ACCESS_KEY_ID=$START_KEY
AWS_SECRET_ACCESS_KEY=$START_SECRET
ADMIN_TOKEN=$START_ADMIN"
START_DATA="s3://my-bucket/vaultwarden?endpoint=https://s3.fr-par.scw.cloud&region=fr-par&enable_virtual_host_style="
START_PFX=" !     "
START_S3_MSG="is not set. Vaultwarden needs an S3 bucket because Scalingo's disk is erased at every restart. See the README, section 'Storage'."
START_NODB="${START_PFX}NO DATABASE_URL FOUND! Please provision a PostgreSQL addon."
START_NODOMAIN="${START_PFX}DOMAIN is not set. Set it to the public HTTPS address of this app, for example https://my-vault.osc-fr1.scalingo.io"

# start_run LABEL [NAME=value | -NAME]...: run start.sh under `env -i` with the
# base environment changed by the arguments (START_SCRIPT names another script,
# for the self-tests only). Sets START_OUT, START_ERR,
# START_RC, START_DIR and START_ENV (the file the fake binary wrote, absent
# when it did not run). Records a problem when any secret is printed.
start_run() {
  START_LABEL="$1"
  shift
  local dir line name arg skip secret
  local envs=()
  dir="$(mktemp -d)"
  while IFS= read -r line; do
    name="${line%%=*}"
    skip=""
    for arg; do
      case "$arg" in "$name="* | "-$name") skip=1 ;; esac
    done
    [ -n "$skip" ] || envs[${#envs[@]}]="$line"
  done <<EOF
$START_BASE
EOF
  for arg; do
    case "$arg" in -*) ;; *) envs[${#envs[@]}]="$arg" ;; esac
  done
  env -i PATH=/usr/bin:/bin VAULTWARDEN_HOME="$START_HOME" FAKE_ENV_OUT="$dir/env" \
    "${envs[@]}" "${START_SCRIPT:-scripts/start.sh}" > "$dir/out" 2> "$dir/err"
  START_RC=$?
  START_OUT="$(cat "$dir/out")"
  START_ERR="$(cat "$dir/err")"
  START_ENV="$dir/env"
  START_DIR="$dir"
  for secret in $START_SECRETS; do
    case "$START_OUT$START_ERR" in
      *"$secret"*) problem scripts/start.sh "must never print a secret ($START_LABEL)" ;;
    esac
  done
}

# start_leak_selftest SCRIPT: run a script that prints a secret through
# start_run, which must record a problem.
start_leak_selftest() {
  START_SCRIPT="$1" start_run "self-test"
  start_clean
}

# start_clean: remove the files of the last start_run.
start_clean() {
  rm -rf "$START_DIR"
}

# start_get NAME: the value of NAME in the environment the fake binary got.
start_get() {
  grep "^$1=" "$START_ENV" 2> /dev/null | head -n 1 | cut -d = -f 2-
}

# start_eq RULE GOT WANT: a problem unless GOT equals WANT.
start_eq() {
  if [ "$2" != "$3" ]; then
    problem scripts/start.sh "$1 ($START_LABEL: got '$2', want '$3')"
  fi
}

# start_ok LABEL RULE [NAME=value | -NAME]...: run, and require a start (exit 0, binary ran).
start_ok() {
  local label="$1" rule="$2"
  shift 2
  start_run "$label" "$@"
  if [ "$START_RC" -ne 0 ] || [ ! -f "$START_ENV" ]; then
    problem scripts/start.sh "$rule: must start (rc=$START_RC, err='$START_ERR')"
  fi
}

# start_fail LABEL WANT_STDERR [NAME=value | -NAME]...: run, and require a refusal.
start_fail() {
  local label="$1" want="$2"
  shift 2
  start_run "$label" "$@"
  if [ "$START_RC" -eq 0 ]; then
    problem scripts/start.sh "must exit non-zero ($START_LABEL)"
  fi
  if [ -f "$START_ENV" ]; then
    problem scripts/start.sh "must not start Vaultwarden ($START_LABEL)"
  fi
  start_eq "must report exactly the expected messages on stderr" "$START_ERR" "$want"
  start_eq "must print nothing on stdout when refusing" "$START_OUT" ""
  start_clean
}

# start_no_admin_token LABEL RULE: the last run must not have passed ADMIN_TOKEN.
start_no_admin_token() {
  if grep -q '^ADMIN_TOKEN=' "$START_ENV" 2> /dev/null; then
    problem scripts/start.sh "$2 ($1)"
  fi
}

# --- Procfile
if ! grep -qE '^web:[[:space:]]+scripts/start\.sh[[:space:]]*$' Procfile 2> /dev/null; then
  problem Procfile "must have a 'web: scripts/start.sh' entry"
fi
if [ ! -x scripts/start.sh ]; then
  problem scripts/start.sh "must be executable"
fi

# --- complete environment
start_ok "complete" "complete environment"
start_eq "exit status" "$START_RC" "0"
start_eq "ROCKET_PORT must equal PORT" "$(start_get ROCKET_PORT)" "8080"
start_eq "ROCKET_ADDRESS must be 0.0.0.0" "$(start_get ROCKET_ADDRESS)" "0.0.0.0"
start_eq "DATABASE_URL must be passed untouched" "$(start_get DATABASE_URL)" "$START_DB"
start_eq "DATA_FOLDER must be the S3 URI (virtual host style)" "$(start_get DATA_FOLDER)" "${START_DATA}true"
start_eq "DATABASE_MAX_CONNS must default to 5" "$(start_get DATABASE_MAX_CONNS)" "5"
start_eq "WEB_VAULT_FOLDER must be under VAULTWARDEN_HOME" "$(start_get WEB_VAULT_FOLDER)" "$START_HOME/web-vault"
start_eq "WEB_VAULT_ENABLED must default to true" "$(start_get WEB_VAULT_ENABLED)" "true"
start_eq "TMP_FOLDER must default to /tmp/vaultwarden" "$(start_get TMP_FOLDER)" "/tmp/vaultwarden"
start_eq "TEMPLATES_FOLDER must be under VAULTWARDEN_HOME" "$(start_get TEMPLATES_FOLDER)" "$START_HOME/templates"
start_eq "ADMIN_TOKEN must be passed through" "$(start_get ADMIN_TOKEN)" "$START_ADMIN"
start_eq "success line must be exact" "$START_OUT" "-----> Starting Vaultwarden 1.37.5 (attachments, Sends and keys stored in s3://my-bucket)"
start_eq "nothing may be written on stderr" "$START_ERR" ""
case "$(start_get DATA_FOLDER)" in
  *"$START_KEY"* | *"$START_SECRET"*) problem scripts/start.sh "DATA_FOLDER must not contain the S3 credentials" ;;
esac
start_clean

# --- variants
start_ok "path style" "S3_PATH_STYLE=true" S3_PATH_STYLE=true
start_eq "S3_PATH_STYLE=true must turn virtual host style off" "$(start_get DATA_FOLDER)" "${START_DATA}false"
start_clean
start_ok "path style upper" "S3_PATH_STYLE=TRUE" S3_PATH_STYLE=TRUE
start_eq "S3_PATH_STYLE is case-insensitive" "$(start_get DATA_FOLDER)" "${START_DATA}false"
start_clean
start_ok "path style false" "S3_PATH_STYLE=false" S3_PATH_STYLE=false
start_eq "S3_PATH_STYLE=false must keep virtual host style" "$(start_get DATA_FOLDER)" "${START_DATA}true"
start_clean
start_ok "forced values" "forced values" ROCKET_ADDRESS=127.0.0.1 ROCKET_PORT=1 DATA_FOLDER=/data
start_eq "ROCKET_ADDRESS is forced" "$(start_get ROCKET_ADDRESS)" "0.0.0.0"
start_eq "ROCKET_PORT is forced" "$(start_get ROCKET_PORT)" "8080"
start_eq "DATA_FOLDER is forced" "$(start_get DATA_FOLDER)" "${START_DATA}true"
start_clean
start_ok "overrides" "operator overrides" DATABASE_MAX_CONNS=3 TMPDIR=/var/tmp
start_eq "DATABASE_MAX_CONNS must be kept when set" "$(start_get DATABASE_MAX_CONNS)" "3"
start_eq "TMP_FOLDER must follow TMPDIR" "$(start_get TMP_FOLDER)" "/var/tmp/vaultwarden"
start_clean
start_ok "scalingo url" "SCALINGO_POSTGRESQL_URL fallback" -DATABASE_URL "SCALINGO_POSTGRESQL_URL=$START_DB"
start_eq "DATABASE_URL must fall back to SCALINGO_POSTGRESQL_URL" "$(start_get DATABASE_URL)" "$START_DB"
start_clean
start_ok "database url wins" "DATABASE_URL wins" "SCALINGO_POSTGRESQL_URL=postgres://other/db"
start_eq "DATABASE_URL must win over SCALINGO_POSTGRESQL_URL" "$(start_get DATABASE_URL)" "$START_DB"
start_clean
start_ok "empty admin token" "empty ADMIN_TOKEN" ADMIN_TOKEN=
start_no_admin_token "empty admin token" "an empty ADMIN_TOKEN must be removed from the environment"
start_clean
start_ok "no admin token" "absent ADMIN_TOKEN" -ADMIN_TOKEN
start_no_admin_token "no admin token" "an absent ADMIN_TOKEN must stay absent"
start_clean
start_ok "no port" "absent PORT" -PORT
start_eq "ROCKET_PORT must default to 8000 without PORT" "$(start_get ROCKET_PORT)" "8000"
start_clean
start_ok "no manifest" "absent manifest" "VAULTWARDEN_HOME=$START_HOME-no-manifest"
start_eq "an absent manifest must give version unknown" "$START_OUT" "-----> Starting Vaultwarden unknown (attachments, Sends and keys stored in s3://my-bucket)"
start_eq "an absent manifest must not write on stderr" "$START_ERR" ""
start_clean
start_ok "no version" "manifest without VAULTWARDEN_VERSION" "VAULTWARDEN_HOME=$START_HOME-no-version"
start_eq "a manifest without the version must give version unknown" "$START_OUT" "-----> Starting Vaultwarden unknown (attachments, Sends and keys stored in s3://my-bucket)"
start_eq "a manifest without the version must not write on stderr" "$START_ERR" ""
start_clean

# --- the secret rule rejects a script that prints a secret (stdout, stderr)
expect_problem "must never print a secret" start_leak_selftest tests/fixtures/start/leaky/stdout.sh
expect_problem "must never print a secret" start_leak_selftest tests/fixtures/start/leaky/stderr.sh

# --- fail early
start_fail "no database" "$START_NODB" -DATABASE_URL
start_fail "empty database" "$START_NODB" DATABASE_URL=
start_fail "no domain" "$START_NODOMAIN" -DOMAIN
start_fail "http domain" "${START_PFX}DOMAIN must start with https:// (got: http://vault.example.com)." DOMAIN=http://vault.example.com
start_fail "bare domain" "${START_PFX}DOMAIN must start with https:// (got: vault.example.com)." DOMAIN=vault.example.com
for start_name in S3_BUCKET S3_ENDPOINT S3_REGION AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY; do
  start_fail "no $start_name" "${START_PFX}$start_name $START_S3_MSG" "-$start_name"
  start_fail "empty $start_name" "${START_PFX}$start_name $START_S3_MSG" "$start_name="
done
start_fail "all S3 missing" "${START_PFX}S3_BUCKET $START_S3_MSG
${START_PFX}S3_ENDPOINT $START_S3_MSG
${START_PFX}S3_REGION $START_S3_MSG
${START_PFX}AWS_ACCESS_KEY_ID $START_S3_MSG
${START_PFX}AWS_SECRET_ACCESS_KEY $START_S3_MSG" -S3_BUCKET -S3_ENDPOINT -S3_REGION -AWS_ACCESS_KEY_ID -AWS_SECRET_ACCESS_KEY
start_fail "everything wrong" "$START_NODB
${START_PFX}DOMAIN must start with https:// (got: http://x).
${START_PFX}S3_REGION $START_S3_MSG
${START_PFX}AWS_SECRET_ACCESS_KEY $START_S3_MSG" -DATABASE_URL DOMAIN=http://x -S3_REGION -AWS_SECRET_ACCESS_KEY
unset start_name
