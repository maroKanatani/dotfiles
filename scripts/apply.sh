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

  printf '==> Claude ユーザー設定を上書き: %s\n' "$target"
  local args=(--target "$target")
  [ "$dry_run" -eq 1 ] && args+=(--dry-run)
  python3 scripts/sync-claude-settings.py "${args[@]}" ||
    fail 'ユーザー設定の更新に失敗しました'
}

# このリポジトリが配布をやめた skill が、apply では消えずに残ることがある。
# 原因は二つある。Home Manager の孤児削除は「直前の世代 ↔ 新世代」の一発差分
# なので、一度取りこぼしたリンクは二度と再試行されない。また Home Manager は
# 自分が作ったリンクしか消さないので、リポジトリを経由せず ~/.claude/skills へ
# 直接書かれたファイルは最初から対象外になる。後者はエージェント自身が
# 書き込むため繰り返し起きる。どちらも残れば全セッションで読み込まれる。
#
# ~/.claude/skills は現行世代のリンクと、別リポジトリの skill を指す store 外の
# symlink だけで構成されるので、それ以外は残骸として消す。~/.agents/skills には
# このリポジトリ以前から Codex 用の実体 skill があるため、取りこぼしたリンク
# だけを消す。
remove_unmanaged_skills() {
  local current
  current="$(readlink -f "${HOME}/.local/state/home-manager/gcroots/current-home/home-files" 2>/dev/null)"
  [ -n "$current" ] && [ -d "$current" ] || return 0

  local dir path target parent found=0

  for dir in "${HOME}/.claude/skills" "${HOME}/.agents/skills"; do
    [ -d "$dir" ] || continue

    while IFS= read -r path; do
      [ -e "$current/${path#"${HOME}"/}" ] && continue

      target="$(readlink "$path" 2>/dev/null)"
      case "$target" in
        "") [ "$dir" = "${HOME}/.claude/skills" ] || continue ;;
        /nix/store/*-home-manager-files/*) ;;
        *) continue ;;
      esac

      if [ "$found" -eq 0 ]; then
        found=1
        printf '==> リポジトリが管理していない skill を削除\n'
      fi
      if [ "$dry_run" -eq 1 ]; then
        printf '  削除対象: %s\n' "$path"
        continue
      fi

      rm -f "$path" || fail "削除できませんでした: $path"
      printf '  削除: %s\n' "$path"

      # 空になった親だけを畳む。非空の rmdir は失敗するのでそれが判定になる。
      parent="$(dirname "$path")"
      while [ "$parent" != "$dir" ] && rmdir "$parent" 2>/dev/null; do
        parent="$(dirname "$parent")"
      done
    done < <(find "$dir" -mindepth 1 \( -type f -o -type l \) -print)
  done
  return 0
}

main() {
  parse_args "$@"
  require_tracked_sources
  run_home_manager
  sync_user_settings
  remove_unmanaged_skills

  if [ "$dry_run" -eq 0 ]; then
    printf '\n完了しました。Claude Code を再起動すると permissions が有効になります。\n'
  fi
}

main "$@"
