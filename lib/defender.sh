#!/usr/bin/env bash
# ----------------------------------------------------------------------------
# defender.sh — detect Microsoft Defender for Endpoint (mdatp) on the host.
#
# Defender's real-time AV daemon (wdavdaemon) scans and locks file I/O. On a
# NetBox Enterprise host that interferes with the embedded Kubernetes cluster
# (containerd image unpacking, etcd, kubelet) and can stall or corrupt the
# install. So: if Defender is actively RUNNING we FAIL; installed-but-stopped
# WARNs; not present is OK. Applies to the debian (Ubuntu) and rhel families.
# This is a read-only probe — 'apply' never stops a security agent on its own.
# ----------------------------------------------------------------------------

# Is the mdatp systemd unit active?
defender_service_active() {
    have systemctl && systemctl is-active --quiet "${DEFENDER_SERVICE}" 2>/dev/null
}

# Echo any Defender daemon processes currently running (one per line).
defender_running_processes() {
    local p
    for p in "${DEFENDER_PROCESSES[@]}"; do
        pgrep -x "$p" >/dev/null 2>&1 && echo "$p"
    done
}

# Is the mdatp package / CLI present at all (even if stopped)?
defender_installed() {
    have "${DEFENDER_CLI}" && return 0
    case "$OS_FAMILY" in
        debian) dpkg -s "${DEFENDER_PACKAGE}" >/dev/null 2>&1 ;;
        rhel)   rpm -q "${DEFENDER_PACKAGE}" >/dev/null 2>&1 ;;
        *)      return 1 ;;
    esac
}

check_defender() {
    header "Endpoint security (Microsoft Defender)"

    local running; running="$(defender_running_processes | tr '\n' ' ')"
    running="${running% }"

    # Running = blocking. Either a live daemon process or the active unit counts.
    if [[ -n "$running" ]] || defender_service_active; then
        local observed
        if [[ -n "$running" ]]; then observed="running: ${running}"; else observed="mdatp.service active"; fi
        [[ -n "$running" ]] && defender_service_active && observed="${observed} (mdatp.service active)"
        add_result "sec.defender" "security" "Microsoft Defender not running" "fail" "high" \
            "$observed" "mdatp / wdavdaemon stopped during install" \
            "Stop and disable Defender for the install: 'systemctl stop mdatp && systemctl disable mdatp'. Re-enable it afterwards, ideally with containerd/kubelet data-dir exclusions so real-time scanning does not interfere."
        return
    fi

    if defender_installed; then
        add_result "sec.defender" "security" "Microsoft Defender not running" "warn" "low" \
            "mdatp installed but not running" "not running (ideally not installed)" \
            "Defender is installed but currently stopped. Keep it stopped during the install, or add containerd/kubelet data-dir exclusions so its real-time scanning does not interfere."
        return
    fi

    add_result "sec.defender" "security" "Microsoft Defender not running" "ok" "info" \
        "not detected" "not running" ""
}
