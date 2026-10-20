#!/usr/bin/env bash

# Home Manager の適用、配布をやめた skill の残骸削除、エージェント設定の配布を続けて行う。
# エージェント設定は Nix ではなく scripts/deploy-agent-config.sh が checkout からリンクする。
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

deploy_agent_config() {
  printf '==> エージェント設定を配布: scripts/deploy-agent-config.sh\n'
  # macOS の bash 3.2 は set -u で空配列の展開に失敗するため、配列を使わない。
  if [ "$dry_run" -eq 1 ]; then
    bash scripts/deploy-agent-config.sh --dry-run
  else
    bash scripts/deploy-agent-config.sh
  fi || fail 'エージェント設定の配布に失敗しました'
}

# skill のディレクトリには apply では消えないゴミが溜まる。Home Manager は
# 自分が作ったリンクしか消さず、その孤児削除も「直前の世代 ↔ 新世代」の一発
# 差分なので、取りこぼしたリンクは二度と再試行されない。リポジトリを経由せず
# 直接書かれたファイルは最初から対象外で、これはエージェント自身が書き込むため
# 繰り返し起きる。残れば全セッションで読み込まれ続ける。
#
# 残すのは、現行世代が管理しているものと、store の外の実在するパスを指す
# symlink だけ。リンク先が消えていれば skill として読み込めないのでゴミであり、
# 現行世代以外の store を指すリンクも配布をやめた残骸なので消す。
# ~/.claude/skills はこのリポジトリが所有するので実体ファイルも消す。
# ~/.agents/skills にはこのリポジトリ以前から Codex 用の実体 skill があるため、
# そちらの実体は残す。
remove_unmanaged_skills() {
  local current
  current="$(readlink -f "${HOME}/.local/state/home-manager/gcroots/current-home/home-files" 2>/dev/null)"
  [ -n "$current" ] && [ -d "$current" ] || return 0

  local dir path target parent found=0

  for dir in "${HOME}/.claude/skills" "${HOME}/.agents/skills"; do
    [ -d "$dir" ] || continue

    while IFS= read -r path; do
      [ -e "$current/${path#"${HOME}"/}" ] && continue

      if [ -L "$path" ]; then
        target="$(readlink "$path")"
        case "$target" in
          /nix/store/*) ;;
          *) [ -e "$path" ] && continue ;;
        esac
      elif [ "$dir" != "${HOME}/.claude/skills" ]; then
        continue
      fi

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
  remove_unmanaged_skills
  deploy_agent_config

  if [ "$dry_run" -eq 0 ]; then
    printf '\n完了しました。Claude Code を再起動すると permissions が有効になります。\n'
  fi
}

main "$@"
