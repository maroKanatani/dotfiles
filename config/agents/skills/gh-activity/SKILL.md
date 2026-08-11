---
name: gh-activity
description: "指定期間・指定リポジトリのGitHub活動を収集し、Markdown報告へ整理する。ユーザーがGitHub活動、週報、作成Issue、作成・マージPR、レビュー候補の一覧化を依頼したときに使用する。"
---

# GitHub活動をまとめる

`scripts/collect.sh`でGitHub Search APIの結果をJSONとして取得し、依頼された形式のMarkdownへ整理する。

## 入力

- 開始日と終了日（`YYYY-MM-DD`）
- 対象リポジトリ（`owner/repo`、複数可）
- 出力先と報告形式。未指定なら結果を会話内に提示し、ファイルは作らない。

## 手順

1. 対象期間、リポジトリ、報告対象を確認する。
2. このSkillのルートで収集スクリプトを実行する。

   ```bash
   bash scripts/collect.sh \
     --since <YYYY-MM-DD> \
     --until <YYYY-MM-DD> \
     --repos <owner/repo,owner/repo>
   ```

3. JSONの`metadata.limitations`を確認し、候補データを確定データのように扱わない。
4. URLをキーに重複を除去し、リポジトリ別・活動種別に整理する。
5. 件数と個別項目を対応させ、検索エラーや取得上限があれば報告する。

## データの意味

- `created_issues`: 期間内に作成したIssue
- `created_prs`: 期間内に作成したPR
- `merged_prs`: 期間内にマージされた自分のPR
- `reviewed_pr_candidates`: 自分が過去にレビューし、期間内に更新されたPR（レビュー日時が期間内とは限らない）
- `commented_item_candidates`: 自分が過去にコメントし、期間内に更新されたIssueまたはPR（コメント日時が期間内とは限らない）

GitHub Searchの`updated:`は対象全体の更新日時であり、レビューやコメント自体の日時ではない。厳密なレビュー日時が必要な依頼では、この候補一覧を起点にレビューAPIなどで追加確認する。

## 安全条件

- スクリプトは読み取り専用のAPIだけを使う。
- API失敗を空の活動として扱わない。失敗時は報告を止め、エラーを示す。
- private repositoryの名前、タイトル、URLをユーザーが指定していない外部出力へ送らない。
