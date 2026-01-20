1. Run `install.sh <agent_type> [target_dir]` (agent_type: claude/codex/gemini)
2. Call `/prd` skill with your feature requirements → outputs `tasks/prd-*.md`
3. Call `/ralph` skill with the PRD → outputs `prd.json`
4. Run `ralph.sh [max_iterations]` for the autonomous loop (default: 10)
