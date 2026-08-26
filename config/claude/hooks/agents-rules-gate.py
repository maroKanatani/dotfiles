#!/usr/bin/env python3
"""AGENTS.md の明示ルールのうち決定的に検査できるものを PreToolUse でブロックする。

このスクリプトはルールを知らない。検査定義は checks.py が持ち、正典は AGENTS.md
にある。各定義は AGENTS.md の原文を `rule` に引用し、起動時に原文の存在を照合する。
原文が見つからない場合は検査を停止して乖離を報告する。

想定外の終了で素通しさせないため、起動は agents-rules-gate.sh 経由にする。
このスクリプトを直接 hook に指定すると、exit 1 で落ちたときに強制が消える。

文体、判断の妥当性、着手前の計画提示など自然言語の解釈を要するルールは、この方式
では検査できない。違反時は exit 2 + stderr でツール呼び出しをブロックする。

環境変数:
  AGENTS_RULES_FILE   AGENTS.md の場所 (既定: ~/.claude/rules/common.md)
  AGENTS_CHECKS_FILE  checks.py の場所 (既定: このスクリプトと同じディレクトリ)
"""

import ast
import json
import os
import re
import shlex
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
CHECKS_PATH = Path(os.environ.get("AGENTS_CHECKS_FILE", HERE / "checks.py"))
RULES_PATH = Path(
    os.environ.get("AGENTS_RULES_FILE", Path.home() / ".claude/rules/common.md")
)

ANY_URL_RE = re.compile(r"https?://\S+")
PREPROCESSORS = {"strip_urls": lambda text: ANY_URL_RE.sub(" ", text)}
ASSERTIONS = ("forbid", "require_if", "standalone", "match", "equals")


class ConfigError(Exception):
    """検査定義そのものが壊れている、または AGENTS.md と乖離している。"""


def load_checks() -> list[dict]:
    """checks.py を読み、別名の展開と AGENTS.md との照合を行う。"""
    try:
        raw = ast.literal_eval(CHECKS_PATH.read_text(encoding="utf-8"))
    except FileNotFoundError as exc:
        raise ConfigError(f"検査定義が見つかりません: {CHECKS_PATH}") from exc
    except (SyntaxError, ValueError, OSError) as exc:
        raise ConfigError(f"検査定義を読めません: {CHECKS_PATH}: {exc}") from exc

    if not isinstance(raw, dict):
        raise ConfigError(f"検査定義の形式が不正です: {CHECKS_PATH}")
    checks = raw.get("checks") or []
    aliases = raw.get("aliases") or {}

    try:
        rules_text = RULES_PATH.read_text(encoding="utf-8")
    except OSError as exc:
        raise ConfigError(f"ルール原典を読めません: {RULES_PATH}: {exc}") from exc

    # 原文が消えた検査を黙って動かし続けないよう、引用の実在を照合する
    stale = [c["id"] for c in checks if c.get("rule", "") not in rules_text]
    if stale:
        raise ConfigError(
            f"{CHECKS_PATH.name} の rule が {RULES_PATH.name} に見つかりません: "
            f"{', '.join(stale)}。原文の変更に合わせて検査定義を更新すること"
        )

    for check in checks:
        for key in ("tools", "bash_command"):
            value = check.get(key)
            if value in aliases:
                check[key] = aliases[value]
        if not any(key in check for key in ASSERTIONS):
            raise ConfigError(f"検査 {check.get('id')} に判定が定義されていません")
    return checks


def extract_commit_message(command: str) -> str | None:
    heredoc = re.search(r"<<-?\s*['\"]?(\w+)['\"]?\n(.*?)\n\1", command, re.DOTALL)
    if heredoc:
        return heredoc.group(2)
    try:
        tokens = shlex.split(command)
    except ValueError:
        return None
    for i, token in enumerate(tokens):
        if token in ("-m", "--message") and i + 1 < len(tokens):
            return tokens[i + 1]
        if token.startswith("--message="):
            return token.split("=", 1)[1]
    return None


