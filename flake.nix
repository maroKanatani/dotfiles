{
  description = "Personal dotfiles";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

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
          # cloud session の VM 向け。VM の中では使えない仮想化と Docker の道具を除く。
          cloud = pkgs.buildEnv {
            name = "dotfiles-packages-cloud";
            paths = builtins.attrValues (
              removeAttrs packageSet [
                "colima"
                "docker"
                "docker-buildx"
                "docker-compose"
                "docker-credential-helpers"
                "lima"
                "qemu"
              ]
            );
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
