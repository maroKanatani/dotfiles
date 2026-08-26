#!/usr/bin/env python3
"""config/claude/settings.json の permissions を、書き込み可能なユーザー設定へ反映する。

`~/.claude/settings.json` は Claude のプラグインコマンドが直接書き換えるため、
Home Manager の読み取り専用リンクにできない (README「Manage Claude Code and Codex」)。
このスクリプトはユーザー設定を書き込み可能なまま保ち、permissions だけを差し替える。
他のキーには触れない。

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


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dry-run", action="store_true", help="書き込まずに差分を表示する")
    parser.add_argument("--source", type=Path, default=DEFAULT_SOURCE, help="リポジトリ側の設定")
    parser.add_argument("--target", type=Path, default=DEFAULT_TARGET, help="ユーザー設定")
    args = parser.parse_args()

    permissions = read_json(args.source).get("permissions")
    if not permissions:
        print(f"error: {args.source} に permissions がありません", file=sys.stderr)
        return 1

    target = read_json(args.target, default={})
    if target.get("permissions") == permissions:
        print("  変更なし (既に最新です)")
        return 0

    if args.dry_run:
        print("  --dry-run のため書き込みません。反映される permissions:")
        print(json.dumps(permissions, ensure_ascii=False, indent=2))
        return 0

    target["permissions"] = permissions
    args.target.parent.mkdir(parents=True, exist_ok=True)
    args.target.write_text(
        json.dumps(target, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    counts = ", ".join(f"{k} {len(v)}件" for k, v in permissions.items() if isinstance(v, list))
    print(f"  更新しました ({counts})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
