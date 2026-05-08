#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || echo "$SCRIPT_DIR/../../../..")"
BASELINE_FILE="$PROJECT_ROOT/baseline.json"
REPORTS_DIR="$PROJECT_ROOT/reports"
ACTIONS_FILE="$REPORTS_DIR/required_actions.txt"

mkdir -p "$REPORTS"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
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

# Clear actions file
: > "$ACTIONS_FILE"

echo "=== Ratchet Babysit: PHP Quality Gate ==="
echo "Mode: $MODE"
echo ""

# ---- Step 1: Security Audit ----
echo "--- Security Audit ---"
SEC_CRITICAL=0
SEC_HIGH=0
SEC_MEDIUM=0
SEC_LOW=0
if command -v composer &> /dev/null; then
  composer audit --format=json 2>/dev/null > "$REPORTS_DIR/composer-audit.json" || true
  if [ -f "$REPORTS_DIR/composer-audit.json" ]; then
    SEC_CRITICAL=$(python3 -c "import json; d=json.load(open('$REPORTS_DIR/composer-audit.json')); print(sum(1 for a in d.get('advisories',[]) if a.get('severity','')=='critical'))" 2>/dev/null || echo "0")
    SEC_HIGH=$(python3 -c "import json; d=json.load(open('$REPORTS_DIR/composer-audit.json')); print(sum(1 for a in d.get('advisories',[]) if a.get('severity','')=='high'))" 2>/dev/null || echo "0")
    SEC_MEDIUM=$(python3 -c "import json; d=json.load(open('$REPORTS_DIR/composer-audit.json')); print(sum(1 for a in d.get('advisories',[]) if a.get('severity','')=='medium'))" 2>/dev/null || echo "0")
    SEC_LOW=$(python3 -c "import json; d=json.load(open('$REPORTS_DIR/composer-audit.json')); print(sum(1 for a in d.get('advisories',[]) if a.get('severity','')=='low'))" 2>/dev/null || echo "0")
  fi
  if [ "$MODE" != "--init" ]; then
    if [ "$SEC_CRITICAL" -gt 0 ] || [ "$SEC_HIGH" -gt 0 ]; then
      echo -e "${RED}BLOCK: Security audit found ${SEC_CRITICAL} critical, ${SEC_HIGH} high advisories${NC}"
      echo "[ACTION] ESCALATE: Update dependencies with critical/high vulnerabilities (critical: $SEC_CRITICAL, high: $SEC_HIGH)" >> "$ACTIONS_FILE"
      [ "$MODE" = "--compare" ] && exit 1
    fi
  fi
  echo "Security: critical=$SEC_CRITICAL high=$SEC_HIGH medium=$SEC_MEDIUM low=$SEC_LOW"
else
  echo "Composer not found, skipping security audit"
fi

# ---- Step 2: Code Style ----
echo "--- Code Style ---"
LINT_VIOLATIONS=0
LINT_FILES=""
if [ -f "vendor/bin/pint" ]; then
  vendor/bin/pint --test 2>&1 | tee "$REPORTS_DIR/pint-output.txt" || true
  LINT_VIOLATIONS=$(grep -c "❌" "$REPORTS_DIR/pint-output.txt" 2>/dev/null || echo "0")
  if [ "$LINT_VIOLATIONS" -gt 0 ]; then
    LINT_FILES=$(grep "❌" "$REPORTS_DIR/pint-output.txt" 2>/dev/null | sed 's/.*❌ //' | head -20 || true)
    echo "$LINT_FILES" | while IFS= read -r line; do
      [ -n "$line" ] && echo "[ACTION] FIX STYLE: $line" >> "$ACTIONS_FILE"
    done
  fi
elif [ -f "vendor/bin/php-cs-fixer" ]; then
  vendor/bin/php-cs-fixer fix --dry-run --diff 2>&1 | tee "$REPORTS_DIR/cs-fixer-output.txt" || true
  LINT_VIOLATIONS=$(grep -c "would be changed" "$REPORTS_DIR/cs-fixer-output.txt" 2>/dev/null || echo "0")
else
  echo "No style tool found (Pint or CS-Fixer), skipping"
fi
echo "Code style violations: $LINT_VIOLATIONS"

