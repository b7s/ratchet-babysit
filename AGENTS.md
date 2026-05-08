# Ratchet Babysit — PHP Quality Guardian

This project provides an AI skill that enforces the "Ratchet" (catraca) principle on PHP Pull Requests: quality metrics can only improve or stay the same, never regress.

## Skill Structure

The skill is available in three formats for different AI coding agents:

| Agent | Path | Frontmatter |
|---|---|---|
| OpenCode | `.opencode/skills/ratchet-babysit/SKILL.md` | `name`, `description`, `license`, `compatibility`, `metadata` |
| Claude Code | `.claude/skills/ratchet-babysit/SKILL.md` | `name`, `description`, `allowed-tools`, `effort`, `context`, `agent` |
| Codex (OpenAI) | `.codex/skills/ratchet-babysit/SKILL.md` | `name`, `description` |

All three share the same `scripts/` and `references/` directories via symlinks.

## Usage

```bash
# Initialize baseline (first run)
bash .opencode/skills/ratchet-babysit/scripts/baseline_check.sh --init

# Compare against baseline
bash .opencode/skills/ratchet-babysit/scripts/baseline_check.sh --compare

# One-shot check
bash .opencode/skills/ratchet-babysit/scripts/baseline_check.sh --check
```

## Quality Gates

The skill enforces these gates in order:

1. Security Audit — zero critical/high advisories
2. Code Style — zero new violations
3. Static Analysis — zero new errors
4. Test Coverage — current >= baseline
5. Duplication — current <= baseline
6. File Size — max 1000 lines per file
7. Cyclomatic Complexity — block at 50, warn at 20

If any gate fails, the skill iteratively fixes the code (max 5 loops) before escalating to a human reviewer.