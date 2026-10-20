{ config, pkgs, ... }:
let
  packages = import ./packages.nix { inherit pkgs; };
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
  # エージェント設定(AGENTS.md、Skill、settings.json、hooks)はここでは配布しない。
  # ローカルとクラウドの両方へ同じ経路で届ける必要があり、Nix の無いクラウド VM
  # にも届く唯一の経路が scripts/deploy-agent-config.sh による checkout への
  # リンクだから。Nix が担うのはこのマシンに入れるツールだけ。
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
