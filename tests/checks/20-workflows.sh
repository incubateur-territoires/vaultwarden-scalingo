#!/usr/bin/env bash
# Rules for .github/workflows/*.yml. The rule function is proven on the
# fixtures in tests/fixtures/workflows (outside .github/, so the real run
# below does not see them).

# check_workflow FILE: the YAML parses and declares name, on, jobs, permissions.
# (YAML 1.1 reads the key `on` as the boolean true: both spellings are accepted.)
check_workflow() {
  local file="$1" report line
  report="$(ruby -ryaml -rdate -e '
    begin
      doc = YAML.safe_load(File.read(ARGV[0]), aliases: true, permitted_classes: [Date, Time])
    rescue StandardError, Psych::SyntaxError => e
      puts "invalid YAML: #{e.message.lines.first.to_s.strip}"
      exit
    end
    unless doc.is_a?(Hash)
      puts "invalid YAML: top level must be a mapping"
      exit
    end
    puts "missing top-level key: name" unless doc.key?("name")
    puts "missing top-level key: on" unless doc.key?("on") || doc.key?(true)
    puts "missing top-level key: jobs" unless doc.key?("jobs")
    puts "permissions must be declared (top-level permissions:)" unless doc.key?("permissions")
  ' "$file" 2>&1)"
  while IFS= read -r line; do
    [ -n "$line" ] && problem "$file" "$line"
  done <<EOF
$report
EOF
}

expect_problem "invalid YAML" check_workflow tests/fixtures/workflows/broken-yaml.yml
expect_problem "permissions must be declared" check_workflow tests/fixtures/workflows/no-permissions.yml
expect_no_problem check_workflow tests/fixtures/workflows/anchors-and-dates.yml
# check_curl_proto FILE: every curl command restricts its protocols with
# --proto '=https', so a redirect cannot leave HTTPS (Sonar S6506). A command
# may continue over several lines with a trailing backslash. curl is a command
# at the start of a line, after `- run:`, after ; & | ( or a backquote, and
# after the words that run what follows (if, !, then, sudo, xargs, ...) with
# their options (-n1, -u root, -I {}) and VAR=value prefixes, and after bare
# VAR=value prefixes. Not detected: a quoted value with a space
# (FOO="a b" curl), a curl whose name is built or quoted ('curl'), and an
# option argument that is not one word.
check_curl_proto() {
  local file="$1" report line
  report="$(ruby -e '
    assign = /(\w+=\S*\s+)*/
    words = /((if|elif|then|else|do|while|until|!|sudo|xargs|exec|time|nohup|command|env)\s+(-\S+\s+(\{\}\s+|\w+\s+)?|\w+=\S*\s+)*)*/
    File.read(ARGV[0]).gsub(/\\\n\s*/, " ").each_line do |l|
      next unless l.strip =~ /(\A(-\s+)?(run:\s+)?|[;&|(`]\s*)#{assign}#{words}curl\s/
      puts "curl without --proto \x27=https\x27: #{l.strip[0, 80]}" unless l.include?("--proto \x27=https\x27")
    end
  ' "$file" 2>&1)"
  while IFS= read -r line; do
    [ -n "$line" ] && problem "$file" "$line"
  done <<EOF
$report
EOF
}

expect_problem "curl without --proto" check_curl_proto tests/fixtures/workflows/curl-no-proto.yml
expect_no_problem check_curl_proto tests/fixtures/workflows/curl-proto.yml
# One fixture per command position: after if, if !, then, sudo, xargs, or on a
# one-line `- run:`. The last one holds every form with the flag, and
# mentions of curl that are not commands.
for form in oneline if if-not "then" sudo xargs assign sudo-user xargs-replace; do
  expect_problem "curl without --proto" check_curl_proto "tests/fixtures/workflows/curl-$form-no-proto.yml"
done
expect_no_problem check_curl_proto tests/fixtures/workflows/curl-oneline-proto.yml
expect_no_problem check_curl_proto tests/fixtures/workflows/curl-forms-proto.yml
optional_tool_selftest actionlint

if [ -d .github/workflows ]; then
  for workflow in .github/workflows/*.yml .github/workflows/*.yaml; do
    [ -f "$workflow" ] || continue
    check_workflow "$workflow"
    check_curl_proto "$workflow"
  done
  if optional_tool actionlint; then
    if ! out="$(actionlint 2>&1)"; then
      problem .github/workflows "actionlint: $out"
    fi
  fi
fi

# The scripts the workflows run follow the same curl rule.
for script in scripts/*.sh scripts/lib/*.sh; do
  [ -f "$script" ] || continue
  check_curl_proto "$script"
done
