#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || echo "$SCRIPT_DIR/../../../..")"
BASELINE_FILE="$PROJECT_ROOT/baseline.json"

TMPDIR=$(mktemp -d "${TMPDIR:-/tmp}/ratchet-babysit.XXXXXX")
trap 'rm -rf "$TMPDIR"' EXIT

ACTIONS=""

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

add_action() {
  ACTIONS="${ACTIONS}${1}"$'\n'
}

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
    echo ""
    echo "All intermediate files are written to a temp directory."
    echo "Only baseline.json is written to the project root."
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

resolve_phpmetrics() {
  if [ -f "vendor/bin/phpmetrics" ]; then
    echo "vendor/bin/phpmetrics"
  elif command -v phpmetrics &> /dev/null; then
    echo "phpmetrics"
  elif [ -f "$HOME/.composer/vendor/bin/phpmetrics" ]; then
    echo "$HOME/.composer/vendor/bin/phpmetrics"
  else
    echo ""
  fi
}

resolve_pint() {
  if [ -f "vendor/bin/pint" ]; then
    echo "vendor/bin/pint"
  elif command -v pint &> /dev/null; then
    echo "pint"
  else
    echo ""
  fi
}

resolve_phpcsfixer() {
  if [ -f "vendor/bin/php-cs-fixer" ]; then
    echo "vendor/bin/php-cs-fixer"
  elif command -v php-cs-fixer &> /dev/null; then
    echo "php-cs-fixer"
  else
    echo ""
  fi
}

resolve_phpstan() {
  if [ -f "vendor/bin/phpstan" ]; then
    echo "vendor/bin/phpstan"
  elif command -v phpstan &> /dev/null; then
    echo "phpstan"
  else
    echo ""
  fi
}

resolve_psalm() {
  if [ -f "vendor/bin/psalm" ]; then
    echo "vendor/bin/psalm"
  elif command -v psalm &> /dev/null; then
    echo "psalm"
  else
    echo ""
  fi
}

resolve_phpunit() {
  if [ -f "vendor/bin/phpunit" ]; then
    echo "vendor/bin/phpunit"
  elif command -v phpunit &> /dev/null; then
    echo "phpunit"
  else
    echo ""
  fi
}

resolve_pest() {
  if [ -f "vendor/bin/pest" ]; then
    echo "vendor/bin/pest"
  elif command -v pest &> /dev/null; then
    echo "pest"
  else
    echo ""
  fi
}

echo "=== Ratchet Babysit: PHP Quality Gate ==="
echo "Mode: $MODE"
echo "Temp dir: $TMPDIR"
echo ""

