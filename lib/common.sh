#!/usr/bin/env bash
# ----------------------------------------------------------------------------
# common.sh — colors, logging, the check-result model, JSON writer, helpers.
# Sourced by every other module. Defines no top-level side effects.
# ----------------------------------------------------------------------------

# ---- Colors (disabled when not a TTY or when NO_COLOR is set) --------------
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
    RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
    CYAN='\033[0;36m'; BLUE='\033[0;34m'; BOLD='\033[1m'; DIM='\033[2m'; NC='\033[0m'
else
    RED=''; GREEN=''; YELLOW=''; CYAN=''; BLUE=''; BOLD=''; DIM=''; NC=''
fi

# ---- Logging helpers -------------------------------------------------------
info()    { echo -e "${CYAN}[INFO]${NC}  $*"; }
ok()      { echo -e "${GREEN}[ OK ]${NC}  $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
fail()    { echo -e "${RED}[FAIL]${NC}  $*" >&2; }
step()    { echo -e "${BLUE}[ -> ]${NC}  $*"; }
die()     { fail "$*"; exit 1; }
header()  { echo -e "\n${BOLD}── $* ──────────────────────────────────────${NC}"; }

# ----------------------------------------------------------------------------
# Result model
# Each check appends one record to RESULTS using a unit-separator delimiter.
# Fields: id | category | title | status | severity | observed | expected | remediation
#   status   : ok | warn | fail | skip
#   severity : info | low | high   (high = blocks install)
# ----------------------------------------------------------------------------
US=$'\x1f'                       # field separator (unlikely to appear in text)
declare -a RESULTS=()
COUNT_OK=0; COUNT_WARN=0; COUNT_FAIL=0; COUNT_SKIP=0

add_result() {
    local id="$1" category="$2" title="$3" status="$4" severity="${5:-info}"
    local observed="${6:-}" expected="${7:-}" remediation="${8:-}"
    RESULTS+=("${id}${US}${category}${US}${title}${US}${status}${US}${severity}${US}${observed}${US}${expected}${US}${remediation}")
    case "$status" in
        ok)   COUNT_OK=$((COUNT_OK+1));   ok   "${title} — ${observed:-OK}" ;;
        warn) COUNT_WARN=$((COUNT_WARN+1)); warn "${title} — ${observed:-see below}"
              [[ -n "$remediation" ]] && echo -e "       ${DIM}fix:${NC} ${remediation}" ;;
        fail) COUNT_FAIL=$((COUNT_FAIL+1)); fail "${title} — ${observed:-FAILED}"
              [[ -n "$remediation" ]] && echo -e "       ${DIM}fix:${NC} ${remediation}" ;;
        skip) COUNT_SKIP=$((COUNT_SKIP+1)); step "${title} — skipped (${observed:-n/a})" ;;
    esac
}

# Overall verdict from accumulated counts.
#   FAIL                -> any high-severity failure
#   PASS_WITH_WARNINGS  -> warnings but no failures
#   PASS                -> clean
compute_verdict() {
    if [[ $COUNT_FAIL -gt 0 ]]; then echo "FAIL"
    elif [[ $COUNT_WARN -gt 0 ]]; then echo "PASS_WITH_WARNINGS"
    else echo "PASS"; fi
}

# ---- JSON helpers (no jq dependency) ---------------------------------------
json_escape() {
    local s="$1"
    s="${s//\\/\\\\}"; s="${s//\"/\\\"}"
    s="${s//$'\t'/\\t}"; s="${s//$'\r'/}"; s="${s//$'\n'/\\n}"
    printf '%s' "$s"
}

# Write the JSON report to $1. Reads RESULTS and host facts populated by os.sh.
write_json_report() {
    local out="$1"
    local verdict; verdict="$(compute_verdict)"
    {
        printf '{\n'
        printf '  "tool": "nbe-validator",\n'
        printf '  "version": "%s",\n' "$(json_escape "${NBE_TOOL_VERSION:-}")"
        printf '  "generated": "%s",\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        printf '  "tier": "%s",\n' "$(json_escape "${TIER:-tiered}")"
        printf '  "host": {\n'
        printf '    "hostname": "%s",\n' "$(json_escape "${HOST_HOSTNAME:-}")"
        printf '    "fqdn": "%s",\n'     "$(json_escape "${HOST_FQDN:-}")"
        printf '    "os": "%s",\n'       "$(json_escape "${HOST_OS:-}")"
        printf '    "os_family": "%s",\n' "$(json_escape "${OS_FAMILY:-}")"
        printf '    "version_id": "%s",\n' "$(json_escape "${HOST_VERSION_ID:-}")"
        printf '    "kernel": "%s",\n'   "$(json_escape "${HOST_KERNEL:-}")"
        printf '    "arch": "%s"\n'      "$(json_escape "${HOST_ARCH:-}")"
        printf '  },\n'
        printf '  "verdict": "%s",\n' "$verdict"
        printf '  "summary": { "ok": %d, "warn": %d, "fail": %d, "skip": %d },\n' \
               "$COUNT_OK" "$COUNT_WARN" "$COUNT_FAIL" "$COUNT_SKIP"
        printf '  "checks": [\n'
        local i n=${#RESULTS[@]}
        for ((i=0; i<n; i++)); do
            IFS="$US" read -r id category title status severity observed expected remediation <<< "${RESULTS[$i]}"
            printf '    {\n'
            printf '      "id": "%s",\n' "$(json_escape "$id")"
            printf '      "category": "%s",\n' "$(json_escape "$category")"
            printf '      "title": "%s",\n' "$(json_escape "$title")"
            printf '      "status": "%s",\n' "$(json_escape "$status")"
            printf '      "severity": "%s",\n' "$(json_escape "$severity")"
            printf '      "observed": "%s",\n' "$(json_escape "$observed")"
            printf '      "expected": "%s",\n' "$(json_escape "$expected")"
            printf '      "remediation": "%s"\n' "$(json_escape "$remediation")"
            if [[ $i -lt $((n-1)) ]]; then printf '    },\n'; else printf '    }\n'; fi
        done
        printf '  ]\n'
        printf '}\n'
    } > "$out"
}

# ---- Misc helpers ----------------------------------------------------------
# confirm "prompt" -> returns 0 if yes. Honors global ASSUME_YES.
confirm() {
    local prompt="${1:-Proceed?}"
    if [[ "${ASSUME_YES:-false}" == "true" ]]; then return 0; fi
    local answer
    read -r -p "$(echo -e "${BOLD}${prompt}${NC} [y/N] ")" answer
    [[ "$answer" =~ ^[yY]([eE][sS])?$ ]]
}

require_root() {
    [[ $EUID -eq 0 ]]
}

have() { command -v "$1" >/dev/null 2>&1; }
