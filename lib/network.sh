#!/usr/bin/env bash
# ----------------------------------------------------------------------------
# network.sh — static IP, hostname resolution, outbound endpoint reachability,
# and local availability of the ports NetBox needs to bind. READ-ONLY.
# ----------------------------------------------------------------------------

check_network() {
    header "Network"

    # --- Hostname resolvable -------------------------------------------------
    if getent hosts "$HOST_HOSTNAME" >/dev/null 2>&1 || [[ "$HOST_FQDN" == *.* ]]; then
        add_result "net.hostname" "network" "Hostname resolvable" "ok" "low" \
            "${HOST_FQDN}" "resolvable FQDN or short name" ""
    else
        add_result "net.hostname" "network" "Hostname resolvable" "warn" "low" \
            "${HOST_HOSTNAME} (not resolvable)" "resolvable hostname/FQDN" \
            "Ensure the hostname resolves (add it to /etc/hosts or DNS). The hostname cannot change after install."
    fi

    # --- Static IP (warn if the primary address came from DHCP) -------------
    local dhcp="unknown"
    if have nmcli; then
        if nmcli -t -f IP4.DHCP4 device show 2>/dev/null | grep -q .; then dhcp="yes"; else dhcp="no"; fi
    elif have networkctl; then
        if networkctl status 2>/dev/null | grep -qi 'DHCP'; then dhcp="yes"; else dhcp="no"; fi
    elif compgen -G "/var/lib/dhcp/*.leases" >/dev/null 2>&1; then
        dhcp="yes"
    fi
    case "$dhcp" in
        no)  add_result "net.staticip" "network" "Static IP" "ok" "low" "no DHCP lease detected" "static IP" "" ;;
        yes) add_result "net.staticip" "network" "Static IP" "warn" "low" "DHCP appears to be in use" "static IP" \
                "Assign a static IP. The IP address cannot change after installation." ;;
        *)   add_result "net.staticip" "network" "Static IP" "skip" "info" "could not determine" "static IP" \
                "Verify manually that this host uses a static IP." ;;
    esac

    # --- Outbound endpoint reachability (TCP 443) ---------------------------
    local ep reachable_fail=0
    for ep in "${NETBOX_ENDPOINTS[@]}"; do
        if _tcp_reachable "$ep" 443; then
            add_result "net.out.${ep}" "network" "Outbound to ${ep}:443" "ok" "low" "reachable" "reachable" ""
        else
            reachable_fail=$((reachable_fail+1))
            add_result "net.out.${ep}" "network" "Outbound to ${ep}:443" "warn" "low" "unreachable" "reachable" \
                "Allow outbound HTTPS to ${ep} (directly or via proxy) — required for install, licensing and image pulls."
        fi
    done

    # --- Local port availability (must not already be bound) ----------------
    local p
    for p in "${PORTS_MUST_BE_FREE[@]}"; do
        if _port_in_use "$p"; then
            add_result "net.port.${p}" "network" "Port ${p} free" "warn" "low" "already in use" "free (not listening)" \
                "Another service is listening on port ${p}; NetBox needs it. Stop the conflicting service."
        else
            add_result "net.port.${p}" "network" "Port ${p} free" "ok" "info" "free" "free" ""
        fi
    done
}

# _tcp_reachable host port — honors HTTPS_PROXY via curl when present.
_tcp_reachable() {
    local host="$1" port="$2"
    if have curl; then
        curl -sS --connect-timeout 8 -o /dev/null "https://${host}:${port}" >/dev/null 2>&1 && return 0
        # curl returns non-zero on TLS/HTTP errors even when TCP connected;
        # treat "connected" as reachable by checking exit code != 7 (couldn't connect).
        local rc=$?; [[ $rc -ne 7 && $rc -ne 6 ]] && return 0
        return 1
    fi
    # Fallback: bash /dev/tcp
    timeout 8 bash -c ">/dev/tcp/${host}/${port}" 2>/dev/null
}

# _port_in_use port — true if something is LISTENing on it.
_port_in_use() {
    local port="$1"
    if have ss; then
        ss -ltn 2>/dev/null | awk '{print $4}' | grep -Eq "[:.]${port}\$"
    elif have netstat; then
        netstat -ltn 2>/dev/null | awk '{print $4}' | grep -Eq "[:.]${port}\$"
    else
        return 1
    fi
}
