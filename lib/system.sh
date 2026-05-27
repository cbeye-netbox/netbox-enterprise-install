#!/usr/bin/env bash
# ----------------------------------------------------------------------------
# system.sh — read-only checks for the system-config items that `apply` can
# remediate: swap, kernel modules, sysctl, kernel headers, SELinux (RHEL).
# The matching mutations live in remediate.sh.
# ----------------------------------------------------------------------------

# --- individual state probes (also used by remediate.sh) --------------------
swap_is_on()        { swapon --show 2>/dev/null | grep -q .; }
module_loaded()     { lsmod 2>/dev/null | grep -q "^$1\b"; }
sysctl_value()      { sysctl -n "$1" 2>/dev/null || echo ""; }
selinux_mode()      { command -v getenforce >/dev/null 2>&1 && getenforce 2>/dev/null || echo "n/a"; }

kernel_headers_pkg() {
    case "$OS_FAMILY" in
        debian) echo "linux-headers-$(uname -r)" ;;
        rhel)   echo "kernel-devel-$(uname -r)" ;;
        suse)   echo "kernel-default-devel" ;;
        *)      echo "" ;;
    esac
}
kernel_headers_installed() {
    case "$OS_FAMILY" in
        debian) dpkg -s "linux-headers-$(uname -r)" >/dev/null 2>&1 ;;
        rhel)   rpm -q "kernel-devel-$(uname -r)" >/dev/null 2>&1 ;;
        suse)   rpm -q kernel-default-devel >/dev/null 2>&1 ;;
        *)      return 0 ;;
    esac
}

check_system() {
    header "System configuration"

    # --- Swap ---------------------------------------------------------------
    if swap_is_on; then
        add_result "sys.swap" "system" "Swap disabled" "fail" "high" "swap is ON" "swap off" \
            "Run 'swapoff -a' and comment swap lines in /etc/fstab (the 'apply' command does this)."
    else
        add_result "sys.swap" "system" "Swap disabled" "ok" "high" "swap off" "swap off" ""
    fi

    # --- Kernel modules -----------------------------------------------------
    local mod missing=()
    for mod in "${KERNEL_MODULES[@]}"; do
        module_loaded "$mod" || missing+=("$mod")
    done
    if [[ ${#missing[@]} -eq 0 ]]; then
        add_result "sys.modules" "system" "Kernel modules loaded" "ok" "high" "all ${#KERNEL_MODULES[@]} loaded" "all loaded" ""
    else
        add_result "sys.modules" "system" "Kernel modules loaded" "fail" "high" \
            "missing: ${missing[*]}" "all of: ${KERNEL_MODULES[*]}" \
            "Load with modprobe and persist via ${MODULES_LOAD_FILE} (the 'apply' command does this)."
    fi

    # --- sysctl -------------------------------------------------------------
    local kv key want got bad=()
    for kv in "${SYSCTL_PARAMS[@]}"; do
        key="${kv%%=*}"; want="${kv#*=}"; got="$(sysctl_value "$key")"
        [[ "$got" == "$want" ]] || bad+=("${key}=${got:-unset}")
    done
    if [[ ${#bad[@]} -eq 0 ]]; then
        add_result "sys.sysctl" "system" "sysctl parameters" "ok" "high" "all set" "all = expected" ""
    else
        add_result "sys.sysctl" "system" "sysctl parameters" "fail" "high" \
            "wrong: ${bad[*]}" "${SYSCTL_PARAMS[*]}" \
            "Write ${SYSCTL_CONF_FILE} and run 'sysctl --system' (the 'apply' command does this)."
    fi

    # --- Kernel headers -----------------------------------------------------
    local pkg; pkg="$(kernel_headers_pkg)"
    if [[ -z "$pkg" ]]; then
        add_result "sys.headers" "system" "Kernel headers" "skip" "info" "n/a for this family" "" ""
    elif kernel_headers_installed; then
        add_result "sys.headers" "system" "Kernel headers" "ok" "low" "$pkg installed" "$pkg" ""
    else
        add_result "sys.headers" "system" "Kernel headers" "warn" "low" "$pkg not installed" "$pkg" \
            "Install matching kernel headers (the 'apply' command does this). Needed only if modules must be built."
    fi

    # --- SELinux (RHEL family only) -----------------------------------------
    if [[ "$OS_FAMILY" == "rhel" ]]; then
        local mode; mode="$(selinux_mode)"
        case "$mode" in
            Enforcing)
                add_result "sys.selinux" "system" "SELinux mode" "fail" "high" "Enforcing" "Permissive (during install)" \
                    "Set SELinux to permissive for installation: 'setenforce 0' + edit /etc/selinux/config (the 'apply' command does this). Re-enable after install." ;;
            Permissive|Disabled)
                add_result "sys.selinux" "system" "SELinux mode" "ok" "low" "$mode" "Permissive during install" "" ;;
            *)
                add_result "sys.selinux" "system" "SELinux mode" "skip" "info" "getenforce unavailable" "Permissive during install" "" ;;
        esac
    fi
}
