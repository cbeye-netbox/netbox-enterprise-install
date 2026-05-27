# NetBox Enterprise — POC Readiness Validator

A single tool that checks whether a Linux host is ready for a **NetBox Enterprise
(Embedded Cluster)** installation — and, when you're ready, prepares the host and
runs the installer.

It works on **Ubuntu/Debian and Red Hat–family distributions** (RHEL, Rocky,
AlmaLinux, Oracle Linux, CentOS Stream, Amazon Linux, Fedora) plus SUSE, by
auto-detecting the OS. Run it on a fresh machine, send us the generated JSON
report, and we'll both know the host is good to go.

```
   _   _      _   ____
  | \ | | ___| |_| __ )  _____  __
  |  \| |/ _ \ __|  _ \ / _ \ \/ /
  | |\  |  __/ |_| |_) | (_) >  <
  |_| \_|\___|\__|____/ \___/_/\_\
      ENTERPRISE · POC READINESS VALIDATOR
```

---

## Quick start

```bash
git clone https://github.com/cbeye-netbox/netbox-enterprise-install.git
cd netbox-enterprise-install

# 1. See where the host stands (read-only, changes nothing)
sudo ./nbe-validator.sh check
```

That prints a colored readiness report **and** writes a JSON file under
`reports/`. **Send that JSON file to NetBox Labs** as proof the host is ready.

---

## The four commands

| Command | Changes the machine? | What it does |
|---------|:--------------------:|--------------|
| `check` *(default)* | ❌ No | Runs every readiness check, prints a report, writes a JSON file, and exits with a PASS/FAIL code. **This is the artifact you send us.** |
| `plan` | ❌ No | Shows the **exact** commands and file changes that `apply` would make — a dry run. Nothing is touched. |
| `apply` | ⚠️ Config only | Applies the system-config fixes (swap, kernel modules, sysctl, firewall, and SELinux on RHEL). **Never changes hardware**, and **refuses to run if hardware is below the minimum**. |
| `install` | ⚠️ Yes | Re-validates, then downloads and runs the official NetBox Enterprise installer. Requires a token and license. |

Typical flow:

```bash
sudo ./nbe-validator.sh check      # gather info & get the report
sudo ./nbe-validator.sh plan       # preview what would change
sudo ./nbe-validator.sh apply      # prepare the host (asks for confirmation)
sudo reboot                        # let module/sysctl/swap changes settle
sudo ./nbe-validator.sh install --token <TOKEN> --license license.yaml
```

---

## What gets checked

Everything below is pulled from the official NetBox Labs docs and lives in a
single editable file, [`lib/requirements.conf`](lib/requirements.conf).

**Hardware (read-only, tiered verdict — never modified)**
- CPU: min **4 vCPU**, recommended **8**
- RAM: min **16 GB**, recommended **24 GB**
- Free disk at `/var/lib`: min **50 GB**, recommended **100 GB**
- `x86_64` architecture, SSD/NVMe recommended

> Tiered verdict: **below minimum → FAIL**, **minimum–recommended → WARN**,
> **at/above recommended → OK**.

**Operating system**
- Supported distribution & version (per the docs matrix)
- Kernel ≥ 4.3

**Network**
- Resolvable hostname / FQDN and static IP
- Outbound reachability to `app.`, `registry.`, `proxy.enterprise.netboxlabs.com`, `replicated.app`
- Ports 80 / 443 / 30000 not already in use

**System configuration** *(these are what `apply` fixes)*
- Swap disabled
- Kernel modules: `br_netfilter ip_vs ip_vs_rr ip_vs_wrr ip_vs_sh overlay`
- sysctl: bridge-nf-call-iptables/ip6tables, ip_forward
- Kernel headers present
- SELinux permissive during install (RHEL family)

**Firewall**
- Required NetBox/Kubernetes TCP/UDP ports open (ufw, iptables, or firewalld)
- Pod-network CIDR routing (`10.244.0.0/17` ↔ `10.244.128.0/17`)

