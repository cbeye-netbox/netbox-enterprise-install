#!/usr/bin/env bash
# ============================================================================
#  nbe-validator.sh — NetBox Enterprise POC readiness validator
#
#  Usage:  sudo ./nbe-validator.sh <command> [flags]
#
#  Commands:
#    check     (default) Read-only readiness report + JSON. Changes nothing.
#    plan                Show exactly what 'apply' would change. Changes nothing.
#    apply               Apply system-config remediation (swap/modules/sysctl/
#                        firewall/SELinux). Never touches hardware.
#    install             Download & run the NetBox Enterprise installer.
#
#  Flags:
#    --tier prod|min     Verdict strictness display (default: tiered).
#    --json <path>       Where to write the JSON report (default: reports/...).
#    --yes               Non-interactive (assume yes to prompts).
#    --token <t>         Auth token for install.
#    --license <file>    License YAML for install.
#    --http-proxy <url>  Proxy passthrough for install.
#    --https-proxy <url> Proxy passthrough for install.
#    --private-ca <file> CA bundle for MITM proxies (install).
#    -h, --help          This help.
#
#  Exit codes:  0 = PASS   1 = FAIL   2 = PASS_WITH_WARNINGS
# ============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="${SCRIPT_DIR}/lib"

# Source order matters: config first, then helpers, then modules.
# shellcheck source=/dev/null
for f in requirements.conf common.sh logo.sh os.sh hardware.sh network.sh \
         system.sh firewall.sh remediate.sh install.sh; do
    . "${LIB}/${f}"
done

# ---- Defaults / flag state -------------------------------------------------
COMMAND="check"
TIER="tiered"
ASSUME_YES="false"
JSON_PATH=""
INSTALL_TOKEN=""; INSTALL_LICENSE=""
HTTP_PROXY_OPT=""; HTTPS_PROXY_OPT=""; PRIVATE_CA_OPT=""

# Print the banner comment block (between the two "# ====" borders) as help.
usage() { sed -n '/^# ===/,/^# ===/p' "${BASH_SOURCE[0]}" | sed 's/^# \?//'; }

parse_args() {
    [[ $# -gt 0 && "$1" != -* ]] && { COMMAND="$1"; shift; }
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --tier)        TIER="$2"; shift 2 ;;
            --json)        JSON_PATH="$2"; shift 2 ;;
            --yes|-y)      ASSUME_YES="true"; shift ;;
            --token)       INSTALL_TOKEN="$2"; shift 2 ;;
            --license)     INSTALL_LICENSE="$2"; shift 2 ;;
            --http-proxy)  HTTP_PROXY_OPT="$2"; shift 2 ;;
            --https-proxy) HTTPS_PROXY_OPT="$2"; shift 2 ;;
            --private-ca)  PRIVATE_CA_OPT="$2"; shift 2 ;;
            -h|--help)     usage; exit 0 ;;
            *) die "Unknown argument: $1 (try --help)" ;;
        esac
    done
}

# ---- Final on-screen summary ----------------------------------------------
print_summary() {
    local verdict="$1"
    echo ""
    echo -e "${BOLD}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}║        NetBox Enterprise — Readiness Summary           ║${NC}"
    echo -e "${BOLD}╚════════════════════════════════════════════════════════╝${NC}"
    echo -e "  Host    : ${HOST_FQDN}  (${HOST_OS})"
    echo -e "  Results : ${GREEN}${COUNT_OK} OK${NC}  ${YELLOW}${COUNT_WARN} WARN${NC}  ${RED}${COUNT_FAIL} FAIL${NC}  ${DIM}${COUNT_SKIP} skip${NC}"

    # List anything not OK so the action items are obvious.
    if [[ $COUNT_FAIL -gt 0 || $COUNT_WARN -gt 0 ]]; then
        echo -e "\n  ${BOLD}Action items:${NC}"
        local r; IFS="$US"
        for r in "${RESULTS[@]}"; do
            read -r id cat title status sev observed expected remediation <<< "$r"
            case "$status" in
                fail) echo -e "   ${RED}✗${NC} ${title}: ${observed}\n     ${DIM}→ ${remediation}${NC}" ;;
                warn) echo -e "   ${YELLOW}!${NC} ${title}: ${observed}\n     ${DIM}→ ${remediation}${NC}" ;;
            esac
        done
        unset IFS
    fi

    echo ""
    case "$verdict" in
        PASS)               echo -e "  ${GREEN}${BOLD}VERDICT: PASS${NC} — this host meets the NetBox Enterprise requirements." ;;
        PASS_WITH_WARNINGS) echo -e "  ${YELLOW}${BOLD}VERDICT: PASS WITH WARNINGS${NC} — usable, but review the items above." ;;
        FAIL)               echo -e "  ${RED}${BOLD}VERDICT: FAIL${NC} — fix the items above before installing." ;;
    esac
}

