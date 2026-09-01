#!/usr/bin/env bash
# apply.sh の remove_unmanaged_skills を偽 HOME で検査する。削除を伴うので、
# 消す対象と残す対象の境界をここで固定する。
set -uo pipefail

root="$(mktemp -d)"
trap 'rm -rf "$root"' EXIT
export HOME="$root/home"

gen="$root/gen/home-files"
mkdir -p "$gen/.claude/skills/managed" "$HOME/.local/state/home-manager/gcroots"
echo managed > "$gen/.claude/skills/managed/SKILL.md"
ln -s "$root/gen" "$HOME/.local/state/home-manager/gcroots/current-home"

mkdir -p "$HOME/.claude/skills/managed" "$HOME/.claude/skills/handwritten" \
  "$HOME/.agents/skills/stale/agents" "$HOME/.agents/skills/pre-nix" "$root/other/external"

# 現行世代が管理しているリンク
ln -s "$gen/.claude/skills/managed/SKILL.md" "$HOME/.claude/skills/managed/SKILL.md"
# 別リポジトリの skill を指す store 外リンク
ln -s "$root/other/external" "$HOME/.claude/skills/external"
# エージェントがリポジトリを経由せず直接書いたファイル
echo handwritten > "$HOME/.claude/skills/handwritten/SKILL.md"
# 孤児削除が取りこぼした旧世代リンク
ln -s /nix/store/deadbeef-home-manager-files/.agents/skills/stale/SKILL.md \
  "$HOME/.agents/skills/stale/SKILL.md"
ln -s /nix/store/deadbeef-home-manager-files/.agents/skills/stale/agents/openai.yaml \
  "$HOME/.agents/skills/stale/agents/openai.yaml"
# このリポジトリ以前から ~/.agents/skills にある Codex 用の実体 skill
echo pre-nix > "$HOME/.agents/skills/pre-nix/SKILL.md"

sed '$d' "$(dirname "${BASH_SOURCE[0]}")/apply.sh" > "$root/apply-lib.sh"
# shellcheck disable=SC1090
source "$root/apply-lib.sh"
remove_unmanaged_skills

fails=0
check() {
  if eval "$2"; then
    printf '  ok: %s\n' "$1"
  else
    printf '  NG: %s\n' "$1"
    fails=1
  fi
}

printf -- '--- 判定\n'
check "現行世代のリンクは残る" '[ -L "$HOME/.claude/skills/managed/SKILL.md" ]'
check "store 外へのリンクは残る" '[ -L "$HOME/.claude/skills/external" ]'
check "直接書かれたファイルは消える" '[ ! -e "$HOME/.claude/skills/handwritten" ]'
check "旧世代リンクは消える" '[ ! -L "$HOME/.agents/skills/stale/SKILL.md" ]'
check "空になった親だけ畳まれる" '[ ! -d "$HOME/.agents/skills/stale" ] && [ -d "$HOME/.agents/skills" ]'
check "リポジトリ以前の実体 skill は残る" '[ -f "$HOME/.agents/skills/pre-nix/SKILL.md" ]'
exit "$fails"