# ---- Step 1: Security Audit ----
echo "--- Security Audit ---"
SEC_CRITICAL=0
SEC_HIGH=0
SEC_MEDIUM=0
SEC_LOW=0
if command -v composer &> /dev/null; then
  AUDIT_JSON=$(composer audit --format=json 2>/dev/null || true)
  if [ -n "$AUDIT_JSON" ]; then
    SEC_CRITICAL=$(echo "$AUDIT_JSON" | python3 -c "import json,sys; d=json.load(sys.stdin); print(sum(1 for a in d.get('advisories',[]) if a.get('severity','')=='critical'))" 2>/dev/null || echo "0")
    SEC_HIGH=$(echo "$AUDIT_JSON" | python3 -c "import json,sys; d=json.load(sys.stdin); print(sum(1 for a in d.get('advisories',[]) if a.get('severity','')=='high'))" 2>/dev/null || echo "0")
    SEC_MEDIUM=$(echo "$AUDIT_JSON" | python3 -c "import json,sys; d=json.load(sys.stdin); print(sum(1 for a in d.get('advisories',[]) if a.get('severity','')=='medium'))" 2>/dev/null || echo "0")
    SEC_LOW=$(echo "$AUDIT_JSON" | python3 -c "import json,sys; d=json.load(sys.stdin); print(sum(1 for a in d.get('advisories',[]) if a.get('severity','')=='low'))" 2>/dev/null || echo "0")
  fi
  if [ "$MODE" != "--init" ]; then
    if [ "$SEC_CRITICAL" -gt 0 ] || [ "$SEC_HIGH" -gt 0 ]; then
      echo -e "${RED}BLOCK: Security audit found ${SEC_CRITICAL} critical, ${SEC_HIGH} high advisories${NC}"
      add_action "[ACTION] ESCALATE: Update dependencies with critical/high vulnerabilities (critical: $SEC_CRITICAL, high: $SEC_HIGH)"
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
PINT_CMD=$(resolve_pint)
CSFIXER_CMD=$(resolve_phpcsfixer)
if [ -n "$PINT_CMD" ]; then
  PINT_OUTPUT=$($PINT_CMD --test 2>&1 || true)
  LINT_VIOLATIONS=$(echo "$PINT_OUTPUT" | grep -c "❌" 2>/dev/null || echo "0")
  if [ "$LINT_VIOLATIONS" -gt 0 ]; then
    echo "$PINT_OUTPUT" | grep "❌" 2>/dev/null | sed 's/.*❌ //' | head -20 | while IFS= read -r line; do
      [ -n "$line" ] && add_action "[ACTION] FIX STYLE: $line"
    done
  fi
elif [ -n "$CSFIXER_CMD" ]; then
  CSFIXER_OUTPUT=$($CSFIXER_CMD fix --dry-run --diff 2>&1 || true)
  LINT_VIOLATIONS=$(echo "$CSFIXER_OUTPUT" | grep -c "would be changed" 2>/dev/null || echo "0")
else
  echo "No style tool found (Pint or CS-Fixer), skipping"
fi
echo "Code style violations: $LINT_VIOLATIONS"

# ---- Step 3: Static Analysis ----
echo "--- Static Analysis ---"
SA_ERRORS=0
SA_WARNINGS=0
PHPSTAN_CMD=$(resolve_phpstan)
PSALM_CMD=$(resolve_psalm)
if [ -n "$PHPSTAN_CMD" ]; then
  SA_JSON=$($PHPSTAN_CMD analyse --memory-limit=512M --error-format=json 2>/dev/null || true)
  if [ -n "$SA_JSON" ]; then
    SA_ERRORS=$(echo "$SA_JSON" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('totals',{}).get('file_errors',0))" 2>/dev/null || echo "0")
    SA_WARNINGS=$(echo "$SA_JSON" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('totals',{}).get('errors',0))" 2>/dev/null || echo "0")
    if [ "$SA_ERRORS" -gt 0 ]; then
      echo "$SA_JSON" | python3 -c "
import json, sys
d = json.load(sys.stdin)
for f, errs in d.get('files', {}).items():
    for e in errs.get('messages', [])[:5]:
        msg = e.get('message', '')
        line = e.get('line', '?')
        print(f'[ACTION] FIX SA: {f}:{line} - {msg}')
" 2>/dev/null || true | while IFS= read -r line; do
        [ -n "$line" ] && add_action "$line"
      done
    fi
  fi
elif [ -n "$PSALM_CMD" ]; then
  PSALM_JSON=$($PSALM_CMD --output-format=json 2>/dev/null || true)
  echo "Psalm analysis: done (parse JSON for error counts)"
else
  echo "No static analysis tool found (PHPStan or Psalm), skipping"
fi
echo "Static analysis errors: $SA_ERRORS, warnings: $SA_WARNINGS"

