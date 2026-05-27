#!/usr/bin/env bash
# ASCII banner printed on every run.

print_logo() {
    # Respect NO_COLOR / non-tty (colors come from common.sh)
    printf '%b' "${CYAN}${BOLD}"
    cat <<'LOGO'

   _   _      _   ____
  | \ | | ___| |_| __ )  _____  __
  |  \| |/ _ \ __|  _ \ / _ \ \/ /
  | |\  |  __/ |_| |_) | (_) >  <
  |_| \_|\___|\__|____/ \___/_/\_\

      E N T E R P R I S E   ·   P O C   R E A D I N E S S   V A L I D A T O R
LOGO
    printf '%b' "${NC}"
    printf '%b' "${DIM}"
    printf '  %s\n' "Validates a host against NetBox Enterprise (Embedded Cluster) requirements"
    printf '  %s\n\n' "v${NBE_TOOL_VERSION:-?}  ·  https://netboxlabs.com/docs/enterprise/"
    printf '%b' "${NC}"
}
