#!/usr/bin/env bash

set -euo pipefail

since=""
until=""
repos=""

usage() {
  printf 'Usage: %s --since YYYY-MM-DD --until YYYY-MM-DD --repos owner/repo[,owner/repo...]\n' "$0" >&2
}

while (($# > 0)); do
  case "$1" in
    --since)
      since="${2:-}"
      shift 2
      ;;
    --until)
      until="${2:-}"
      shift 2
      ;;
    --repos)
      repos="${2:-}"
      shift 2
      ;;
    *)
      usage
      exit 2
      ;;
  esac
done

if [[ ! "$since" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] ||
  [[ ! "$until" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] ||
  [[ -z "$repos" ]]; then
  usage
  exit 2
fi

command -v gh >/dev/null 2>&1 || {
  printf 'error: gh is required\n' >&2
  exit 1
}
command -v jq >/dev/null 2>&1 || {
  printf 'error: jq is required\n' >&2
  exit 1
}
gh auth status >/dev/null

repo_query=""
IFS=',' read -r -a repo_list <<<"$repos"
for repo in "${repo_list[@]}"; do
  repo="${repo#"${repo%%[![:space:]]*}"}"
  repo="${repo%"${repo##*[![:space:]]}"}"
  if [[ ! "$repo" =~ ^[^/[:space:]]+/[^/[:space:]]+$ ]]; then
    printf 'error: invalid repository: %s\n' "$repo" >&2
    exit 2
  fi
  repo_query="${repo_query} repo:${repo}"
done

username="$(gh api user --jq .login)"
date_range="${since}..${until}"

search_items() {
  local query="$1"
  gh api --method GET search/issues \
    -f q="$query" \
    -f per_page=100 \
    --paginate \
    --slurp |
    jq '[.[].items[] | {
      repo: (.repository_url | split("/") | .[-2:] | join("/")),
      number,
      title,
      url: .html_url,
      state,
      created_at,
      updated_at
    }]'
}

created_issues="$(search_items "is:issue author:${username} created:${date_range}${repo_query}")"
created_prs="$(search_items "is:pr author:${username} created:${date_range}${repo_query}")"
merged_prs="$(search_items "is:pr author:${username} merged:${date_range}${repo_query}")"
reviewed_pr_candidates="$(search_items "is:pr reviewed-by:${username} updated:${date_range} -author:${username}${repo_query}")"
# GitHub Search APIはis:issue / is:pull-requestのいずれかを必須とするため、種別ごとに検索して結合する
commented_pr_candidates="$(search_items "is:pr commenter:${username} updated:${date_range} -author:${username}${repo_query}")"
commented_issue_candidates="$(search_items "is:issue commenter:${username} updated:${date_range} -author:${username}${repo_query}")"
commented_item_candidates="$(jq -n \
  --argjson prs "$commented_pr_candidates" \
  --argjson issues "$commented_issue_candidates" \
  '$prs + $issues')"

jq -n \
  --arg since "$since" \
  --arg until "$until" \
  --arg user "$username" \
  --argjson created_issues "$created_issues" \
  --argjson created_prs "$created_prs" \
  --argjson merged_prs "$merged_prs" \
  --argjson reviewed_pr_candidates "$reviewed_pr_candidates" \
  --argjson commented_item_candidates "$commented_item_candidates" \
  '{
    metadata: {
      since: $since,
      until: $until,
      user: $user,
      limitations: [
        "GitHub Search API returns at most 1000 results per query.",
        "reviewed_pr_candidates and commented_item_candidates use the item updated timestamp, not the review or comment timestamp."
      ]
    },
    created_issues: $created_issues,
    created_prs: $created_prs,
    merged_prs: $merged_prs,
    reviewed_pr_candidates: $reviewed_pr_candidates,
    commented_item_candidates: $commented_item_candidates
  }'
