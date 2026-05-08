# PHP Toolchain Reference

## Tool Resolution

The `baseline_check.sh` script resolves each tool in this order:

1. **Local install** (`vendor/bin/<tool>`) — project dependency
2. **Global install** (`<tool>` in `$PATH`) — `composer global require` or standalone PHAR
3. **Composer global bin** (`~/.composer/vendor/bin/<tool>`) — common macOS/Linux location
4. **Skip** if not found

This means tools installed via any of these methods work automatically:

```bash
# Local (project-level, preferred)
composer require --dev phpmetrics/phpmetrics
composer require --dev phpstan/phpstan
composer require --dev laravel/pint

# Global (user-level)
composer global require phpmetrics/phpmetrics
composer global require phpstan/phpstan

# PHAR (system-level)
curl -L https://github.com/phpmetrics/PhpMetrics/releases/latest/download/phpmetrics.phar -o /usr/local/bin/phpmetrics
chmod +x /usr/local/bin/phpmetrics

# Package manager
brew install phpmetrics          # macOS
sudo apt install phpmetrics     # Debian/Ubuntu
```

## Temporary Files

The script uses a temp directory (`mktemp -d`) for all intermediate files. This means:

- **No write permissions needed** in the project directory (except for `baseline.json`)
- **No `reports/` directory** is created in the project
- **Cleaned up automatically** on exit (via `trap`)
- Only `baseline.json` is written to the project root

## Tool-by-Tool Reference

### 1. Composer (Dependency & Security)

#### Install dependencies (deterministic)
```bash
composer install --no-interaction --prefer-dist
```

#### Audit for vulnerabilities (stdout)
```bash
composer audit --format=json
```
Output goes directly to stdout — no intermediate file needed. The script pipes JSON directly to Python for parsing.

Exit code 0 = no vulnerabilities. Non-zero = advisories found.
Check for `critical` or `high` severity. `medium` and `low` are tracked but do not block.

### 2. Laravel Pint (Code Style — Preferred)

#### Check mode (dry-run, does not modify files)
```bash
vendor/bin/pint --test
# or globally:
pint --test
```
Exit code 0 = all files pass. Non-zero = violations found.

#### Auto-fix mode
```bash
vendor/bin/pint
# or globally:
pint
```

#### Check specific paths
```bash
vendor/bin/pint --test app/ tests/
```

### 3. PHP-CS-Fixer (Code Style — Alternative)

#### Dry-run check
```bash
vendor/bin/php-cs-fixer fix --dry-run --diff
# or globally:
php-cs-fixer fix --dry-run --diff
```

#### Auto-fix
```bash
vendor/bin/php-cs-fixer fix
```

### 4. PHPStan (Static Analysis — Preferred)

#### Run analysis (stdout JSON)
```bash
vendor/bin/phpstan analyse --memory-limit=512M --error-format=json
# or globally:
phpstan analyse --memory-limit=512M --error-format=json
```

The script pipes PHPStan's JSON output directly — no intermediate file needed.

#### Configuration file
By default reads `phpstan.neon` or `phpstan.neon.dist` in the project root.

#### Common levels
- Level 1-3: Basic checks
- Level 4-6: Type safety
- Level 7-8: Strict checks
- Level 9: Max strictness (PHPStan's highest)

### 5. Psalm (Static Analysis — Alternative)

#### Run analysis (stdout JSON)
```bash
vendor/bin/psalm --output-format=json
# or globally:
psalm --output-format=json
```

### 6. PHPUnit (Tests & Coverage — Preferred)

#### Run tests with coverage
```bash
vendor/bin/phpunit --coverage-clover=clover.xml --coverage-text
# or globally:
phpunit --coverage-clover=clover.xml --coverage-text
```

The script writes `clover.xml` to the temp directory and parses it directly. No project-level file is created.

#### Minimum coverage threshold
```bash
vendor/bin/phpunit --coverage-clover=clover.xml --coverage-text --min-coverage=80
```

### 7. Pest (Tests & Coverage — Alternative)

#### Run tests with coverage
```bash
vendor/bin/pest --coverage --min=80
# or globally:
pest --coverage --min=80
```

### 8. jscpd (Duplication Check — Preferred)

```bash
npx jscpd --threshold 0 --reporters json --output /tmp/ratchet-babysit.XXXXXX src/
```

JSON report is written to the temp directory. The script:
1. Extracts overall duplication percentage
2. Extracts clone count
3. Extracts per-clone details with file:line ranges

### Parsing duplication from JSON report
Each clone entry in `jscpd-report.json` contains:
- `firstFile.name` (or `firstFile.path`) + `firstFile.start` / `firstFile.end`
- `secondFile.name` (or `secondFile.path`) + `secondFile.start` / `secondFile.end`

Output format:
```
src/ServiceA.php:10-50 <-> src/ServiceB.php:100-140 (40L)
```

### 9. phpcpd (Duplication Check — Alternative)

```bash
vendor/bin/phpcpd src/
# or globally:
phpcpd src/
```

Text output only — no JSON format. The script captures its output for manual review.

### 10. phpmetrics (Cyclomatic Complexity)

#### Installation methods
```bash
# Local (project-level, preferred)
composer require --dev phpmetrics/phpmetrics
vendor/bin/phpmetrics --report-json=/tmp/phpmetrics.json src/

# Global (user-level)
composer global require phpmetrics/phpmetrics
phpmetrics --report-json=/tmp/phpmetrics.json src/

# PHAR
curl -L https://github.com/phpmetrics/PhpMetrics/releases/latest/download/phpmetrics.phar -o /usr/local/bin/phpmetrics
chmod +x /usr/local/bin/phpmetrics
phpmetrics --report-json=/tmp/phpmetrics.json src/

# Docker
docker run --rm --volume "$(pwd)":/project herloct/phpmetrics --report-json=/tmp/phpmetrics.json src/

# macOS
brew install phpmetrics

# Debian/Ubuntu
sudo apt install phpmetrics
```

The script resolves `phpmetrics` in this order: `vendor/bin/phpmetrics` → `phpmetrics` (PATH) → `~/.composer/vendor/bin/phpmetrics`.

#### JSON output structure
The `--report-json` flag produces a JSON file with this structure:

```json
{
  "files": {
    "path/to/File.php": {
      "methods": [
        { "name": "methodName", "ccn": 5 }
      ]
    }
  },
  "classes": {
    "App\\Services\\PaymentService": {
      "methods": {
        "process": { "ccn": 15 }
      }
    }
  }
}
```

Note: The structure varies between phpmetrics versions. The script handles both `classes` → method dicts and `files` → method lists.

#### Key metrics extracted
- Maximum cyclomatic complexity per method (`ccn`)
- Files exceeding 1000 lines
- Class complexity distribution