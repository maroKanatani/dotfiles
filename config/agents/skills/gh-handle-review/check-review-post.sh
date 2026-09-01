#!/usr/bin/env bash
# gh-handle-review の数えられる規約(手順3の must 上限・手順3の prefix・手順4の段落数・
# 手順6の禁止記載)を、レビュー投稿コマンドの実行前に検査する PreToolUse hook。
# 対象外のコマンドと判定不能な入力は exit 0(過剰ブロックしない)。違反は exit 2 で
# 停止し、stderr の内容が Claude へ返る。規約の文章は SKILL.md 側が正で、この
# スクリプトが持つのは数値契約(prefix 6種 / must<=2 / 2段落以内 / 禁止語)のみ。
set -uo pipefail
INPUT=$(cat)
export CHECK_INPUT="$INPUT"
python3 - <<'PY'
import json, os, re, shlex, sys

def ok():
    sys.exit(0)

try:
    data = json.loads(os.environ["CHECK_INPUT"])
    cmd = (data.get("tool_input") or {}).get("command") or ""
except Exception:
    ok()

# 対象: gh api で pulls/<n>/reviews または pulls/<n>/comments への POST のみ
if "gh api" not in cmd or not re.search(r"pulls/[^\s'\"]*/(reviews|comments)\b", cmd):
    ok()
m = re.search(r"(?:-X|--method)[= ]+(\w+)", cmd)
method = (m.group(1).upper() if m else None)
has_fields = bool(re.search(r"(?:^|\s)(?:-f|-F|--field|--raw-field|--input)(?:\s|=)", cmd))
if method != "POST" and not (method is None and has_fields):
    ok()  # GET/PUT/PATCH/DELETE と読み取りは対象外

# 投稿ボディの取得: --input ファイル、または -f/--raw-field body=
review_body, comments = "", []
try:
    tokens = shlex.split(cmd)
except ValueError:
    ok()  # heredoc 等で解析不能なら失敗側に倒さない
path = None
for i, t in enumerate(tokens):
    if t == "--input" and i + 1 < len(tokens):
        path = tokens[i + 1]
    elif t.startswith("--input="):
        path = t.split("=", 1)[1]
if path:
    if path == "-":
        ok()  # stdin 渡しは検査できない
    if not os.path.isabs(path):
        path = os.path.join(data.get("cwd") or ".", path)
    try:
        payload = json.load(open(os.path.expanduser(path)))
    except Exception:
        ok()
    review_body = payload.get("body") or ""
    comments = [c.get("body") or "" for c in payload.get("comments") or []]
else:
    for i, t in enumerate(tokens):
        for flag in ("-f", "-F", "--field", "--raw-field"):
            v = None
            if t == flag and i + 1 < len(tokens):
                v = tokens[i + 1]
            elif t.startswith(flag + "="):
                v = t.split("=", 1)[1]
            if v and v.startswith("body="):
                b = v[len("body="):]
                if re.search(r"/comments\b", cmd):
                    comments.append(b)
                else:
                    review_body = b
if not review_body and not comments:
    ok()

def paragraphs(text):
    text = re.sub(r"```.*?```", "", text, flags=re.S)  # コードブロックは段落に数えない
    return [p for p in text.split("\n\n") if p.strip()]

PREFIXES = ("must:", "imo:", "nr:", "nits:", "fyi:", "q:")
FORBIDDEN = ["却下した指摘", "確認済み・問題なし", "網羅不足", "検証の透明性", "深刻度の集計", "高リスク領域チェック"]

violations = []
must = 0
for n, body in enumerate(comments, 1):
    if not body.startswith(PREFIXES):
        violations.append(f"コメント{n}: prefix がない(手順3)")
    if body.startswith("must:"):
        must += 1
    if "<details>" not in body and len(paragraphs(body)) > 2:
        violations.append(f"コメント{n}: {len(paragraphs(body))}段落あり2段落を超える(手順4)")
if must > 2:
    violations.append(f"must: が{must}件あり2件を超える(手順3)")
hits = [w for w in FORBIDDEN if w in review_body]
if hits:
    violations.append(f"レビュー本文に書かない対象が含まれる(手順6): {hits}")

if violations:
    print("gh-handle-review の規約違反のため投稿を停止:", file=sys.stderr)
    for v in violations:
        print(f"- {v}", file=sys.stderr)
    print("SKILL.md の該当手順に沿って修正してから投稿し直すこと。", file=sys.stderr)
    sys.exit(2)
ok()
PY
