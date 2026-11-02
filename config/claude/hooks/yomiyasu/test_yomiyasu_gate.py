#!/usr/bin/env python3
"""yomiyasu_gate.py を、hookと同じく標準入力のJSONで呼び出して判定を確かめる。

    python3 config/claude/hooks/yomiyasu/test_yomiyasu_gate.py

前提: ~/.claude/skills/yomiyasu/scripts/yomiyasu_lint.py が配置済みであること。
"""

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

GATE = Path(__file__).with_name("yomiyasu_gate.py")

# 文の書き方のルール（同じ文末の3連続）に当たる文
BAD_SENTENCES = "これは確認します。これは試します。これは送ります。"
GOOD_SENTENCES = "確認しました。結果は3件です。"
# review-pr Skillの書式（深刻度の記号、太字、見出し、箇条書き）で、文はyomiyasuの基準を満たす
REVIEW_PR_BODY = """## 自動レビュー結果

\U0001F6D1 マージ前に要修正

### \U0001F6D1 マージ前に修正が必要

**[F1] 作業ツリーを書き換えるため、未コミットの変更が消える** — `logic-reviewer.md:35`

修正案は、別の作業ツリーの中だけで変異を行わせることである。

### \U0001F7E1 修正を推奨

- 削除の条件を、仕様上の場面が同じ行に絞る。
- 列名を判断基準の文言に合わせる。

### \U0001F535 任意の改善提案

- 参照先の名前を直す。
"""
# kernerのPRテンプレートの書式（太字の小見出しと箇条書き）で、文はyomiyasuの基準を満たす
TEMPLATE_PR_BODY = """## 概要

**現状や解決する課題**

- 月次明細CSVの取得が、大きい組織で504になる。
- close #428

**変更後どうなるか**

- 2,625万行の組織月でもCSVを取得できる。

**変更の要点**

- 集約キーの値で区切ったチャンクごとに生成する。

## 実装アプローチ

- チャンクの境界は並び順の先頭の集約キーに置く。一度に集約した結果と同じ行になるため。
- 大きい組織月はStep Functionsのジョブにして202を返す。API Gatewayの60秒を超えるため。
"""


def run_gate(mode: str, payload) -> tuple:
    raw = payload if isinstance(payload, str) else json.dumps(payload, ensure_ascii=False)
    proc = subprocess.run([sys.executable, "-I", str(GATE), mode], input=raw,
                          capture_output=True, text=True, timeout=60)
    return proc.returncode, proc.stdout.strip(), proc.stderr.strip()


def blocked(mode: str, payload) -> bool:
    code, out, _ = run_gate(mode, payload)
    assert code == 0, f"exit {code}"
    if not out:
        return False
    data = json.loads(out)
    if mode == "stop":
        return data.get("decision") == "block"
    return data["hookSpecificOutput"]["permissionDecision"] == "deny"


def bash(command: str, cwd: str = "/") -> dict:
    return {"tool_name": "Bash", "tool_input": {"command": command}, "cwd": cwd}


