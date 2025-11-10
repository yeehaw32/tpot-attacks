#!/usr/bin/env bash
# stage-recon/recon_only.sh
# Recon-only TCP scans + banner grabs. Works standalone or with lib/common.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="${REPO_ROOT}/config.yml"

# If lib/common.sh exists, source for helpers; otherwise provide minimal helpers
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

# target from arg or first entry in config.yml
TARGET="${1:-}"
if [ -z "$TARGET" ] && [ -f "$CONFIG" ]; then
  TARGET="$(awk '/^targets:/{getline; gsub(/[- ]/,"",$1); print $1; exit}' "$CONFIG" 2>/dev/null || true)"
fi
if [ -z "$TARGET" ]; then
  echo "Usage: $0 <target-ip>  OR set 'targets:' in config.yml" >&2
  exit 1
fi

# nmap settings (safe defaults)
TOPPORTS="$(awk -F': ' '/^nmap:/{f=1;next} f && /^  top_ports:/{print $2; exit}' "$CONFIG" 2>/dev/null || echo 1000)"
SYN_DELAY="$(awk -F': ' '/^nmap:/{f=1;next} f && /^  syn_delay:/{print $2; exit}' "$CONFIG" 2>/dev/null || echo "100ms")"
MIN_RATE="$(awk -F': ' '/^nmap:/{f=1;next} f && /^  min_rate:/{print $2; exit}' "$CONFIG" 2>/dev/null || echo 50)"

OUTDIR="$(mk_outdir "recon")"
LOGFILE="${OUTDIR}/run.log"
echo "Recon-only run for ${TARGET} -> ${OUTDIR}" | tee "$LOGFILE"

check_tools || { echo "Install required tools (nmap, curl, awk, grep, sed, timeout) and retry."; exit 1; }

# Stage A: SYN top-ports (fast-ish)
log "Stage A: top-${TOPPORTS} SYN scan"
run_cmd "nmap -sS -Pn --top-ports ${TOPPORTS} -T2 --scan-delay ${SYN_DELAY} -oA \"${OUTDIR}/nmap_top\" ${TARGET}"
sleep 2

# extract open TCP ports (only 'open' ports)
PORTS="$(awk '/\/tcp/ && /open/ {split($1,a,"/"); printf a[1]\",\" }' "${OUTDIR}/nmap_top.nmap" 2>/dev/null | sed 's/,$//')"
if [ -n "$PORTS" ]; then
  log "Discovered open ports: ${PORTS}"
else
  log "No open TCP ports found in Stage A."
fi

# Stage B: TCP connect on discovered ports (noisy, completes handshake)
if [ -n "$PORTS" ]; then
  log "Stage B: TCP connect (-sT) on ${PORTS}"
  run_cmd "nmap -sT -Pn -p \"${PORTS}\" -T3 -oN \"${OUTDIR}/nmap_connect.txt\" ${TARGET}"
else
  log "Stage B: skipping (no ports)"
fi
sleep 1

# banner grab helper: HTTP via curl, fallback raw /dev/tcp probe
banner_grab(){
  local host="$1"; local port="$2"; local out="$3"
  # HTTP header probe
  if run_cmd bash -c "curl -sI --max-time 4 http://${host}:${port} >/dev/null 2>&1"; then
    run_cmd "curl -sI --max-time 6 http://${host}:${port} >> \"${out}\" 2>&1 || true"
    echo -e "\n[HTTP header probe done]" >> "${out}"
    return
  fi
  # raw tcp banner fallback (may not return)
  run_cmd bash -c "timeout 5 bash -c 'echo | cat > /dev/tcp/${host}/${port}' >> \"${out}\" 2>&1 || true"
}

# Stage C: banner grabs per discovered port
if [ -n "$PORTS" ]; then
  log "Stage C: banner grabs on ${PORTS}"
  IFS=',' read -r -a p_arr <<< "$PORTS"
  for p in "${p_arr[@]}"; do
    [ -z "$p" ] && continue
    outf="${OUTDIR}/banner_${p}.txt"
    echo "Banner grab ${TARGET}:${p} - $(date)" > "${outf}"
    banner_grab "${TARGET}" "${p}" "${outf}"
  done
else
  log "Stage C: no ports => skipping banner grabs"
fi
sleep 1

# Stage D: safe NSE scripts against discovered ports (non-destructive)
if [ -n "$PORTS" ]; then
  log "Stage D: NSE safe scripts on ${PORTS}"
  run_cmd "nmap -sV -Pn -p \"${PORTS}\" --script default,safe -T2 -oN \"${OUTDIR}/nmap_nse.txt\" ${TARGET}"
else
  log "Stage D: skipping NSE"
fi
sleep 1

# Stage E: optional slow full TCP scan in background (long, noisy)
log "Stage E: optional slow full scan (background)"
run_cmd "nmap -p- -sS -Pn -T1 --scan-delay 500ms --min-rate ${MIN_RATE} -oN \"${OUTDIR}/nmap_slow_full.txt\" ${TARGET} &"

log "Recon-only run complete. Outputs in ${OUTDIR}"
