#!/usr/bin/env bash

# Claude Code と Codex の設定を home へ入れる。
# ローカルでは scripts/apply.sh が、cloud では scripts/cloud-setup.sh がこの1本を呼ぶ。
# 必要なのは git と python3 だけで、何度実行しても同じ結果になる。

set -uo pipefail

repo="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
claude_home="$HOME/.claude"
codex_home="$HOME/.codex"
agents_home="$HOME/.agents"

link() {
  mkdir -p "$(dirname "$2")"
  if [[ -e "$2" && ! -L "$2" ]]; then
    printf 'setup: 既存の実体を残しました: %s\n' "$2" >&2
    return
  fi
  ln -sfn "$1" "$2"
}

# 1. 共通指示、rules、自作 Skill、付属ファイルを checkout からリンクする。
link "$repo/config/agents/AGENTS.md" "$claude_home/rules/common.md"
link "$repo/config/agents/AGENTS.md" "$codex_home/AGENTS.md"
link "$repo/config/claude/rules/pstack-models.md" "$claude_home/rules/pstack-models.md"
link "$repo/config/claude/statusline-command.sh" "$claude_home/statusline-command.sh"
link "$repo/config/claude/hooks/notification/completed.wav" \
  "$claude_home/hooks/notification/completed.wav"
link "$repo/config/codex/rules/git-workflow.rules" "$codex_home/rules/git-workflow.rules"
for skill in "$repo"/config/agents/skills/*/; do
  link "${skill%/}" "$claude_home/skills/$(basename "$skill")"
  link "${skill%/}" "$agents_home/skills/$(basename "$skill")"
done

# 2. settings.json は checkout のファイルへ1段の絶対パスでリンクする。
#    Claude Code が書いた変更は、このリポジトリの git diff に出る。
#    通常ファイルが既にあれば、1度だけ退避してからリンクに置き換える。
settings="$claude_home/settings.json"
if [[ -e "$settings" && ! -L "$settings" ]]; then
  mv "$settings" "$settings.pre-link.bak"
  printf 'setup: 既存の settings.json を退避しました: %s\n' "$settings.pre-link.bak"
fi
ln -sfn "$repo/config/claude/settings.json" "$settings"

# 3. このリポジトリから消したファイルを指すリンクを取り除く。
while IFS= read -r path; do
  [[ "$(readlink "$path")" == "$repo"/* && ! -e "$path" ]] && rm -f "$path"
done < <(find "$claude_home" "$codex_home" "$agents_home" -maxdepth 4 -type l 2>/dev/null)

# 4. settings.json で有効にしている plugin を、各 CLI のコマンドで入れる。
#    cloud は宣言だけでは plugin を入れないので、ここで明示して導入する。
plugins="$(python3 - "$repo/config/claude/settings.json" <<'PY'
import json, sys

settings = json.load(open(sys.argv[1], encoding="utf-8"))
markets = settings.get("extraKnownMarketplaces", {})
for plugin, enabled in settings.get("enabledPlugins", {}).items():
    market = plugin.rpartition("@")[2]
    source = markets.get(market, {}).get("source", {}).get("repo")
    if enabled and source:
        print(source, plugin)
PY
)"

while read -r source plugin; do
  [[ -z "$source" ]] && continue
  if command -v claude >/dev/null 2>&1; then
    claude plugin marketplace add "$source" >/dev/null 2>&1
    claude plugin install "$plugin" --scope user >/dev/null 2>&1 ||
      printf 'setup: claude への導入に失敗しました: %s\n' "$plugin" >&2
  fi
  # codex@openai-codex は Claude Code から Codex を呼ぶ plugin なので、Codex には入れない。
  if [[ "$plugin" != codex@* ]] && command -v codex >/dev/null 2>&1; then
    codex plugin marketplace add "$source" >/dev/null 2>&1
    codex plugin add "$plugin" >/dev/null 2>&1 ||
      printf 'setup: codex への導入に失敗しました: %s\n' "$plugin" >&2
  fi
done <<<"$plugins"