class StopHook(unittest.TestCase):
    """会話の返答。書式もエージェントが決めるため、全ルールで止める"""

    def test_文のルールに当たる返答を止める(self):
        self.assertTrue(blocked("stop", {"last_assistant_message": BAD_SENTENCES}))

    def test_絵文字を付けた返答を止める(self):
        self.assertTrue(blocked("stop", {"last_assistant_message": "\U0001F534 " + GOOD_SENTENCES}))

    def test_箇条書きと太字の多い返答を止める(self):
        # yomiyasu_lint.pyは太字の頻度と箇条書きの比率を、300字を超える文章でだけ判定する
        reply = "\n".join(f"- **項目{i}**は、配布後の設定ファイルで登録を確認し、問題は見つからなかった。" for i in range(10))
        self.assertTrue(blocked("stop", {"last_assistant_message": reply}))

    def test_箇条書きの中の文のルール違反も止める(self):
        reply = "- これは確認します。\n- これは試します。\n- これは送ります。"
        self.assertTrue(blocked("stop", {"last_assistant_message": reply}))

    def test_問題の無い返答は通す(self):
        self.assertFalse(blocked("stop", {"last_assistant_message": GOOD_SENTENCES}))

    def test_書き直しの返答は再検査しない(self):
        self.assertFalse(blocked("stop", {"last_assistant_message": BAD_SENTENCES, "stop_hook_active": True}))

    def test_英語だけの返答は検査しない(self):
        self.assertFalse(blocked("stop", {"last_assistant_message": "Done. All tests passed."}))

    def test_コードブロックの中は検査しない(self):
        reply = f"{GOOD_SENTENCES}\n```\n{BAD_SENTENCES}\n```"
        self.assertFalse(blocked("stop", {"last_assistant_message": reply}))


class GitHubAndCommit(unittest.TestCase):
    """GitHubへの投稿とコミット。書式はリポジトリが決めるため、文のルールだけで止める"""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.dir = Path(self.tmp.name)

    def tearDown(self):
        self.tmp.cleanup()

    def write(self, name: str, text: str) -> str:
        path = self.dir / name
        path.write_text(text, encoding="utf-8")
        return str(path)

    def test_review_prの書式のコメントはgh_apiで投稿できる(self):
        body = self.write("review.md", REVIEW_PR_BODY)
        self.assertFalse(blocked("pretooluse", bash(f"gh api repos/o/r/issues/1/comments -F body=@{body}")))

    def test_review_prの書式でも文のルールに当たれば止める(self):
        body = self.write("review.md", REVIEW_PR_BODY + "\n" + BAD_SENTENCES)
        self.assertTrue(blocked("pretooluse", bash(f"gh api repos/o/r/issues/1/comments -F body=@{body}")))

    def test_PRテンプレートの書式の本文はgh_pr_createで作れる(self):
        body = self.write("pr.md", TEMPLATE_PR_BODY)
        self.assertFalse(blocked("pretooluse", bash(f"gh pr create --draft --title 'feat: 生成を分ける' --body-file {body}")))

    def test_PR本文の箇条書きの中の半角空白は止める(self):
        self.assertTrue(blocked("pretooluse", bash("gh pr create --draft --title t --body '- PRの本文で gate を直す。'")))

    def test_PR本文の箇条書きの中の同じ文末の連続は止める(self):
        body = "- これは確認します。\n- これは試します。\n- これは送ります。"
        self.assertTrue(blocked("pretooluse", bash(f"gh pr create --draft --title t --body '{body}'")))

    def test_gh_pr_commentのbodyの文のルール違反を止める(self):
        self.assertTrue(blocked("pretooluse", bash(f"gh pr comment 1 --body '{BAD_SENTENCES}'")))

    def test_gh_issue_createのbody違反を止める(self):
        self.assertTrue(blocked("pretooluse", bash(f"gh issue create -t タイトル -b '{BAD_SENTENCES}'")))

    def test_ヒアドキュメントのコミットメッセージ違反を止める(self):
        cmd = f"git commit -m \"$(cat <<'EOF'\nfeat: 追加\n\n{BAD_SENTENCES}\nEOF\n)\""
        self.assertTrue(blocked("pretooluse", bash(cmd)))

    def test_絵文字入りでも文が正しいコミットメッセージは通す(self):
        cmd = f"git commit -m \"$(cat <<'EOF'\nfeat: ✅ 検査を分ける\n\n{GOOD_SENTENCES}\nEOF\n)\""
        self.assertFalse(blocked("pretooluse", bash(cmd)))

    def test_ファイルから読むコミットメッセージ違反を止める(self):
        msg = self.write("msg.txt", BAD_SENTENCES)
        self.assertTrue(blocked("pretooluse", bash(f"git -C repo commit -F {msg}")))


