#!/bin/bash

##
## cron_runner.sh - IRR cron wrapper
##

set -eu

basedir="$(cd "$(dirname "$0")/.." && pwd)"
timestamp="$(date +%Y%m%d-%H%M%S)"
CRON_DIR="${basedir}/logs/scripts/cron/${timestamp}"
mkdir -p "${CRON_DIR}"

usage() {
cat <<'EOF'
Usage:
  cron_runner.sh --registry <RR> --mode <production|dry-run> --mail-sender <addr> [--objects <list>] [--chunk-size <N>] [--smtp-no-check]

Notes:
  --objects accepts a single comma-separated value, e.g.
    --objects route,route6
EOF
}

REGISTRY=""
MODE=""
MAIL_SENDER=""
OBJECTS="route,route6,mntner,aut-num,as-set"
CHUNK_SIZE=0
SMTP_NO_CHECK=""

# cron mail settings
if [ -f "${basedir}/settings/cron/mail.conf" ]; then
    # shellcheck disable=SC1090
    . "${basedir}/settings/cron/mail.conf"
fi

while [ $# -gt 0 ]; do
    case "$1" in
        --registry) REGISTRY="${2:-}"; shift 2 ;;
        --mode) MODE="${2:-}"; shift 2 ;;
        --mail-sender) MAIL_SENDER="${2:-}"; shift 2 ;;
        --objects) OBJECTS="${2:-}"; shift 2 ;;
        --chunk-size) CHUNK_SIZE="${2:-0}"; shift 2 ;;
        --smtp-no-check) SMTP_NO_CHECK="--smtp-no-check"; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "ERROR: unknown option: $1" >&2; usage; exit 2 ;;
    esac
done

[ -n "${REGISTRY}" ] || { echo "ERROR: --registry is required" >&2; usage; exit 2; }
[ -n "${MODE}" ] || { echo "ERROR: --mode is required" >&2; usage; exit 2; }
[ -n "${MAIL_SENDER}" ] || { echo "ERROR: --mail-sender is required" >&2; usage; exit 2; }

case "${MODE}" in
    production|dry-run) ;;
    *) echo "ERROR: --mode must be production or dry-run" >&2; exit 2 ;;
esac

SUMMARY="${CRON_DIR}/summary.txt"
JOBS="${CRON_DIR}/jobs.txt"
CRONLOG="${CRON_DIR}/cron.log"

{
echo "cron_runner.sh"
echo "Timestamp : ${timestamp}"
echo "Registry  : ${REGISTRY}"
echo "Mode      : ${MODE}"
echo "From      : ${MAIL_SENDER}"
echo "Objects   : ${OBJECTS}"
echo "Log dir   : ${CRON_DIR}"
echo "----------------------------------------------------"
} > "${SUMMARY}"

split_ini_into_chunks() {
    ini="$1"
    chunk_size="$2"
    out_prefix="$3"

    file_idx=0
    sec_count=0
    out=""

    while IFS= read -r line || [ -n "${line}" ]; do
        case "${line}" in
            \[*\])
                if [ -z "${out}" ] || [ "${sec_count}" -ge "${chunk_size}" ]; then
                    file_idx=$((file_idx + 1))
                    sec_count=0
                    out="$(printf '%s.%03d.ini' "${out_prefix}" "${file_idx}")"
                    : > "${out}" || return 1
                fi
                sec_count=$((sec_count + 1))
                ;;
        esac
        [ -n "${out}" ] && printf '%s
' "${line}" >> "${out}"
    done < "${ini}"
}

run_one() {
    obj="$1"
    ini_override="$2"

    LOG_DIR="${CRON_DIR}" \
    OBJECTS_INI_OVERRIDE="${ini_override}" \
    NON_INTERACTIVE="true" \
    FLAG_YES="true" \
    NO_INI_UPDATE="true" \
    IRR_CRON="1" \
    SMTP_AUTH_USER="${smtp_user:-}" \
    SMTP_AUTH_PASS="${smtp_pass:-}" \
    bash "${basedir}/scripts/irr_update.sh" \
      --registry "${REGISTRY}" \
      --object "${obj}" \
      --update \
      --mode "${MODE}" \
      --mail-sender "${MAIL_SENDER}" \
      --yes \
      --no-ini-update \
      ${SMTP_NO_CHECK:+--smtp-no-check} \
      </dev/null
}

ok=0
ng=0

OLDIFS="$IFS"
IFS=','

for obj in ${OBJECTS}; do
    obj="$(printf '%s' "${obj}" | sed 's/^ *//;s/ *$//')"
    [ -n "${obj}" ] || continue
    echo "${obj}" >> "${JOBS}"

    ini="${basedir}/objects/${obj}.ini"
    if [ ! -f "${ini}" ]; then
        echo "WARN: missing ini: ${ini}" >> "${SUMMARY}"
        continue
    fi

    if [ "${CHUNK_SIZE}" -le 0 ]; then
        if run_one "${obj}" "" >>"${CRONLOG}" 2>&1; then
            ok=$((ok+1))
            echo "OK : ${obj} update" >> "${SUMMARY}"
        else
            ng=$((ng+1))
            echo "NG : ${obj} update" >> "${SUMMARY}"
        fi
        continue
    fi

    outp="${CRON_DIR}/${obj}.chunk"
    rm -f "${outp}."*.ini 2>/dev/null || true
    split_ini_into_chunks "${ini}" "${CHUNK_SIZE}" "${outp}" || true
    for chunk_ini in "${outp}."*.ini; do
        [ -f "${chunk_ini}" ] || continue
        if run_one "${obj}" "${chunk_ini}" >>"${CRONLOG}" 2>&1; then
            ok=$((ok+1))
            echo "OK : ${obj} update (chunk $(basename "${chunk_ini}"))" >> "${SUMMARY}"
        else
            ng=$((ng+1))
            echo "NG : ${obj} update (chunk $(basename "${chunk_ini}"))" >> "${SUMMARY}"
        fi
    done
done

IFS="$OLDIFS"

{
echo "----------------------------------------------------"
echo "Result: OK=${ok} NG=${ng}"
echo "See: ${CRON_DIR}"
} >> "${SUMMARY}"

exit 0