# ---- Step 4: Tests & Coverage ----
echo "--- Tests & Coverage ---"
COVERAGE_PCT=0.0
PHPUNIT_CMD=$(resolve_phpunit)
PEST_CMD=$(resolve_pest)
if [ -n "$PHPUNIT_CMD" ]; then
  $PHPUNIT_CMD --coverage-clover="$TMPDIR/clover.xml" --coverage-text="$TMPDIR/coverage.txt" 2>&1 | tee "$TMPDIR/phpunit-output.txt" || true
  if [ -f "$TMPDIR/clover.xml" ]; then
    COVERAGE_PCT=$(python3 -c "
import xml.etree.ElementTree as ET
tree = ET.parse('$TMPDIR/clover.xml')
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
elif [ -n "$PEST_CMD" ]; then
  $PEST_CMD --coverage --min=0 2>&1 | tee "$TMPDIR/pest-output.txt" || true
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
  npx jscpd --threshold 0 --reporters json --output "$TMPDIR" src/ 2>/dev/null || true
  JSCPD_REPORT="$TMPDIR/jscpd/jscpd-report.json"
  if [ -f "$JSCPD_REPORT" ]; then
    DUP_PCT=$(python3 -c "import json; d=json.load(open('$JSCPD_REPORT')); print(d['statistics']['total']['percentage'])" 2>/dev/null || echo "0.0")
    DUP_CLONES_COUNT=$(python3 -c "import json; d=json.load(open('$JSCPD_REPORT')); print(d['statistics']['total']['clones'])" 2>/dev/null || echo "0")
    DUP_DETAILS=$(python3 -c "
import json
d = json.load(open('$JSCPD_REPORT'))
for clone in d.get('duplicates', [])[:30]:
    f1 = clone.get('firstFile', {}).get('name', clone.get('firstFile', {}).get('path', '?'))
    l1_start = clone.get('firstFile', {}).get('start', '?')
    l1_end = clone.get('firstFile', {}).get('end', '?')
    f2 = clone.get('secondFile', {}).get('name', clone.get('secondFile', {}).get('path', '?'))
    l2_start = clone.get('secondFile', {}).get('start', '?')
    l2_end = clone.get('secondFile', {}).get('end', '?')
    try:
        lines = int(l1_end) - int(l1_start)
    except (ValueError, TypeError):
        lines = '?'
    print(f'  {f1}:{l1_start}-{l1_end} <-> {f2}:{l2_start}-{l2_end} ({lines}L)')
" 2>/dev/null || true)
    if [ -n "$DUP_DETAILS" ]; then
      echo -e "${CYAN}Duplicate clones found ($DUP_CLONES_COUNT):${NC}"
      echo "$DUP_DETAILS"
      echo "$DUP_DETAILS" | while IFS= read -r line; do
        [ -n "$line" ] && add_action "[ACTION] REFACTOR DUP:$line"
      done
    fi
  fi
elif command -v phpcpd &> /dev/null || [ -f "vendor/bin/phpcpd" ]; then
  PHPCPD_CMD="phpcpd"
  [ -f "vendor/bin/phpcpd" ] && PHPCPD_CMD="vendor/bin/phpcpd"
  PHPCPD_OUTPUT=$($PHPCPD_CMD src/ 2>&1 || true)
  DUP_DETAILS=$(echo "$PHPCPD_OUTPUT" | grep -A2 "duplicated lines" 2>/dev/null || echo "")
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
    add_action "[ACTION] MODULARIZE: ${f} is ${lines} lines (max 1000)"
  fi
done < <(find "$PROJECT_ROOT/src" "$PROJECT_ROOT/app" -name "*.php" 2>/dev/null | head -500)
echo "Largest file: $MAX_LINES_FILE ($MAX_LINES lines)"
if [ -n "$OVERSIZE_FILES" ]; then
  echo -e "${RED}Files exceeding 1000 lines:${NC}${OVERSIZE_FILES}"
fi

MAX_CYCLO=0
MAX_CYCLO_FILE="N/A"
PHPMETRICS_CMD=$(resolve_phpmetrics)
if [ -n "$PHPMETRICS_CMD" ]; then
  $PHPMETRICS_CMD --report-json="$TMPDIR/phpmetrics.json" src/ 2>/dev/null || true
  if [ -f "$TMPDIR/phpmetrics.json" ]; then
    CYCLO_RESULT=$(python3 -c "
import json, sys
try:
    d = json.load(open('$TMPDIR/phpmetrics.json'))
except:
    print('0|N/A')
    sys.exit(0)
max_ccn = 0
max_method = 'N/A'
if 'classes' in d:
    for cls_name, cls_data in d['classes'].items():
        if not isinstance(cls_data, dict):
            continue
        methods = cls_data.get('methods', {})
        if not isinstance(methods, dict):
            for m in methods if isinstance(methods, list) else []:
                if isinstance(m, dict):
                    ccn = m.get('ccn', 0)
                    mname = m.get('name', '?')
                    if ccn > max_ccn:
                        max_ccn = ccn
                        max_method = f'{cls_name}::{mname}'
        else:
            for mname, mdata in methods.items():
                if isinstance(mdata, dict):
                    ccn = mdata.get('ccn', 0)
                elif isinstance(mdata, (int, float)):
                    ccn = mdata
                    mname = mname
                else:
                    ccn = 0
                if ccn > max_ccn:
                    max_ccn = ccn
                    max_method = f'{cls_name}::{mname}'
if max_ccn == 0 and 'files' in d:
    for fname, fdata in d['files'].items():
        if not isinstance(fdata, dict):
            continue
        fmethods = fdata.get('methods', [])
        for m in fmethods if isinstance(fmethods, list) else []:
            if isinstance(m, dict):
                ccn = m.get('ccn', 0)
                mname = m.get('name', '?')
                if ccn > max_ccn:
                    max_ccn = ccn
                    max_method = f'{fname}::{mname}'
print(f'{max_ccn}|{max_method}')
" 2>/dev/null || echo "0|N/A")
    MAX_CYCLO=$(echo "$CYCLO_RESULT" | cut -d'|' -f1)
    MAX_CYCLO_FILE=$(echo "$CYCLO_RESULT" | cut -d'|' -f2)
  fi
  echo "phpmetrics: max cyclomatic complexity = $MAX_CYCLO ($MAX_CYCLO_FILE)"
else
  echo "phpmetrics not found (tried vendor/bin/phpmetrics, ~/.composer/vendor/bin/phpmetrics, global phpmetrics), skipping complexity check"
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
    if [ -n "$ACTIONS" ]; then
      echo "$ACTIONS"
      echo "Total: $(echo "$ACTIONS" | grep -c '\[') action(s) required"
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
      add_action "[ACTION] ADD TESTS: Coverage dropped from ${BASE_COV}% to ${COVERAGE_PCT}%. Add tests for uncovered code paths."
    fi

    if ! python3 -c "exit(0 if $DUP_PCT <= $BASE_DUP else 1)"; then
      PASS=false
      echo -e "${RED}FAIL: Duplication increased: ${DUP_PCT}% > baseline ${BASE_DUP}%${NC}"
      add_action "[ACTION] REFACTOR DUP: Duplication increased from ${BASE_DUP}% to ${DUP_PCT}% ($DUP_CLONES_COUNT clones found). Extract shared logic into Traits, Actions, or Services."
    fi

    if [ "$LINT_VIOLATIONS" -gt "$BASE_LINT" ]; then
      PASS=false
      echo -e "${RED}FAIL: Lint violations increased: $LINT_VIOLATIONS > baseline $BASE_LINT${NC}"
      add_action "[ACTION] FIX STYLE: Run vendor/bin/pint to auto-fix style violations"
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
    if [ -n "$ACTIONS" ]; then
      echo "$ACTIONS"
      echo "Total: $(echo "$ACTIONS" | grep -c '\[') action(s) required"
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
    if [ -n "$ACTIONS" ]; then
      echo "$ACTIONS"
      echo "Total: $(echo "$ACTIONS" | grep -c '\[') action(s) required"
    else
      echo "No actions required."
    fi
    ;;
esac