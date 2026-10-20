#!/usr/bin/env bash

# Claude Code のクラウドセッション VM 向けの起動スクリプト。配布本体は
# scripts/deploy-agent-config.sh で、ここではクラウドにしかない作業だけを足す。
# クラウド環境の Setup script 欄に次を登録する:
#
#   git clone --depth 1 https://github.com/maroKanatani/dotfiles.git /opt/dotfiles
#   bash /opt/dotfiles/scripts/cloud-setup.sh
#   exit 0

set -uo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

bash "$repo_root/scripts/deploy-agent-config.sh"

# Codex CLI は cloud VM に無いため npm で導入する。環境キャッシュに保存され、
# 新規セッションでは再インストール不要。認証はここでは行わない。環境変数の
# 更新でキャッシュが再構築される保証がないため、config/agents/skills/codex-review
# がセッション内で CODEX_AUTH_JSON_B64 から auth.json を復元するか、無ければ
# `codex login --device-auth` を案内する。
if ! command -v codex >/dev/null 2>&1; then
  npm install -g @openai/codex ||
    printf 'cloud-setup: Codex CLI のインストールに失敗しました\n' >&2
fi

# pstack。cloud session は enabledPlugins の plugin を install しないため
# (docs: cloud-environments「What carries over from your setup」)、plugin 機構を
# 使わず skill と agent を ~/.claude へ直接リンクする。setup script が書いた
# ファイルは snapshot に残る。ローカルは plugin として入れるので名前に
# `pstack:` が付くが、cloud では `/poteto-mode` のように付かない。
pstack_root=/opt/cursor-plugins
if [[ ! -d "$pstack_root" ]]; then
  git clone --depth 1 https://github.com/cursor/plugins.git "$pstack_root" ||
    printf 'cloud-setup: cursor/plugins の clone に失敗しました\n' >&2
fi
pstack="$pstack_root/harness/pstack/claude-code"
if [[ -d "$pstack" ]]; then
  mkdir -p "$HOME/.claude/skills" "$HOME/.claude/agents"
  for skill in "$pstack"/skills/*/; do
    ln -sfn "${skill%/}" "$HOME/.claude/skills/$(basename "$skill")"
  done
  for agent in "$pstack"/agents/*.md; do
    ln -sfn "$agent" "$HOME/.claude/agents/$(basename "$agent")"
  done
fi

exit 0
