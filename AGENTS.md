# dotfilesリポジトリの運用

- `config/agents/AGENTS.md`は全リポジトリへ配布する共通指示、ここはこのdotfilesだけの指示として扱う。
- Claude Codeの利用者設定の原本は`config/claude/settings.json`、Codexのhooksとrulesの原本は`config/codex/`で管理する。プロジェクト設定へ個人の共通設定を複製しない。
- 共通Skillの原本は`config/agents/skills/`に置き、Claude CodeまたはCodexだけの実行時状態を混ぜない。
- 認証情報、履歴、cache、session、memoryなどの実行時状態を追跡しない。
- エージェント設定を変更したら`scripts/check-agent-config.sh`を実行する。Nixの配布定義を変更したら`nix-instantiate --parse nix/home.nix`も実行する。
