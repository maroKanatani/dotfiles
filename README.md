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
- `scripts/`: `apply.sh` for this machine, `cloud-setup.sh` for cloud VMs; both call `setup-agents.sh`, the single agent-configuration path

No username or home-directory path is stored in this repository, and the Nix
expressions do not use an impure environment lookup.

## Design

Nix declares the tools installed on this machine. Agent configuration is kept
in this repository as the source of truth and deployed, on every environment,
by one script that links the checkout into the home directory and installs the
declared plugins. `~/.claude/settings.json` is a link too, so what the CLI
writes shows up as a diff in this repository.

| Concern | Managed by | Why |
|---|---|---|
| Packages, mise, zsh, gh extensions, Docker plugins | `nix/home.nix` | Only this machine needs them; reproducible versions matter |
| `AGENTS.md`, own Skills, status line, Codex rules | `scripts/setup-agents.sh`, linked | Needed on the local machine and on cloud VMs, which have no Nix |
| `~/.claude/settings.json` | same script, linked | CLI edits become reviewable diffs instead of being overwritten |
| Plugins | same script, from `settings.json` | One declaration installs the same plugins locally and in the cloud |
| Codex `config.toml`, authentication | not managed | Generated and updated by the CLIs themselves |

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

User-level shared instructions live in `config/agents/AGENTS.md`. This
repository's own instructions live in the root `AGENTS.md`; `CLAUDE.md` imports
it for Claude Code.

`scripts/setup-agents.sh` links the checkout into the home directory and then
installs the declared plugins. It needs only `git` and `python3`, and running
it again changes nothing.

| Source | Target |
|---|---|
| `config/agents/AGENTS.md` | `~/.claude/rules/common.md`, `~/.codex/AGENTS.md` |
| `config/claude/rules/pstack-models.md` | `~/.claude/rules/pstack-models.md` |
| `config/agents/skills/<name>/` | `~/.claude/skills/<name>`, `~/.agents/skills/<name>` |
| `config/claude/settings.json` | `~/.claude/settings.json` |
| `config/claude/statusline-command.sh` | `~/.claude/statusline-command.sh` |
| `config/claude/hooks/notification/completed.wav` | `~/.claude/hooks/notification/completed.wav` |
| `config/codex/rules/*.rules` | `~/.codex/rules/` |

An existing regular file or non-empty directory at a target is kept and
reported instead of replaced. A link that points into this checkout at a file
that no longer exists is removed, so deleting a Skill here also removes it from
the home directory on the next run.

Locally `scripts/apply.sh` runs the Home Manager apply and then this script.
On a cloud VM `scripts/cloud-setup.sh` runs the same script, so both
environments get the same files and the same plugins from one source.

```sh
scripts/apply.sh --dry-run
scripts/apply.sh
```

`--dry-run` covers Home Manager only; `setup-agents.sh` has no read-only mode
and is skipped.

### Settings

`~/.claude/settings.json` is a one-level absolute symlink to
`config/claude/settings.json`. Whatever Claude Code writes, such as `/model`,
`/effort`, or `claude plugin install`, lands in this repository: review it with
`git diff` and commit it or discard it. Nothing is overwritten on apply, so
there is no copy to carry back.

