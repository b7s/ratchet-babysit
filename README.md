# Ratchet Babysit

> **Quality only goes up. Never down.** That's the ratchet.

An AI skill that acts as a **Quality Guardian** for PHP projects, enforcing the **Ratchet (catraca)** principle on every Pull Request: quality metrics can only improve or stay the same — they can **never regress**.

## How It Works

```
PR Submitted → Run Toolchain → Compare vs Baseline → Pass? → Merge
                                                    → Fail? → Auto-fix → Re-run (up to 5x)
```

1. **Security audit** — blocks critical/high vulnerabilities
2. **Code style** — zero new violations (Pint or CS-Fixer)
3. **Static analysis** — zero new errors (PHPStan or Psalm)
4. **Tests & coverage** — coverage must be ≥ baseline (PHPUnit/Pest)
5. **Duplication check** — must be ≤ baseline (jscpd or phpcpd)
6. **Cyclomatic complexity** — warning at 20, block at 50

If any gate fails, the AI iteratively fixes the code and re-runs the pipeline (max 5 attempts before escalating to a human).

## Quick Start

### 1. Add the skill to your project

Copy `ratchet-babysit.md` into your project's AI configuration (e.g., `.github/`, `.agents/`, or your preferred location).

### 2. Establish a baseline

On the first run (before any PR review), execute the full toolchain and generate `baseline.json`:

```bash
composer install --no-interaction --prefer-dist
composer audit

vendor/bin/pint --test
vendor/bin/phpstan analyse --memory-limit=512M
vendor/bin/phpunit --coverage-clover=clover.xml

npx jscpd --threshold 0 --reporters json --output ./reports src/
vendor/bin/phpmetrics --report-html=reports/phpmetrics.html src/
```

### 3. Commit `baseline.json`

```bash
git add baseline.json
git commit -m "chore: establish quality baseline"
```

### 4. Let the babysitter watch your PRs

On every subsequent PR, the skill will compare current metrics against `baseline.json`. If everything passes, the baseline is updated. If not, the AI fixes the code until it passes.

## Quality Gate Summary

| Metric | Rule | Blocks? |
|---|---|---|
| Security | Zero critical/high advisories | Yes |
| Code Style | Zero new violations | Yes |
| Static Analysis | Zero new errors | Yes |
| Coverage | `current ≥ baseline` | Yes |
| Duplication | `current ≤ baseline` | Yes |
| File Size | Max 1,000 lines per file | Yes |
| Cyclomatic Complexity | ≤ 50 per method | Yes |
| Cyclomatic Complexity | ≤ 20 per method | Warning |

## Baseline Schema

The `baseline.json` file tracks all metrics:

```json
{
  "version": 1,
  "timestamp": "2025-01-01T00:00:00Z",
  "commit": "abc1234",
  "metrics": {
    "coverage_percent": 80.0,
    "duplication_percent": 3.0,
    "lint_violations": 0,
    "phpstan_errors": 0,
    "phpstan_warnings": 12,
    "security_advisories": {
      "critical": 0,
      "high": 0,
      "medium": 2,
      "low": 5
    },
    "file_sizes": {
      "max_lines": 847,
      "max_lines_file": "app/Services/PaymentService.php"
    },
    "cyclomatic_complexity": {
      "max_per_method": 18,
      "max_per_method_file": "app/Services/PaymentService.php::process()"
    }
  }
}
```

## Why "Ratchet"?

A ratchet (catraca in Portuguese) only turns in one direction. Applied to code quality, this means every PR must maintain or improve the current metrics — never regress them. Over time, this guarantees your codebase quality **monotonically increases**.

## Why Use This Skill?

- **Eliminates the human bottleneck** — the AI acts as a first-pass reviewer, catching PSR violations, coverage drops, and quality regressions before a human ever sees the code.
- **Forces modularization** — hard cap of 1,000 lines per file prevents unmaintainable monoliths.
- **Artifact-driven, not guesswork** — reads `clover.xml`, `jscpd` reports, and `phpmetrics` HTML to know exactly where quality dropped.
- **Iterative self-healing** — doesn't just report failures; it fixes them (up to 5 iterations) before escalating.

## License

MIT