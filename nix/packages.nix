{ pkgs }:
let
  ghPrGraphVersion = "0.14.5";
  ghPrGraphAssets = {
    aarch64-darwin = {
      name = "darwin-arm64";
      hash = "sha256-rvaXDwVLx3eo1FQ4pz42eVYjr0A4Iy2bEIc1xZn0Mis=";
    };
    aarch64-linux = {
      name = "linux-arm64";
      hash = "sha256-KesZnPG5r6GgYQAh/qEQSTk/xu5jeHoSqVhm/0nEpcs=";
    };
    x86_64-linux = {
      name = "linux-amd64";
      hash = "sha256-Ppe1ByxaFoJNDfYg2x2rOUQs9PqXAWjRE2mMDvKS1nI=";
    };
  };
  ghPrGraphAsset = ghPrGraphAssets.${pkgs.stdenv.hostPlatform.system};
in
{
  bat = pkgs.bat;
  colima = pkgs.colima;
  direnv = pkgs.direnv;
  docker = pkgs.docker-client;
  docker-buildx = pkgs.docker-buildx;
  docker-compose = pkgs.docker-compose;
  docker-credential-helpers = pkgs.docker-credential-helpers;
  eza = pkgs.eza;
  fd = pkgs.fd;
  fzf = pkgs.fzf;
  gh = pkgs.gh;
  gh-pr-graph = pkgs.stdenvNoCC.mkDerivation {
    pname = "gh-pr-graph";
    version = ghPrGraphVersion;
    src = pkgs.fetchurl {
      url = "https://github.com/orangain/gh-pr-graph/releases/download/v${ghPrGraphVersion}/${ghPrGraphAsset.name}";
      hash = ghPrGraphAsset.hash;
    };
    dontUnpack = true;
    installPhase = ''
      runHook preInstall
      install -Dm755 "$src" "$out/bin/gh-pr-graph"
      runHook postInstall
    '';
    meta = {
      description = "GitHub CLI extension for visualizing pull requests and stacked branches";
      homepage = "https://github.com/orangain/gh-pr-graph";
      license = pkgs.lib.licenses.mit;
      mainProgram = "gh-pr-graph";
      platforms = builtins.attrNames ghPrGraphAssets;
    };
  };
  herdr = pkgs.herdr;
  jq = pkgs.jq;
  lazygit = pkgs.lazygit;
  lima = pkgs.lima;
  mise = pkgs.mise;
  neovim = pkgs.neovim;
  qemu = pkgs.qemu;
  ripgrep = pkgs.ripgrep;
  starship = pkgs.starship;
  tmux = pkgs.tmux;
  tree = pkgs.tree;
  yq = pkgs.yq;
  zat = pkgs.zat;
  zoxide = pkgs.zoxide;
}
