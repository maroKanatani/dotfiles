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

User-level shared instructions live in `config/agents/AGENTS.md`. Home Manager
deploys the same source as `~/.codex/AGENTS.md` for Codex and
`~/.claude/rules/common.md` for Claude Code. This repository's own instructions
live in the root `AGENTS.md`; `CLAUDE.md` imports it for Claude Code.

Codex command policies live in `config/codex/rules/` and are deployed to
`~/.codex/rules/`. They prompt before merge, pull, and PR creation commands;
the corresponding Agent Skills define the preferred workflow and output.

Reusable workflows follow the Agent Skills layout under
`config/agents/skills/`. Keeping the source outside a discovery directory
avoids loading the same skill once from this repository and again from the
user-level path.

Home Manager exposes the same sources at both `~/.agents/skills/` for Codex and
`~/.claude/skills/` for Claude Code. The target directories are populated
recursively so unmanaged, product-specific skills can coexist with the managed
skills.

An optional `agents/openai.yaml` customizes OpenAI's skill UI and default
prompt; the workflow itself remains in `SKILL.md`.

The curated set contains only focused workflows that are actively maintained;
see `config/agents/skills/` for the current set.

Skills maintained in another repository are vendored with `gh skill`, which
copies the upstream `SKILL.md` into `config/agents/skills/` and records the
source repository, ref, and tree SHA in its front matter:

```bash
gh skill install github/gh-stack gh-stack --pin main --dir config/agents/skills --force
```

Home Manager deploys the vendored copy like any curated skill. Rerun the same
command to refresh it from `main`; the pin prevents `gh skill update` from
replacing it with the latest tagged release.
`gh skill` does not verify skill contents, so read the file before committing
it. Prefer a copy that a package already ships, as the Herdr skill below shows.

The Herdr skill is not curated here. Herdr ships it inside its own package at
`share/herdr/skills/herdr/SKILL.md`, and Home Manager deploys that file to
`~/.agents/skills/herdr/SKILL.md` and `~/.claude/skills/herdr/SKILL.md`. The
skill therefore always describes the `herdr` binary that is actually installed,
which matters because the skill instructs the agent to treat the installed CLI
as the authority for command syntax. It follows the package version, so
`nix flake update nixpkgs` updates the binary and the skill together.

Do not install it with `npx skills add herdrdev/herdr --skill herdr -g` and do
not copy the upstream file into `config/agents/skills/`. Both write a second,
independently versioned copy into a path Home Manager already owns.

Domain-specific business knowledge is managed outside this repository and is
not included in the shared set. Add a new skill only when a repeated task needs
specialized knowledge, a deterministic script, or a stable output contract.

The complete Claude Code user settings are preserved in
`config/claude/settings.json`. Home Manager does not deploy this file yet:
Claude's plugin commands update the user settings in place, while a normal Home
Manager source would be a read-only Nix store link. Keep the existing writable
user settings active until a writable out-of-store adoption flow is selected.
Do not duplicate these personal settings in a repository's
`.claude/settings.json`; that path is project-scoped.

`scripts/sync-claude-settings.py` copies that file over the writable user
settings instead. The repository is the source of truth and the script
overwrites the whole file, so anything the CLI wrote in place is lost on the
next run: after `claude plugin install` or a `/config` change, carry the new
value back into `config/claude/settings.json` before applying again. Both
scripts back the previous file up first. `scripts/apply.sh` runs it after the
Home Manager apply, and `cloud-setup.sh` runs it for cloud sessions.
`nix run .#apply` never touches that file, so a removed setting only reaches
the user settings through `scripts/apply.sh`.

`scripts/apply.sh` also deletes skills that this repository no longer deploys
but Home Manager leaves behind, because a leftover skill is loaded by every
session from then on. Home Manager deletes only links it created itself, and
its orphan sweep compares the previous generation with the new one exactly
once, so a link it misses is never retried and a file written straight into
`~/.claude/skills` was never a candidate. The latter happens repeatedly because
the agents themselves write there. In `~/.claude/skills` every entry is either a
current-generation link or a symlink to a skill outside the Nix store, so
anything else is a leftover and is deleted; `~/.agents/skills` also holds Codex
skills that predate this repository, so only missed links are deleted there.
`scripts/test-apply-prune.sh` pins that classification.

Deploying the file is what makes permission rules work at all: a rule only
takes effect when a settings file the session reads declares it, so an
undeployed `ask` list never fires.

