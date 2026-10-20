#!/usr/bin/env bash

# エージェント設定をこのリポジトリの checkout から home へ配布する。
# ローカル(scripts/apply.sh)とクラウドセッション(scripts/cloud-setup.sh)の両方が
# この1本を呼ぶ。Nix は使わない。配布先に Nix があるとは限らず、checkout を
# 参照するリンクだけが両環境に共通の経路だから。
#
#   scripts/deploy-agent-config.sh              配布する
#   scripts/deploy-agent-config.sh --dry-run    settings.json の差分だけ表示する

set -uo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
home="${HOME:-/root}"
claude_home="$home/.claude"
codex_home="$home/.codex"
agents_home="$home/.agents"
dry_run=0
[[ "${1:-}" == "--dry-run" ]] && dry_run=1

link() {
  local source_path="$1"
  local target_path="$2"

  # Home Manager が管理をやめた skill ディレクトリは中身のリンクだけ消えて
  # 空の実ディレクトリが残る。空なら畳んでからリンクする。
  if [[ -d "$target_path" && ! -L "$target_path" ]]; then
    rmdir "$target_path" 2>/dev/null || true
  fi
  if [[ -e "$target_path" && ! -L "$target_path" ]]; then
    printf 'deploy: kept existing path: %s\n' "$target_path" >&2
    return
  fi

  [[ "$dry_run" -eq 1 ]] && return
  ln -sfn "$source_path" "$target_path"
  printf 'deploy: linked %s -> %s\n' "$target_path" "$source_path"
}

mkdir -p "$claude_home/rules" "$claude_home/skills" "$claude_home/hooks/notification" \
  "$codex_home/rules" "$agents_home/skills"

# 共通指示
link "$repo_root/config/agents/AGENTS.md" "$claude_home/rules/common.md"
link "$repo_root/config/agents/AGENTS.md" "$codex_home/AGENTS.md"

# Skill は1つずつリンクする。管理外の skill が同じディレクトリに共存できるようにするため。
for skill_source in "$repo_root"/config/agents/skills/*/; do
  link "${skill_source%/}" "$claude_home/skills/$(basename "$skill_source")"
  link "${skill_source%/}" "$agents_home/skills/$(basename "$skill_source")"
done

# Claude Code の付属ファイル。~/.claude/hooks は Herdr が自分のスクリプトを書くので
# ディレクトリ自体はリンクにせず、中のファイルだけリンクする。
link "$repo_root/config/claude/statusline-command.sh" "$claude_home/statusline-command.sh"
link "$repo_root/config/claude/hooks/notification/completed.wav" \
  "$claude_home/hooks/notification/completed.wav"

# Codex の hooks と rules
link "$repo_root/config/codex/hooks.json" "$codex_home/hooks.json"
link "$repo_root/config/codex/rules/git-workflow.rules" "$codex_home/rules/git-workflow.rules"

# settings.json はリンクにできない。Claude 自身が書き換えるファイルだからで、
# 代わりに内容を複製する。これを省くと permissions が一切読まれない。
target="$claude_home/settings.json"
if [[ "$dry_run" -eq 0 && -f "$target" ]]; then
  backup="$target.bak.$(date +%Y%m%d%H%M%S)"
  cp -p "$target" "$backup" && printf 'deploy: backed up %s\n' "$backup"
fi
args=(--source "$repo_root/config/claude/settings.json" --target "$target")
[[ "$dry_run" -eq 1 ]] && args+=(--dry-run)
python3 "$repo_root/scripts/sync-claude-settings.py" "${args[@]}" ||
  printf 'deploy: Claude ユーザー設定の反映に失敗しました\n' >&2