def extract_option_value(command: str, names: tuple[str, ...]) -> str | None:
    """`--body <値>` のようなオプションの値を取り出す。"""
    heredoc = re.search(r"<<-?\s*['\"]?(\w+)['\"]?\n(.*?)\n\1", command, re.DOTALL)
    try:
        tokens = shlex.split(command)
    except ValueError:
        return None
    for i, token in enumerate(tokens):
        if token in names and i + 1 < len(tokens):
            value = tokens[i + 1]
            # `--body-file -` はヒアドキュメントから読む
            return heredoc.group(2) if value == "-" and heredoc else value
        for name in names:
            if token.startswith(f"{name}="):
                return token.split("=", 1)[1]
    return None


def field_value(field: str, tool_input: dict, command: str | None):
    """検査対象の値を取り出す。対象外なら None を返す。"""
    if field == "text":
        if command is not None:
            # コマンド全体を見ると、本文と無関係な引数まで違反として拾う。
            # 投稿されるのは本文だけなので、その値に絞る。
            body = extract_option_value(command, ("--body", "-b", "--body-file", "-F"))
            return body if body is not None else command
        for key in ("body", "text"):
            value = tool_input.get(key)
            if isinstance(value, str) and value.strip():
                return value
        return None
    if field == "commit_message":
        return extract_commit_message(command) if command is not None else None
    if field == "pr_draft":
        if command is not None:
            # gh は `--draft=false` で Draft を明示的に無効化できるため、値まで見る
            explicit = re.search(r"(?:^|\s)--draft=(\S+)", command)
            if explicit:
                return explicit.group(1).lower() not in ("false", "0", "no")
            return bool(re.search(r"(^|\s)(-d|--draft)(\s|$)", command))
        return tool_input.get("draft") is True
    raise ConfigError(f"未知の field: {field}")


def applies(check: dict, tool_name: str, command: str | None) -> bool:
    if command is not None:
        pattern = check.get("bash_command")
        return bool(pattern) and bool(re.search(pattern, command))
    pattern = check.get("tools")
    return bool(pattern) and bool(re.search(pattern, tool_name))


def violated(check: dict, value) -> bool:
    if "equals" in check:
        return value != check["equals"]

    text = value if isinstance(value, str) else str(value)
    preprocess = check.get("preprocess")
    if preprocess:
        if preprocess not in PREPROCESSORS:
            raise ConfigError(f"未知の preprocess: {preprocess}")
        text = PREPROCESSORS[preprocess](text)

    if "forbid" in check:
        return bool(re.search(check["forbid"], text))
    if "match" in check:
        subject = text.strip().splitlines()[0] if text.strip() else ""
        return not re.match(check["match"], subject)
    if "require_if" in check:
        if not re.search(check["require_if"], text):
            return False
        return not re.search(check["require"], text)
    if "standalone" in check:
        lines = [line.strip() for line in text.splitlines()]
        return any(m.strip() not in lines for m in re.findall(check["standalone"], text))
    return False


def main() -> int:
    # 入力を解釈できない状態は「違反なし」ではない。ハーネスの入力形式が変わった
    # ときに強制が無言で消えるのを防ぐため、読めなければ止める。
    try:
        payload = json.load(sys.stdin)
    except (json.JSONDecodeError, ValueError) as exc:
        print(f"AGENTS ルール検査を実行できません: 入力を解釈できません: {exc}", file=sys.stderr)
        return 2
    if not isinstance(payload, dict):
        print("AGENTS ルール検査を実行できません: 入力が想定の形式ではありません", file=sys.stderr)
        return 2

    tool_name = payload.get("tool_name", "")
    tool_input = payload.get("tool_input") or {}
    if not isinstance(tool_input, dict):
        return 0
    command = tool_input.get("command", "") if tool_name == "Bash" else None

    try:
        checks = load_checks()
        violations = [
            check
            for check in checks
            if applies(check, tool_name, command)
            and (value := field_value(check["field"], tool_input, command)) is not None
            and violated(check, value)
        ]
    except ConfigError as exc:
        # 検査できない状態で素通しすると強制の意味が失われるため、止めて報告する
        print(f"AGENTS ルール検査を実行できません: {exc}", file=sys.stderr)
        return 2

    if not violations:
        return 0

    out = ["AGENTS.md のルールに違反しています。修正してから再実行してください。", ""]
    for check in violations:
        out.append(f"  [{check['id']}] {check['message']}")
        out.append(f"      根拠 ({RULES_PATH.name}): {check['rule']}")
    print("\n".join(out), file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main())