---

## Example run

Running `sudo ./nbe-validator.sh check` on a prepared Ubuntu 24.04 host
(4 vCPU / 16 GB / HDD) looks like this:

```text
   _   _      _   ____
  | \ | | ___| |_| __ )  _____  __
  |  \| |/ _ \ __|  _ \ / _ \ \/ /
  | |\  |  __/ |_| |_) | (_) >  <
  |_| \_|\___|\__|____/ \___/_/\_\

      E N T E R P R I S E   ·   P O C   R E A D I N E S S   V A L I D A T O R
  Validates a host against NetBox Enterprise (Embedded Cluster) requirements
  v1.0.0  ·  https://netboxlabs.com/docs/enterprise/


── Operating system ──────────────────────────────────────
[ OK ]  OS family — Ubuntu 24.04.4 LTS (family: debian, pkg: apt-get, fw: ufw)
[ OK ]  CPU architecture — x86_64
[ OK ]  Kernel version — 6.8.0-117-generic
[ OK ]  Distribution version — ubuntu 24.04

── Hardware (read-only — never modified) ──────────────────────────────────────
[WARN]  CPU cores — 4 vCPU
       fix: Meets the non-production minimum but is below the production recommendation of 8 vCPU.
[WARN]  Memory — 16 GB
       fix: Meets the non-production minimum but is below the production recommendation of 24 GB.
[WARN]  Free disk at /var/lib — 94 GB
       fix: Meets the non-production minimum but is below the production recommendation of 100 GB.
[WARN]  Storage type — rotational (HDD)
       fix: SSD or NVMe storage is recommended for database performance.

── Network ──────────────────────────────────────
[ OK ]  Hostname resolvable — netbox-active
[ OK ]  Static IP — no DHCP lease detected
[ OK ]  Outbound to app.enterprise.netboxlabs.com:443 — reachable
[ OK ]  Outbound to registry.enterprise.netboxlabs.com:443 — reachable
[ OK ]  Outbound to proxy.enterprise.netboxlabs.com:443 — reachable
[ OK ]  Outbound to replicated.app:443 — reachable
[ OK ]  Port 80 free — free
[ OK ]  Port 443 free — free
[ OK ]  Port 30000 free — free

── System configuration ──────────────────────────────────────
[ OK ]  Swap disabled — swap off
[ OK ]  Kernel modules loaded — all 6 loaded
[ OK ]  sysctl parameters — all set
[ OK ]  Kernel headers — linux-headers-6.8.0-117-generic installed

── Firewall ──────────────────────────────────────
[ OK ]  Firewall backend — ufw active
[ OK ]  Required ports open — critical TCP ports allowed (80 443 6443 30000)

╔════════════════════════════════════════════════════════╗
║        NetBox Enterprise — Readiness Summary           ║
╚════════════════════════════════════════════════════════╝
  Host    : netbox-active  (Ubuntu 24.04.4 LTS)
  Results : 19 OK  4 WARN  0 FAIL  0 skip

  Action items:
   ! CPU cores: 4 vCPU
     → Meets the non-production minimum but is below the production recommendation of 8 vCPU.
   ! Memory: 16 GB
     → Meets the non-production minimum but is below the production recommendation of 24 GB.
   ! Free disk at /var/lib: 94 GB
     → Meets the non-production minimum but is below the production recommendation of 100 GB.
   ! Storage type: rotational (HDD)
     → SSD or NVMe storage is recommended for database performance.

  VERDICT: PASS WITH WARNINGS — usable, but review the items above.

  JSON report written: reports/nbe-report-netbox-active-20260527-200255.json
  Send this file to NetBox Labs as proof of readiness.
```

