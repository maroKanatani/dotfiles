---
name: codex-review
description: "Codex CLI(ChatGPT認証)にコードレビューを並列実行させ、自分のレビューと統合して報告する。ユーザーが「codexにもレビューさせて」「codexでクロスレビュー」などCodexによるレビューを依頼したときに使用する。Codexを使わない通常のレビューには使用しない。"
---

# Codexクロスレビュー

Codex CLIを非対話モードで起動して対象の差分をレビューさせ、自分のレビュー(依頼があればリポジトリ固有のレビューSkill)と並列で走らせて、完了後に両者の指摘を統合して報告する。

## 前提確認

1. `command -v codex`でCLIの有無を確認する。無い場合は環境別に案内して終了する。
   - cloudセッション: dotfilesの`scripts/cloud-setup.sh`がcloud環境のsetup scriptに登録されているか、環境キャッシュがスクリプト変更後に再構築されたかを利用者に確認してもらう。
   - ローカル: `npm install -g @openai/codex`等での導入を案内する。
2. `codex login status`で認証状態を確認する。未認証の場合は`codex login --device-auth`をバックグラウンドで実行し、出力されるURLと確認コードをそのまま利用者へ提示して、利用者が手元のブラウザで承認するのを待つ。承認完了を`codex login status`で確認するまでレビューへ進まない。
   - この認証はChatGPTアカウントのサブスクリプション範囲で動作し、APIキーによる従量課金を使わない。
   - `~/.codex/auth.json`は認証情報なので、内容の表示、環境変数への登録、コミットをしない。

## レビュー実行

3. レビュー対象を特定する。PR番号の指定があれば`gh pr checkout <PR番号>`で作業ツリーをPR headへ一致させ、base branchを`gh pr view <PR番号> --json baseRefName`で取得する。指定がなければ現在のブランチの分岐元を対象にする。
4. base branchがローカルに無ければ`git fetch origin <base>`してから、Codexをバックグラウンドで実行する。Codex自身にネットワークアクセスは不要で、作業ツリーの差分をレビューさせる:

   ```bash
   codex exec review --base <base-branch>
   ```

   観点を絞る依頼があれば`codex exec review --base <base-branch> "<観点の指示>"`で渡す。
5. 自分のレビューも依頼されている場合は、Codexの完了を待たずに並列で実施する。

## 統合報告

6. Codexの出力から指摘を抽出し、自分の指摘と統合する。同一file:line・同一趣旨はマージし、各指摘に検出元(Claude / Codex / 両方)を明記する。両方が独立に検出した指摘は、実在を支持する材料として扱う。
7. Codexの指摘も鵜呑みにせず、file:lineの実在と根拠を確認してから報告に載せる。確認できなかった指摘は未検証と明記する。
8. 指示がない限りPRへコメントは投稿せず、結果はこの場で報告するだけにとどめる。
