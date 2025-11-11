#!/usr/bin/env bash
# stage-recon/recon_only.sh
# Recon-only scans optimized for T-Pot honeypot validation.
# Scans common honeypot ports (Cowrie, Dionaea, Wordpot, Elasticpot, etc.)
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="${REPO_ROOT}/config.yml"

# If lib/common.sh exists, source it; otherwise provide minimal helpers
if [ -f "${REPO_ROOT}/lib/common.sh" ]; then
  # shellcheck source=/dev/null
  source "${REPO_ROOT}/lib/common.sh"
else
  OUTPUT_BASE="$(awk -F': ' '/^output_base:/{print $2; exit}' "$CONFIG" 2>/dev/null || echo "/bertil/tpot-test")"
  DRY_RUN_DEFAULT="$(awk -F': ' '/^dry_run:/{print $2; exit}' "$CONFIG" 2>/dev/null || echo "false")"
  DRY_RUN="${DRY_RUN:-$DRY_RUN_DEFAULT}"
  timestamp(){ date +%F_%H%M%S; }
  mk_outdir(){ out="${OUTPUT_BASE}/$1/$(timestamp)"; mkdir -p "$out"; echo "$out"; }
  log(){ echo "[$(date +'%F %T')] $*"; }
  run_cmd(){ if [ "${DRY_RUN,,}" = "true" ] || [ "${DRY_RUN}" = "1" ]; then echo "[DRY] $*"; else eval "$@"; fi; }
  check_tools(){
    local miss=0
    for c in nmap curl awk sed grep timeout; do
      command -v "$c" >/dev/null 2>&1 || { echo "MISSING:$c"; miss=1; }
    done
    [ "$miss" -eq 0 ]
  }
fi

# Target from arg or config
TARGET="${1:-}"
if [ -z "$TARGET" ] && [ -f "$CONFIG" ]; then
  TARGET="$(awk '/^targets:/{getline; gsub(/[- ]/,"",$1); print $1; exit}' "$CONFIG" 2>/dev/null || true)"
fi
if [ -z "$TARGET" ]; then
  echo "Usage: $0 <target-ip>  OR set 'targets:' in config.yml" >&2
  exit 1
fi

# Load nmap config
TOPPORTS="$(awk -F': ' '/^nmap:/{f=1;next} f && /^  top_ports:/{print $2; exit}' "$CONFIG" 2>/dev/null || echo 1000)"
SYN_DELAY="$(awk -F': ' '/^nmap:/{f=1;next} f && /^  syn_delay:/{print $2; exit}' "$CONFIG" 2>/dev/null || echo "100ms")"
MIN_RATE="$(awk -F': ' '/^nmap:/{f=1;next} f && /^  min_rate:/{print $2; exit}' "$CONFIG" 2>/dev/null || echo 50)"

OUTDIR="$(mk_outdir "recon")"
LOGFILE="${OUTDIR}/run.log"
echo "Recon-only run for ${TARGET} -> ${OUTDIR}" | tee "$LOGFILE"

check_tools || { echo "Install required tools (nmap, curl, awk, grep, sed, timeout) and retry."; exit 1; }

# 🔑 HONEYPOT PORTS: Fixed list to ensure coverage
# Cowrie: 22,23 | Dionaea: 21,25,80,135,139,445,1433,3306,5060 | Wordpot: 80,8080 | Elasticpot: 9200
HONEYPOT_PORTS="21,22,23,25,80,110,135,139,445,1433,3306,5060,8080,9200"
PORTS="$HONEYPOT_PORTS"

log "Using fixed honeypot ports for reliable T-Pot triggering: ${PORTS}"

# Stage A: SYN + light version scan on top ports (for discovery) + honeypot ports
log "Stage A: top-${TOPPORTS} SYN + version scan (intensity=0)"
run_cmd "nmap -sSV -Pn --version-intensity 0 --top-ports ${TOPPORTS} -T2 --scan-delay ${SYN_DELAY} -oA \"${OUTDIR}/nmap_top\" ${TARGET}"
sleep 2

# Stage B: TCP connect scan on known honeypot ports (ensures handshake completion)
log "Stage B: TCP connect (-sT) on honeypot ports: ${PORTS}"
run_cmd "nmap -sT -Pn -p \"${PORTS}\" -T3 -oN \"${OUTDIR}/nmap_connect.txt\" ${TARGET}"
sleep 1

# Banner grab helper
banner_grab(){
  local host="$1"; local port="$2"; local out="$3"
  # HTTP header probe
  if timeout 6 bash -c "curl -sfI http://${host}:${port} >/dev/null 2>&1" 2>/dev/null; then
    timeout 6 curl -sfI "http://${host}:${port}" >> "${out}" 2>&1 || true
    echo -e "\n[HTTP header probe done]" >> "${out}"
    return
  fi
  # Raw TCP banner fallback
  timeout 5 bash -c "echo -ne 'banner probe\r\n' | nc -w 3 ${host} ${port}" >> "${out}" 2>&1 || true
}

# Stage C: Banner grabs on honeypot ports
log "Stage C: banner grabs on ${PORTS}"
IFS=',' read -r -a p_arr <<< "$PORTS"
for p in "${p_arr[@]}"; do
  [ -z "$p" ] && continue
  outf="${OUTDIR}/banner_${p}.txt"
  echo "Banner grab ${TARGET}:${p} - $(date)" > "${outf}"
  if [ "${DRY_RUN,,}" = "true" ] || [ "${DRY_RUN}" = "1" ]; then
    echo "[DRY] banner_grab ${TARGET} ${p}" >> "${outf}"
  else
    banner_grab "${TARGET}" "${p}" "${outf}"
  fi
done
sleep 1

# Stage D: Safe NSE scripts on honeypot ports
log "Stage D: NSE safe scripts on ${PORTS}"
run_cmd "nmap -sV -Pn -p \"${PORTS}\" --script default,safe -T2 -oN \"${OUTDIR}/nmap_nse.txt\" ${TARGET}"
sleep 1

# Stage E: Optional UDP scan (light)
log "Stage E: top-50 UDP scan (light)"
run_cmd "nmap -sU -Pn --top-ports 50 -T2 --scan-delay 200ms -oN \"${OUTDIR}/nmap_udp.txt\" ${TARGET}" 2>/dev/null || true
sleep 1

# Stage F: Full TCP scan (background, only if not dry-run)
if [ "${DRY_RUN,,}" != "true" ] && [ "${DRY_RUN}" != "1" ]; then
  log "Stage F: slow full TCP scan (background)"
  run_cmd "nmap -p- -sS -Pn -T1 --scan-delay 500ms --min-rate ${MIN_RATE} -oN \"${OUTDIR}/nmap_slow_full.txt\" ${TARGET} &"
else
  log "Stage F: skipped (dry-run mode)"
fi

log "Recon-only run complete. Outputs in ${OUTDIR}"