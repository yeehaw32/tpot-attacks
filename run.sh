#!/usr/bin/env bash
# run.sh - simple orchestrator: ./run.sh stage-recon/recon_only.sh 10.20.20.10
set -euo pipefail
SCRIPT="${1:-}"
if [ -z "$SCRIPT" ] || [ ! -f "$SCRIPT" ]; then
  echo "Usage: $0 path/to/script [target]" >&2
  exit 1
fi
shift || true
echo "Running $SCRIPT $*"
git rev-parse --is-inside-work-tree >/dev/null 2>&1 && echo "git commit: $(git rev-parse --short HEAD || echo unknown)"
"$SCRIPT" "$@"
