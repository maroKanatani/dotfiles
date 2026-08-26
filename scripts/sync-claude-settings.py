#!/usr/bin/env python3
"""config/claude/settings.json の PreToolUse フックを、書き込み可能なユーザー設定へ反映する。

`~/.claude/settings.json` は Claude のプラグインコマンドが直接書き換えるため、
Home Manager の読み取り専用リンクにできない (README「Apply Home Manager settings」)。
このスクリプトはユーザー設定を書き込み可能なまま保ち、対象のフック項目だけを
差し替える。他のキーには触れない。

    python3 scripts/sync-claude-settings.py [--dry-run] [--source PATH] [--target PATH]

終了コード: 0 = 成功 (変更なしを含む) / 1 = 失敗
"""

import argparse
import json
import sys
from pathlib import Path

# 同期対象のフックを見分ける目印。command 文字列そのものは
# config/claude/settings.json を唯一の出所とし、ここでは選別だけを行う。
MARKER = "agents-rules-gate"

DEFAULT_SOURCE = Path(__file__).resolve().parent.parent / "config/claude/settings.json"
DEFAULT_TARGET = Path.home() / ".claude/settings.json"


def is_target_entry(entry: dict) -> bool:
    """同期対象の PreToolUse 項目か。"""
    return any(MARKER in hook.get("command", "") for hook in entry.get("hooks", []))


def read_json(path: Path, default: dict | None = None) -> dict:
    if not path.exists():
        if default is None:
            raise SystemExit(f"error: {path} が見つかりません")
        return default
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (json.JSONDecodeError, OSError) as exc:
        raise SystemExit(f"error: {path} を読めません: {exc}") from exc


def pre_tool_use(settings: dict) -> list:
    return settings.get("hooks", {}).get("PreToolUse", [])


def merge(current: list, wanted: list) -> list:
    """目印を持つ既存項目を wanted で置き換える。再実行しても重複しない。"""
    return [entry for entry in current if not is_target_entry(entry)] + wanted


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dry-run", action="store_true", help="書き込まずに差分を表示する")
    parser.add_argument("--source", type=Path, default=DEFAULT_SOURCE, help="リポジトリ側の設定")
    parser.add_argument("--target", type=Path, default=DEFAULT_TARGET, help="ユーザー設定")
    args = parser.parse_args()

    wanted = [e for e in pre_tool_use(read_json(args.source)) if is_target_entry(e)]
    if not wanted:
        print(f"error: {MARKER} を含む PreToolUse が {args.source} にありません", file=sys.stderr)
        return 1

    target = read_json(args.target, default={})
    current = pre_tool_use(target)
    merged = merge(current, wanted)

    if current == merged:
        print("  変更なし (既に最新です)")
        return 0

    if args.dry_run:
        print("  --dry-run のため書き込みません。追加または更新される項目:")
        print(json.dumps(wanted, ensure_ascii=False, indent=2))
        return 0

    target.setdefault("hooks", {})["PreToolUse"] = merged
    args.target.parent.mkdir(parents=True, exist_ok=True)
    args.target.write_text(
        json.dumps(target, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print(f"  更新しました ({len(wanted)} 件)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
