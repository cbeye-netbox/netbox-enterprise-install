#!/usr/bin/env bash
# ----------------------------------------------------------------------------
# install.sh — downloads and runs the NetBox Enterprise installer.
# Guarded: re-validates first and refuses to install on a FAIL verdict.
# Requires --token and --license. Supports proxy / private-CA passthrough.
# ----------------------------------------------------------------------------

run_install() {
    header "NetBox Enterprise installation"

    if ! require_root; then
        die "Installation must run as root (use sudo)."
    fi

    # --- Pre-flight: validate the host first --------------------------------
    info "Re-validating the host before installation..."
    detect_os
    check_os; check_hardware; check_network; check_system; check_firewall
    local verdict; verdict="$(compute_verdict)"
    echo ""
    case "$verdict" in
        FAIL)
            die "Host verdict is FAIL — refusing to install. Run './nbe-validator.sh check' and fix the failures (or './nbe-validator.sh apply')." ;;
        PASS_WITH_WARNINGS)
            warn "Host verdict is PASS_WITH_WARNINGS."
            confirm "Continue installing despite warnings?" || die "Aborted by user." ;;
        PASS)
            ok "Host verdict is PASS." ;;
    esac

    # --- Required inputs ----------------------------------------------------
    [[ -n "${INSTALL_TOKEN:-}" ]]   || die "Missing --token <auth-token> (from NetBox Labs)."
    [[ -n "${INSTALL_LICENSE:-}" ]] || die "Missing --license <license.yaml>."
    [[ -f "${INSTALL_LICENSE}" ]]   || die "License file not found: ${INSTALL_LICENSE}"

    # --- Proxy passthrough --------------------------------------------------
    local curl_proxy="" install_proxy=()
    if [[ -n "${HTTPS_PROXY_OPT:-}" ]]; then
        curl_proxy="--proxy ${HTTPS_PROXY_OPT}"
        install_proxy+=(--https-proxy "${HTTPS_PROXY_OPT}")
    fi
    [[ -n "${HTTP_PROXY_OPT:-}" ]]  && install_proxy+=(--http-proxy "${HTTP_PROXY_OPT}")
    [[ -n "${PRIVATE_CA_OPT:-}" ]]  && install_proxy+=(--private-ca "${PRIVATE_CA_OPT}")

    # --- Download -----------------------------------------------------------
    header "Downloading installer (~300 MB)"
    step "curl ${INSTALLER_URL} -> ${INSTALLER_TARBALL}"
    # shellcheck disable=SC2086
    curl -f ${curl_proxy} "${INSTALLER_URL}" \
        -H "Authorization: ${INSTALL_TOKEN}" \
        -o "${INSTALLER_TARBALL}" \
        || die "Download failed — check the token and outbound access to app.enterprise.netboxlabs.com."

    if ! file "${INSTALLER_TARBALL}" | grep -qi "gzip compressed"; then
        die "Downloaded file is not a gzip archive — the token may be invalid. Got: $(file "${INSTALLER_TARBALL}")"
    fi
    ok "Installer downloaded and verified."

    # --- Extract & install --------------------------------------------------
    header "Extracting"
    run_or_die tar -xzf "${INSTALLER_TARBALL}"
    [[ -x "./${INSTALL_BIN_NAME}" ]] || die "Installer binary ./${INSTALL_BIN_NAME} not found after extraction."

    header "Running installer"
    info "This typically takes 30–45 minutes (5–10 min cluster, 10–15 min app init)."
    ./"${INSTALL_BIN_NAME}" install --license "${INSTALL_LICENSE}" "${install_proxy[@]}" \
        || die "Installer exited with an error."

    echo ""
    ok "Installer finished."
    echo -e "  ${BOLD}Next:${NC} open the Admin Console to configure NetBox Enterprise:"
    echo -e "        ${CYAN}http://${HOST_FQDN}:${ADMIN_CONSOLE_PORT}${NC}"
    echo -e "  Use the Admin Console password you set during install."
}

run_or_die() { "$@" || die "Command failed: $*"; }
