# Baseline JSON Schema

The `baseline.json` file lives in the project root and tracks quality metrics over time. It is the single source of truth for the Ratchet principle: metrics can only improve, never regress.

## Schema Definition

```json
{
  "$schema": "https://raw.githubusercontent.com/b7s/ratchet-babysit/main/.codex/skills/ratchet-babysit/references/baseline-schema.json",
  "version": 1,
  "timestamp": "ISO 8601 datetime of last baseline update",
  "commit": "Git commit SHA of last baseline update",
  "metrics": {
    "coverage_percent": "float — test coverage percentage",
    "duplication_percent": "float — code duplication percentage",
    "lint_violations": "integer — number of style violations",
    "phpstan_errors": "integer — number of PHPStan/Psalm errors",
    "phpstan_warnings": "integer — number of PHPStan/Psalm warnings (non-blocking)",
    "security_advisories": {
      "critical": "integer — number of critical advisories (must be 0 to pass)",
      "high": "integer — number of high advisories (must be 0 to pass)",
      "medium": "integer — tracked but non-blocking",
      "low": "integer — tracked but non-blocking"
    },
    "file_sizes": {
      "max_lines": "integer — lines of the largest file",
      "max_lines_file": "string — path of the largest file"
    },
    "cyclomatic_complexity": {
      "max_per_method": "integer — highest cyclomatic complexity of any method",
      "max_per_method_file": "string — fully-qualified method reference (e.g., App\\Services\\PaymentService::process)"
    }
  }
}
```

## Example

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
    "security_advisories": {
      "critical": 0,
      "high": 0,
      "medium": 1,
      "low": 3
    },
    "file_sizes": {
      "max_lines": 623,
      "max_lines_file": "app/Services/PaymentService.php"
    },
    "cyclomatic_complexity": {
      "max_per_method": 14,
      "max_per_method_file": "App\\Services\\PaymentService::process"
    }
  }
}
```

## Versioning Rules

- `version` starts at `1` and must be incremented if the schema changes in a backward-incompatible way.
- New fields can be added without incrementing the version — consumers should ignore unknown fields.
- The `timestamp` and `commit` fields are updated every time `baseline.json` is written.

## First Run

When `baseline.json` does not exist in the project root, the first run of the quality toolchain will create it with the current metrics. This is treated as a PASS since there is no prior baseline to compare against.

## Comparison Rules

For each metric:

| Metric | Comparison | Fails if |
|---|---|---|
| `coverage_percent` | `current >= baseline` | Current < baseline (any regression) |
| `duplication_percent` | `current <= baseline` | Current > baseline (any increase) |
| `lint_violations` | `current <= baseline` | Current > baseline (any new violation) |
| `phpstan_errors` | `current <= baseline` | Current > baseline (any new error) |
| `phpstan_warnings` | Tracked only | No comparison (informational) |
| `security_advisories.critical` | `current == 0` | Any critical advisory |
| `security_advisories.high` | `current == 0` | Any high advisory |
| `security_advisories.medium` | `current <= baseline` | Any increase |
| `security_advisories.low` | `current <= baseline` | Any increase |
| `file_sizes.max_lines` | `current <= 1000` | Any file > 1000 lines |
| `cyclomatic_complexity.max_per_method` | `current <= 50` | Any method > 50 (warn > 20) |