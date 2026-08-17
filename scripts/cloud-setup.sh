#!/usr/bin/env bash

# Deploy the shared agent configuration into a Claude Code cloud session VM.
# Cloud sessions read only the cloned repository and the VM's own home
# directory, so the Home Manager links in nix/home.nix never reach them.
# Register the bootstrap command in the cloud environment's setup script field:
#
#   git clone --depth 1 https://github.com/maroKanatani/dotfiles.git /opt/dotfiles
#   bash /opt/dotfiles/scripts/cloud-setup.sh
#   exit 0

set -uo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
claude_home="${HOME:-/root}/.claude"

link() {
  local source_path="$1"
  local target_path="$2"

  if [[ -e "$target_path" && ! -L "$target_path" ]]; then
    printf 'cloud-setup: kept existing path: %s\n' "$target_path" >&2
    return
  fi

  ln -sfn "$source_path" "$target_path"
  printf 'cloud-setup: linked %s -> %s\n' "$target_path" "$source_path"
}

mkdir -p "$claude_home/rules" "$claude_home/skills"
link "$repo_root/config/agents/AGENTS.md" "$claude_home/rules/common.md"

# Link each skill individually so unmanaged skills in the session image can
# coexist, matching the recursive Home Manager deployment.
for skill_source in "$repo_root"/config/agents/skills/*/; do
  link "${skill_source%/}" "$claude_home/skills/$(basename "$skill_source")"
done

exit 0
