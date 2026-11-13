{ pkgs }:
let
  ghPrGraphVersion = "0.15.2";
  ghPrGraphAssets = {
    aarch64-darwin = {
      name = "darwin-arm64";
      hash = "sha256-YFjw/Yd4GTVgZg/jbuW6KPbrGojquQ/aodMWt7tea1E=";
    };
    aarch64-linux = {
      name = "linux-arm64";
      hash = "sha256-EYqkza8exdD+M3Zb6yQyRVjxeIIMDEqa2/xdqykNYLM=";
    };
    x86_64-linux = {
      name = "linux-amd64";
      hash = "sha256-JNQV/yzhgNLPdlBkyye2wuJ0GKA6i7ahxLVyM8RHPgQ=";
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
  # zat 0.5.3 が同梱する tree-sitter-haskell 0.23.1 の array.h には strict aliasing 違反があり、
  # gcc 16 で最適化すると Haskell の解析中にヒープを壊す (checkPhase が SIGABRT で落ちる)。
  # 上流の修正 bglgwyng/zat#3 が取り込まれるまで、Linux では最適化の前提を外してビルドする。
  # macOS は clang でビルドされ、この問題は起きないので、キャッシュ済みの pkgs.zat を使う。
  zat =
    if pkgs.stdenv.hostPlatform.isLinux then
      pkgs.zat.overrideAttrs (old: {
        env = (old.env or { }) // {
          NIX_CFLAGS_COMPILE = "-fno-strict-aliasing";
        };
      })
    else
      pkgs.zat;
  zoxide = pkgs.zoxide;
}
