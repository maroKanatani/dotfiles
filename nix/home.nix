{ config, pkgs, ... }:
let
  packages = import ./packages.nix { inherit pkgs; };
  # 日本語の文書作成・推敲Skill。既存の日本語文章Skillを置き換えるため、
  # 外部リポジトリをcommit固定で取り込む。
  naturalJapanese = pkgs.fetchFromGitHub {
    owner = "coji";
    repo = "natural-japanese";
    rev = "21e632661a910bf97289c501089ad11eb8b4d85f"; # v1.5.0
    hash = "sha256-2haz6fzdiUlUkzzmyxIEzIAFCig3we54sb01RX5zD0c=";
  };
in
{
  home.stateVersion = "26.05";

  home.packages = builtins.attrValues packages;

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
  # settings.json の Stop hook が参照する通知音。recursive にして実ディレクトリを
  # 作り、Herdr が ~/.claude/hooks/ へ自分のスクリプトを書けるようにする。
  home.file.".claude/hooks" = {
    source = ../config/claude/hooks;
    recursive = true;
  };
  home.file.".agents/skills" = {
    source = ../config/agents/skills;
    recursive = true;
  };
  home.file.".claude/skills" = {
    source = ../config/agents/skills;
    recursive = true;
  };
  # Herdr ships its own agent skill inside the package. Deploying that copy
  # keeps the skill and the binary on the same version instead of letting a
  # vendored snapshot drift away from the installed CLI.
  home.file.".agents/skills/herdr/SKILL.md".source =
    "${packages.herdr}/share/herdr/skills/herdr/SKILL.md";
  home.file.".claude/skills/herdr/SKILL.md".source =
    "${packages.herdr}/share/herdr/skills/herdr/SKILL.md";
  home.file.".agents/skills/natural-japanese".source =
    "${naturalJapanese}/skills/natural-japanese";
  home.file.".claude/skills/natural-japanese".source =
    "${naturalJapanese}/skills/natural-japanese";
  home.file.".docker/cli-plugins/docker-buildx".source =
    "${pkgs.docker-buildx}/libexec/docker/cli-plugins/docker-buildx";
  home.file.".docker/cli-plugins/docker-compose".source =
    "${pkgs.docker-compose}/libexec/docker/cli-plugins/docker-compose";

  # gh extensions are declared here instead of being installed at runtime with
  # `gh extension install`. Home Manager owns the whole extension directory, so
  # every extension has to be listed; `gh cache` replaced gh-actions-cache in
  # gh itself, which is why only gh-poi remains.
  programs.gh = {
    enable = true;
    package = packages.gh;
    extensions = [
      pkgs.gh-dash
      pkgs.gh-f
      pkgs.gh-markdown-preview
      pkgs.gh-poi
      pkgs.gh-stack
      packages.gh-pr-graph
    ];
    settings = {
      git_protocol = "https";
      aliases.co = "pr checkout";
    };
  };

  programs.home-manager.enable = true;
}
