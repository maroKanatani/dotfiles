#!/usr/bin/env python3
"""日本語の文章を出す前にyomiyasu_lint.pyで検査するClaude Codeのhook。

AGENTS.md「言語と対話」の「日本語の文章は、出す前にすべてyomiyasuで推敲する」を、
エージェントの記憶に頼らず機械的に守らせる。

    yomiyasu_gate.py stop        Stop hook。直前の返答を検査し、警告があれば書き直させる
    yomiyasu_gate.py pretooluse  PreToolUse hook。commit、PR、Issue、コメント、Markdown、
                                 Artifactの本文を検査し、警告があればツールの実行を止める

リンターの指摘は2つの層に分けて扱う。文の書き方のルール（文末の連続、半角空白、比喩、
否定の対比、語彙など）は、どの出力でも止める。書式のルール（FORMAT_RULES）は、書式を
エージェント自身が決める会話の返答とArtifactでだけ止める。GitHubへの投稿、コミット、
リポジトリ内のMarkdownの書式は、リポジトリのテンプレートやSkillが決めるためである。

入力はhookのJSON（標準入力）で、止めるときだけhookのJSONを標準出力に書く。
止める対象はseverityがwarnかerrorの指摘で、infoでは止めない。かなを含まない文章は検査しない。
hook自身の不具合で作業を止めないよう、例外はすべて素通しにする。
"""

import html
import json
import os
import re
import shlex
import subprocess
import sys
from pathlib import Path

LINT = Path.home() / ".claude/skills/yomiyasu/scripts/yomiyasu_lint.py"
KANA = re.compile(r"[぀-ヿ]")
MAX_FINDINGS_IN_REASON = 8

# yomiyasu_lint.pyのルールIDのうち、書式を見るもの。
# review-pr Skillの深刻度の記号やPRテンプレートの箇条書きは、これらに当たっても正しい書式である
FORMAT_RULES = {"emoji_prohibited", "excess_bold", "excess_list", "trailing_colon"}


def strip_markdown_code(text: str) -> str:
    """コードブロックを除く。インラインコードは、前後の空白も検査するため中身を残す"""
    text = re.sub(r"```.*?```", "", text, flags=re.S)
    return re.sub(r"`([^`\n]*)`", r"\1", text)


def html_to_text(src: str) -> str:
    src = re.sub(r"<(style|script|pre)\b.*?</\1>", "", src, flags=re.S | re.I)
    src = re.sub(r"<code>(.*?)</code>", r"\1", src, flags=re.S)
    src = re.sub(r"</(p|li|h[1-6]|td|th|figcaption|text|div|summary)>", "\n", src, flags=re.I)
    src = html.unescape(re.sub(r"<[^>]+>", "", src))
    return "\n".join(line.strip() for line in src.splitlines() if line.strip())


def run_lint(text: str) -> list:
    result = subprocess.run(
        [sys.executable, "-I", str(LINT), "--json"],
        input=text, capture_output=True, text=True, timeout=20, check=True,
    )
    return [f for f in json.loads(result.stdout)["findings"] if f["severity"] in ("warn", "error")]


def prose_only(text: str) -> str:
    """見出し、箇条書き、チェックボックス、引用、太字の記号を外し、各行を地の文にする。

    yomiyasu_lint.pyは箇条書きや見出しの行を文のルールの検査から外す。PRテンプレートのように
    本文の大半が箇条書きの出力でも文の書き方を検査するため、記号だけを外して渡す。
    行の数は変えないので、指摘の行番号は元の本文と一致する。
    """
    lines = []
    for line in text.split("\n"):
        s = line.strip()
        s = re.sub(r"^#{1,6}\s+", "", s)
        s = re.sub(r"^>\s*", "", s)
        s = re.sub(r"^(?:[-*+]|\d+\.)\s+(?:\[[ xX]\]\s+)?", "", s)
        lines.append(s.replace("**", "").replace("__", ""))
    return "\n".join(lines)


def lint(text: str, check_format: bool) -> list:
    """止める対象の指摘を返す。文のルールは記号を外した本文で、書式のルールは元の本文で判定する。

    check_formatが偽なら書式のルールで止めない。かなを含まない文章なら空のリストを返す。
    """
    if not KANA.search(text):
        return []
    findings = [f for f in run_lint(prose_only(text)) if f["rule"] not in FORMAT_RULES]
    if check_format:
        findings = [f for f in run_lint(text) if f["rule"] in FORMAT_RULES] + findings
    return findings


