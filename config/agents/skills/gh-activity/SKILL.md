---
name: gh-activity
description: "指定期間・指定リポジトリのGitHub活動を収集し、Markdown報告書を作成して`.md`ファイルに保存する。ユーザーがGitHub活動、週報、GitHub報告書、作成Issue、作成・マージPR、レビュー、アサインの一覧化を依頼したときに使用する。"
---

# GitHub活動をまとめる

`scripts/collect.sh`でGitHub Search APIの結果をJSONとして取得し、Markdown報告書を作成して`.md`ファイルに保存する。

## 入力

- 開始日と終了日（`YYYY-MM-DD`）。未指定なら直近1週間を提案する。
- 対象リポジトリ（`owner/repo`、複数可）
- 出力先と報告形式。未指定なら下記のデフォルトに従う。

## 手順

1. 対象期間、リポジトリ、報告対象を確認する。
2. このSkillのルートで収集スクリプトを実行し、JSONを一時ファイルへ保存する。

   ```bash
   bash scripts/collect.sh \
     --since <YYYY-MM-DD> \
     --until <YYYY-MM-DD> \
     --repos <owner/repo,owner/repo> \
     > /tmp/gh_activity_<since>_<until>.json
   ```

   スクリプトはstdoutにJSON、進捗をstderrに出す。非ゼロ終了ならstderrの内容をユーザーへ報告して中断する。
3. JSONの`metadata.limitations`を確認し、期間内の活動と確定できないものを確定データのように扱わない。
4. 下記の報告書ルールに従いMarkdown報告書を作成する。
5. `.md`ファイルとして保存し、パスと件数サマリーを通知する。

## データの意味

- `created_issues`: 期間内に作成したIssue
- `created_prs`: 期間内に更新のあった自作PR、および更新日時を問わず現在Openの自作PR
- `reviews`: 自分がレビューまたはコメントし、期間内に更新されたPR（レビュー日時が期間内とは限らない）
- `commented_issues`: 自分がコメントし、期間内に更新されたIssue（コメント日時が期間内とは限らない）
- `assigned`: 自分にアサインされ、期間内に更新されたIssueとPR

各アイテムは`status`（`Open` / `PR` / `Draft` / `Merged` / `Close`）、`labels`、`merged_at`、`author`を持つ。

GitHub Searchの`updated:`は対象全体の更新日時であり、レビューやコメント自体の日時ではない。厳密なレビュー日時が必要な依頼では、この一覧を起点にレビューAPIなどで追加確認する。

## 報告書ルール

1. トップレベルはリポジトリ名（`owner/repo`の`repo`部分のみ）を`-`の箇条書きにする。
2. `created_issues` / `created_prs` / `assigned` は省略せず全件記載する。
3. 各アイテムの下の階層に`status`を書く。
4. 同一リポジトリに5件以上あるときは、タイトルとラベルからトピックを推定してグループ化する。5件未満ならグループ化しない。どのグループにも入らないものは「その他」にまとめる。
5. 並び順は関連度の高い順にする。
6. レビューは「コードレビュー」の項目名だけを書き、個別のPRは列挙しない。
7. `assigned`のうち`created_issues` / `created_prs`と重複するものは除外する。
8. 活動が1件もないリポジトリは報告書に含めない。

### フォーマット例

```md
- repository1
  - 型アサーション対応
    - [asの削除1](https://github.com/owner/repository1/pull/xxx)
      - Merged
    - [asの削除2](https://github.com/owner/repository1/pull/yyy)
      - PR
  - その他
    - [ドキュメント更新](https://github.com/owner/repository1/pull/bbb)
      - Merged
  - コードレビュー
- repository2
  - [機能A追加](https://github.com/owner/repository2/pull/ccc)
    - Merged
  - コードレビュー
```

## 出力

1. 報告書を`.md`ファイルとして保存する。
   - ファイル名: `gh_activity_<開始日>_<終了日>.md`
   - 保存先: カレントディレクトリ。ユーザーが出力先を指定した場合はそちらを優先する。
2. 保存後、次を通知する。
   - 報告書ファイルのパス
   - JSONデータのパス
   - 件数サマリー（起票Issue / 作成PR / コードレビュー / アサイン）
   - 検索エラーや取得上限に触れたものがあればその内容

## 安全条件

- スクリプトは読み取り専用のAPIだけを使う。
- API失敗を空の活動として扱わない。失敗時は報告を止め、エラーを示す。
- private repositoryの名前、タイトル、URLをユーザーが指定していない外部出力へ送らない。
