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
5. **Duplication** — extract shared logic into Traits, Actions, or Services
6. **File size over 1000 lines** — modularize: extract into Traits, Actions, Services, or separate classes
7. **Cyclomatic complexity > 50** — decompose methods into smaller, focused units

## Classification Guide

### When to Auto-Fix vs Escalate

| Situation | Auto-Fix | Escalate |
|---|---|---|
| Style violation (Pint/CS-Fixer) | Yes | |
| Missing type annotation | Yes | |
| Missing test for new code | Yes | |
| Duplicated logic extractable to service | Yes | |
| Large file modularizable into traits | Yes | |
| Critical dependency vulnerability | | Yes |
| Breaking change required in dependencies | | Yes |
| Architectural design decision needed | | Yes |
| 5 iterations exhausted | | Yes |

## First Run Behavior

When no `baseline.json` exists in the project root:

1. Run the full PHP toolchain and collect all metrics.
2. Write the collected metrics to `baseline.json`.
3. Report the established baseline values.
4. Treat this as a PASS (since there is no previous baseline to compare against).
5. Commit `baseline.json` to the repository so subsequent PRs can compare against it.