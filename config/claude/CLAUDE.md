@AGENTS.md

# Claude Code固有の設定境界

- 共通の運用原則と共通Skillは、Claude Code固有設定に複製しない。
- Claude Codeのsettings、hooks、権限、pluginだけを `config/claude/` で管理する。
- 共通Skillの原本は `config/agents/skills/` に置き、Claude Codeから参照できる場所へ配布する。
- Claude Codeだけで必要なSkillや指示は、共通設定と分けて管理する。
- 認証情報、履歴、cache、session、memoryなどの実行時状態はdotfilesで管理しない。
