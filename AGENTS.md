# dotfilesリポジトリの運用

- `config/agents/AGENTS.md`は全リポジトリへ配布する共通指示、ここはこのdotfilesだけの指示として扱う.
- Claude Codeの利用者設定の原本は`config/claude/settings.json`、Codexのrulesの原本は`config/codex/`で管理する.プロジェクト設定へ個人の共通設定を複製しない.
- 共通Skillの原本は`config/agents/skills/`に置き、Claude CodeまたはCodexだけの実行時状態を混ぜない.
- エージェント設定はNixではなく`scripts/setup-agents.sh`がcheckoutからリンクして配布する.`~/.claude/settings.json`もこのcheckoutへのリンクなので、Claude Codeが書いた変更は`git diff`で確認してコミットするか破棄する.ローカルは`scripts/apply.sh`、cloudセッションは`scripts/cloud-setup.sh`がこれを呼ぶ.個人の共通設定を各リポジトリの`.claude/`へ複製しない.
- 外部のSkillは複製せず、pluginとして`config/claude/settings.json`の`enabledPlugins`と`extraKnownMarketplaces`で宣言する.`scripts/setup-agents.sh`がこの宣言を読んでClaude CodeとCodexへ導入する.
- 認証情報、履歴、cache、session、memoryなどの実行時状態を追跡しない.
- エージェント設定を変更したら`bash -n scripts/*.sh`と`python3 -m json.tool config/claude/settings.json`を実行する.Nixの配布定義を変更したら`nix-instantiate --parse nix/home.nix`も実行する.
