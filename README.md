# dotfiles

Personal dotfiles managed with Nix. The repository provides a package bundle,
formatting, and a Home Manager entry point without storing machine-specific user
information in the repository.

## Contents

- `flake.nix`: package outputs, formatter, and Home Manager entry points
- `nix/packages.nix`: catalog of packages managed by this repository
- `nix/home.nix`: shared Home Manager settings
- `zsh/home-manager.zsh`: zsh bridge for standalone Home Manager sessions

No username or home-directory path is stored in this repository, and the Nix
expressions do not use an impure environment lookup.

## Install managed packages

Install the managed package bundle into the current user's Nix profile:

```sh
nix profile install .#default
```

Individual catalog entries can also be installed directly. The current catalog
contains `jq` as its first entry:

```sh
nix profile install .#jq
```

Start a new zsh session, or reload the current one, and verify the command:

```sh
exec zsh
zsh -lic 'command -v jq; jq --version'
```

## Apply Home Manager settings

Use the repository's entry point to apply the Home Manager settings:

```sh
nix run .#apply
```

Use a dry run first if desired:

```sh
nix run .#apply -- --dry-run
```

The entry point reads the current login name and home directory at the shell
boundary, writes them to a temporary flake input, and then evaluates Home
Manager with those values explicitly. The repository does not contain a fixed
username, and the Home Manager evaluation does not use `--impure`.

The shared module is also available as `homeManagerModules.default` for other
flakes that want to compose it.

## Update managed tools

Update the `nixpkgs` input, review the lock-file change, apply the updated Home
Manager configuration, and verify the tool version:

```sh
nix flake update nixpkgs
git diff -- flake.lock
nix run .#apply
jq --version
```

Use `nix flake update` to update all flake inputs, or
`nix flake update home-manager` to update only Home Manager. This repository
manages tools through the flake and Home Manager, so `nix profile upgrade` is
not normally used.

If an update causes a problem, restore the `flake.lock` change and apply the
configuration again:

```sh
git restore -- flake.lock
nix run .#apply
```

## Format

Format the repository and fail if formatting would change files:

```sh
nix run .#fmt -- --fail-on-change
```

The flake also exposes the standard `formatter` output, so `nix fmt` can be
used locally.

For an existing `~/.zshrc`, load the Home Manager session environment once:

```zsh
# Home Manager
if [[ -r "$HOME/.config/zsh/home-manager.zsh" ]]; then
  source "$HOME/.config/zsh/home-manager.zsh"
fi
```
