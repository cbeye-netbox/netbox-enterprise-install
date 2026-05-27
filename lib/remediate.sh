#!/usr/bin/env bash
# ----------------------------------------------------------------------------
# remediate.sh — applies (or, in plan mode, prints) the system-config changes
# needed for NetBox Enterprise. Touches ONLY software/config: swap, kernel
# modules, sysctl, kernel headers, SELinux (RHEL), firewall. Never touches
# hardware. Family-aware and idempotent.
#
# Every change goes through run(): in DRY_RUN it is printed, otherwise executed.
# ----------------------------------------------------------------------------

DRY_RUN="${DRY_RUN:-false}"

run() {
    if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "       ${DIM}\$ $*${NC}"
    else
        step "$*"
        eval "$@"
    fi
}

# Print a file we would write (plan) or actually write it (apply).
write_file() {
    local path="$1" content="$2"
    if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "       ${DIM}write ${path}:${NC}"
        sed 's/^/         | /' <<< "$content"
    else
        step "writing ${path}"
        printf '%s\n' "$content" > "$path"
    fi
}

# ---------------------------------------------------------------------------
remediate_swap() {
    if swap_is_on || grep -qP '^\s*[^#].*\bswap\b' /etc/fstab 2>/dev/null; then
        header "Swap"
        run "swapoff -a"
        run "sed -i -E 's|^([^#].*\\\bswap\\\b.*)\$|# \\\1|' /etc/fstab"
    fi
}

remediate_modules() {
    header "Kernel modules"
    local mod
    for mod in "${KERNEL_MODULES[@]}"; do
        module_loaded "$mod" || run "modprobe ${mod}"
    done
    write_file "$MODULES_LOAD_FILE" "$(printf '%s\n' "${KERNEL_MODULES[@]}")"
}

remediate_sysctl() {
    header "sysctl"
    local body="" kv
    for kv in "${SYSCTL_PARAMS[@]}"; do body+="${kv%%=*} = ${kv#*=}"$'\n'; done
    write_file "$SYSCTL_CONF_FILE" "${body%$'\n'}"
    run "sysctl --system >/dev/null"
}

remediate_headers() {
    kernel_headers_installed && return 0
    local pkg; pkg="$(kernel_headers_pkg)"; [[ -z "$pkg" ]] && return 0
    header "Kernel headers"
    case "$OS_FAMILY" in
        debian) run "DEBIAN_FRONTEND=noninteractive ${PKG_MGR} install -y ${pkg}" ;;
        rhel)   run "${PKG_MGR} install -y ${pkg}" ;;
        suse)   run "${PKG_MGR} install -y ${pkg}" ;;
    esac
}

remediate_selinux() {
    [[ "$OS_FAMILY" == "rhel" ]] || return 0
    [[ "$(selinux_mode)" == "Enforcing" ]] || return 0
    header "SELinux (set permissive for installation)"
    run "setenforce 0"
    run "sed -i 's/^SELINUX=enforcing/SELINUX=permissive/' /etc/selinux/config"
}

# ---- Firewall (per-family) -------------------------------------------------
# Builds the full required port lists from requirements.conf.
remediate_firewall() {
    header "Firewall"
    local backend="${FW_BACKEND:-$(detect_firewall)}"

    case "$OS_FAMILY" in
        rhel|suse) _fw_firewalld ;;
        debian)
            if [[ "$backend" == "iptables" ]]; then _fw_iptables; else _fw_ufw; fi ;;
        *) warn "Unknown OS family — skipping firewall configuration" ;;
    esac
}

_fw_firewalld() {
    have firewall-cmd || run "${PKG_MGR} install -y firewalld"
    run "systemctl enable --now firewalld"
    local p
    for p in "${TCP_PORTS[@]}" "${FIREWALLD_EXTRA_PORTS[@]}"; do
        run "firewall-cmd --permanent --add-port=${p}/tcp"
    done
    for p in "${TCP_PORT_RANGES[@]}"; do
        run "firewall-cmd --permanent --add-port=${p/:/-}/tcp"
    done
    for p in "${UDP_PORTS[@]}"; do
        run "firewall-cmd --permanent --add-port=${p}/udp"
    done
    run "firewall-cmd --permanent --add-masquerade"
    run "firewall-cmd --reload"
}

_fw_ufw() {
    have ufw || run "${PKG_MGR} install -y ufw"
    # Allow SSH BEFORE enabling, so we never lock out a remote session.
    run "ufw allow ${SSH_PORT}/tcp"
    run "ufw --force enable"
    local joined
    joined="$(IFS=,; echo "${TCP_PORTS[*]}")"
    run "ufw allow ${joined}/tcp"
    local p
    for p in "${TCP_PORT_RANGES[@]}"; do run "ufw allow ${p}/tcp"; done
    for p in "${UDP_PORTS[@]}"; do run "ufw allow ${p}/udp"; done
    run "ufw route allow from ${POD_CIDR_A} to ${POD_CIDR_B}"
    run "ufw route allow from ${POD_CIDR_B} to ${POD_CIDR_A}"
    run "ufw reload"
}

_fw_iptables() {
    run "DEBIAN_FRONTEND=noninteractive ${PKG_MGR} install -y iptables-persistent"
    local joined; joined="$(IFS=,; echo "${TCP_PORTS[*]}")"
    run "iptables -C INPUT -p tcp -m multiport --dports ${joined} -j ACCEPT 2>/dev/null || iptables -I INPUT -p tcp -m multiport --dports ${joined} -j ACCEPT"
    local p
    for p in "${TCP_PORT_RANGES[@]}"; do
        run "iptables -C INPUT -p tcp --dport ${p} -j ACCEPT 2>/dev/null || iptables -I INPUT -p tcp --dport ${p} -j ACCEPT"
    done
    for p in "${UDP_PORTS[@]}"; do
        run "iptables -C INPUT -p udp --dport ${p} -j ACCEPT 2>/dev/null || iptables -I INPUT -p udp --dport ${p} -j ACCEPT"
    done
    run "iptables -C FORWARD -s ${POD_CIDR_A} -d ${POD_CIDR_B} -j ACCEPT 2>/dev/null || iptables -I FORWARD -s ${POD_CIDR_A} -d ${POD_CIDR_B} -j ACCEPT"
    run "iptables -C FORWARD -s ${POD_CIDR_B} -d ${POD_CIDR_A} -j ACCEPT 2>/dev/null || iptables -I FORWARD -s ${POD_CIDR_B} -d ${POD_CIDR_A} -j ACCEPT"
    run "netfilter-persistent save"
}

# ---- Orchestration ---------------------------------------------------------
# Runs every remediation step in the current DRY_RUN mode.
remediate_all() {
    remediate_swap
    remediate_modules
    remediate_sysctl
    remediate_headers
    remediate_selinux
    remediate_firewall
}
