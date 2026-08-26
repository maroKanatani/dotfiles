#!/bin/sh
# agents-rules-gate.py を起動し、想定外の終了を必ずブロックへ倒す。
#
# フックが exit 1 や 127 で落ちると Claude Code はツールを実行してしまい、
# 強制が無言で消える。検査できない状態は「違反なし」ではないため、
# 0 と 2 以外はすべて 2 (ブロック) に変換する。

set -u

gate="${AGENTS_GATE_SCRIPT:-$HOME/.claude/hooks/agents-rules-gate.py}"

if [ ! -r "$gate" ]; then
  printf 'AGENTS ルール検査を実行できません: %s を読めません\n' "$gate" >&2
  exit 2
fi

python=""
for candidate in python3 python; do
  if command -v "$candidate" >/dev/null 2>&1; then
    python="$candidate"
    break
  fi
done
if [ -z "$python" ]; then
  printf 'AGENTS ルール検査を実行できません: python3 が見つかりません\n' >&2
  exit 2
fi

output=$("$python" "$gate" 2>&1)
code=$?

case "$code" in
  0) exit 0 ;;
  2)
    printf '%s\n' "$output" >&2
    exit 2
    ;;
  *)
    printf 'AGENTS ルール検査が異常終了しました (exit %s)。検査できない状態で素通しさせないためブロックします。\n%s\n' \
      "$code" "$output" >&2
    exit 2
    ;;
esac
