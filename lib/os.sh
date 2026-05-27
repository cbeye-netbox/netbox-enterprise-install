#!/usr/bin/env bash
# ----------------------------------------------------------------------------
# os.sh — detect the OS family/version/kernel/arch and validate against the
# supported matrix in requirements.conf. Populates HOST_* and OS_FAMILY which
# every other module and the JSON report rely on.
# ----------------------------------------------------------------------------

# Detection: sets globals, no output. Always call before any check.
detect_os() {
    HOST_HOSTNAME="$(hostname 2>/dev/null || echo unknown)"
    HOST_FQDN="$(hostname -f 2>/dev/null || echo "$HOST_HOSTNAME")"
    HOST_KERNEL="$(uname -r 2>/dev/null || echo unknown)"
    HOST_ARCH="$(uname -m 2>/dev/null || echo unknown)"

    HOST_OS="unknown"; HOST_VERSION_ID=""; OS_ID=""; OS_FAMILY="unknown"
    PKG_MGR=""; FW_TOOL=""

    local osrel="${OS_RELEASE_FILE:-/etc/os-release}"
    if [[ -r "$osrel" ]]; then
        # shellcheck disable=SC1091
        . "$osrel"
        HOST_OS="${PRETTY_NAME:-${NAME:-unknown}}"
        HOST_VERSION_ID="${VERSION_ID:-}"
        OS_ID="${ID:-}"
        local like="${ID_LIKE:-}"

        case "$OS_ID" in
            ubuntu|debian)                         OS_FAMILY="debian" ;;
            rhel|centos|rocky|almalinux|ol|fedora|amzn) OS_FAMILY="rhel" ;;
            sles|opensuse*|suse)                   OS_FAMILY="suse" ;;
            *)
                case " $like " in
                    *" debian "*|*" ubuntu "*) OS_FAMILY="debian" ;;
                    *" rhel "*|*" fedora "*|*" centos "*) OS_FAMILY="rhel" ;;
                    *" suse "*) OS_FAMILY="suse" ;;
                esac ;;
        esac
    fi

    case "$OS_FAMILY" in
        debian) PKG_MGR="apt-get"; FW_TOOL="ufw" ;;
        rhel)   PKG_MGR="$(command -v dnf >/dev/null 2>&1 && echo dnf || echo yum)"; FW_TOOL="firewalld" ;;
        suse)   PKG_MGR="zypper"; FW_TOOL="firewalld" ;;
    esac
}

# Returns the space-separated supported-version list for the detected distro.
_supported_versions_for() {
    case "$OS_ID" in
        ubuntu)    echo "$SUPPORTED_UBUNTU" ;;
        debian)    echo "$SUPPORTED_DEBIAN" ;;
        rhel)      echo "$SUPPORTED_RHEL" ;;
        rocky)     echo "$SUPPORTED_ROCKY" ;;
        almalinux) echo "$SUPPORTED_ALMA" ;;
        ol)        echo "$SUPPORTED_ORACLE" ;;
        centos)    echo "$SUPPORTED_CENTOS" ;;
        amzn)      echo "$SUPPORTED_AMAZON" ;;
        fedora)    echo "$SUPPORTED_FEDORA" ;;
        sles|opensuse*|suse) echo "$SUPPORTED_SUSE" ;;
        *)         echo "" ;;
    esac
}

# version_ge "5.14.0" "4.3" -> 0 if first >= second
version_ge() {
    [[ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -n1)" == "$2" ]]
}

check_os() {
    header "Operating system"

    # Family detected?
    if [[ "$OS_FAMILY" == "unknown" ]]; then
        add_result "os.family" "os" "OS family detection" "fail" "high" \
            "could not classify ID='${OS_ID:-?}'" "debian / rhel / suse based" \
            "Use a supported distribution (Ubuntu, RHEL, Rocky, Oracle, CentOS Stream, Debian, Amazon Linux, Fedora, SUSE)."
    else
        add_result "os.family" "os" "OS family" "ok" "info" \
            "${HOST_OS} (family: ${OS_FAMILY}, pkg: ${PKG_MGR}, fw: ${FW_TOOL})" "supported family" ""
    fi

    # Architecture
    if [[ "$HOST_ARCH" == "$REQUIRED_ARCH" ]]; then
        add_result "os.arch" "os" "CPU architecture" "ok" "high" "$HOST_ARCH" "$REQUIRED_ARCH" ""
    else
        add_result "os.arch" "os" "CPU architecture" "fail" "high" "$HOST_ARCH" "$REQUIRED_ARCH" \
            "NetBox Enterprise requires ${REQUIRED_ARCH}. This host is ${HOST_ARCH} and is not supported."
    fi

    # Kernel >= MIN_KERNEL
    local kver="${HOST_KERNEL%%-*}"
    if version_ge "$kver" "$MIN_KERNEL"; then
        add_result "os.kernel" "os" "Kernel version" "ok" "high" "$HOST_KERNEL" ">= ${MIN_KERNEL}" ""
    else
        add_result "os.kernel" "os" "Kernel version" "fail" "high" "$HOST_KERNEL" ">= ${MIN_KERNEL}" \
            "Upgrade the kernel to ${MIN_KERNEL} or newer."
    fi

    # Distro version against the support matrix (unknown version warns)
    local supported; supported="$(_supported_versions_for)"
    if [[ -z "$supported" ]]; then
        add_result "os.version" "os" "Distribution version" "warn" "low" \
            "${HOST_OS} ${HOST_VERSION_ID}" "a documented distribution" \
            "This distribution is not in the documented matrix; installation may still work but is untested."
    elif grep -qw -- "$HOST_VERSION_ID" <<< "$supported"; then
        add_result "os.version" "os" "Distribution version" "ok" "info" \
            "${OS_ID} ${HOST_VERSION_ID}" "one of: ${supported}" ""
    else
        add_result "os.version" "os" "Distribution version" "warn" "low" \
            "${OS_ID} ${HOST_VERSION_ID}" "one of: ${supported}" \
            "Version ${HOST_VERSION_ID} is not in the tested list (${supported}). Proceed with caution."
    fi
}
