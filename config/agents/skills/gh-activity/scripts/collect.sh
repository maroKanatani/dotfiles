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
repo_list=()
IFS=',' read -r -a repo_array <<<"$repos"
for repo in "${repo_array[@]}"; do
  repo="${repo#"${repo%%[![:space:]]*}"}"
  repo="${repo%"${repo##*[![:space:]]}"}"
  if [[ ! "$repo" =~ ^[^/[:space:]]+/[^/[:space:]]+$ ]]; then
    printf 'error: invalid repository: %s\n' "$repo" >&2
    exit 2
  fi
  repo_list+=("$repo")
  repo_query="${repo_query} repo:${repo}"
done

username="$(gh api user --jq .login)"
date_range="${since}..${until}"

# GitHub Search APIはis:issue / is:pull-requestのいずれかを必須とする。
# 修飾子のないクエリはHTTP 422で失敗するため、種別ごとに検索して結合する。
search_raw() {
  local query="$1"
  gh api --method GET search/issues \
    -f q="$query" \
    -f per_page=100 \
    --paginate \
    --slurp |
    jq '[.[].items[]]'
}

status_filter='
  if .pull_request then
    if (.pull_request.merged_at // "") != "" then "Merged"
    elif .state == "open" then (if .draft then "Draft" else "PR" end)
    else "Close"
    end
  else
    if .state == "open" then "Open"
    else "Close"
    end
  end
'

transform='[.[] | {
  repo: (.repository_url | split("/") | .[-2:] | join("/")),
  number,
  title,
  url: .html_url,
  type: (if .pull_request then "pr" else "issue" end),
  state,
  status: ('"$status_filter"'),
  labels: [.labels[].name],
  created_at,
  updated_at,
  merged_at: (.pull_request.merged_at // null),
  draft: (.draft // false),
  author: .user.login
}]'

search_items() {
  search_raw "$1" | jq "$transform"
}

# 同一itemが複数クエリで重複するため、repo#numberで排除する
dedupe() {
  jq -s 'add | group_by(.repo + "#" + (.number | tostring)) | map(.[0])'
}

printf 'Collecting data for %s in [%s] from %s to %s...\n' "$username" "$repos" "$since" "$until" >&2

printf '  [1/5] Created issues...\n' >&2
created_issues="$(search_items "is:issue author:${username} created:${date_range}${repo_query}")"

# 期間内に動いた自作PRに加えて、現在Openの自作PRを更新日時を問わず拾う。
# 更新が止まったままレビュー待ちのPRを落とさないため。
printf '  [2/5] Created PRs (updated in range + currently open)...\n' >&2
prs_updated="$(search_items "is:pr author:${username} updated:${date_range}${repo_query}")"
prs_open="$(search_items "is:pr author:${username} is:open created:<=${until}${repo_query}")"
created_prs="$(printf '%s\n%s' "$prs_updated" "$prs_open" | dedupe)"

printf '  [3/5] Reviewed PRs...\n' >&2
reviewed_prs="$(search_items "is:pr reviewed-by:${username} updated:${date_range} -author:${username}${repo_query}")"

printf '  [4/5] Commented PRs and issues...\n' >&2
commented_prs="$(search_items "is:pr commenter:${username} updated:${date_range} -author:${username}${repo_query}")"
commented_issues="$(search_items "is:issue commenter:${username} updated:${date_range} -author:${username}${repo_query}")"
reviews="$(printf '%s\n%s' "$reviewed_prs" "$commented_prs" | dedupe)"

printf '  [5/5] Assigned issues and PRs...\n' >&2
assigned_issues="$(search_items "is:issue assignee:${username} updated:${date_range}${repo_query}")"
assigned_prs="$(search_items "is:pr assignee:${username} updated:${date_range}${repo_query}")"
assigned="$(printf '%s\n%s' "$assigned_issues" "$assigned_prs" | dedupe)"

jq -n \
  --arg generated_at "$(date -Iseconds)" \
  --arg since "$since" \
  --arg until "$until" \
  --arg user "$username" \
  --argjson repos "$(printf '%s\n' "${repo_list[@]}" | jq -R . | jq -s .)" \
  --argjson created_issues "$created_issues" \
  --argjson created_prs "$created_prs" \
  --argjson reviews "$reviews" \
  --argjson commented_issues "$commented_issues" \
  --argjson assigned "$assigned" \
  '{
    metadata: {
      generated_at: $generated_at,
      since: $since,
      until: $until,
      user: $user,
      repos: $repos,
      limitations: [
        "GitHub Search API returns at most 1000 results per query.",
        "created_prs includes PRs merely updated in the range by anyone, plus every currently open PR regardless of update time.",
        "reviews, commented_issues and assigned use the item updated timestamp, not the review, comment or assignment timestamp."
      ]
    },
    created_issues: $created_issues,
    created_prs: $created_prs,
    reviews: $reviews,
    commented_issues: $commented_issues,
    assigned: $assigned
  }'

printf 'Done.\n' >&2
