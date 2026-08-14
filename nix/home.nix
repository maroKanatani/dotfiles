{ config, pkgs, ... }:
{
  home.stateVersion = "26.05";

  home.packages = builtins.attrValues (import ./packages.nix { inherit pkgs; });

  home.sessionPath = [
    "${config.home.profileDirectory}/bin"
  ];

  home.sessionVariables.MISE_IDIOMATIC_VERSION_FILE_ENABLE_TOOLS = "node,python,deno,java,pnpm,terraform,zig";

  home.file.".config/zsh/home-manager.zsh".source = ../zsh/home-manager.zsh;
  home.file.".config/mise/config.toml".source = ../mise/config.toml;
  # Agent configuration is linked without force. Home Manager will stop instead
  # of replacing an existing file, which makes adoption of legacy dotfiles
  # explicit and recoverable.
  home.file.".codex/AGENTS.md".source = ../config/agents/AGENTS.md;
  home.file.".codex/hooks.json".source = ../config/codex/hooks.json;
  home.file.".codex/rules/git-workflow.rules".source = ../config/codex/rules/git-workflow.rules;
  home.file.".claude/rules/common.md".source = ../config/agents/AGENTS.md;
  home.file.".claude/statusline-command.sh".source = ../config/claude/statusline-command.sh;
  home.file.".agents/skills" = {
    source = ../config/agents/skills;
    recursive = true;
  };
  home.file.".claude/skills" = {
    source = ../config/agents/skills;
    recursive = true;
  };
  home.file.".docker/cli-plugins/docker-buildx".source =
    "${pkgs.docker-buildx}/libexec/docker/cli-plugins/docker-buildx";
  home.file.".docker/cli-plugins/docker-compose".source =
    "${pkgs.docker-compose}/libexec/docker/cli-plugins/docker-compose";

  programs.home-manager.enable = true;
}
