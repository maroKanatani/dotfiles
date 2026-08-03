{ config, pkgs, ... }:
{
  home.stateVersion = "26.05";

  home.packages = builtins.attrValues (import ./packages.nix { inherit pkgs; });

  home.sessionPath = [
    "${config.home.profileDirectory}/bin"
  ];

  home.file.".config/zsh/home-manager.zsh".source = ../zsh/home-manager.zsh;

  programs.home-manager.enable = true;
}