class CommandDetection(unittest.TestCase):
    """本文を外へ出すコマンドだけを検査し、文字列を含むだけのコマンドは通す"""

    def test_引数にgh_pr_createの文字列を含むだけのコマンドは通す(self):
        cmd = f"jq -cn --arg c \"gh pr create --body '{BAD_SENTENCES}'\" '{{}}'"
        self.assertFalse(blocked("pretooluse", bash(cmd)))

    def test_echoやgrepで文字列を扱うだけのコマンドは通す(self):
        self.assertFalse(blocked("pretooluse", bash(f"echo 'git commit -m {BAD_SENTENCES}' | grep commit")))

    def test_連結したコマンドの中のgit_commitは検査する(self):
        self.assertTrue(blocked("pretooluse", bash(f"cd repo && git add -A && git commit -m '{BAD_SENTENCES}'")))

    def test_別のコマンドのヒアドキュメントは本文とみなさない(self):
        cmd = f"cat > note.txt <<'EOF'\n{BAD_SENTENCES}\nEOF\ngit commit -m '{GOOD_SENTENCES}'"
        self.assertFalse(blocked("pretooluse", bash(cmd)))

    def test_投稿しないghコマンドは通す(self):
        self.assertFalse(blocked("pretooluse", bash(f"gh pr view 1 --json body --jq '.body' # {BAD_SENTENCES}")))

    def test_スクリプト中のhook確認用のテキストは通す(self):
        cmd = "python3 - <<'EOF'\ndef split(cmd):\n    return cmd\nEOF"
        self.assertFalse(blocked("pretooluse", bash(cmd)))


class MarkdownAndArtifact(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.dir = Path(self.tmp.name)

    def tearDown(self):
        self.tmp.cleanup()

    def test_リポジトリのMarkdownは書式のルールで止めない(self):
        payload = {"tool_name": "Write", "tool_input": {"file_path": "/r/README.md", "content": REVIEW_PR_BODY}}
        self.assertFalse(blocked("pretooluse", payload))

    def test_Markdownの文のルール違反は止める(self):
        payload = {"tool_name": "Edit", "tool_input": {"file_path": "/r/docs/a.md", "new_string": BAD_SENTENCES}}
        self.assertTrue(blocked("pretooluse", payload))

    def test_Markdown以外のファイルは検査しない(self):
        payload = {"tool_name": "Write", "tool_input": {"file_path": "/r/a.rs", "content": BAD_SENTENCES}}
        self.assertFalse(blocked("pretooluse", payload))

    def test_Artifactは絵文字も止める(self):
        page = self.dir / "a.html"
        page.write_text(f"<title>t</title><p>\U0001F534 {GOOD_SENTENCES}</p>", encoding="utf-8")
        self.assertTrue(blocked("pretooluse", {"tool_name": "Artifact", "tool_input": {"file_path": str(page)}}))

    def test_Artifactのeditsを当てた結果で判定する(self):
        page = self.dir / "a.html"
        page.write_text(f"<p>{BAD_SENTENCES}</p><pre>{BAD_SENTENCES}</pre>", encoding="utf-8")
        edits = [{"old_str": "これは送ります。", "new_str": "送信は明日です。"}]
        payload = {"tool_name": "Artifact", "tool_input": {"file_path": str(page), "edits": edits}}
        self.assertFalse(blocked("pretooluse", payload))


class Robustness(unittest.TestCase):
    def test_不正な入力では止めず理由を標準エラーに書く(self):
        code, out, err = run_gate("pretooluse", "not json")
        self.assertEqual((code, out), (0, ""))
        self.assertIn("skipped", err)

    def test_対象外のツールは通す(self):
        self.assertFalse(blocked("pretooluse", {"tool_name": "Read", "tool_input": {"file_path": "/a.md"}}))


if __name__ == "__main__":
    unittest.main(verbosity=2)
