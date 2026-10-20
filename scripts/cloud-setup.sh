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

exit 0
