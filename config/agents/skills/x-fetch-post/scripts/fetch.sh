#!/usr/bin/env bash

set -euo pipefail

usage() {
  printf 'Usage: %s <X/TwitterのステータスURL>\n' "$0" >&2
  exit 2
}

if (($# != 1)); then
  usage
fi

url="$1"

if [[ ! "$url" =~ ^https?://(x\.com|twitter\.com)/([^/?]+)/status/([0-9]+) ]]; then
  printf 'error: URLの形式が不正です（例: https://x.com/user/status/123456789012345678）: %s\n' "$url" >&2
  exit 1
fi

screen_name="${BASH_REMATCH[2]}"
status_id="${BASH_REMATCH[3]}"

decode_html_text() {
  python3 -c '
import sys, re, html
raw = sys.stdin.read()
m = re.search(r"<p[^>]*>(.*?)</p>", raw, re.S)
body = m.group(1) if m else raw
body = re.sub(r"<br\s*/?>", "\n", body)
body = re.sub(r"<[^>]+>", "", body)
print(html.unescape(body).strip())
'
}

oembed="$(curl -sS -f -L -G "https://publish.twitter.com/oembed" --data-urlencode "url=${url}" 2>/dev/null)" || oembed=""

if [[ -n "$oembed" ]]; then
  text="$(printf '%s' "$oembed" | jq -r '.html' | decode_html_text)"
  if [[ "$text" != *"…" ]]; then
    printf '%s' "$oembed" | jq --arg text "$text" \
      '{url: .url, author_name: .author_name, author_url: .author_url, text: $text, source: "oembed"}'
    exit 0
  fi
  printf 'warning: oEmbedの本文が省略されている可能性があるため、非公式ミラーへフォールバックします: %s\n' "$url" >&2
fi

fallback="$(curl -sS -f "https://api.fxtwitter.com/${screen_name}/status/${status_id}")" || {
  printf 'error: X公式oEmbedと非公式ミラー(fxtwitter)の両方で取得に失敗しました。SKILL.mdの代替手順（WebSearch、ユーザーへの確認）を試してください: %s\n' "$url" >&2
  exit 1
}

printf '%s' "$fallback" | jq \
  '{url: .tweet.url, author_name: .tweet.author.name, author_url: .tweet.author.url, text: .tweet.text, source: "fxtwitter-fallback"}'
