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

## 2. Laravel Pint (Code Style — Preferred)

### Check mode (dry-run, does not modify files)
```bash
vendor/bin/pint --test
```
Exit code 0 = all files pass. Non-zero = violations found.

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
Use the `baseline_check.sh` script, which extracts coverage percentage from `clover.xml` using `xmllint` or `grep`.

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

### Parsing duplication from JSON report
```bash
cat reports/jscpd/jscpd-report.json | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['statistics']['total']['percentage'])"
```

## 9. phpcpd (Duplication Check — Alternative)

```bash
vendor/bin/phpcpd src/
```

## 10. phpmetrics (Cyclomatic Complexity)

```bash
vendor/bin/phpmetrics --report-html=reports/phpmetrics.html src/
```

Also generates JSON report at `reports/phpmetrics.json`.

### Key metrics to extract
- Maximum cyclomatic complexity per method
- Files exceeding 1000 lines
- Class complexity distribution