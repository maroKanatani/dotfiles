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
  home.file.".docker/cli-plugins/docker-buildx".source =
    "${pkgs.docker-buildx}/libexec/docker/cli-plugins/docker-buildx";
  home.file.".docker/cli-plugins/docker-compose".source =
    "${pkgs.docker-compose}/libexec/docker/cli-plugins/docker-compose";

  programs.home-manager.enable = true;
}
