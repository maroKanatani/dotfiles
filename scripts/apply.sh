#!/usr/bin/env bash

# Home Manager の適用と、Home Manager が扱えない Claude ユーザー設定の反映を続けて行う。
#
#   scripts/apply.sh              適用する
#   scripts/apply.sh --dry-run    変更内容を表示するだけで書き込まない

set -uo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root" || exit 1

dry_run=0

fail() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

parse_args() {
  for arg in "$@"; do
    case "$arg" in
      --dry-run) dry_run=1 ;;
      -h | --help)
        sed -n '3,6p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
        exit 0
        ;;
      *) fail "未知の引数: $arg" ;;
    esac
  done
}

# Nix の flake は git 管理下のファイルだけを store へ複製する。未追跡のままだと
# home.nix が参照するパスが store に存在せず「does not exist」で失敗する。
require_tracked_sources() {
  local untracked
  untracked="$(git ls-files --others --exclude-standard -- config nix scripts)"
  [ -n "$untracked" ] || return 0

  {
    printf '未追跡のファイルがあります。Nix flake は git 管理下のファイルだけを取り込むため、\n'
    printf 'このまま適用すると「does not exist」で失敗します。\n\n'
    printf '%s\n\n' "$untracked"
    printf '次を実行してから再実行してください:\n'
    printf '  git add %s\n' "$(printf '%s' "$untracked" | tr '\n' ' ')"
  } >&2
  exit 1
}

run_home_manager() {
  if [ "$dry_run" -eq 1 ]; then
    printf '==> nix run .#apply -- --dry-run\n'
    nix run .#apply -- --dry-run || fail 'Home Manager の dry-run が失敗しました'
  else
    printf '==> nix run .#apply\n'
    nix run .#apply || fail 'Home Manager の適用が失敗しました'
  fi
}

sync_user_settings() {
  local target="${HOME}/.claude/settings.json"

  if [ "$dry_run" -eq 0 ] && [ -f "$target" ]; then
    local backup="${target}.bak.$(date +%Y%m%d%H%M%S)"
    cp -p "$target" "$backup" || fail 'バックアップを作成できませんでした'
    printf '==> バックアップ: %s\n' "$backup"
  fi

  printf '==> Claude ユーザー設定へ permissions を反映: %s\n' "$target"
  local args=(--target "$target")
  [ "$dry_run" -eq 1 ] && args+=(--dry-run)
  python3 scripts/sync-claude-settings.py "${args[@]}" ||
    fail 'ユーザー設定の更新に失敗しました'
}

main() {
  parse_args "$@"
  require_tracked_sources
  run_home_manager
  sync_user_settings

  if [ "$dry_run" -eq 0 ]; then
    printf '\n完了しました。Claude Code を再起動すると permissions が有効になります。\n'
  fi
}

main "$@"
