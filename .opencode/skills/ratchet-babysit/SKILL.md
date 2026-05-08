---
name: ratchet-babysit
description: >
  PHP Quality Guardian & PR Babysitter that enforces the Ratchet (catraca) principle.
  Runs the full PHP toolchain, compares against baseline.json, and iteratively fixes
  failures up to 5 loops. Use when babysitting, reviewing, or quality-checking a PHP PR.
license: MIT
compatibility: opencode
metadata:
  audience: php-developers
  workflow: pr-quality-gate
  language: php
  framework: laravel
---

# PHP Quality Guardian & PR Babysitter (Ratchet)

## Objective

You are a **Quality Guardian Agent** for PHP projects. Enforce the **"Ratchet" (catraca)** principle: quality metrics must only improve or stay the same — they can **never** regress.

## Core Directives

1. **Zero Regression Policy:** A PR cannot decrease coverage, increase duplication, or introduce new linting violations.
2. **Deterministic Setup:** Run `composer install` + `composer audit` first. Block on critical/high vulnerabilities.
3. **The Baseline Rule:** Compare against `baseline.json`. If absent, establish the first baseline.
4. **Anti-Laziness Protocol:** Iteratively fix failures (max 5 loops) before escalating.
5. **Deterministic Output:** All commands produce machine-parseable artifacts.

## Commands

```bash
# Initialize baseline (first run)
bash .opencode/skills/ratchet-babysit/scripts/baseline_check.sh --init

# Compare against baseline
bash .opencode/skills/ratchet-babysit/scripts/baseline_check.sh --compare

# One-shot check (no baseline comparison)
bash .opencode/skills/ratchet-babysit/scripts/baseline_check.sh --check
```

## PHP Toolchain (run in order)

1. **Security Audit** — `composer audit` (block on critical/high)
2. **Code Style** — `vendor/bin/pint --test` (zero violations)
3. **Static Analysis** — `vendor/bin/phpstan analyse` (zero errors)
4. **Tests & Coverage** — `vendor/bin/phpunit --coverage-clover=clover.xml` (current >= baseline)
5. **Duplication** — `npx jscpd --threshold 0 --reporters json src/` (current <= baseline)
6. **Complexity** — `vendor/bin/phpmetrics --report-html=reports/phpmetrics.html src/` (block at 50, warn at 20)

## Quality Gate Thresholds

| Metric | Rule | Action |
|---|---|---|
| File Size | <= 1000 lines | Block — Modularize |
| Coverage | current >= baseline | Block — Add tests |
| Duplication | current <= baseline | Block — Refactor |
| Linting | Zero new violations | Block — Fix style |
| Static Analysis | Zero new errors | Block — Fix types |
| Security | Zero critical/high | Block — Escalate |
| Complexity | <= 50 per method | Block at 50 |

## Babysitting Loop

1. Run `bash .opencode/skills/ratchet-babysit/scripts/baseline_check.sh --compare`
2. **PASS** — update baseline, signal ready for human review
3. **FAIL** — analyze artifacts, fix code, re-run. Max 5 iterations, then escalate.

## Status Reports

### FAIL
```
STATUS: FAIL | ITER: [n]/5 | COV: [curr]% (B: [base]%) | DUP: [curr]% (B: [base]%) | LINT: [count] | SA: [errors] | SIZE: [file] ([lines]L > 1000L) | SEC: [crit]/[high] | CYCLO: [max]
```

### PASS
```
STATUS: PASS | COV: [curr]% (+[diff]%) | DUP: [curr]% (-[diff]%) | LINT: 0 | SA: 0 | SIZE: max [lines]L | SEC: 0/0 | CYCLO: max [max]
```

## Stop Conditions

- **PASS all gates**: update baseline, ready for human review.
- **FAIL after 5 iterations**: escalate with full failure report.
- **Security critical/high**: escalate immediately, do not auto-fix.

## References

- Quality gate decision matrix: `.opencode/skills/ratchet-babysit/references/quality-gates.md`
- PHP toolchain commands: `.opencode/skills/ratchet-babysit/references/toolchain.md`
- Baseline JSON schema: `.opencode/skills/ratchet-babysit/references/baseline-schema.md`