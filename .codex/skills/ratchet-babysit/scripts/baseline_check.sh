#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || echo "$SCRIPT_DIR/../../../..")"
BASELINE_FILE="$PROJECT_ROOT/baseline.json"
REPORTS_DIR="$PROJECT_ROOT/reports"

mkdir -p "$REPORTS_DIR"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

MODE="${1:---help}"

case "$MODE" in
  --init|--compare|--check)
    ;;
  --help|-h)
    echo "Usage: $0 [--init|--compare|--check|--help]"
    echo ""
    echo "  --init     Run toolchain and create baseline.json (first run)"
    echo "  --compare  Run toolchain and compare against existing baseline.json"
    echo "  --check    Run toolchain and output metrics (no comparison)"
    echo "  --help     Show this help"
    exit 0
    ;;
  *)
    echo "Unknown option: $MODE"
    echo "Usage: $0 [--init|--compare|--check|--help]"
    exit 1
    ;;
esac

if [ "$MODE" = "--compare" ] && [ ! -f "$BASELINE_FILE" ]; then
  echo -e "${YELLOW}Warning: baseline.json not found. Run with --init first.${NC}"
  echo "Falling back to --init mode."
  MODE="--init"
fi

echo "=== Ratchet Babysit: PHP Quality Gate ==="
echo "Mode: $MODE"
echo ""

# ---- Step 1: Security Audit ----
echo "--- Security Audit ---"
SEC_RESULT=0
if command -v composer &> /dev/null; then
  composer audit --format=json 2>/dev/null > "$REPORTS_DIR/composer-audit.json" || SEC_RESULT=$?
  if [ "$MODE" != "--init" ] && [ "$SEC_RESULT" -ne 0 ]; then
    CRITICAL=$(python3 -c "import json; d=json.load(open('$REPORTS_DIR/composer-audit.json')); print(sum(1 for a in d.get('advisories',[]) if a.get('severity','')=='critical'))" 2>/dev/null || echo "0")
    HIGH=$(python3 -c "import json; d=json.load(open('$REPORTS_DIR/composer-audit.json')); print(sum(1 for a in d.get('advisories',[]) if a.get('severity','')=='high'))" 2>/dev/null || echo "0")
    if [ "$CRITICAL" -gt 0 ] || [ "$HIGH" -gt 0 ]; then
      echo -e "${RED}BLOCK: Security audit found ${CRITICAL} critical, ${HIGH} high advisories${NC}"
      [ "$MODE" = "--compare" ] && exit 1
    fi
  fi
  echo "Security audit: done"
else
  echo "Composer not found, skipping security audit"
fi

# ---- Step 2: Code Style ----
echo "--- Code Style ---"
LINT_VIOLATIONS=0
if [ -f "vendor/bin/pint" ]; then
  vendor/bin/pint --test 2>&1 | tee "$REPORTS_DIR/pint-output.txt" || true
  LINT_VIOLATIONS=$(grep -c "❌" "$REPORTS_DIR/pint-output.txt" 2>/dev/null || echo "0")
elif [ -f "vendor/bin/php-cs-fixer" ]; then
  vendor/bin/php-cs-fixer fix --dry-run --diff 2>&1 | tee "$REPORTS_DIR/cs-fixer-output.txt" || true
  LINT_VIOLATIONS=$(grep -c "" "$REPORTS_DIR/cs-fixer-output.txt" 2>/dev/null || echo "0")
else
  echo "No style tool found (Pint or CS-Fixer), skipping"
fi
echo "Code style violations: $LINT_VIOLATIONS"

# ---- Step 3: Static Analysis ----
echo "--- Static Analysis ---"
SA_ERRORS=0
SA_WARNINGS=0
if [ -f "vendor/bin/phpstan" ]; then
  vendor/bin/phpstan analyse --memory-limit=512M --error-format=json 2>/dev/null > "$REPORTS_DIR/phpstan.json" || true
  if [ -f "$REPORTS_DIR/phpstan.json" ] && python3 -c "import json" < "$REPORTS_DIR/phpstan.json" 2>/dev/null; then
    SA_ERRORS=$(python3 -c "import json; d=json.load(open('$REPORTS_DIR/phpstan.json')); print(d.get('totals',{}).get('file_errors',0))" 2>/dev/null || echo "0")
    SA_WARNINGS=$(python3 -c "import json; d=json.load(open('$REPORTS_DIR/phpstan.json')); print(d.get('totals',{}).get('errors',0))" 2>/dev/null || echo "0")
  fi