```sh
scripts/apply.sh --dry-run
scripts/apply.sh
```

The `ask` list covers the operations that are visible to other people: pull
request and issue comments, reviews, PR creation, merges, and `gh api`, which
can reach all of them over REST. Claude executes them, but the harness prompts
first, in every session and regardless of what Claude decides. `git push`,
commits, and file edits stay in `allow` so unattended work is not interrupted.

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
The `herdr` binary itself is part of the Nix package catalog, but the hook
scripts those integrations install are generated by their own CLIs and are not
managed here; hook commands check for their environment and scripts and become
no-ops when they are unavailable.

### Claude Code cloud sessions

Cloud sessions, which include Claude Code on the web, `claude --cloud`, and
routines, run on a fresh VM. They read the cloned repository, that VM's own home
directory, and the cloud environment configuration; the Home Manager links on a
local machine never reach them.

`scripts/cloud-setup.sh` deploys the same shared sources into the session VM.
Register the bootstrap in the **Setup script** field of the cloud environment at
[claude.ai/code](https://claude.ai/code):

```sh
git clone --depth 1 https://github.com/maroKanatani/dotfiles.git /opt/dotfiles
bash /opt/dotfiles/scripts/cloud-setup.sh
exit 0
```

One environment-level registration covers every repository, so no personal
configuration is committed to a project's `.claude/` directory. Start a new
cloud session afterwards and confirm that the shared skills are listed and the
shared instructions are loaded.

The setup script runs when an environment has no cached snapshot, and the
resulting filesystem is reused for roughly seven days. A change in this
repository therefore reaches new sessions after the cache is rebuilt; editing
the environment's setup script field rebuilds it immediately.

`config/claude/settings.json` is not deployed to a cloud session. Its hooks,
status line, and output style depend on the local machine, and user-scoped
`enabledPlugins` is not applied there; plugins for a cloud session have to be
declared in the target repository's project settings.

### Adopted AI plugins

Ponytail, Reviewable HTML Workbench, show-me, ELI5, and Matt Pocock's skills
are installed from their upstream marketplaces. Use the host CLIs instead of
copying their Skills or hooks into this repository:

```sh
codex plugin marketplace add DietrichGebert/ponytail
codex plugin add ponytail@ponytail
codex plugin marketplace add u-ichi/reviewable-html-workbench
codex plugin add reviewable-html-workbench@reviewable-html-workbench-local
codex plugin marketplace add humanlayer/skills
codex plugin add show-me@skills
codex plugin marketplace add anthropics/claude-plugins-community
codex plugin add eli5@claude-community
codex plugin marketplace add anthropics/claude-plugins-official
codex plugin add mattpocock-skills@claude-plugins-official

claude plugin marketplace add DietrichGebert/ponytail
claude plugin install ponytail@ponytail
claude plugin marketplace add u-ichi/reviewable-html-workbench
claude plugin install reviewable-html-workbench
claude plugin marketplace add humanlayer/skills
claude plugin install show-me@skills
claude plugin marketplace add anthropics/claude-plugins-community
claude plugin install eli5@claude-community
claude plugin marketplace add anthropics/claude-plugins-official
claude plugin install mattpocock-skills@claude-plugins-official
```

After installing Ponytail in Codex, start `codex`, open `/hooks`, review and
trust the plugin hooks, and then start a new thread. Start a new Claude Code
session after either plugin changes. Node.js must be available to non-interactive
hooks for Ponytail, and Reviewable HTML Workbench requires Python 3.11 or later.

Twenty-five skills arrive with `mattpocock-skills`, eleven of them
model-invoked, so those fire on their own whenever a task matches. Two overlaps
are worth knowing before they surprise you: `writing-for-agents` triggers on
edits to a skill or an `AGENTS.md`, which covers most work in this repository,
and its `code-review` skill covers the same ground as the disabled
`code-review@claude-plugins-official` plugin. Turn an individual skill off
through the plugin instead of copying an edited file into
`config/agents/skills/`. `setup-matt-pocock-skills` writes `docs/agents/*.md`
and an `## Agent skills` section into whichever repository it runs in, so run
it only where that per-repository configuration is wanted.

Do not copy Codex's generated marketplace, plugin, or hook-trust state from
`~/.codex/config.toml` into this repository. Claude's reproducible marketplace
and enabled-plugin keys remain recorded in `config/claude/settings.json`; the
CLI-owned user file stays writable.

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
