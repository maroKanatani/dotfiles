---
name: gh-create-pr
description: "GitHub CLIでPull Requestを作成する。ユーザーがPRの作成、提出、公開、ドラフト作成を依頼したときに使用する。既存PRのレビュー指摘対応や、PRを作らない通常のコミットには使用しない。"
---

# GitHub Pull Requestを作成する

Pull Requestへ含める変更、検証結果、メタデータを確認してから、`gh`で作成する。

## 手順

1. リポジトリ固有の指示とPRテンプレートを確認する。
2. `git status --short`、現在のブランチ、upstream、派生元候補を確認する。既定ブランチを`main`と決めつけない。
3. コミット済み・ステージ済み・未追跡の変更を分け、依頼と無関係な差分をPRへ含めない。
4. 必要なテスト、lint、formatを実行する。未実行または失敗した検証はPR本文へ明記する。
5. コミットが必要な場合は、関係するファイルをパス指定でステージする。`git add .`と`git add -A`は使わない。リポジトリの規約がなければConventional Commits形式を使う。
6. push前に、現在のブランチと送信先remoteを確認する。
7. PRタイトルと本文を作る。本文はリポジトリのテンプレートを保ち、変更内容、判断理由、検証結果を記載する。自動生成署名は追加しない。
8. `gh pr create`でPRを作成し、base、head、draftなど、結果を左右する値は明示する。
9. assignee、label、reviewer、projectは、ユーザーまたはリポジトリの指示がある場合だけ設定する。過去のPRから推測して強制しない。
10. 作成後にPRを取得し、URL、base、head、draft状態、指定したメタデータを確認する。

## コマンド例

```bash
gh pr create \
  --base <base-branch> \
  --head <head-branch> \
  --title '<title>' \
  --body-file <body-file>

gh pr view --json url,title,baseRefName,headRefName,isDraft,labels,assignees,projectItems
```

`gh pr create --dry-run`もpushする場合があるため、読み取り専用の確認とはみなさない。

## 完了条件

- PRに依頼対象の変更だけが含まれている。
- PR本文がテンプレートに従い、検証結果と残るリスクを示している。
- 指定されたメタデータが反映されている。
- 作成したPRのURLをユーザーへ報告している。
