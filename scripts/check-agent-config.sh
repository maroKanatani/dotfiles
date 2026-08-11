#!/usr/bin/env bash

set -uo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root" || exit 1

errors=0

report_error() {
  printf 'error: %s\n' "$*" >&2
  errors=$((errors + 1))
}

check_instruction_import() {
  local shared_instructions=config/agents/AGENTS.md
  local claude_instructions=config/claude/CLAUDE.md

  if [[ ! -e "$claude_instructions" ]]; then
    return
  fi

  if [[ ! -f "$shared_instructions" ]]; then
    report_error "$shared_instructions is missing while $claude_instructions exists"
    return
  fi

  if [[ ! -f "$claude_instructions" ]]; then
    report_error "$claude_instructions is not a regular file"
    return
  fi

  if ! rg --quiet '^[[:space:]]*@AGENTS\.md[[:space:]]*$' "$claude_instructions"; then
    report_error "$claude_instructions must import AGENTS.md with a standalone @AGENTS.md line"
  fi
}

frontmatter_value() {
  local skill_file="$1"
  local field="$2"

  awk -v field="$field" '
    NR == 1 {
      if ($0 != "---") {
        exit
      }
      in_frontmatter = 1
      next
    }
    in_frontmatter && $0 == "---" {
      exit
    }
    in_frontmatter && $0 ~ ("^[[:space:]]*" field "[[:space:]]*:") {
      sub("^[[:space:]]*" field "[[:space:]]*:[[:space:]]*", "")
      sub(/[[:space:]]+$/, "")
      if (($0 ~ /^".*"$/) || ($0 ~ /^'\''.*'\''$/)) {
        $0 = substr($0, 2, length($0) - 2)
      }
      print
      exit
    }
  ' "$skill_file"
}

check_skills() {
  local skills_dir=config/agents/skills
  local broken_link
  local skill_dir
  local skill_file
  local skill_name
  local description
  local directory_name
  local duplicate_found
  local index
  local -a skill_names=()
  local -a skill_files=()

  if [[ ! -e "$skills_dir" && ! -L "$skills_dir" ]]; then
    return
  fi

  while IFS= read -r -d '' broken_link; do
    report_error "broken symlink: $broken_link"
  done < <(find "$skills_dir" -type l ! -exec test -e '{}' \; -print0 2>/dev/null)

  if [[ ! -d "$skills_dir" ]]; then
    report_error "$skills_dir is not a readable directory"
    return
  fi

  while IFS= read -r -d '' skill_dir; do
    skill_file="$skill_dir/SKILL.md"
    directory_name="${skill_dir##*/}"

    if [[ ! -f "$skill_file" ]]; then
      report_error "$skill_dir must contain SKILL.md"
      continue
    fi

    if [[ "$(sed -n '1p' "$skill_file")" != "---" ]] ||
      [[ "$(awk 'NR > 1 && $0 == "---" { print; exit }' "$skill_file")" != "---" ]]; then
      report_error "$skill_file must start with YAML frontmatter delimited by ---"
      continue
    fi

    skill_name="$(frontmatter_value "$skill_file" name)"
    description="$(frontmatter_value "$skill_file" description)"

    if [[ -z "$skill_name" ]]; then
      report_error "$skill_file is missing non-empty frontmatter field: name"
      continue
    fi

    if [[ -z "$description" ]]; then
      report_error "$skill_file is missing non-empty frontmatter field: description"
    fi

    if [[ ! "$skill_name" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]]; then
      report_error "$skill_file has invalid skill name: $skill_name"
    fi

    if [[ "$skill_name" != "$directory_name" ]]; then
      report_error "$skill_file name '$skill_name' does not match directory '$directory_name'"
    fi

    duplicate_found=false
    for index in "${!skill_names[@]}"; do
      if [[ "${skill_names[$index]}" == "$skill_name" ]]; then
        report_error "duplicate skill name '$skill_name': ${skill_files[$index]} and $skill_file"
        duplicate_found=true
        break
      fi
    done

    if [[ "$duplicate_found" == false ]]; then
      skill_names+=("$skill_name")
      skill_files+=("$skill_file")
    fi
  done < <(find "$skills_dir" -mindepth 1 -maxdepth 1 \( -type d -o -type l \) -print0 2>/dev/null)
}

check_json() {
  local json_file="$1"

  if [[ ! -e "$json_file" ]]; then
    return
  fi

  if [[ ! -f "$json_file" ]]; then
    report_error "$json_file is not a regular file"
    return
  fi

  if ! command -v jq >/dev/null 2>&1; then
    report_error "jq is required to validate $json_file"
    return
  fi

  if ! jq empty "$json_file" >/dev/null; then
    report_error "$json_file is not valid JSON"
  fi
}

check_forbidden_tracked_files() {
  local tracked_file

  while IFS= read -r -d '' tracked_file; do
    case "$tracked_file" in
      .claude/.credentials.json | \
        .claude/history.jsonl | \
        .claude/settings.local.json | \
        .claude/stats-cache.json | \
        .claude/cache/* | \
        .claude/debug/* | \
        .claude/downloads/* | \
        .claude/file-history/* | \
        .claude/projects/* | \
        .claude/session-env/* | \
        .claude/shell-snapshots/* | \
        .claude/telemetry/* | \
        .claude/todos/* | \
        .claude/plugins/cache/* | \
        .codex/auth.json | \
        .codex/history.jsonl | \
        .codex/cache/* | \
        .codex/log/* | \
        .codex/sessions/* | \
        .codex/tmp/* | \
        .codex/plugins/cache/*)
        report_error "runtime or secret file must not be tracked: $tracked_file"
        ;;
    esac
  done < <(git ls-files -z)
}

check_instruction_import
check_skills
check_json config/claude/settings.json
check_json config/codex/hooks.json
check_forbidden_tracked_files

if ((errors > 0)); then
  printf 'Agent configuration check failed with %d error(s).\n' "$errors" >&2
  exit 1
fi

printf 'Agent configuration check passed.\n'
