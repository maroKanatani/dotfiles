#!/usr/bin/env python3
"""config/claude/settings.json を、書き込み可能な Claude ユーザー設定へ複製する。

Home Manager でリンクにはできない。Claude のプラグインコマンドや `/config` が
`~/.claude/settings.json` を書き換えるためで、読み取り専用の Nix store リンクだと
それらが失敗する。書き込み可能な実体を保ったまま、内容だけを揃える。

リポジトリ側が正典であり、このスクリプトは全体を上書きする。ローカルで
`claude plugin install` などを実行して設定が変わったら、その内容を
config/claude/settings.json へ反映してから次回の適用を行う。

Home Manager が届かないクラウドセッションでは cloud-setup.sh から呼ばれる。

    python3 scripts/sync-claude-settings.py [--dry-run] [--source PATH] [--target PATH]

終了コード: 0 = 成功 (変更なしを含む) / 1 = 失敗
"""

import argparse
import json
import sys
from pathlib import Path

DEFAULT_SOURCE = Path(__file__).resolve().parent.parent / "config/claude/settings.json"
DEFAULT_TARGET = Path.home() / ".claude/settings.json"


def read_json(path: Path, default: dict | None = None) -> dict:
    if not path.exists():
        if default is None:
            raise SystemExit(f"error: {path} が見つかりません")
        return default
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (json.JSONDecodeError, OSError) as exc:
        raise SystemExit(f"error: {path} を読めません: {exc}") from exc


def describe(before: dict, after: dict) -> str:
    removed = sorted(set(before) - set(after))
    added = sorted(set(after) - set(before))
    changed = sorted(k for k in set(before) & set(after) if before[k] != after[k])
    parts = []
    if added:
        parts.append(f"追加 {', '.join(added)}")
    if changed:
        parts.append(f"変更 {', '.join(changed)}")
    if removed:
        parts.append(f"削除 {', '.join(removed)}")
    return " / ".join(parts) if parts else "差分なし"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dry-run", action="store_true", help="書き込まずに差分を表示する")
    parser.add_argument("--source", type=Path, default=DEFAULT_SOURCE, help="リポジトリ側の設定")
    parser.add_argument("--target", type=Path, default=DEFAULT_TARGET, help="ユーザー設定")
    args = parser.parse_args()

    source = read_json(args.source)
    if not source:
        print(f"error: {args.source} が空です", file=sys.stderr)
        return 1

    target = read_json(args.target, default={})
    if target == source:
        print("  変更なし (既に最新です)")
        return 0

    summary = describe(target, source)
    if args.dry_run:
        print(f"  --dry-run のため書き込みません。{summary}")
        return 0

    args.target.parent.mkdir(parents=True, exist_ok=True)
    args.target.write_text(
        json.dumps(source, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print(f"  上書きしました。{summary}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
