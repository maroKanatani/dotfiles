# AGENTS.md の記述のうち、決定的に検査できるものだけを宣言する。
#
# 正典は AGENTS.md であり、このファイルはその実行可能な写像にすぎない。
# 各 check の "rule" には AGENTS.md の原文の一部を引用する。起動時に原文の存在を
# 照合し、見つからない場合は検査を停止して乖離を報告する。
#
# ast.literal_eval で読むため、Python の値リテラルだけを書く。外部ライブラリと
# Python のバージョン下限を作らないための選択で、コードは書けない。
#
# field       : "text"（body / text / Bash の command）| "commit_message" | "pr_draft"
# tools       : tool_name に対する正規表現。省略すると Bash 以外にマッチしない
# bash_command: Bash の command に対する正規表現。省略すると Bash を対象にしない
# 判定は forbid / require_if+require / standalone / match / equals のいずれか。
{
    "aliases": {
        "GITHUB_TEXT_TOOLS": '(add_issue_comment|add_comment_to_pending_review|add_reply_to_pull_request_comment|pull_request_review_write|create_pull_request|update_pull_request|issue_write)$',
        "GITHUB_COMMENT_TOOLS": '(add_issue_comment|add_comment_to_pending_review|add_reply_to_pull_request_comment|pull_request_review_write)$',
        "GH_POST_COMMAND": r'\bgh\s+(pr|issue)\s+(comment|create|review|edit)\b',
    },
    "checks": [
        {
            "id": 'issue-pr-autolink',
            "rule": '同一リポジトリのIssueとPull Requestは`#123`、別リポジトリは`owner/repo#123`',
            "tools": 'GITHUB_TEXT_TOOLS',
            "bash_command": 'GH_POST_COMMAND',
            "field": 'text',
            "forbid": r'https?://github\.com/[\w.-]+/[\w.-]+/(issues|pull)/\d+',
            "message": 'Issue / PR を URL で参照しています。同一リポジトリなら #123、別リポジトリなら owner/repo#123 と書く',
        },
        {
            "id": 'commit-autolink',
            "rule": 'コミットはSHAをそのまま書き、別リポジトリのコミットは`owner/repo@SHA`と書く',
            "tools": 'GITHUB_TEXT_TOOLS',
            "bash_command": 'GH_POST_COMMAND',
            "field": 'text',
            "forbid": r'https?://github\.com/[\w.-]+/[\w.-]+/commit/[0-9a-f]{7,40}',
            "message": 'コミットを URL で参照しています。同一リポジトリなら SHA をそのまま、別リポジトリなら owner/repo@SHA と書く',
        },
        {
            "id": 'permalink-pinned',
            "rule": 'コードを引用するときは行番号付きのpermalink',
            "tools": 'GITHUB_TEXT_TOOLS',
            "bash_command": 'GH_POST_COMMAND',
            "field": 'text',
            "forbid": r'https?://github\.com/[\w.-]+/[\w.-]+/blob/(?![0-9a-f]{40}/)[^/\s]+/',
            "message": 'permalink がブランチ名やタグを指しています。40 桁の commit SHA に固定する',
        },
        {
            "id": 'permalink-standalone',
            "rule": 'permalink(`https://github.com/owner/repo/blob/SHA/path#L10-L20`)を単独行に貼り、該当行を展開させる',
            "tools": 'GITHUB_TEXT_TOOLS',
            "bash_command": 'GH_POST_COMMAND',
            "field": 'text',
            "standalone": r'https?://github\.com/[\w.-]+/[\w.-]+/blob/[0-9a-f]{40}/\S*#L\d+\S*',
            "message": 'permalink が単独行にありません。該当行を展開させるため、前後に文を置かず単独行に貼る',
        },
        {
            "id": 'code-reference-permalink',
            "rule": 'コードを引用するときは行番号付きのpermalink',
            "tools": 'GITHUB_COMMENT_TOOLS',
            "bash_command": r'\bgh\s+(pr|issue)\s+(comment|review)\b',
            "field": 'text',
            "preprocess": 'strip_urls',
            "require_if": r'[\w./\[\]$@-]+\.(ts|tsx|js|jsx|mjs|cjs|mts|cts|py|go|rs|rb|java|kt|swift|c|h|hpp|cpp|cc|cs|php|sh|bash|zsh|sql|md|json|ya?ml|toml|tf|vue|svelte)\b|:\d+\b|\d+\s*行目',
            "require": r'https?://github\.com/[\w.-]+/[\w.-]+/blob/[0-9a-f]{40}/\S*#L\d+',
            "message": 'ソースファイルまたは行番号に言及していますが、行番号付き permalink がありません。該当箇所を https://github.com/owner/repo/blob/<40桁SHA>/path#L10-L20 の形で単独行に貼る',
        },
        {
            "id": 'conventional-commits',
            "rule": 'コミットメッセージはConventional Commits形式で具体的な変更内容を書く',
            "bash_command": r'\bgit\s+(-\S+\s+|--\S+(=\S+)?\s+)*commit\b',
            "field": 'commit_message',
            "match": r'^(feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert)(\([^)]+\))?!?: .+',
            "message": 'コミットメッセージが Conventional Commits 形式ではありません。`<type>(<scope>): <具体的な変更内容>` の形で書く',
        },
        {
            "id": 'commit-message-specific',
            "rule": '`fix: レビュー指摘に対応`のように作業の契機だけを示し、差分を特定できないメッセージは使わない',
            "bash_command": r'\bgit\s+(-\S+\s+|--\S+(=\S+)?\s+)*commit\b',
            "field": 'commit_message',
            "forbid": r'(レビュー指摘に対応|指摘に対応|レビュー対応|修正しました|不具合を修正|バグ修正|軽微な修正|いろいろ|その他|WIP|wip|fix bug)\s*$',
            "message": 'コミットメッセージから差分を特定できません。作業の契機ではなく、何をどう変えたかを書く',
        },
        {
            "id": 'draft-pull-request',
            "rule": 'Pull Requestは、利用者がReady状態を明示しない限りDraftで作成する',
            "tools": 'create_pull_request$',
            "bash_command": r'\bgh\s+pr\s+create\b',
            "field": 'pr_draft',
            "equals": True,
            "message": 'Pull Request を Draft 以外で作成しようとしています。Draft で作成する（gh なら --draft、MCP なら draft: true）',
        },
    ],
}