run_all_checks() {
    detect_os
    check_os
    check_hardware
    check_network
    check_system
    check_firewall
}

write_report() {
    local path="${JSON_PATH}"
    if [[ -z "$path" ]]; then
        mkdir -p "${SCRIPT_DIR}/reports" 2>/dev/null || true
        path="${SCRIPT_DIR}/reports/nbe-report-${HOST_HOSTNAME}-$(date +%Y%m%d-%H%M%S).json"
    fi
    write_json_report "$path"
    echo -e "\n  ${CYAN}JSON report written:${NC} ${path}"
    echo -e "  ${DIM}Send this file to NetBox Labs as proof of readiness.${NC}"
}

exit_for_verdict() {
    case "$1" in
        PASS) exit 0 ;;
        FAIL) exit 1 ;;
        *)    exit 2 ;;
    esac
}

# ---- Commands --------------------------------------------------------------
cmd_check() {
    run_all_checks
    local verdict; verdict="$(compute_verdict)"
    print_summary "$verdict"
    write_report
    exit_for_verdict "$verdict"
}

cmd_plan() {
    run_all_checks
    local verdict; verdict="$(compute_verdict)"
    print_summary "$verdict"
    echo -e "\n${BOLD}━━ DRY-RUN: changes 'apply' would make ━━━━━━━━━━━━━━━━━━━━${NC}"
    if hardware_below_minimum; then
        warn "Hardware is below the minimum — 'apply' would REFUSE to run. Hardware cannot be auto-fixed."
    fi
    DRY_RUN="true" remediate_all
    echo -e "\n  ${DIM}No changes were made. Run 'sudo ./nbe-validator.sh apply' to apply them.${NC}"
    exit_for_verdict "$verdict"
}

cmd_apply() {
    require_root || die "'apply' must run as root (use sudo)."
    run_all_checks
    if hardware_below_minimum; then
        print_summary "$(compute_verdict)"
        die "Hardware is below the minimum (CPU/RAM/disk). Refusing to change the system — fix hardware first."
    fi
    echo -e "\n${BOLD}'apply' will modify system configuration (swap, modules, sysctl, firewall$([[ "$OS_FAMILY" == rhel ]] && echo ", SELinux")).${NC}"
    confirm "Proceed with applying these changes?" || die "Aborted by user."
    DRY_RUN="false" remediate_all
    echo ""
    ok "Remediation complete. Re-validating..."
    # Reset counters/results for a clean re-check.
    RESULTS=(); COUNT_OK=0; COUNT_WARN=0; COUNT_FAIL=0; COUNT_SKIP=0
    run_all_checks
    local verdict; verdict="$(compute_verdict)"
    print_summary "$verdict"
    write_report
    echo -e "\n  ${YELLOW}A reboot is recommended${NC} so module/sysctl/swap changes fully settle: ${BOLD}sudo reboot${NC}"
    exit_for_verdict "$verdict"
}

cmd_install() { run_install; }

main() {
    parse_args "$@"
    print_logo
    case "$COMMAND" in
        check)   cmd_check ;;
        plan)    cmd_plan ;;
        apply)   cmd_apply ;;
        install) cmd_install ;;
        help)    usage ;;
        *) die "Unknown command: ${COMMAND} (try --help)" ;;
    esac
}

main "$@"
