# Ratchet Babysit

> **Quality only goes up. Never down.** That's the ratchet.

A multi-agent AI skill that acts as a **Quality Guardian** for PHP projects, enforcing the **Ratchet (catraca)** principle on every Pull Request: quality metrics can only improve or stay the same — they can **never regress**.

Works with **OpenCode**, **Claude Code**, and **OpenAI Codex**.

## How It Works

```
PR Submitted → Run Toolchain → Compare vs Baseline → Pass? → Update baseline, ready for review
                                                     → Fail? → Auto-fix → Re-run (up to 5x) → Escalate if still failing
```

1. **Security audit** — blocks critical/high vulnerabilities
2. **Code style** — zero new violations (Pint or CS-Fixer)
3. **Static analysis** — zero new errors (PHPStan or Psalm)
4. **Tests & coverage** — coverage must be >= baseline (PHPUnit/Pest)
5. **Duplication check** — must be <= baseline (jscpd or phpcpd)
6. **File size** — hard cap of 1,000 lines per file
7. **Cyclomatic complexity** — block at 50, warn at 20 (phpmetrics)

## Quick Start

### 1. Install the skill

Copy the appropriate skill directory into your project:

| Agent | Install path |
|---|---|
| OpenCode | `.opencode/skills/ratchet-babysit/` |
| Claude Code | `.claude/skills/ratchet-babysit/` |
| Codex (OpenAI) | `.codex/skills/ratchet-babysit/` |

Or add as a submodule:

```bash
git submodule add https://github.com/b7s/ratchet-babysit.git .opencode/skills/ratchet-babysit
```

### 2. Establish a baseline

```bash
bash .opencode/skills/ratchet-babysit/scripts/baseline_check.sh --init
```

### 3. Commit `baseline.json`

```bash
git add baseline.json
git commit -m "chore: establish quality baseline"
```

### 4. Run quality checks on every PR

```bash
# One-shot check (no baseline comparison)
bash .opencode/skills/ratchet-babysit/scripts/baseline_check.sh --check

# Compare against baseline
bash .opencode/skills/ratchet-babysit/scripts/baseline_check.sh --compare
```

Or let your AI agent handle it automatically by invoking the skill.

## Project Structure

```
.opencode/skills/ratchet-babysit/     # OpenCode skill
.claude/skills/ratchet-babysit/        # Claude Code skill (symlinks to shared files)
.codex/skills/ratchet-babysit/         # Codex skill (canonical location)
├── SKILL.md                           # Skill definition (YAML frontmatter + instructions)
├── agents/
│   └── openai.yaml                    # OpenAI Codex agent config
├── references/
│   ├── baseline-schema.md             # baseline.json schema + comparison rules
│   ├── quality-gates.md               # Quality gate decision matrix
│   └── toolchain.md                   # PHP toolchain commands reference
└── scripts/
    └── baseline_check.sh               # Executable script: --init, --compare, --check
```

Each agent's SKILL.md has tool-specific frontmatter:

| Frontmatter Field | OpenCode | Claude Code | Codex |
|---|---|---|---|
| `name` | Yes | Yes | Yes |
| `description` | Yes | Yes | Yes |
| `license` | Yes | — | — |
| `compatibility` | Yes | — | — |
| `metadata` | Yes | — | — |
| `allowed-tools` | — | Yes | — |
| `effort` | — | Yes | — |
| `context` | — | Yes | — |
| `agent` | — | Yes | — |

## Quality Gate Summary

| Metric | Rule | Blocks? |
|---|---|---|
| Security | Zero critical/high advisories | Yes |
| Code Style | Zero new violations | Yes |
| Static Analysis | Zero new errors | Yes |
| Coverage | `current >= baseline` | Yes |
| Duplication | `current <= baseline` | Yes |
| File Size | Max 1,000 lines per file | Yes |
| Cyclomatic Complexity | <= 50 per method | Yes |
| Cyclomatic Complexity | <= 20 per method | Warning |

## Baseline Schema

See `.codex/skills/ratchet-babysit/references/baseline-schema.md` for the full specification.

Example `baseline.json`:

```json
{
  "version": 1,
  "timestamp": "2025-01-15T10:30:00Z",
  "commit": "a1b2c3d",
  "metrics": {
    "coverage_percent": 82.5,
    "duplication_percent": 3.2,
    "lint_violations": 0,
    "phpstan_errors": 0,
    "phpstan_warnings": 5,
    "security_advisories": { "critical": 0, "high": 0, "medium": 1, "low": 3 },
    "file_sizes": { "max_lines": 623, "max_lines_file": "app/Services/PaymentService.php" },
    "cyclomatic_complexity": { "max_per_method": 14, "max_per_method_file": "App\\Services\\PaymentService::process" }
  }
}
```

## Why "Ratchet"?

A ratchet (catraca in Portuguese) only turns in one direction. Applied to code quality, this means every PR must maintain or improve the current metrics — never regress them. Over time, this guarantees your codebase quality **monotonically increases**.

## License

MIT