def describe(findings: list) -> str:
    lines = [f"L{f['line']} {f['message']}「{f['snippet'][:80]}」" for f in findings[:MAX_FINDINGS_IN_REASON]]
    if len(findings) > MAX_FINDINGS_IN_REASON:
        lines.append(f"ほか{len(findings) - MAX_FINDINGS_IN_REASON}件")
    return "\n".join(lines)


def last_reply_from_transcript(path: str) -> str:
    """last_assistant_messageが無い古い版向けに、transcriptから最後の返答の本文を取り出す"""
    texts = []
    for raw in Path(path).read_text(encoding="utf-8").splitlines():
        try:
            entry = json.loads(raw)
        except json.JSONDecodeError:
            continue
        if entry.get("type") == "user" and not entry.get("isMeta"):
            content = entry.get("message", {}).get("content")
            if isinstance(content, str):  # 利用者の新しい発話で区切る
                texts = []
        if entry.get("type") == "assistant":
            for part in entry.get("message", {}).get("content", []):
                if isinstance(part, dict) and part.get("type") == "text":
                    texts.append(part["text"])
    return texts[-1] if texts else ""


def on_stop(data: dict) -> None:
    # 書き直しの返答まで検査すると、リンターの指摘が消えないときに止まらなくなる
    if data.get("stop_hook_active"):
        return
    text = data.get("last_assistant_message")
    if text is None and data.get("transcript_path"):
        text = last_reply_from_transcript(data["transcript_path"])
    findings = lint(strip_markdown_code(text or ""), check_format=True)
    if findings:
        reason = (
            f"直前の返答にyomiyasu_lint.pyの警告が{len(findings)}件あります。"
            "yomiyasu Skillの基準で書き直した返答を、もう一度出してください。\n" + describe(findings)
        )
        print(json.dumps({"decision": "block", "reason": reason}, ensure_ascii=False))


HEREDOC = re.compile(r"<<-?\s*['\"]?(\w+)['\"]?[^\n]*\n(.*?)\n\s*\1\s*(?=\n|$|\))", re.S)
SEPARATORS = {";", "&&", "||", "|", "&", "(", ")", "\n", ";;", "|&"}
ASSIGNMENT = re.compile(r"^[A-Za-z_]\w*=")
# サブコマンドごとの、本文を値に取る引数と、本文のファイルを値に取る引数
GIT_COMMIT_FLAGS = ({"-m", "--message"}, {"-F", "--file"})
GH_WRITE_FLAGS = ({"-b", "--body", "-t", "--title"}, {"-F", "--body-file"})
GH_WRITE = {("pr", "create"), ("pr", "edit"), ("pr", "comment"), ("pr", "review"),
            ("issue", "create"), ("issue", "edit"), ("issue", "comment")}
GH_API_FIELD_FLAGS = {"-f", "-F", "--field", "--raw-field"}


def simple_commands(command: str) -> list:
    """コマンド文字列を、演算子と改行で区切った単純コマンドのトークン列に分ける"""
    lexer = shlex.shlex(command, posix=True, punctuation_chars=";&|()\n")
    lexer.whitespace = " \t\r"
    lexer.whitespace_split = True
    commands, current = [], []
    for token in lexer:
        if token in SEPARATORS:
            if current:
                commands.append(current)
            current = []
        else:
            current.append(token)
    if current:
        commands.append(current)
    return commands


def read_file(path: str, cwd: str) -> str:
    p = Path(path) if os.path.isabs(path) else Path(cwd or ".") / path
    return p.read_text(encoding="utf-8") if p.is_file() else ""


def flag_values(args: list, text_flags: set, file_flags: set, cwd: str) -> list:
    texts = []
    for i, arg in enumerate(args):
        key, sep, inline = arg.partition("=") if arg.startswith("--") else (arg, "", "")
        value = inline if sep else (args[i + 1] if i + 1 < len(args) else "")
        if key in text_flags:
            texts.append(value)
        elif key in file_flags and value != "-":
            texts.append(read_file(value, cwd))
    return texts


