#!/usr/bin/env bash
# ----------------------------------------------------------------------------
# firewall.sh — report firewall state and whether the required ports are open.
# Per-family tooling: debian -> ufw or iptables-persistent; rhel/suse -> firewalld.
# The rule-application logic lives in remediate.sh.
# ----------------------------------------------------------------------------

# Detect the active firewall backend: ufw | firewalld | iptables | none
detect_firewall() {
    if have firewall-cmd && firewall-cmd --state >/dev/null 2>&1; then
        echo "firewalld"
    elif have ufw && ufw status 2>/dev/null | grep -qi "Status: active"; then
        echo "ufw"
    elif have iptables && iptables -S 2>/dev/null | grep -q '.'; then
        # has rules beyond default? treat as iptables-managed
        if iptables -S 2>/dev/null | grep -qv -e '^-P' -e '^-N'; then echo "iptables"; else echo "none"; fi
    else
        echo "none"
    fi
}

# Critical ports to spot-check are open (the full set is opened by 'apply').
_critical_tcp_ports() { echo "80 443 6443 ${ADMIN_CONSOLE_PORT}"; }

# Does a single allow-spec cover <port>? Handles exact ("443"),
# comma lists ("22,80,443") and ranges ("30000:32767" / "30000-32767").
_spec_covers_port() {
    local spec="$1" port="$2" tok
    spec="${spec//-/:}"                       # normalize firewalld range dash to colon
    IFS=',' read -ra _toks <<< "$spec"
    for tok in "${_toks[@]}"; do
        if [[ "$tok" == *:* ]]; then
            (( port >= ${tok%%:*} && port <= ${tok##*:} )) && return 0
        elif [[ "$tok" == "$port" ]]; then
            return 0
        fi
    done
    return 1
}

# Emit every allowed TCP port-spec (one per line, "/tcp" stripped) for the backend.
_allowed_tcp_specs() {
    case "$1" in
        firewalld)
            { firewall-cmd --list-ports 2>/dev/null; firewall-cmd --list-all 2>/dev/null; } \
                | grep -oE '[0-9][0-9,:-]*/tcp' | sed 's:/tcp::' ;;
        ufw)
            ufw status 2>/dev/null | grep -oE '[0-9][0-9,:]*/tcp' | sed 's:/tcp::' ;;
        iptables)
            iptables -S 2>/dev/null | grep -- '-j ACCEPT' \
                | grep -oE -- '--dports? [0-9][0-9,:]*' | grep -oE '[0-9][0-9,:]*' ;;
    esac
}

# Is <port>/tcp allowed under the active backend?
_port_allowed() {
    local backend="$1" port="$2" spec
    [[ "$backend" == "none" ]] && return 0     # no firewall = nothing blocking
    while IFS= read -r spec; do
        [[ -z "$spec" ]] && continue
        _spec_covers_port "$spec" "$port" && return 0
    done < <(_allowed_tcp_specs "$backend")
    return 1
}

check_firewall() {
    header "Firewall"

    local backend; backend="$(detect_firewall)"
    FW_BACKEND="$backend"   # exported for remediate.sh

    if [[ "$backend" == "none" ]]; then
        add_result "fw.backend" "firewall" "Firewall backend" "warn" "low" \
            "no active firewall" "ufw / firewalld / iptables managing the required ports" \
            "No active firewall detected — required ports are reachable, but configuring one (the 'apply' command will) is recommended for persistence."
        return
    fi

    add_result "fw.backend" "firewall" "Firewall backend" "ok" "info" "$backend active" "managed firewall" ""

    local p missing=()
    for p in $(_critical_tcp_ports); do
        _port_allowed "$backend" "$p" || missing+=("$p")
    done

    if [[ ${#missing[@]} -eq 0 ]]; then
        add_result "fw.ports" "firewall" "Required ports open" "ok" "high" \
            "critical TCP ports allowed ($(_critical_tcp_ports))" "open" ""
    else
        add_result "fw.ports" "firewall" "Required ports open" "fail" "high" \
            "missing/closed: ${missing[*]}" "open: $(_critical_tcp_ports) (+ cluster ports)" \
            "Open the required NetBox/Kubernetes ports via ${backend} (the 'apply' command does this)."
    fi
}