On Claude Code 2.1.322 the link survived `claude plugin disable`,
`claude plugin enable`, and `/effort`. Reports of the link being replaced by a
regular file concern chains of two or more links and links through read-only
locations (https://github.com/anthropics/claude-code/issues/78162), so keep it
at one level. If `ls -l ~/.claude/settings.json` ever shows a regular file,
run `scripts/setup-agents.sh` again: it moves the file to
`settings.json.pre-link.bak` once and restores the link.

The CLI reorders the top-level keys when it saves. The tracked file is kept in
that order so later saves do not produce reordering noise.

Permission decisions are delegated to auto mode; `autoMode.soft_deny` keeps
merges, Ready-for-review, close, and remote deletions behind an explicit user
instruction, while commits, pushes, Draft PRs, and file edits run unattended.

### Plugins and Skills

pstack, Matt Pocock's skills, and yomiyasu are the centre of the workflow, and
all three are installed as plugins rather than copied. The declaration is the
`enabledPlugins` and `extraKnownMarketplaces` keys of
`config/claude/settings.json`:

| Plugin | Marketplace |
|---|---|
| `pstack@cursor-plugins` | `cursor/plugins` |
| `mattpocock-skills@claude-plugins-official` | `anthropics/claude-plugins-official` |
| `yomiyasu@yomiyasu` | `nanaism/yomiyasu` |
| `codex@openai-codex` | `openai/codex-plugin-cc` |

`setup-agents.sh` reads that declaration and runs `claude plugin install` and
`codex plugin add` for every enabled entry. A declaration alone is not enough
in a cloud session, which does not install declared plugins by itself.
`codex@openai-codex` calls Codex from Claude Code, so it is not added to Codex.

To add a plugin, run `claude plugin marketplace add` and
`claude plugin install` once and commit the resulting diff. To remove one, run
`claude plugin uninstall` and commit; the script never uninstalls.

pstack does not list Codex as a target. Codex reads its `.claude-plugin`
manifest, so the skills load, but treat that as best effort.

The only Skill kept in this repository is `gh-activity`, which has no plugin
equivalent. Add another one only when a repeated task needs specialized
knowledge, a deterministic script, or a stable output contract, and no adopted
plugin covers it.

pstack reads its per-role model choices from `~/.claude/rules/pstack-models.md`.
The tracked copy under `config/claude/rules/` is the source of truth and is
linked by the setup script, so cloud sessions get the same mapping. To change
it, run `/pstack:setup-pstack`, then copy the written file back into the
repository.

`setup-matt-pocock-skills` writes `docs/agents/*.md` and an `## Agent skills`
section into whichever repository it runs in, so run it only where that
per-repository configuration is wanted. Turn an individual skill off through
the plugin instead of copying an edited file into `config/agents/skills/`.

### Hooks

Two hooks remain. The completion sound plays on Stop and is a no-op where
`afplay` is missing. The yomiyasu hook is the plugin's own
`scripts/yomiyasu_hook.py`; the command in `settings.json` resolves the newest
installed version at run time and exits 0 when the plugin is absent, so a
missing file can never block a tool call.

The yomiyasu hook only acts on a draft that was registered with
`yomiyasu_check.py start`. It does not lint every reply. Japanese text is
polished by invoking the `yomiyasu:yomiyasu` Skill, as the shared instructions
require. No hook is registered for Codex.

### Codex

Codex's `config.toml` is intentionally not managed because Codex stores both
durable preferences and machine-local state in that file. Do not copy its
generated marketplace, plugin, or hook-trust state into this repository.

Authentication, histories, caches, sessions, memories, project trust entries,
and marketplace refresh timestamps are not part of this repository.

### Checks

Before applying a change to the agent configuration:

```sh
for script in scripts/*.sh; do bash -n "$script"; done
python3 -m json.tool config/claude/settings.json > /dev/null
scripts/apply.sh --dry-run
```

### Claude Code cloud sessions

Cloud sessions, which include Claude Code on the web, `claude --cloud`, and
routines, run on a fresh VM. Register the bootstrap in the **Setup script**
field of the cloud environment at [claude.ai/code](https://claude.ai/code):

```sh
git clone --depth 1 https://github.com/maroKanatani/dotfiles.git /opt/dotfiles
bash /opt/dotfiles/scripts/cloud-setup.sh
exit 0
```

`scripts/cloud-setup.sh` installs the Codex CLI and then runs
`scripts/setup-agents.sh`. One environment-level registration covers every
repository, so no personal configuration is committed to a project's `.claude/`
directory.

What was confirmed on real cloud runs:

- The session reads the VM's own `~/.claude/settings.json`, hooks, rules, and
  Skills written by the setup script. Only the files on your local machine are
  not carried over.
- `claude` is on the PATH while the setup script runs, and a plugin installed
  there with `claude plugin install` is loaded by the session. Plugin skills
  therefore have the same names as on the local machine, for example
  `/pstack:poteto-mode`.
- Installing a plugin from inside a running cloud session is refused by the
  auto mode classifier, so the setup script is the only place to do it.

The setup script runs when an environment has no cached snapshot, and the
resulting filesystem is reused for roughly seven days. A change in this
repository therefore reaches new sessions after the cache is rebuilt; editing
the environment's setup script field rebuilds it immediately.

The Codex CLI in a cloud session is not authenticated by the setup script. Put
the output of `scripts/refresh-codex-web-token.sh` into the environment
variable `CODEX_AUTH_JSON_B64` and restore it inside the session:

```sh
mkdir -p ~/.codex && printf '%s' "$CODEX_AUTH_JSON_B64" | base64 -d > ~/.codex/auth.json && chmod 600 ~/.codex/auth.json
```

Whether Codex Cloud reads `~/.codex` or plugins written by a setup script has
not been verified. The path its documentation guarantees is the repository's
own `AGENTS.md`.

### local-mcp evaluation

`local-mcp` is not installed by this repository. It is a local MCP server for
giving a remote ChatGPT session file and command access, but this repository
does not define a ChatGPT connector endpoint, authenticated tunnel, background
service, or allowed workspace roots. Installing only the binary would not
produce a usable or reproducible connection.

If those operational pieces are added later, keep `/permission ask` as the
session default and start `local-mcp` from the exact project directory. Do not
use `/permissions yolo`; treat every `without_sandbox` call as a separate
host-and-network access decision.

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

## Manage gh extensions

Home Manager declares gh extensions in `programs.gh.extensions` and owns the
whole `~/.local/share/gh/extensions` directory. `gh extension install` and
`gh extension upgrade` therefore no longer apply: add the nixpkgs package to
the list in `nix/home.nix` and run `nix run .#apply`, and update it with
`nix flake update nixpkgs`.

An extension that is missing from nixpkgs cannot be declared this way. Check
whether gh itself already covers the feature before packaging it; the former
`gh-actions-cache` extension was dropped from nixpkgs because `gh cache`
replaced it. `gh-pr-graph` is not in nixpkgs, so `nix/packages.nix` packages
its versioned upstream binaries and `nix/home.nix` declares that package as an
extension.

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
