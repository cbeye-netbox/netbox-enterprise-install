#!/usr/bin/env bash
# ----------------------------------------------------------------------------
# install.sh — downloads and runs the NetBox Enterprise installer.
# Guarded: re-validates first and refuses to install on a FAIL verdict.
# Requires --token. The license is bundled inside the downloaded tarball and is
# auto-detected after extraction (override with --license). The installer then
# prompts interactively for an Admin Console password.
# Supports proxy / private-CA passthrough.
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
    [[ -n "${INSTALL_TOKEN:-}" ]] || die "Missing --token <auth-token> (from NetBox Labs)."
    # If --license was given explicitly, it must exist. Otherwise it is bundled
    # in the tarball and auto-detected after extraction (below).
    if [[ -n "${INSTALL_LICENSE:-}" && ! -f "${INSTALL_LICENSE}" ]]; then
        die "License file not found: ${INSTALL_LICENSE}"
    fi

    # --- Proxy passthrough --------------------------------------------------
    local curl_proxy="" install_proxy=()
    if [[ -n "${HTTPS_PROXY_OPT:-}" ]]; then
        curl_proxy="--proxy ${HTTPS_PROXY_OPT}"
        install_proxy+=(--https-proxy "${HTTPS_PROXY_OPT}")
    fi
    [[ -n "${HTTP_PROXY_OPT:-}" ]]  && install_proxy+=(--http-proxy "${HTTP_PROXY_OPT}")
    [[ -n "${PRIVATE_CA_OPT:-}" ]]  && install_proxy+=(--private-ca "${PRIVATE_CA_OPT}")

    # --- Build the download URL: BASE / CHANNEL [ / VERSION ] ---------------
    # --channel / --version override the config; --version latest => no version.
    local channel="${INSTALLER_CHANNEL_OPT:-$INSTALLER_CHANNEL}"
    local version="$INSTALLER_VERSION"
    [[ -n "${INSTALLER_VERSION_OPT:-}" ]] && version="$INSTALLER_VERSION_OPT"
    [[ "$version" == "latest" ]] && version=""
    local url="${INSTALLER_BASE_URL}/${channel}"
    [[ -n "$version" ]] && url="${url}/${version}"

    # --- Download -----------------------------------------------------------
    header "Downloading installer (~300 MB)"
    info "Channel: ${channel}${version:+   Version: ${version}}"
    step "curl ${url} -> ${INSTALLER_TARBALL}"
    # shellcheck disable=SC2086
    curl -f ${curl_proxy} "${url}" \
        -H "Authorization: ${INSTALL_TOKEN}" \
        -o "${INSTALLER_TARBALL}" \
        || die "Download failed — check the token, version (${version:-latest}), and outbound access to app.enterprise.netboxlabs.com."

    if ! file "${INSTALLER_TARBALL}" | grep -qi "gzip compressed"; then
        die "Downloaded file is not a gzip archive — the token may be invalid. Got: $(file "${INSTALLER_TARBALL}")"
    fi
    ok "Installer downloaded and verified."

    # --- Extract ------------------------------------------------------------
    header "Extracting"
    run_or_die tar -xzf "${INSTALLER_TARBALL}"
    [[ -x "./${INSTALL_BIN_NAME}" ]] || die "Installer binary ./${INSTALL_BIN_NAME} not found after extraction."

    # --- Resolve the bundled license ----------------------------------------
    if [[ -z "${INSTALL_LICENSE:-}" ]]; then
        INSTALL_LICENSE="$(find . -maxdepth 2 -type f \
            \( -iname 'license.yaml' -o -iname 'license.yml' -o -iname '*license*.yaml' \) \
            2>/dev/null | head -1)"
        [[ -n "$INSTALL_LICENSE" ]] && ok "Found bundled license: ${INSTALL_LICENSE}"
    fi
    local lic_arg=()
    if [[ -n "${INSTALL_LICENSE:-}" && -f "${INSTALL_LICENSE}" ]]; then
        lic_arg=(--license "${INSTALL_LICENSE}")
    else
        warn "No license file detected after extraction — letting the installer locate its bundled license."
    fi

    # --- Install ------------------------------------------------------------
    header "Running installer"
    info "This typically takes 30–45 minutes (5–10 min cluster, 10–15 min app init)."
    info "The installer will prompt you to create an Admin Console password — save it."
    ./"${INSTALL_BIN_NAME}" install "${lic_arg[@]}" "${install_proxy[@]}" \
        || die "Installer exited with an error."

    echo ""
    ok "Installer finished."
    echo -e "  ${BOLD}Next:${NC} open the Admin Console to configure NetBox Enterprise:"
    echo -e "        ${CYAN}http://${HOST_FQDN}:${ADMIN_CONSOLE_PORT}${NC}"
    echo -e "  Use the Admin Console password you set during install."
}

run_or_die() { "$@" || die "Command failed: $*"; }
