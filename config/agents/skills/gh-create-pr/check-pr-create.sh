#!/usr/bin/env bash
# gh pr create の Draft 既定(AGENTS.md「GitとGitHub」)を PreToolUse hook で守る。
# Draft 指定がある作成と対象外のコマンドは黙って通し、Draft の無い作成だけを
# 利用者の承認(ask)へ回す。利用者が Ready を明示した依頼なら、その場で承認
# すればよい。これにより gh pr create を permissions.ask に置く必要がなくなり、
# 既定である Draft 作成は確認なしで通る。
set -uo pipefail

cmd=$(jq -r '.tool_input.command // ""' 2>/dev/null) || exit 0

case "$cmd" in
  *"gh pr create"*) ;;
  *) exit 0 ;;
esac

# --draft / --draft=true / -d を Draft 指定とみなす。--draft=false は該当しない。
if printf '%s' "$cmd" | grep -Eq -- '(^|[[:space:]])(--draft(=true)?|-d)([[:space:]]|$)'; then
  exit 0
fi

printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"Draft指定のないPR作成です。利用者がReady状態を明示している場合だけ承認してください。"}}\n'
