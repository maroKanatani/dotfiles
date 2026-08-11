{
  description = "Personal dotfiles";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Nixpkgs may lag behind tirith fixes that are important for this scan.
    # Keep the scanner itself pinned independently of the system package set.
    tirith.url = "github:sheeki03/tirith/e748ca15e07e3e106e483535562a226a72df7b1f";
  };

  outputs =
    { nixpkgs, home-manager, ... }:
    let
      systems = [
        "aarch64-darwin"
        "aarch64-linux"
        "x86_64-linux"
      ];

      forAllSystems = nixpkgs.lib.genAttrs systems;

      packagesFor =
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          packageSet = import ./nix/packages.nix { inherit pkgs; };
        in
        packageSet
        // {
          default = pkgs.buildEnv {
            name = "dotfiles-packages";
            paths = builtins.attrValues packageSet;
          };
        };

      appsFor =
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          dotfilesSource = toString ./.;
          nixpkgsSource = toString nixpkgs;
          homeManagerSource = toString home-manager;

          apply = pkgs.writeShellApplication {
            name = "dotfiles-apply";
            runtimeInputs = [
              pkgs.coreutils
              pkgs.nix
              home-manager.packages.${system}.home-manager
            ];
            text = ''
              set -eu

              config_dir="$(mktemp -d)"
              trap 'rm -rf "$config_dir"' EXIT

              printf '%s' "$(id -un)" > "$config_dir/username"
              printf '%s' "$HOME" > "$config_dir/home-directory"

              cat > "$config_dir/flake.nix" <<EOF
              {
                inputs = {
                  nixpkgs.url = "path:${nixpkgsSource}";
                  home-manager = {
                    url = "path:${homeManagerSource}";
                    inputs.nixpkgs.follows = "nixpkgs";
                  };
                  dotfiles.url = "path:${dotfilesSource}";
                };

                outputs = { nixpkgs, home-manager, dotfiles, ... }:
                  {
                    homeConfigurations.default =
                      home-manager.lib.homeManagerConfiguration {
                        pkgs = nixpkgs.legacyPackages.${system};
                        modules = [
                          dotfiles.homeManagerModules.default
                          {
                            home.username = builtins.readFile ./username;
                            home.homeDirectory = builtins.readFile ./home-directory;
                          }
                        ];
                      };
                  };
              }
              EOF

              home-manager switch --flake "$config_dir#default" "$@"
            '';
          };
        in
        {
          fmt = {
            type = "app";
            program = "${pkgs.nixfmt-tree}/bin/treefmt";
          };

          apply = {
            type = "app";
            program = "${apply}/bin/dotfiles-apply";
          };
        };
    in
    {
      packages = forAllSystems packagesFor;
      formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.nixfmt-tree);
      apps = forAllSystems appsFor;
      homeManagerModules.default = ./nix/home.nix;
    };
}
