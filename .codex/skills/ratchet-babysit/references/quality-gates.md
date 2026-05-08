# Quality Gate Decision Matrix

## Gate Evaluation Order

Gates are evaluated in this exact order. If any gate **blocks**, stop and report immediately — do not continue to subsequent gates.

| # | Gate | Block Condition | Pass Condition |
|---|---|---|---|
| 1 | Security Audit | Any critical or high advisory | Zero critical/high advisories |
| 2 | Code Style | Any new violation | Zero new violations |
| 3 | Static Analysis | Any new error | Zero new errors (warnings tracked, not blocking) |
| 4 | Test Coverage | `current%` < `baseline%` | `current%` >= `baseline%` |
| 5 | Duplication | `current%` > `baseline%` | `current%` <= `baseline%` |
| 6 | File Size | Any file > 1000 lines | All files <= 1000 lines |
| 7 | Cyclomatic Complexity | Any method > 50 | All methods <= 50 (warnings at > 20) |

## Auto-Fix Priority

When the babysitting loop encounters failures, fix them in this priority order:

1. **Security advisories** — cannot be auto-fixed; escalate to human immediately
2. **Code style violations** — usually auto-fixable with `vendor/bin/pint` (without `--test`) or `vendor/bin/php-cs-fixer fix`
3. **Static analysis errors** — fix type annotations, add missing return types, fix structural issues
4. **Test coverage gaps** — add missing test cases for uncovered code paths
5. **Duplication** — extract shared logic into Traits, Actions, or Services; see clone details for exact locations
6. **File size over 1000 lines** — modularize: extract into Traits, Actions, Services, or separate classes
7. **Cyclomatic complexity > 50** — decompose methods into smaller, focused units

## Required Actions Output

Every run produces a `reports/required_actions.txt` file with one `[ACTION]` per line, ordered by priority:

| Prefix | Meaning | Example |
|---|---|---|
| `[ACTION] ESCALATE:` | Human intervention required | `[ACTION] ESCALATE: Update dependencies with critical/high vulnerabilities (critical: 2, high: 1)` |
| `[ACTION] FIX STYLE:` | Auto-fixable style violation | `[ACTION] FIX STYLE: app/Http/Controllers/UserController.php` |
| `[ACTION] FIX SA:` | Static analysis error with location | `[ACTION] FIX SA: app/Models/User.php:42 - Property User::$name is never read` |
| `[ACTION] ADD TESTS:` | Coverage regression | `[ACTION] ADD TESTS: Coverage dropped from 82% to 78%. Add tests for uncovered code paths.` |
| `[ACTION] REFACTOR DUP:` | Duplicate code with file:line ranges | `[ACTION] REFACTOR DUP: src/ServiceA.php:10-50 <-> src/ServiceB.php:100-140 (40L)` |
| `[ACTION] MODULARIZE:` | File exceeds 1000 lines | `[ACTION] MODULARIZE: app/Services/PaymentService.php is 1200 lines (max 1000)` |

## Classification Guide

### When to Auto-Fix vs Escalate

| Situation | Auto-Fix | Escalate |
|---|---|---|
| Style violation (Pint/CS-Fixer) | Yes | |
| Missing type annotation | Yes | |
| Missing test for new code | Yes | |
| Duplicated logic extractable to service (see REFACTOR DUP actions) | Yes | |
| Large file modularizable into traits | Yes | |
| Critical dependency vulnerability | | Yes |
| Breaking change required in dependencies | | Yes |
| Architectural design decision needed | | Yes |
| 5 iterations exhausted | | Yes |

## Duplication Detail Extraction

The `baseline_check.sh` script extracts duplicate clone details from `jscpd` JSON output. Each clone shows:

```
src/ServiceA.php:10-50 <-> src/ServiceB.php:100-140 (40L)
```

Meaning: lines 10-50 of `src/ServiceA.php` are duplicated in lines 100-140 of `src/ServiceB.php`, spanning 40 lines.

When refactoring:
- **Small clones (< 10L):** Consider whether they're coincidental or truly duplicated logic.
- **Medium clones (10-30L):** Extract to a shared Trait or Action class.
- **Large clones (> 30L):** Extract to a dedicated Service class with an interface.

## First Run Behavior

When no `baseline.json` exists in the project root:

1. Run the full PHP toolchain and collect all metrics.
2. Write the collected metrics to `baseline.json`.
3. Report the established baseline values.
4. Treat this as a PASS (since there is no previous baseline to compare against).
5. Commit `baseline.json` to the repository so subsequent PRs can compare against it.