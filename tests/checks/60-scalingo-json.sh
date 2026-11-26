#!/usr/bin/env bash
# Rules for scalingo.json, the one-click deploy manifest. The rule function is
# proven on the fixtures in tests/fixtures/scalingo-json (one bad file per
# rule), then runs on the real file. Every problem is reported as
# "check: scalingo.json: <rule>".

# The repository the deploy button points at. The README check reuses it.
SCALINGO_REPO_URL="https://github.com/incubateur-territoires/vaultwarden-scalingo"

# Variables the operator fills in the form: required, with no value.
SCALINGO_OPERATOR_FILLED="DOMAIN S3_BUCKET S3_ENDPOINT S3_REGION AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY"

# The words of the deploy form (the epic, verbatim), one "KEY|text" per line.
# "@key" lines are top-level keys; the others are the env vars, and they are
# also the exact set of variables the form may hold.
scalingo_words() {
  cat <<WORDS
@name|Vaultwarden
@description|Vaultwarden, a lightweight Bitwarden-compatible password manager server, with PostgreSQL and S3 storage.
@website|https://github.com/dani-garcia/vaultwarden
@repository|$SCALINGO_REPO_URL
@logo|https://raw.githubusercontent.com/dani-garcia/vaultwarden/1.37.5/resources/vaultwarden-icon.svg
DOMAIN|Public HTTPS address of this instance, for example https://my-vault.osc-fr1.scalingo.io (use the app name you chose above). Required: used in emails and by the Bitwarden clients.
S3_BUCKET|Name of the S3-compatible bucket that stores attachments, Sends, icons and the signing key. Scalingo's disk is erased at every restart, so this is required.
S3_ENDPOINT|S3 endpoint URL of your provider, for example https://s3.fr-par.scw.cloud
S3_REGION|Region of the bucket, for example fr-par
AWS_ACCESS_KEY_ID|Access key of a user allowed to read and write this bucket only.
AWS_SECRET_ACCESS_KEY|Secret key that goes with the access key.
ADMIN_TOKEN|Secret that opens the /admin page. Generated for you; read it later in this app's environment variables. Leave it empty to disable the admin page.
SIGNUPS_ALLOWED|Let anyone who can reach this instance create an account. Set to false once your users have registered.
S3_PATH_STYLE|Set to true if your provider requires path-style URLs (https://endpoint/bucket) instead of bucket.endpoint addresses.
WORDS
}

# scalingo_jq_rules FILE JQ_PROGRAM [JQ_ARGS...]: every line the program prints
# is a rule that FILE breaks.
scalingo_jq_rules() {
  local file="$1" program="$2" out line
  shift 2
  out="$(jq -r "$@" "$program" "$file" 2>&1)"
  while IFS= read -r line; do
    [ -n "$line" ] && problem scalingo.json "$line"
  done <<EOF
$out
EOF
}

# check_scalingo_json FILE
check_scalingo_json() {
  local file="$1" words operators

  if [ ! -f "$file" ]; then
    problem scalingo.json "file not found"
    return
  fi
  if ! jq -e . "$file" > /dev/null 2>&1; then
    problem scalingo.json "invalid JSON"
    return
  fi
  if ! jq -e 'type == "object"' "$file" > /dev/null 2>&1; then
    problem scalingo.json "the top level must be an object"
    return
  fi

  words="$(scalingo_words | jq -Rn '
    [inputs | split("|") | {key: .[0], value: (.[1:] | join("|"))}] | from_entries')"
  # shellcheck disable=SC2086 # the list is words on purpose
  operators="$(printf '%s\n' $SCALINGO_OPERATOR_FILLED | jq -Rn '[inputs]')"

  # Top-level keys, the one postgresql addon, the words of the top-level keys.
  scalingo_jq_rules "$file" '
    (["name", "description", "website", "repository", "logo", "env", "addons"][] as $k
      | select(has($k) | not) | "missing top-level key: \($k)"),
    (select(has("addons")) | .addons
      | if type != "array" then "addons must be an array"
        else ([.[] | select(type == "string" and startswith("postgresql:"))] | length) as $n
          | select($n != 1) | "addons must contain exactly one postgresql: addon (found \($n))"
        end),
    (. as $m | ["name", "description", "website", "repository", "logo"][] as $k
      | select(has($k) and $m[$k] != $words["@" + $k])
      | "\($k) must be \($words["@" + $k] | tojson)")
  ' --argjson words "$words"

  if ! jq -e '(.env | type) == "object"' "$file" > /dev/null 2>&1; then
    if [ "$(jq 'has("env")' "$file")" = true ]; then
      problem scalingo.json "env must be an object"
    fi
    return
  fi

  # The form: exactly the variables of the epic, each one well formed.
  scalingo_jq_rules "$file" '
    ($words | keys | map(select(startswith("@") | not))) as $want
    | (.env | keys) as $have
    | .env as $env
    | (($want - $have)[] | "missing env var: \(.)"),
      (($have - $want)[] | "unexpected env var: \(.)"),
      ($have[] as $k | $env[$k] as $v
        | if ($v | type) != "object" then "env var \($k) must be an object"
          else
            (select(($v.description | type) != "string" or ($v.description | test("^\\s*$")))
              | "env var \($k) has no description"),
            (select(($v.description | type) == "string" and ($v.description | test("\\S"))
                    and ($words[$k] != null) and $v.description != $words[$k])
              | "env var \($k) description differs from the epic"),
            (select($v.required == true and ($v | has("value") | not)
                    and ($v | has("generator") | not) and ($operators | index($k) | not))
              | "env var \($k) is required but has no value, no generator and is not filled by the operator"),
            (select(($operators | index($k)) != null
                    and ($v.required != true or ($v | has("value")) or ($v | has("generator"))))
              | "env var \($k) is filled by the operator: it must be required: true with no value and no generator")
          end)
  ' --argjson words "$words" --argjson operators "$operators"

  # The defaults the epic fixes.
  scalingo_jq_rules "$file" '
    (.env.ADMIN_TOKEN | select(type == "object")
      | (select(.generator != "secret") | "ADMIN_TOKEN generator must be \"secret\""),
        (select(.required != false) | "ADMIN_TOKEN must be required: false")),
    (.env.SIGNUPS_ALLOWED | select(type == "object")
      | select(.value != "true") | "SIGNUPS_ALLOWED value must be \"true\""),
    (.env.S3_PATH_STYLE | select(type == "object")
      | (select(.value != "false") | "S3_PATH_STYLE value must be \"false\""),
        (select(.required != false) | "S3_PATH_STYLE must be required: false"))
  '
}

fixtures=tests/fixtures/scalingo-json
expect_problem "invalid JSON" check_scalingo_json $fixtures/invalid.json
expect_problem "the top level must be an object" check_scalingo_json $fixtures/not-an-object.json
expect_problem "missing top-level key: logo" check_scalingo_json $fixtures/no-logo.json
expect_problem "addons must contain exactly one postgresql: addon (found 0)" check_scalingo_json $fixtures/no-postgresql.json
expect_problem "addons must contain exactly one postgresql: addon (found 2)" check_scalingo_json $fixtures/two-postgresql.json
expect_problem "missing env var: S3_BUCKET" check_scalingo_json $fixtures/env-missing.json
expect_problem "unexpected env var: BUILDPACK_URL" check_scalingo_json $fixtures/env-extra.json
expect_problem "env var DOMAIN has no description" check_scalingo_json $fixtures/no-description.json
expect_problem "env var S3_REGION description differs from the epic" check_scalingo_json $fixtures/description-changed.json
expect_problem "env var SIGNUPS_ALLOWED is required but has no value" check_scalingo_json $fixtures/required-without-value.json
expect_problem "env var S3_BUCKET is filled by the operator" check_scalingo_json $fixtures/operator-with-value.json
expect_problem "ADMIN_TOKEN generator must be \"secret\"" check_scalingo_json $fixtures/admin-token-no-generator.json
expect_problem "SIGNUPS_ALLOWED value must be \"true\"" check_scalingo_json $fixtures/signups-false.json
expect_problem "S3_PATH_STYLE value must be \"false\"" check_scalingo_json $fixtures/path-style-true.json
expect_problem "description must be" check_scalingo_json $fixtures/description-changed-top.json
expect_problem "repository must be \"$SCALINGO_REPO_URL\"" check_scalingo_json $fixtures/other-repository.json

check_scalingo_json scalingo.json
