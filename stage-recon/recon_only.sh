#!/usr/bin/env bash
# stage-recon/recon_only.sh
# Recon-only TCP portscan. Uses lib/common.sh and config.yml
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${REPO_ROOT}/lib/common.sh"

TARGET="${1:-$(awk '/targets:/{getline; print $1}' "$REPO_ROOT/config.yml" | tr -d '-')}"
if [ -z "$TARGET" ]; then
  echo "Usage: $0 <target-ip>  OR set targets: in config.yml" >&2
  exit 1
fi

OUTDIR="$(mk_outdir "recon")"
LOGFILE="${OUTDIR}/run.log"
echo "Recon-only run for $TARGET -> $OUTDIR" | tee "$LOGFILE"

check_tools || { echo "Install required tools and retry."; exit 1; }

# optional safety gate for destructive scripts; here recon-only so we skip
# require_snapshot_confirm

# Load nmap settings from config.yml (simple parsing)
TOPPORTS=$(awk '/nmap:/{flag=1;next} flag && /top_ports:/{print $2; exit}' "$REPO_ROOT/config.yml" 2>/dev/null || echo 200)
SYN_DELAY=$(awk '/nmap:/{flag=1;next} flag && /syn_delay:/{print $2; exit}' "$REPO_ROOT/config.yml" 2>/dev/null || echo "200ms")
MIN_RATE=$(awk '/nmap:/{flag=1;next} flag && /min_rate:/{print $2; exit}' "$REPO_ROOT/config.yml" 2>/dev/null || echo 20)

# Stage A
log "Stage A: top-${TOPPORTS} SYN scan (T2)"
run_cmd "nmap -sS -Pn --top-ports ${TOPPORTS} -T2 --scan-delay ${SYN_DELAY} -oA \"${OUTDIR}/nmap_top\" ${TARGET}"
sleep 3

# Stage B
PORTS=$(grep -oP '^\d+\/tcp' "${OUTDIR}/nmap_top.nmap" 2>/dev/null | cut -d/ -f1 | tr '\n' ',' | sed 's/,$//')
if [ -n "$PORTS" ]; then
  log "Stage B: service/version probe on discovered ports: $PORTS"
  run_cmd "nmap -sV -Pn -p \"${PORTS}\" -T2 --version-intensity 0 -oN \"${OUTDIR}/nmap_sv.txt\" ${TARGET}"
else
  log "Stage B: no open ports found; skipping service probe"
fi
sleep 3

# Stage C: NSE safe scripts
if [ -n "$PORTS" ]; then
  log "Stage C: NSE safe scripts on $PORTS"
  run_cmd "nmap -sV -Pn -p \"${PORTS}\" --script default,safe -T2 -oN \"${OUTDIR}/nmap_nse.txt\" ${TARGET}"
else
  log "Stage C: skipping NSE (no ports)"
fi
sleep 3

# Stage D: slow full scan background
log "Stage D: slow full TCP scan (background)"
run_cmd "nmap -p- -sS -Pn -T1 --scan-delay 500ms --min-rate ${MIN_RATE} -oN \"${OUTDIR}/nmap_slow_full.txt\" ${TARGET} &"

log "Recon-only run complete. Outputs in ${OUTDIR}"
