---
name: x-fetch-post
description: "X(旧Twitter)の投稿URLから本文を確実に取得する。ユーザーがX/Twitterの投稿内容の確認・引用・要約・レビューを依頼したとき、または会話にX/Twitterの投稿URLが含まれるときに使用する。通常のWebFetchがログイン要求やアクセス制限で失敗した場合の代替手段として使う。"
---

# X投稿の本文を取得する

`scripts/fetch.sh`が、まずX公式のoEmbed API(`publish.twitter.com/oembed`)で投稿本文を取得する。oEmbedは埋め込みウィジェット表示用の仕様上、長文投稿の本文を末尾「…」で省略することがある。省略を検知した場合に限り、非公式ミラーAPI(fxtwitter)へ自動フォールバックする。WebFetchがX公式ドメインへの直接アクセスで失敗しても、この手順を試すまでは取得不可と報告しない。

## 手順

1. 対象のX/TwitterステータスURLを確認する(`https://x.com/<user>/status/<id>`または`https://twitter.com/<user>/status/<id>`)。
2. このSkillのルートで取得スクリプトを実行する。

   ```bash
   bash scripts/fetch.sh "https://x.com/<user>/status/<id>"
   ```

   成功すると`{url, author_name, author_url, text, source}`のJSONをstdoutへ出す。`source`は取得経路(`oembed`または`fxtwitter-fallback`)を示す。非ゼロ終了ならstderrの内容を確認し、下記の代替手順に進む。
3. `text`を本文として扱う。`source`が`fxtwitter-fallback`の場合、非公式ミラー経由で取得したことをユーザーへの報告に明記する。
4. スレッド(自己リプライの連投)の後続または先行の投稿を確認する依頼では、該当URLをユーザーの発言や参照元から特定し、同じ手順で個別に取得する。取得APIはいずれもスレッド内の他ツイート一覧を返さないため、URLが特定できない場合はユーザーに確認する。

## 失敗時の代替手順

oEmbedとfxtwitterの両方が失敗しても、その時点で「取得できません」と報告しない。次を順に試す。

1. WebSearchで投稿の引用や転載がないか検索する。
2. それでも取得できない場合のみ未確認と明示し、投稿本文の共有をユーザーに依頼する。

## 安全条件

- oEmbedはX公式が埋め込みウィジェット生成のために公開しているAPIで、規約上の懸念はない。fxtwitterはXの非公式サードパーティミラーであり、X公式サービスではない。可用性はXが保証せず、規約上の位置づけも公式には確認できていない。oEmbedで本文が完全に取得できる限り、fxtwitterは使わない。
- 公開投稿のみ取得できる。鍵アカウントや削除済み投稿は取得できず、認証情報を使って回避しない。
- ユーザーが指定したURL以外の投稿やアカウントの情報を、依頼にない範囲まで収集しない。
