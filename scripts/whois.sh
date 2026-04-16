#!/bin/bash
# whois.sh - helper for consistent whois queries per registry (scoped by -s <SOURCE> when specified).
set -eu

HOST=""
SRC=""
QUERY=""

die() { echo "ERROR: $*" >&2; exit 2; }

while [ $# -gt 0 ]; do
  case "$1" in
    --host) HOST="${2:-}"; shift 2;;
    --source) SRC="${2:-}"; shift 2;;
    --query) QUERY="${2:-}"; shift 2;;
    -h|--help)
      cat <<'EOF'
whois.sh --host <whois_host> [--source <SOURCE>] --query "<q>"
  --host     whois server hostname
  --source   registry SOURCE (passed to whois as: -s <SOURCE>)
  --query    query string passed to whois as a SINGLE argument
EOF
      exit 0
      ;;
    *) die "unknown option: $1";;
  esac
done

[ -n "${HOST}" ] || die "--host is required"
[ -n "${QUERY}" ] || die "--query is required"

if ! command -v whois >/dev/null 2>&1; then
  die "whois command not found. Please install 'whois' package."
fi

if [ -n "${SRC}" ]; then
  whois -h "${HOST}" -s "${SRC}" "${QUERY}" 2>/dev/null || true
else
  whois -h "${HOST}" "${QUERY}" 2>/dev/null || true
fi