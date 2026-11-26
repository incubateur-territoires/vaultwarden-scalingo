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
optional_tool_selftest actionlint

if [ -d .github/workflows ]; then
  for workflow in .github/workflows/*.yml .github/workflows/*.yaml; do
    [ -f "$workflow" ] || continue
    check_workflow "$workflow"
  done
  if optional_tool actionlint; then
    if ! out="$(actionlint 2>&1)"; then
      problem .github/workflows "actionlint: $out"
    fi
  fi
fi
