---
name: git-create-worktree
description: "Gitのlinked worktreeを安全に作成する。ユーザーが別ブランチの並行開発、隔離した実装環境、緊急修正用worktreeの作成を依頼したときに使用する。通常のブランチ切り替えだけには使用しない。"
---

# Git worktreeを作成する

既存の作業ディレクトリを変更せず、明示したbranchとpathでlinked worktreeを作成する。

## 手順

1. `git rev-parse --show-toplevel`でリポジトリを確認する。
2. `git status --short`と`git worktree list --porcelain`で、既存変更とworktreeを確認する。
3. 作成するbranch、起点となるcommitまたはbranch、配置pathを決める。既定ブランチを`main`と決めつけない。
4. branchとpathが既存のworktree、local branch、remote-tracking branchと衝突しないか確認する。
5. 新規branchなら`git worktree add -b <branch> <path> <start-point>`を使う。既存branchなら`git worktree add <path> <branch>`を使う。
6. 作成後に`git worktree list --porcelain`と新worktreeの`git status --short --branch`を確認する。
7. リポジトリに明示されたセットアップ手順があれば案内する。依頼がない限り、自動実行しない。

## 安全条件

- `--force`や`-B`でGitの衝突防止を無効化しない。
- `.env`、認証ファイル、秘密情報をworktreeへ自動コピーしない。
- package install、build、`make setup`などを暗黙に実行しない。
- 作成処理の一部として既存worktreeやbranchを削除しない。
- pathがリポジトリ全体やホームディレクトリなど広すぎる場合は実行しない。

## コマンド例

```bash
git worktree add -b <new-branch> <path> <start-point>
git worktree add <path> <existing-branch>
git worktree list --porcelain
```
