#!/usr/bin/env bash

# Claude Code の cloud session の VM 向けの起動スクリプト。設定の導入は
# scripts/setup-agents.sh が行い、ここでは cloud にしかない作業だけを足す。
# cloud 環境の Setup script 欄に次を登録する。
#
#   git clone --depth 1 https://github.com/maroKanatani/dotfiles.git /opt/dotfiles
#   bash /opt/dotfiles/scripts/cloud-setup.sh
#   exit 0

set -uo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

# Codex CLI は cloud の VM に無いため npm で入れる。setup-agents.sh は codex コマンドが
# あるときだけ Codex へ plugin を足すので、先に入れておく。認証はここでは行わない。
# 手順は README の「Claude Code cloud sessions」にある。
if ! command -v codex >/dev/null 2>&1; then
  npm install -g @openai/codex ||
    printf 'cloud-setup: Codex CLI のインストールに失敗しました\n' >&2
fi

bash "$repo_root/scripts/setup-agents.sh"

exit 0