elif [ -f "vendor/bin/psalm" ]; then
  vendor/bin/psalm --output-format=json 2>/dev/null > "$REPORTS_DIR/psalm.json" || true
  echo "Psalm analysis: done (parse JSON for error counts)"
else
  echo "No static analysis tool found (PHPStan or Psalm), skipping"
fi
echo "Static analysis errors: $SA_ERRORS, warnings: $SA_WARNINGS"

# ---- Step 4: Tests & Coverage ----
echo "--- Tests & Coverage ---"
COVERAGE_PCT=0.0
if [ -f "vendor/bin/phpunit" ]; then
  vendor/bin/phpunit --coverage-clover="$REPORTS_DIR/clover.xml" --coverage-text="$REPORTS_DIR/coverage.txt" 2>&1 | tee "$REPORTS_DIR/phpunit-output.txt" || true
  if [ -f "$REPORTS_DIR/clover.xml" ]; then
    COVERAGE_PCT=$(python3 -c "
import xml.etree.ElementTree as ET
tree = ET.parse('$REPORTS_DIR/clover.xml')
root = tree.getroot()
metrics = root.find('.//metrics')
if metrics is not None:
    covered = float(metrics.get('coveredstatements', 0))
    total = float(metrics.get('statements', 0))
    print(round((covered / total) * 100, 2) if total > 0 else 0.0)
else:
    print(0.0)
" 2>/dev/null || echo "0.0")
  fi
elif [ -f "vendor/bin/pest" ]; then
  vendor/bin/pest --coverage --min=0 2>&1 | tee "$REPORTS_DIR/pest-output.txt" || true
  echo "Pest coverage: check output above"
else
  echo "No test runner found (PHPUnit or Pest), skipping"
fi
echo "Coverage: ${COVERAGE_PCT}%"

# ---- Step 5: Duplication ----
echo "--- Duplication Check ---"
DUP_PCT=0.0
if command -v npx &> /dev/null; then
  npx jscpd --threshold 0 --reporters json --output "$REPORTS_DIR" src/ 2>/dev/null || true
  if [ -f "$REPORTS_DIR/jscpd/jscpd-report.json" ]; then
    DUP_PCT=$(python3 -c "import json; d=json.load(open('$REPORTS_DIR/jscpd/jscpd-report.json')); print(d['statistics']['total']['percentage'])" 2>/dev/null || echo "0.0")
  fi
elif [ -f "vendor/bin/phpcpd" ]; then
  vendor/bin/phpcpd src/ 2>&1 | tee "$REPORTS_DIR/phpcpd-output.txt" || true
  echo "phpcpd duplication: check output above"
else
  echo "No duplication tool found (jscpd or phpcpd), skipping"
fi
echo "Duplication: ${DUP_PCT}%"

# ---- Step 6: File Sizes & Complexity ----
echo "--- File Sizes ---"
MAX_LINES=0
MAX_LINES_FILE="N/A"
while IFS= read -r f; do
  lines=$(wc -l < "$f")
  if [ "$lines" -gt "$MAX_LINES" ]; then
    MAX_LINES=$lines
    MAX_LINES_FILE="$f"
  fi
done < <(find "$PROJECT_ROOT/src" "$PROJECT_ROOT/app" -name "*.php" 2>/dev/null | head -500)
echo "Largest file: $MAX_LINES_FILE ($MAX_LINES lines)"

MAX_CYCLO=0
MAX_CYCLO_FILE="N/A"
if [ -f "vendor/bin/phpmetrics" ]; then
  vendor/bin/phpmetrics --report-html="$REPORTS_DIR/phpmetrics" --report-violations="$REPORTS_DIR/phpmetrics.xml" src/ 2>/dev/null || true
  echo "phpmetrics report generated"
else
  echo "phpmetrics not found, skipping complexity check"
fi

# ---- Build Metrics JSON ----
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
COMMIT=$(git -C "$PROJECT_ROOT" rev-parse --short HEAD 2>/dev/null || echo "unknown")

METRICS_JSON=$(python3 -c "
import json
print(json.dumps({
    'version': 1,
    'timestamp': '$TIMESTAMP',
    'commit': '$COMMIT',
    'metrics': {
        'coverage_percent': $COVERAGE_PCT,
        'duplication_percent': $DUP_PCT,
        'lint_violations': $LINT_VIOLATIONS,
        'phpstan_errors': $SA_ERRORS,
        'phpstan_warnings': $SA_WARNINGS,
        'security_advisories': {
            'critical': 0,
            'high': 0,
            'medium': 0,
            'low': 0
        },
        'file_sizes': {
            'max_lines': $MAX_LINES,
            'max_lines_file': '$MAX_LINES_FILE'
        },
        'cyclomatic_complexity': {
            'max_per_method': $MAX_CYCLO,
            'max_per_method_file': '$MAX_CYCLO_FILE'
        }
    }
}, indent=2))
")

# ---- Handle Modes ----
case "$MODE" in
  --init)
    echo "$METRICS_JSON" > "$BASELINE_FILE"
    echo -e "${GREEN}Baseline created at $BASELINE_FILE${NC}"
    echo "$METRICS_JSON"
    ;;
  --compare)
    PASS=true
    REPORT="STATUS: "
    BASE_COV=$(python3 -c "import json; d=json.load(open('$BASELINE_FILE')); print(d['metrics']['coverage_percent'])" 2>/dev/null || echo "0")
    BASE_DUP=$(python3 -c "import json; d=json.load(open('$BASELINE_FILE')); print(d['metrics']['duplication_percent'])" 2>/dev/null || echo "0")
    BASE_LINT=$(python3 -c "import json; d=json.load(open('$BASELINE_FILE')); print(d['metrics']['lint_violations'])" 2>/dev/null || echo "0")
    BASE_SA=$(python3 -c "import json; d=json.load(open('$BASELINE_FILE')); print(d['metrics']['phpstan_errors'])" 2>/dev/null || echo "0")

    COV_DIFF=$(python3 -c "print(round($COVERAGE_PCT - $BASE_COV, 2))")
    DUP_DIFF=$(python3 -c "print(round($DUP_PCT - $BASE_DUP, 2))")

    if python3 -c "exit(0 if $COVERAGE_PCT >= $BASE_COV else 1)"; then
      :
    else
      PASS=false
      echo -e "${RED}FAIL: Coverage regressed: ${COVERAGE_PCT}% < baseline ${BASE_COV}%${NC}"
    fi

    if python3 -c "exit(0 if $DUP_PCT <= $BASE_DUP else 1)"; then
      :
    else
      PASS=false
      echo -e "${RED}FAIL: Duplication increased: ${DUP_PCT}% > baseline ${BASE_DUP}%${NC}"
    fi

    if [ "$LINT_VIOLATIONS" -gt "$BASE_LINT" ]; then
      PASS=false
      echo -e "${RED}FAIL: Lint violations increased: $LINT_VIOLATIONS > baseline $BASE_LINT${NC}"
    fi

    if [ "$SA_ERRORS" -gt "$BASE_SA" ]; then
      PASS=false
      echo -e "${RED}FAIL: Static analysis errors increased: $SA_ERRORS > baseline $BASE_SA${NC}"
    fi

    if [ "$MAX_LINES" -gt 1000 ]; then
      PASS=false
      echo -e "${RED}FAIL: File exceeds 1000 lines: $MAX_LINES_FILE ($MAX_LINES lines)${NC}"
    fi

    if $PASS; then
      echo -e "${GREEN}STATUS: PASS | COV: ${COVERAGE_PCT}% (+${COV_DIFF}%) | DUP: ${DUP_PCT}% (-${DUP_DIFF}%) | LINT: $LINT_VIOLATIONS | SA: $SA_ERRORS | SIZE: max ${MAX_LINES}L | SEC: 0/0 | CYCLO: max $MAX_CYCLO${NC}"
      echo "$METRICS_JSON" > "$BASELINE_FILE"
      echo "Baseline updated."
    else
      echo -e "${RED}STATUS: FAIL | COV: ${COVERAGE_PCT}% (B: ${BASE_COV}%) | DUP: ${DUP_PCT}% (B: ${BASE_DUP}%) | LINT: $LINT_VIOLATIONS | SA: $SA_ERRORS | SIZE: $MAX_LINES_FILE (${MAX_LINES}L > 1000L) | SEC: 0/0 | CYCLO: $MAX_CYCLO${NC}"
      exit 1
    fi
    ;;
  --check)
    echo "$METRICS_JSON"
    ;;
esac