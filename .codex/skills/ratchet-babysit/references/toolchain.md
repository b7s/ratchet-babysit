# PHP Toolchain Reference

## 1. Composer (Dependency & Security)

### Install dependencies (deterministic)
```bash
composer install --no-interaction --prefer-dist
```

### Audit for vulnerabilities
```bash
composer audit
```
Exit code 0 = no vulnerabilities. Non-zero = advisories found.
Check for `critical` or `high` severity in the output. `medium` and `low` are tracked but do not block.

To audit and get JSON output:
```bash
composer audit --format=json
```

The script extracts advisory counts by severity (critical, high, medium, low) and adds `[ACTION] ESCALATE:` entries for any critical/high findings.

## 2. Laravel Pint (Code Style — Preferred)

### Check mode (dry-run, does not modify files)
```bash
vendor/bin/pint --test
```
Exit code 0 = all files pass. Non-zero = violations found.

The script captures each violating file and adds `[ACTION] FIX STYLE:` entries.

### Auto-fix mode
```bash
vendor/bin/pint
```
Automatically fixes style violations in place.

### Check specific paths
```bash
vendor/bin/pint --test app/ tests/
```

## 3. PHP-CS-Fixer (Code Style — Alternative)

### Dry-run check
```bash
vendor/bin/php-cs-fixer fix --dry-run --diff
```

### Auto-fix
```bash
vendor/bin/php-cs-fixer fix
```

## 4. PHPStan (Static Analysis — Preferred)

### Run analysis
```bash
vendor/bin/phpstan analyse --memory-limit=512M --error-format=table
```

### JSON output (for programmatic parsing)
```bash
vendor/bin/phpstan analyse --memory-limit=512M --error-format=json
```

The script parses the JSON output and extracts each error as:
```
[ACTION] FIX SA: app/Models/User.php:42 - Property User::$name is never read
```

### Configuration file
By default reads `phpstan.neon` or `phpstan.neon.dist` in the project root.

### Common levels
- Level 1-3: Basic checks
- Level 4-6: Type safety
- Level 7-8: Strict checks
- Level 9: Max strictness (PHPStan's highest)

## 5. Psalm (Static Analysis — Alternative)

### Run analysis
```bash
vendor/bin/psalm --show-info=false
```

### JSON output
```bash
vendor/bin/psalm --output-format=json
```

## 6. PHPUnit (Tests & Coverage — Preferred)

### Run tests with coverage
```bash
vendor/bin/phpunit --coverage-clover=clover.xml --coverage-text
```

### Minimum coverage threshold
```bash
vendor/bin/phpunit --coverage-clover=clover.xml --coverage-text --min-coverage=80
```

### Parsing coverage from clover.xml
Use the `baseline_check.sh` script, which extracts coverage percentage from `clover.xml`.

When coverage regresses, the script adds:
```
[ACTION] ADD TESTS: Coverage dropped from 82% to 78%. Add tests for uncovered code paths.
```

## 7. Pest (Tests & Coverage — Alternative)

### Run tests with coverage
```bash
vendor/bin/pest --coverage --min=80
```

### Coverage output
Pest can generate `clover.xml` when configured in `phpunit.xml`.

## 8. jscpd (Duplication Check — Preferred)

```bash
npx jscpd --threshold 0 --reporters json --output ./reports src/
```

JSON report will be at `./reports/jscpd/jscpd-report.json`. The `threshold` flag set to 0 means no threshold enforcement — we compare against baseline instead.

### Parsing duplication details from JSON report

The script extracts:
1. **Overall percentage** — used for baseline comparison
2. **Clone count** — number of duplicate code blocks found
3. **Per-clone details** — source/target files with line ranges:

```
src/ServiceA.php:10-50 <-> src/ServiceB.php:100-140 (40L)
app/TraitX.php:5-25 <-> app/ModelY.php:200-220 (20L)
```

Each clone generates a `[ACTION] REFACTOR DUP:` entry in the Required Actions list.

### How to read clone details
- `fileA:start-end <-> fileB:start-end (linesL)` means lines `start` to `end` in `fileA` are duplicated at lines `start` to `end` in `fileB`, spanning `lines` lines.

### Refactoring guidance by clone size
- **< 10 lines:** Often coincidental. Review before extracting.
- **10-30 lines:** Extract to a shared Trait or Action class.
- **> 30 lines:** Extract to a dedicated Service class with an interface.

## 9. phpcpd (Duplication Check — Alternative)

```bash
vendor/bin/phpcpd src/
```

phcpd output shows duplicate code blocks but does not provide JSON format. The script captures its text output for manual review.

## 10. phpmetrics (Cyclomatic Complexity)

```bash
vendor/bin/phpmetrics --report-html=reports/phpmetrics.html --report-json=reports/phpmetrics.json src/
```

Also generates an HTML report at `reports/phpmetrics.html`.

### Key metrics to extract
- Maximum cyclomatic complexity per method
- Files exceeding 1000 lines
- Class complexity distribution

### File size detection
The script also directly checks all `.php` files under `src/` and `app/` for the 1000-line limit. Files exceeding the limit generate `[ACTION] MODULARIZE:` entries.