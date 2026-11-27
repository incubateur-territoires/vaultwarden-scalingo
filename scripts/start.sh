#!/usr/bin/env bash
# Scalingo `web` process: check the environment, derive what Vaultwarden needs
# from the platform variables, then start the binary. Nothing here prints
# DATABASE_URL, AWS_* or ADMIN_TOKEN.
set -eu

APP_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VAULTWARDEN_HOME="${VAULTWARDEN_HOME:-$APP_ROOT/vaultwarden}"

# shellcheck source=scripts/lib/kv.sh
. "$APP_ROOT/scripts/lib/kv.sh"

DATABASE_URL="${DATABASE_URL:-${SCALINGO_POSTGRESQL_URL:-}}"

# Validation: every problem is reported, then nothing starts.
problems=0
fail() {
  echo " !     $*" >&2
  problems=$((problems + 1))
}

if [ -z "$DATABASE_URL" ]; then
  fail "NO DATABASE_URL FOUND! Please provision a PostgreSQL addon."
fi

DOMAIN="${DOMAIN:-}"
case "$DOMAIN" in
  "")
    fail "DOMAIN is not set. Set it to the public HTTPS address of this app, for example https://my-vault.osc-fr1.scalingo.io"
    ;;
  https://*) ;;
  *)
    fail "DOMAIN must start with https:// (got: $DOMAIN)."
    ;;
esac

S3_BUCKET="${S3_BUCKET:-}"
S3_ENDPOINT="${S3_ENDPOINT:-}"
S3_REGION="${S3_REGION:-}"
AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID:-}"
AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY:-}"
[ -n "$S3_BUCKET" ] || fail "S3_BUCKET is not set. Vaultwarden needs an S3 bucket because Scalingo's disk is erased at every restart. See the README, section 'Storage'."
[ -n "$S3_ENDPOINT" ] || fail "S3_ENDPOINT is not set. Vaultwarden needs an S3 bucket because Scalingo's disk is erased at every restart. See the README, section 'Storage'."
[ -n "$S3_REGION" ] || fail "S3_REGION is not set. Vaultwarden needs an S3 bucket because Scalingo's disk is erased at every restart. See the README, section 'Storage'."
[ -n "$AWS_ACCESS_KEY_ID" ] || fail "AWS_ACCESS_KEY_ID is not set. Vaultwarden needs an S3 bucket because Scalingo's disk is erased at every restart. See the README, section 'Storage'."
[ -n "$AWS_SECRET_ACCESS_KEY" ] || fail "AWS_SECRET_ACCESS_KEY is not set. Vaultwarden needs an S3 bucket because Scalingo's disk is erased at every restart. See the README, section 'Storage'."

if [ "$problems" -gt 0 ]; then
  exit 1
fi

# Path-style providers need virtual host style off. The credentials stay in
# AWS_* (the standard chain), never in the URI.
virtual_host_style=true
if [ "$(printf '%s' "${S3_PATH_STYLE:-}" | tr '[:upper:]' '[:lower:]')" = "true" ]; then
  virtual_host_style=false
fi

# Forced: what the platform and the storage design require.
export DATABASE_URL
export ROCKET_ADDRESS=0.0.0.0
export ROCKET_PORT="${PORT:-8000}"
export DATA_FOLDER="s3://$S3_BUCKET/vaultwarden?endpoint=$S3_ENDPOINT&region=$S3_REGION&enable_virtual_host_style=$virtual_host_style"

# Defaults the operator may override. Temporary files and templates stay local.
export DATABASE_MAX_CONNS="${DATABASE_MAX_CONNS:-5}"
export WEB_VAULT_ENABLED="${WEB_VAULT_ENABLED:-true}"
export WEB_VAULT_FOLDER="${WEB_VAULT_FOLDER:-$VAULTWARDEN_HOME/web-vault}"
export TMP_FOLDER="${TMP_FOLDER:-${TMPDIR:-/tmp}/vaultwarden}"
export TEMPLATES_FOLDER="${TEMPLATES_FOLDER:-$VAULTWARDEN_HOME/templates}"

# The admin form says "leave it empty to disable": an empty token must not
# reach Vaultwarden.
if [ -z "${ADMIN_TOKEN:-}" ]; then
  unset ADMIN_TOKEN
fi

# The version is cosmetic: a missing manifest is not worth a line on stderr. A
# manifest that exists but cannot be parsed (a duplicated key) still is.
version=unknown
if [ -f "$VAULTWARDEN_HOME/manifest" ]; then
  version="$(read_kv "$VAULTWARDEN_HOME/manifest" VAULTWARDEN_VERSION)" || version=unknown
fi
echo "-----> Starting Vaultwarden $version (attachments, Sends and keys stored in s3://$S3_BUCKET)"

exec "$VAULTWARDEN_HOME/vaultwarden"
