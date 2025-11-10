#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

SCRIPT="${1:-}"
if [ -z "$SCRIPT" ]; then
  echo "Usage: $0 {recon|sshbrute|path/to/script} [args...]" >&2
  exit 1
fi
shift || true

# map friendly stage names to scripts in the repo
case "$SCRIPT" in
  recon)
    RESOLVED_SCRIPT="$REPO_ROOT/stage-recon/recon_only.sh"
    ;;
  sshbrute|ssh_brute)
    RESOLVED_SCRIPT="$REPO_ROOT/stage-sshbruteforce/ssh_brute.py"
    ;;
  *)
    # allow either a path relative to CWD or relative to repo root
    if [ -f "$SCRIPT" ]; then
      RESOLVED_SCRIPT="$SCRIPT"
    elif [ -f "$REPO_ROOT/$SCRIPT" ]; then
      RESOLVED_SCRIPT="$REPO_ROOT/$SCRIPT"
    else
      echo "No such script: $SCRIPT" >&2
      exit 1
    fi
    ;;
esac

if [ ! -f "$RESOLVED_SCRIPT" ]; then
  echo "No such script: $RESOLVED_SCRIPT" >&2
  exit 1
fi

echo "Running $RESOLVED_SCRIPT $*"
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "git commit: $(git rev-parse --short HEAD || echo unknown)"
fi

# run python files with python3, otherwise execute with bash
case "$RESOLVED_SCRIPT" in
  *.py) python3 "$RESOLVED_SCRIPT" "$@" ;;
  *) bash "$RESOLVED_SCRIPT" "$@" ;;
esac