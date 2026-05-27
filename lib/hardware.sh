#!/usr/bin/env bash
# ----------------------------------------------------------------------------
# hardware.sh — CPU / RAM / disk / storage-type checks. READ-ONLY: this module
# never changes the machine; hardware shortfalls can only be reported.
# Tiered verdict: below MIN -> FAIL, MIN..REC -> WARN, >= REC -> OK.
# ----------------------------------------------------------------------------

# _tier_check <title> <id> <observed_num> <min> <rec> <unit>
# Emits an add_result with tiered status and matching remediation.
_tier_check() {
    local title="$1" id="$2" val="$3" min="$4" rec="$5" unit="$6"
    if   (( val < min )); then
        add_result "$id" "hardware" "$title" "fail" "high" \
            "${val}${unit}" ">= ${min}${unit} (min), ${rec}${unit} recommended" \
            "Increase ${title} to at least ${min}${unit} (recommended ${rec}${unit}). Cannot be auto-fixed."
    elif (( val < rec )); then
        add_result "$id" "hardware" "$title" "warn" "low" \
            "${val}${unit}" ">= ${rec}${unit} recommended" \
            "Meets the non-production minimum but is below the production recommendation of ${rec}${unit}."
    else
        add_result "$id" "hardware" "$title" "ok" "info" \
            "${val}${unit}" ">= ${rec}${unit}" ""
    fi
}

check_hardware() {
    header "Hardware (read-only — never modified)"

    # CPU
    local cpus; cpus="$(nproc 2>/dev/null || echo 0)"
    _tier_check "CPU cores" "hw.cpu" "$cpus" "$MIN_VCPU" "$REC_VCPU" " vCPU"

    # RAM — MemTotal is kB; round to nearest GB so a "16 GB" box reporting
    # ~15.6 GB usable is not unfairly failed.
    local kb gb
    kb="$(awk '/MemTotal/{print $2}' /proc/meminfo 2>/dev/null || echo 0)"
    gb=$(( (kb + 524288) / 1048576 ))
    _tier_check "Memory" "hw.ram" "$gb" "$MIN_RAM_GB" "$REC_RAM_GB" " GB"

    # Disk free at DISK_PATH (falls back to nearest existing parent)
    local path="$DISK_PATH"
    while [[ ! -d "$path" && "$path" != "/" ]]; do path="$(dirname "$path")"; done
    local disk_gb
    disk_gb="$(df -BG --output=avail "$path" 2>/dev/null | tail -1 | tr -dc '0-9')"
    disk_gb="${disk_gb:-0}"
    _tier_check "Free disk at ${DISK_PATH}" "hw.disk" "$disk_gb" "$MIN_DISK_GB" "$REC_DISK_GB" " GB"

    # Storage type (SSD/NVMe recommended) — informational only
    if have lsblk; then
        local src rota
        # -T resolves the mount backing an arbitrary path (e.g. /var/lib on /).
        src="$(findmnt -no SOURCE -T "$path" 2>/dev/null)"
        rota="$(lsblk -no rota "$src" 2>/dev/null | head -1 | tr -dc '0-9')"
        if [[ "$rota" == "0" ]]; then
            add_result "hw.storage" "hardware" "Storage type" "ok" "info" "SSD/NVMe (non-rotational)" "SSD/NVMe recommended" ""
        elif [[ "$rota" == "1" ]]; then
            add_result "hw.storage" "hardware" "Storage type" "warn" "low" "rotational (HDD)" "SSD/NVMe recommended" \
                "SSD or NVMe storage is recommended for database performance."
        else
            add_result "hw.storage" "hardware" "Storage type" "skip" "info" "could not determine" "SSD/NVMe recommended" ""
        fi
    else
        add_result "hw.storage" "hardware" "Storage type" "skip" "info" "lsblk not available" "SSD/NVMe recommended" ""
    fi
}

# Used by remediate/install to gate on hardware: returns 1 if below minimum.
hardware_below_minimum() {
    local cpus kb gb path disk_gb
    cpus="$(nproc 2>/dev/null || echo 0)"
    kb="$(awk '/MemTotal/{print $2}' /proc/meminfo 2>/dev/null || echo 0)"
    gb=$(( (kb + 524288) / 1048576 ))
    path="$DISK_PATH"; while [[ ! -d "$path" && "$path" != "/" ]]; do path="$(dirname "$path")"; done
    disk_gb="$(df -BG --output=avail "$path" 2>/dev/null | tail -1 | tr -dc '0-9')"; disk_gb="${disk_gb:-0}"
    (( cpus < MIN_VCPU || gb < MIN_RAM_GB || disk_gb < MIN_DISK_GB ))
}