def gh_api_values(args: list, cwd: str) -> list:
    texts = []
    for i, arg in enumerate(args):
        if arg in GH_API_FIELD_FLAGS and i + 1 < len(args) and args[i + 1].startswith("body="):
            body = args[i + 1][len("body="):]
            texts.append(read_file(body[1:], cwd) if body.startswith("@") else body)
        elif arg == "--input" and i + 1 < len(args) and args[i + 1] != "-":
            try:
                texts.append(str(json.loads(read_file(args[i + 1], cwd) or "{}").get("body", "")))
            except (json.JSONDecodeError, AttributeError):
                pass
    return texts


def outgoing_texts(tokens: list, cwd: str):
    """単純コマンドが本文を外へ出すものなら、その本文のリストを返す。対象外ならNone"""
    while tokens and ASSIGNMENT.match(tokens[0]):
        tokens = tokens[1:]
    if not tokens:
        return None
    if Path(tokens[0]).name == "git":
        rest, i = tokens[1:], 0
        while i < len(rest) and rest[i].startswith("-"):  # -C path や -c key=value などの全体オプション
            i += 2 if rest[i] in ("-C", "-c") else 1
        if i < len(rest) and rest[i] == "commit":
            return flag_values(rest[i + 1:], *GIT_COMMIT_FLAGS, cwd)
        return None
    if Path(tokens[0]).name == "gh" and len(tokens) >= 2:
        if tokens[1] == "api":
            return gh_api_values(tokens[2:], cwd)
        if len(tokens) >= 3 and (tokens[1], tokens[2]) in GH_WRITE:
            return flag_values(tokens[3:], *GH_WRITE_FLAGS, cwd)
    return None


def bash_texts(command: str, cwd: str) -> list:
    bodies = []

    def mark(match):
        bodies.append(match.group(2))
        return f"__HEREDOC_{len(bodies) - 1}__"

    try:
        commands = simple_commands(HEREDOC.sub(mark, command))
    except ValueError:
        return []
    texts = []
    for tokens in commands:
        values = outgoing_texts(tokens, cwd)
        if values is None:
            continue
        # ヒアドキュメントは、本文を外へ出すコマンドの中に置かれたものだけを本文とみなす
        joined = " ".join(tokens)
        texts += [body for i, body in enumerate(bodies) if f"__HEREDOC_{i}__" in joined]
        texts += [v for v in values if "__HEREDOC_" not in v]
    return texts


def artifact_text(tool_input: dict) -> str:
    if tool_input.get("action") not in (None, "publish") or tool_input.get("asset"):
        return ""
    path = tool_input.get("file_path") or ""
    if not path.endswith((".html", ".md")) or not os.path.isfile(path):
        return ""
    src = Path(path).read_text(encoding="utf-8")
    for edit in tool_input.get("edits") or []:
        src = src.replace(edit.get("old_str", ""), edit.get("new_str", ""), 1)
    return html_to_text(src) if path.endswith(".html") else strip_markdown_code(src)


def on_pretooluse(data: dict) -> None:
    tool, tool_input = data.get("tool_name"), data.get("tool_input") or {}
    if tool == "Bash":
        texts, check_format = bash_texts(tool_input.get("command", ""), data.get("cwd", "")), False
    elif tool in ("Write", "Edit") and str(tool_input.get("file_path", "")).endswith(".md"):
        texts = [strip_markdown_code(tool_input.get("content") or tool_input.get("new_string") or "")]
        check_format = False
    elif tool == "Artifact":
        texts, check_format = [artifact_text(tool_input)], True
    else:
        return
    findings = lint("\n".join(t for t in texts if t), check_format)
    if findings:
        reason = (
            f"送る文章にyomiyasu_lint.pyの警告が{len(findings)}件あります。"
            "yomiyasu Skillの基準で書き直してから、もう一度実行してください。\n" + describe(findings)
        )
        print(json.dumps({"hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": reason,
        }}, ensure_ascii=False))


def main() -> None:
    mode = sys.argv[1] if len(sys.argv) > 1 else ""
    try:
        data = json.load(sys.stdin)
        {"stop": on_stop, "pretooluse": on_pretooluse}[mode](data)
    except Exception as exc:  # noqa: BLE001 hookの不具合で作業を止めない
        print(f"yomiyasu_gate: skipped ({type(exc).__name__}: {exc})", file=sys.stderr)


if __name__ == "__main__":
    main()
