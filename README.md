# dotfiles

Personal dotfiles managed with Nix. The repository provides a package bundle,
formatting, and a Home Manager entry point without storing machine-specific user
information in the repository.

## Contents

- `flake.nix`: package outputs, formatter, and Home Manager entry points
- `nix/packages.nix`: catalog of packages managed by this repository
- `nix/home.nix`: shared Home Manager settings
- `mise/config.toml`: global versions for language runtimes and development tools
- `zsh/home-manager.zsh`: zsh bridge for standalone Home Manager sessions
- `config/agents/AGENTS.md`: shared instructions for coding agents
- `config/agents/skills/`: curated shared Agent Skills sources
- `config/claude/`: Claude Code user settings and managed assets
- `config/codex/`: Codex settings that can be managed independently of runtime state

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

## Manage Claude Code and Codex

Shared instructions live in `config/agents/AGENTS.md`. Home Manager deploys
them to each product's user-level standard location. Claude Code loads
`config/claude/CLAUDE.md`, which imports the shared instructions and adds only
Claude-specific guidance.

Reusable workflows follow the Agent Skills layout under
`config/agents/skills/`. Keeping the source outside a discovery directory
avoids loading the same skill once from this repository and again from the
user-level path.

Home Manager exposes the same sources at both `~/.agents/skills/` for Codex and
`~/.claude/skills/` for Claude Code. The target directories are populated
recursively so unmanaged, product-specific skills can coexist with the managed
skills.

The curated set contains only focused workflows that are actively maintained:
`gh-activity`, `gh-create-pr`, `git-create-worktree`, and
`japanese-tech-writing`. Domain-specific business knowledge such as CMAPI is
managed outside this repository and is not included in the shared set. Add a
new skill only when a repeated task needs
specialized knowledge, a deterministic script, or a stable output contract.

The complete Claude Code user settings are preserved in
`config/claude/settings.json`. Home Manager does not deploy this file yet:
Claude's plugin commands update the user settings in place, while a normal Home
Manager source would be a read-only Nix store link. Keep the existing writable
settings link active until a writable out-of-store adoption flow is selected.

Codex's `config.toml` is also intentionally not managed because Codex currently
stores both durable preferences and machine-local state in that file. The
separately managed `config/codex/hooks.json` does not require taking ownership
of `config.toml`.

Authentication, histories, caches, sessions, memories, project trust entries,
marketplace refresh timestamps, and generated hook trust hashes are not part of
this repository.

Before applying the configuration, run the checks and a Home Manager dry run:

```sh
scripts/check-agent-config.sh
nix run .#apply -- --dry-run
```

The Home Manager entries do not use `force`. If a legacy file or symlink is
already present, activation stops rather than replacing it. Compare the legacy
target with the corresponding source in this repository and preserve a backup
before adopting the managed path. A normal apply should only be run after the
dry run reports no unexpected collision.

Claude and Codex hooks retain optional integrations with Superset and Herdr.
Those integrations are not installed or managed here; hook commands check for
their environment and scripts and become no-ops when they are unavailable.

### Skills, plugins, and APM

Keep a workflow as a standalone Skill while it is personal or still evolving.
Use a product-specific plugin only when several Skills, hooks, agents, or MCP
servers need to be installed and versioned as one unit.

Microsoft APM is not part of the initial setup. Evaluate it in an isolated
fixture when external Skill dependencies require a lockfile, the same package
must be deployed to more agent products, or duplicated MCP configuration has
become a real maintenance problem. Home Manager and APM must never own the same
generated path.

## Install mise-managed tools

Home Manager deploys `mise/config.toml` to `~/.config/mise/config.toml`. It pins
Python, Node.js, pnpm, Deno, Temurin 21, Zig, uv, Terraform, and actionlint for
the whole user environment.

Apply the Home Manager settings, start a new shell, and install the pinned
versions:

```sh
nix run .#apply
exec zsh
mise install
mise current
```

The configuration is deployed as mise's global config instead of a root-level
`mise.toml`, because these tools should be available outside this repository as
well. A project can still override the global versions with its own
`mise.toml` or `.tool-versions` file.

Existing project-specific version files are also enabled for the managed
tools. For example, mise reads `.node-version`, `.nvmrc`, `.python-version`,
`.deno-version`, `.java-version`, `.terraform-version`, `.zig-version`, and
the Node.js or pnpm version declared in `package.json`. Enter the project and
install any missing version:

```sh
cd path/to/project
mise current
mise install
```

## Use Docker with Colima

Nix manages Colima, the Docker CLI, Buildx, Compose, credential helpers, Lima,
and QEMU. Home Manager links the Buildx and Compose plugins into
`~/.docker/cli-plugins/`; it does not manage `~/.docker/config.json`.

After applying the Home Manager settings, start Colima and verify the Docker
CLI and its plugins:

```sh
nix run .#apply
colima start
docker version
docker buildx version
docker compose version
```

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
