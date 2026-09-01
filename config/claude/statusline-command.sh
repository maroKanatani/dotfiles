#!/bin/bash
# Claude Code statusline script
# Displays: folder path, repo|branch|PR, context|model, 5h/7d usage, cost, worktree

input=$(cat)

# Parse statusline JSON
cwd=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // ""')
# rate_limits 側と同じ整数への整形。小数が来ると後続の $(( )) が構文エラーになる
used_pct=$(echo "$input" | jq -r '.context_window.used_percentage // 0' | awk '{printf "%d", $1}')
model=$(echo "$input" | jq -r '.model.display_name // ""')
pct_5h=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // 0' | awk '{printf "%d", $1}')
pct_7d=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // 0' | awk '{printf "%d", $1}')
cost=$(echo "$input" | jq -r '.cost.total_cost_usd // 0' | awk '{printf "$%.2f", $1}')
duration_ms=$(echo "$input" | jq -r '.cost.total_duration_ms // 0')
duration_min=$(echo "$duration_ms" | awk '{printf "%d", $1/60000}')
wt_name=$(echo "$input" | jq -r '.worktree.name // ""')
agent_name=$(echo "$input" | jq -r '.agent.name // ""')

# Git info
repo_name=""
branch_name=""
if git -C "$cwd" rev-parse --git-dir > /dev/null 2>&1; then
  repo_name=$(basename "$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null)")
  branch_name=$(git -C "$cwd" --no-optional-locks symbolic-ref --short HEAD 2>/dev/null || git -C "$cwd" --no-optional-locks rev-parse --short HEAD 2>/dev/null)
fi

# PR number for current branch (cached 5min, refreshed in background)
pr_num=""
if [ -n "$branch_name" ] && command -v gh > /dev/null 2>&1; then
  repo_root=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null)
  cache="/tmp/statusline-pr-$(id -u)-$(printf '%s|%s' "$repo_root" "$branch_name" | tr -c 'A-Za-z0-9' '_')"
  [ -f "$cache" ] && pr_num=$(cat "$cache")
  if [ -z "$(find "$cache" -mmin -5 2>/dev/null)" ]; then
    (cd "$repo_root" && gh pr view "$branch_name" --json number -q '.number // empty' > "$cache.tmp" 2>/dev/null
     mv -f "$cache.tmp" "$cache" 2>/dev/null) < /dev/null > /dev/null 2>&1 &
  fi
fi

# Progress bar
progress_bar() {
  local pct=$1 width=20
  local filled=$(( pct * width / 100 ))
  local empty=$(( width - filled ))
  local bar=""
  for ((i=0; i<filled; i++)); do bar+="█"; done
  for ((i=0; i<empty; i++)); do bar+="░"; done
  echo "$bar"
}

bar=$(progress_bar "$used_pct")

# --- Output ---

# Line 1: 📁 full path
printf '📁 %s\n' "$cwd"

# Line 2: 🐙 repo | 🌿 branch
if [ -n "$repo_name" ] && [ -n "$branch_name" ]; then
  if [ -n "$pr_num" ]; then
    printf '🐙 %s | 🌿 %s | 🔀 #%s\n' "$repo_name" "$branch_name" "$pr_num"
  else
    printf '🐙 %s | 🌿 %s\n' "$repo_name" "$branch_name"
  fi
elif [ -n "$repo_name" ]; then
  printf '🐙 %s\n' "$repo_name"
fi

# Line 3: 🧠 context bar % | 💪 model
printf '🧠 %s %s%% | 💪 %s\n' "$bar" "$used_pct" "$model"

# Line 4: 💰 5h/7d usage | cost | duration
printf '💰 5h %s%% | 7d %s%% | 💵 %s | ⏱ %sm\n' "$pct_5h" "$pct_7d" "$cost" "$duration_min"

# Line 5: 🌲 Worktree (only when in a worktree)
if [ -n "$wt_name" ]; then
  printf '🌲 %s\n' "$wt_name"
fi

# Line 6: 🤖 Agent name (only when a subagent is active)
if [ -n "$agent_name" ]; then
  printf '🤖 %s\n' "$agent_name"
fi