# ---- Step 3: Static Analysis ----
echo "--- Static Analysis ---"
SA_ERRORS=0
SA_WARNINGS=0
SA_DETAILS=""
if [ -f "vendor/bin/phpstan" ]; then
  vendor/bin/phpstan analyse --memory-limit=512M --error-format=json 2>/dev/null > "$REPORTS_DIR/phpstan.json" || true
  if [ -f "$REPORTS_DIR/phpstan.json" ] && python3 -c "import json" < "$REPORTS_DIR/phpstan.json" 2>/dev/null; then
    SA_ERRORS=$(python3 -c "import json; d=json.load(open('$REPORTS_DIR/phpstan.json')); print(d.get('totals',{}).get('file_errors',0))" 2>/dev/null || echo "0")
    SA_WARNINGS=$(python3 -c "import json; d=json.load(open('$REPORTS_DIR/phpstan.json')); print(d.get('totals',{}).get('errors',0))" 2>/dev/null || echo "0")
    if [ "$SA_ERRORS" -gt 0 ]; then
      SA_DETAILS=$(python3 -c "
import json
d = json.load(open('$REPORTS_DIR/phpstan.json'))
for f, errs in d.get('files', {}).items():
    for e in errs.get('messages', [])[:5]:
        msg = e.get('message', '')
        line = e.get('line', '?')
        print(f'[ACTION] FIX SA: {f}:{line} - {msg}')
" 2>/dev/null || true)
      echo "$SA_DETAILS" >> "$ACTIONS_FILE"
    fi
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
UNCOVERED_FILES=""
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
else
  echo "No test runner found (PHPUnit or Pest), skipping"
fi
echo "Coverage: ${COVERAGE_PCT}%"

# ---- Step 5: Duplication Check ----
echo "--- Duplication Check ---"
DUP_PCT=0.0
DUP_DETAILS=""
DUP_CLONES_COUNT=0
if command -v npx &> /dev/null; then
  npx jscpd --threshold 0 --reporters json --output "$REPORTS_DIR" src/ 2>/dev/null || true
  if [ -f "$REPORTS_DIR/jscpd/jscpd-report.json" ]; then
    DUP_PCT=$(python3 -c "import json; d=json.load(open('$REPORTS_DIR/jscpd/jscpd-report.json')); print(d['statistics']['total']['percentage'])" 2>/dev/null || echo "0.0")
    DUP_CLONES_COUNT=$(python3 -c "import json; d=json.load(open('$REPORTS_DIR/jscpd/jscpd-report.json')); print(d['statistics']['total']['clones'])" 2>/dev/null || echo "0")
    DUP_DETAILS=$(python3 -c "
import json
d = json.load(open('$REPORTS_DIR/jscpd/jscpd-report.json'))
for clone in d.get('duplicates', [])[:30]:
    f1 = clone.get('firstFile', {}).get('name', '?')
    l1_start = clone.get('firstFile', {}).get('start', '?')
    l1_end = clone.get('firstFile', {}).get('end', '?')
    f2 = clone.get('secondFile', {}).get('name', '?')
    l2_start = clone.get('secondFile', {}).get('start', '?')
    l2_end = clone.get('secondFile', {}).get('end', '?')
    lines = int(l1_end) - int(l1_start) if isinstance(l1_end, int) and isinstance(l1_start, int) else '?'
    print(f'  {f1}:{l1_start}-{l1_end} <-> {f2}:{l2_start}-{l2_end} ({lines}L)')
" 2>/dev/null || true)
    if [ -n "$DUP_DETAILS" ]; then
      echo -e "${CYAN}Duplicate clones found ($DUP_CLONES_COUNT):${NC}"
      echo "$DUP_DETAILS"
      echo "$DUP_DETAILS" | while IFS= read -r line; do
        [ -n "$line" ] && echo "[ACTION] REFACTOR DUP: $line" >> "$ACTIONS_FILE"
      done
    fi
  fi
elif [ -f "vendor/bin/phpcpd" ]; then
  vendor/bin/phpcpd src/ 2>&1 | tee "$REPORTS_DIR/phpcpd-output.txt" || true
  DUP_DETAILS=$(grep -E "^\s+\d+\.\d+%.*duplicated lines" "$REPORTS_DIR/phpcpd-output.txt" 2>/dev/null || echo "")
  echo "phpcpd duplication: check output above"
else
  echo "No duplication tool found (jscpd or phpcpd), skipping"
fi
echo "Duplication: ${DUP_PCT}% ($DUP_CLONES_COUNT clones)"

# ---- Step 6: File Sizes & Complexity ----
echo "--- File Sizes ---"
MAX_LINES=0
MAX_LINES_FILE="N/A"
OVERSIZE_FILES=""
while IFS= read -r f; do
  lines=$(wc -l < "$f")
  if [ "$lines" -gt "$MAX_LINES" ]; then
    MAX_LINES=$lines
    MAX_LINES_FILE="$f"
  fi
  if [ "$lines" -gt 1000 ]; then
    OVERSIZE_FILES="${OVERSIZE_FILES}  ${f} (${lines}L)
"
    echo "[ACTION] MODULARIZE: ${f} is ${lines} lines (max 1000)" >> "$ACTIONS_FILE"
  fi
done < <(find "$PROJECT_ROOT/src" "$PROJECT_ROOT/app" -name "*.php" 2>/dev/null | head -500)
echo "Largest file: $MAX_LINES_FILE ($MAX_LINES lines)"
if [ -n "$OVERSIZE_FILES" ]; then
  echo -e "${RED}Files exceeding 1000 lines:${NC}${OVERSIZE_FILES}"
fi

MAX_CYCLO=0
MAX_CYCLO_FILE="N/A"
if [ -f "vendor/bin/phpmetrics" ]; then
  vendor/bin/phpmetrics --report-html="$REPORTS_DIR/phpmetrics" --report-violations="$REPORTS_DIR/phpmetrics.xml" --report-json="$REPORTS_DIR/phpmetrics.json" src/ 2>/dev/null || true
  if [ -f "$REPORTS_DIR/phpmetrics.json" ]; then
    MAX_CYCLO=$(python3 -c "
import json
d = json.load(open('$REPORTS_DIR/phpmetrics.json'))
max_c = 0
max_f = 'N/A'
for cls, info in d.get('classes', {}).items():
    for m, minfo in info.get('methods', {}).items() if isinstance(info.get('methods',{}), dict) else []:
        cc = minfo if isinstance(minfo, int) else minfo.get('ccn', 0) if isinstance(minfo, dict) else 0
        if cc > max_c:
            max_c = cc
            max_f = f'{cls}::{m}'
print(f'{max_c}|{max_f}')
" 2>/dev/null || echo "0|N/A")
    MAX_CYCLO_FILE=$(echo "$MAX_CYCLO" | cut -d'|' -f2)
    MAX_CYCLO=$(echo "$MAX_CYCLO" | cut -d'|' -f1)
  fi
  echo "phpmetrics: max cyclomatic complexity = $MAX_CYCLO ($MAX_CYCLO_FILE)"
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
        'duplication_clones': $DUP_CLONES_COUNT,
        'lint_violations': $LINT_VIOLATIONS,
        'phpstan_errors': $SA_ERRORS,
        'phpstan_warnings': $SA_WARNINGS,
        'security_advisories': {
            'critical': $SEC_CRITICAL,
            'high': $SEC_HIGH,
            'medium': $SEC_MEDIUM,
            'low': $SEC_LOW
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
    echo ""
    echo "=== Required Actions ==="
    if [ -s "$ACTIONS_FILE" ]; then
      cat "$ACTIONS_FILE"
    else
      echo "No actions required."
    fi
    ;;
  --compare)
    PASS=true
    BASE_COV=$(python3 -c "import json; d=json.load(open('$BASELINE_FILE')); print(d['metrics']['coverage_percent'])" 2>/dev/null || echo "0")
    BASE_DUP=$(python3 -c "import json; d=json.load(open('$BASELINE_FILE')); print(d['metrics']['duplication_percent'])" 2>/dev/null || echo "0")
    BASE_LINT=$(python3 -c "import json; d=json.load(open('$BASELINE_FILE')); print(d['metrics']['lint_violations'])" 2>/dev/null || echo "0")
    BASE_SA=$(python3 -c "import json; d=json.load(open('$BASELINE_FILE')); print(d['metrics']['phpstan_errors'])" 2>/dev/null || echo "0")

    COV_DIFF=$(python3 -c "print(round($COVERAGE_PCT - $BASE_COV, 2))")
    DUP_DIFF=$(python3 -c "print(round($DUP_PCT - $BASE_DUP, 2))")

    if ! python3 -c "exit(0 if $COVERAGE_PCT >= $BASE_COV else 1)"; then
      PASS=false
      echo -e "${RED}FAIL: Coverage regressed: ${COVERAGE_PCT}% < baseline ${BASE_COV}%${NC}"
      echo "[ACTION] ADD TESTS: Coverage dropped from ${BASE_COV}% to ${COVERAGE_PCT}%. Add tests for uncovered code paths." >> "$ACTIONS_FILE"
    fi

    if ! python3 -c "exit(0 if $DUP_PCT <= $BASE_DUP else 1)"; then
      PASS=false
      echo -e "${RED}FAIL: Duplication increased: ${DUP_PCT}% > baseline ${BASE_DUP}%${NC}"
      echo "[ACTION] REFACTOR DUP: Duplication increased from ${BASE_DUP}% to ${DUP_PCT}% ($DUP_CLONES_COUNT clones found). Extract shared logic into Traits, Actions, or Services." >> "$ACTIONS_FILE"
    fi

    if [ "$LINT_VIOLATIONS" -gt "$BASE_LINT" ]; then
      PASS=false
      echo -e "${RED}FAIL: Lint violations increased: $LINT_VIOLATIONS > baseline $BASE_LINT${NC}"
      echo "[ACTION] FIX STYLE: Run vendor/bin/pint to auto-fix style violations" >> "$ACTIONS_FILE"
    fi

    if [ "$SA_ERRORS" -gt "$BASE_SA" ]; then
      PASS=false
      echo -e "${RED}FAIL: Static analysis errors increased: $SA_ERRORS > baseline $BASE_SA${NC}"
    fi

    if [ "$MAX_LINES" -gt 1000 ]; then
      PASS=false
      echo -e "${RED}FAIL: Files exceed 1000 lines limit${NC}"
    fi

    echo ""
    if $PASS; then
      echo -e "${GREEN}STATUS: PASS | COV: ${COVERAGE_PCT}% (+${COV_DIFF}%) | DUP: ${DUP_PCT}% (-${DUP_DIFF}%) | LINT: $LINT_VIOLATIONS | SA: $SA_ERRORS | SIZE: max ${MAX_LINES}L | SEC: ${SEC_CRITICAL}/${SEC_HIGH} | CYCLO: max $MAX_CYCLO${NC}"
      if [ -n "$DUP_DETAILS" ]; then
        echo -e "${CYAN}Duplicates (informational, within baseline):${NC}"
        echo "$DUP_DETAILS"
      fi
      echo "$METRICS_JSON" > "$BASELINE_FILE"
      echo "Baseline updated."
    else
      echo -e "${RED}STATUS: FAIL | COV: ${COVERAGE_PCT}% (B: ${BASE_COV}%) | DUP: ${DUP_PCT}% (B: ${BASE_DUP}%) | LINT: $LINT_VIOLATIONS | SA: $SA_ERRORS | SIZE: ${MAX_LINES_FILE} (${MAX_LINES}L > 1000L) | SEC: ${SEC_CRITICAL}/${SEC_HIGH} | CYCLO: $MAX_CYCLO${NC}"
      if [ -n "$DUP_DETAILS" ]; then
        echo -e "${RED}Duplicate code locations:${NC}"
        echo "$DUP_DETAILS"
      fi
    fi

    echo ""
    echo "=== Required Actions ==="
    ACTIONS_COUNT=$(wc -l < "$ACTIONS_FILE" | tr -d ' ')
    if [ "$ACTIONS_COUNT" -gt 0 ]; then
      cat "$ACTIONS_FILE"
      echo ""
      echo "Total: $ACTIONS_COUNT action(s) required"
    else
      echo "No actions required."
    fi

    if ! $PASS; then
      exit 1
    fi
    ;;
  --check)
    echo "$METRICS_JSON"
    echo ""
    if [ -n "$DUP_DETAILS" ]; then
      echo -e "${CYAN}Duplicate clones ($DUP_CLONES_COUNT):${NC}"
      echo "$DUP_DETAILS"
    fi
    echo ""
    echo "=== Required Actions ==="
    if [ -s "$ACTIONS_FILE" ]; then
      cat "$ACTIONS_FILE"
      ACTIONS_COUNT=$(wc -l < "$ACTIONS_FILE" | tr -d ' ')
      echo ""
      echo "Total: $ACTIONS_COUNT action(s) required"
    else
      echo "No actions required."
    fi
    ;;
esac