> On a **fresh, unprepared** host the swap / kernel-module / sysctl / firewall
> checks come back **FAIL** instead — running `sudo ./nbe-validator.sh apply`
> fixes those, and a re-check then reports the result shown above (the only
> remaining warnings are hardware below the *production* recommendation).

The matching `reports/nbe-report-<host>-<timestamp>.json` for that run:

```json
{
  "tool": "nbe-validator",
  "version": "1.0.0",
  "generated": "2026-05-27T20:02:55Z",
  "tier": "tiered",
  "host": {
    "hostname": "netbox-active",
    "fqdn": "netbox-active",
    "os": "Ubuntu 24.04.4 LTS",
    "os_family": "debian",
    "version_id": "24.04",
    "kernel": "6.8.0-117-generic",
    "arch": "x86_64"
  },
  "verdict": "PASS_WITH_WARNINGS",
  "summary": { "ok": 19, "warn": 4, "fail": 0, "skip": 0 },
  "checks": [
    {
      "id": "hw.ram",
      "category": "hardware",
      "title": "Memory",
      "status": "warn",
      "severity": "low",
      "observed": "16 GB",
      "expected": ">= 24 GB recommended",
      "remediation": "Meets the non-production minimum but is below the production recommendation of 24 GB."
    },
    {
      "id": "sys.modules",
      "category": "system",
      "title": "Kernel modules loaded",
      "status": "ok",
      "severity": "high",
      "observed": "all 6 loaded",
      "expected": "all loaded",
      "remediation": ""
    }
    // … 21 more checks (os / network / system / firewall)
  ]
}
```

---

## The JSON report

`check` (and `apply`) write a machine-readable report to
`reports/nbe-report-<host>-<timestamp>.json`:

```json
{
  "tool": "nbe-validator",
  "verdict": "PASS_WITH_WARNINGS",
  "host": { "hostname": "...", "os": "Ubuntu 24.04.4 LTS", "os_family": "debian", ... },
  "summary": { "ok": 18, "warn": 2, "fail": 0, "skip": 1 },
  "checks": [
    { "id": "hw.ram", "category": "hardware", "status": "ok",
      "observed": "16 GB", "expected": ">= 24 GB", "remediation": "..." }
  ]
}
```

Exit codes (handy for automation): **0 = PASS, 1 = FAIL, 2 = PASS_WITH_WARNINGS**.

---

## Flags

```
--tier prod|min      Verdict display strictness (default: tiered)
--json <path>        Custom JSON report path
--yes, -y            Non-interactive (assume "yes")
--token <t>          Auth token            (install)
--license <file>     License YAML          (install)
--http-proxy <url>   Proxy passthrough     (install)
--https-proxy <url>  Proxy passthrough     (install)
--private-ca <file>  CA bundle for MITM proxy (install)
-h, --help           Show help
```

---

## Updating requirements

When the NetBox Enterprise requirements change, edit **only**
[`lib/requirements.conf`](lib/requirements.conf) — every threshold, port,
kernel module, endpoint, and supported version is defined there as a variable.
No other file needs touching.

## Layout

```
nbe-validator.sh        # entrypoint: logo, flags, command dispatch
lib/
  requirements.conf     # SINGLE SOURCE OF TRUTH (edit this when docs change)
  common.sh             # logging, result model, JSON writer
  logo.sh               # ASCII banner
  os.sh                 # OS/family/kernel/arch detection + support matrix
  hardware.sh           # CPU/RAM/disk/storage (read-only, tiered)
  network.sh            # hostname, static IP, outbound, port availability
  system.sh             # swap, modules, sysctl, headers, SELinux (checks)
  firewall.sh           # firewall backend + required-port checks
  remediate.sh          # apply/plan the system-config changes
  install.sh            # download + run the NetBox Enterprise installer
reports/                # generated JSON reports
```

---

*Requirements sourced from the NetBox Labs
[Embedded Cluster documentation](https://netboxlabs.com/docs/enterprise/embedded-cluster/nbe-ec-requirements/).*
