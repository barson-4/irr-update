#!/bin/bash
#------------------------------------------------------------------------------
# send_mail.sh
#
# Mail / SMTP common functions for irr_update.sh
#
# Responsibilities:
# - Optional internal SMTP pre-check via nc (netcat)
# - Interactive SMTP AUTH LOGIN send via nc
# - Save full SMTP session log
#
# Notes:
# - Variables expected from irr_update.sh / config:
#   smtp_host, smtp_port, SMTP_AUTH, FLAG_SMTP_NO_CHECK
#   ARG_USER, ARG_SENDER, MAIL_SENDER_ADDR, from_mail_address, log_dir, LINE
#   SMTP_AUTH_USER, SMTP_AUTH_PASS (optional plain values)
# - Produces / uses:
#   smtp_user_address (plain)
#
# Policy:
# - telnet fallback is removed
# - nc is required
#------------------------------------------------------------------------------

send_mail_require_nc() {
    command -v nc >/dev/null 2>&1 && return 0
    echo "ERROR: nc (netcat) command not found. Please install it." >&2
    return 1
}

send_mail_auth_user_plain() {
    if [ -n "${SMTP_AUTH_USER:-}" ]; then
        printf '%s' "${SMTP_AUTH_USER}"
        return 0
    fi
    if [ -n "${smtp_user_address:-}" ]; then
        printf '%s' "${smtp_user_address}"
        return 0
    fi
    if [ -n "${ARG_USER:-}" ]; then
        printf '%s' "${ARG_USER}"
        return 0
    fi
    if [ -n "${ARG_SENDER:-}" ]; then
        printf '%s' "${ARG_SENDER}"
        return 0
    fi
    if [ -n "${MAIL_SENDER_ADDR:-}" ]; then
        printf '%s' "${MAIL_SENDER_ADDR}"
        return 0
    fi
    printf '%s' "${from_mail_address:-}"
}

send_mail_ensure_auth_plain() {
    if [ "${SMTP_AUTH:-false}" != "true" ]; then
        return 0
    fi

    # Backward compatibility: accept smtp_user/smtp_pass from config.
    if [ -n "${smtp_user:-}" ] && [ -z "${SMTP_AUTH_USER:-}" ]; then
        SMTP_AUTH_USER="${smtp_user}"
    fi
    if [ -n "${smtp_pass:-}" ] && [ -z "${SMTP_AUTH_PASS:-}" ]; then
        SMTP_AUTH_PASS="${smtp_pass}"
    fi

    smtp_user_address="$(send_mail_auth_user_plain)"
    if [ -z "${smtp_user_address}" ]; then
        echo "ERROR: SMTP auth user is empty. Set --smtp-user." >&2
        return 1
    fi
    export smtp_user_address
    export SMTP_AUTH_USER="${smtp_user_address}"

    if [ -z "${SMTP_AUTH_PASS:-}" ]; then
        printf "Enter SMTP Password: " >&2
        stty -echo 2>/dev/null || true
        read -r SMTP_AUTH_PASS
        stty echo 2>/dev/null || true
        printf "\n" >&2
    fi

    if [ -z "${SMTP_AUTH_PASS:-}" ]; then
        echo "ERROR: SMTP password is required (SMTP_AUTH=true)." >&2
        return 1
    fi

    return 0
}

send_mail_auth_user_b64() {
    local plain
    plain="$(send_mail_auth_user_plain)"
    printf '%s' "${plain}" | base64 | tr -d '\n'
}

send_mail_auth_pass_b64() {
    printf '%s' "${SMTP_AUTH_PASS:-}" | base64 | tr -d '\n'
}

send_mail_log_path_smtp_check() {
    printf "%s/smtp_check.txt" "${log_dir}"
}

send_mail_build_precheck_session() {
    printf 'EHLO localhost\r\n'
    if [ "${SMTP_AUTH:-false}" = "true" ]; then
        printf 'auth login\r\n'
        printf '%s\r\n' "$(send_mail_auth_user_b64)"
        printf '%s\r\n' "$(send_mail_auth_pass_b64)"
    fi
    printf 'quit\r\n'
}

send_mail_validate_precheck_log() {
    local log_file="$1"

    if [ "${SMTP_AUTH:-false}" = "true" ]; then
        grep -Eq '(^|[[:space:]])235[[:space:]]' "${log_file}" >/dev/null 2>&1
        return $?
    fi

    grep -Eq '(^|[[:space:]])(220|250)[[:space:]]' "${log_file}" >/dev/null 2>&1
}

send_mail_init() {
    # Internal SMTP pre-check. Writes: ${log_dir}/smtp_check.txt
    # Returns: 0 on success, 1 on failure (unless --smtp-no-check was used upstream)

    if [ -z "${log_dir:-}" ]; then
        if [ -n "${RUN_DIR:-}" ]; then
            log_dir="${RUN_DIR}"
        elif [ -n "${LOG_DIR:-}" ]; then
            log_dir="${LOG_DIR}"
        fi
    fi

    if [ -z "${log_dir:-}" ]; then
        echo "ERROR: log_dir is not set" >&2
        return 1
    fi

    mkdir -p "${log_dir}" 2>/dev/null || true

    if [ "${FLAG_SMTP_NO_CHECK:-false}" = "true" ]; then
        return 0
    fi

    echo "${LINE:-----------------------------------------------------}"
    echo "        SMTP Pre-check (internal)"
    echo "${LINE:-----------------------------------------------------}"

    if [ -z "${smtp_host:-}" ] || [ -z "${smtp_port:-}" ]; then
        echo "ERROR: smtp_host/smtp_port is not set. Check settings/mail.conf" >&2
        return 1
    fi

    if ! send_mail_require_nc; then
        return 1
    fi

    if ! send_mail_ensure_auth_plain; then
        return 1
    fi

    : > "${log_dir}/smtp_check.txt"
    send_mail_build_precheck_session | nc -w 10 "${smtp_host}" "${smtp_port}" > "${log_dir}/smtp_check.txt" 2>&1
    local rc=$?

    if [ ${rc} -eq 0 ] && send_mail_validate_precheck_log "${log_dir}/smtp_check.txt"; then
        echo "OK: SMTP pre-check succeeded. Saved: ${log_dir}/smtp_check.txt"
        return 0
    fi

    echo "ERROR: SMTP pre-check failed. See: ${log_dir}/smtp_check.txt" >&2
    return 1
}

smtp_send_line() {
    local fd="$1"
    shift
    printf '%s\r\n' "$*" >&$fd
}

smtp_read_response() {
    local fd="$1"
    local line=""
    SMTP_LAST_CODE=""

    while IFS= read -r -u "$fd" -t 15 line; do
        printf '%s\n' "$line"
        case "$line" in
            [0-9][0-9][0-9]" "*)
                SMTP_LAST_CODE="${line%% *}"
                return 0
                ;;
            [0-9][0-9][0-9]-*)
                continue
                ;;
        esac
    done
    return 1
}

send_mail_mask_auth_in_file() {
    local src="$1" dst="$2" auth_lines_to_mask=0 line
    : > "${dst}" || return 1
    while IFS= read -r line || [ -n "${line}" ]; do
        if [ "${auth_lines_to_mask}" -gt 0 ]; then
            printf '********\n' >> "${dst}" || return 1
            auth_lines_to_mask=$((auth_lines_to_mask - 1))
            continue
        fi
        printf '%s\n' "${line}" >> "${dst}" || return 1
        case "${line}" in
            auth\ login|AUTH\ LOGIN) auth_lines_to_mask=2 ;;
        esac
    done < "${src}"
}

send_mail_finalize_session_file() {
    local session_file="$1" tmp_file line in_data=0 inserted=0
    if [ "${MAIL_MODE:-${MODE:-}}" != "dry-run" ]; then
        if [ -n "${MAIL_OUT:-}" ]; then
            send_mail_mask_auth_in_file "${session_file}" "${MAIL_OUT}" || return 1
        fi
        return 0
    fi
    tmp_file="$(mktemp)" || return 1
    while IFS= read -r line || [ -n "${line}" ]; do
        printf '%s\n' "${line}" >> "${tmp_file}" || { rm -f "${tmp_file}"; return 1; }
        if [ "${in_data}" -eq 0 ]; then
            [ "${line}" = "data" ] && in_data=1
            continue
        fi
        if [ "${inserted}" -eq 0 ] && [ -z "${line}" ]; then
            printf '*********************************************\n' >> "${tmp_file}" || { rm -f "${tmp_file}"; return 1; }
            printf '** This Mail is Testing Mail of IRR Update **\n' >> "${tmp_file}" || { rm -f "${tmp_file}"; return 1; }
            printf '*********************************************\n' >> "${tmp_file}" || { rm -f "${tmp_file}"; return 1; }
            printf '\n' >> "${tmp_file}" || { rm -f "${tmp_file}"; return 1; }
            inserted=1
        fi
    done < "${session_file}"
    cat "${tmp_file}" > "${session_file}" || { rm -f "${tmp_file}"; return 1; }
    rm -f "${tmp_file}"
    if [ -n "${MAIL_OUT:-}" ]; then
        send_mail_mask_auth_in_file "${session_file}" "${MAIL_OUT}" || return 1
    fi
    return 0
}

send_mail_send_session_file() {
    # $1: SMTP session file (mail.txt)
    local session_file="$1"
    local host port auth_user auth_pass
    local mail_from rcpt_to
    local tmp_body line

    host="${SMTP_SERVER:-${smtp_host:-}}"
    port="${SMTP_PORT:-${smtp_port:-25}}"

    [ -n "${host}" ] || { echo "ERROR: SMTP host is not set" >&2; return 1; }
    [ -n "${port}" ] || { echo "ERROR: SMTP port is not set" >&2; return 1; }
    [ -f "${session_file}" ] || { echo "ERROR: session file not found: ${session_file}" >&2; return 1; }

    if ! send_mail_require_nc; then
        return 1
    fi
    if ! send_mail_ensure_auth_plain; then
        return 1
    fi
    if ! send_mail_finalize_session_file "${session_file}"; then
        return 1
    fi

    auth_user="$(send_mail_auth_user_plain)"
    auth_pass="${SMTP_AUTH_PASS:-}"

    mail_from=""
    rcpt_to=""
    while IFS= read -r __line || [ -n "${__line}" ]; do
        case "${__line}" in
            mail\ from:\ *) [ -n "${mail_from}" ] || mail_from="${__line}" ;;
            rcpt\ to:\ *) [ -n "${rcpt_to}" ] || rcpt_to="${__line}" ;;
        esac
        [ -n "${mail_from}" ] && [ -n "${rcpt_to}" ] && break
    done < "${session_file}"

    [ -n "${mail_from}" ] || { echo "ERROR: mail from line not found in ${session_file}" >&2; return 1; }
    [ -n "${rcpt_to}" ] || { echo "ERROR: rcpt to line not found in ${session_file}" >&2; return 1; }

    tmp_body="$(mktemp)"
    in_data=0
    : > "${tmp_body}" || return 1
    while IFS= read -r __line || [ -n "${__line}" ]; do
        if [ "${in_data}" -eq 0 ]; then
            [ "${__line}" = "data" ] && in_data=1
            continue
        fi
        [ "${__line}" = "." ] && break
        printf '%s
' "${__line}" >> "${tmp_body}"
    done < "${session_file}"

    coproc SMTPPROC { nc -w 20 "${host}" "${port}"; }

    # banner
    smtp_read_response "${SMTPPROC[0]}" || { rm -f "${tmp_body}"; return 1; }
    case "${SMTP_LAST_CODE}" in
        220) ;;
        *) rm -f "${tmp_body}"; return 1 ;;
    esac

    # EHLO
    smtp_send_line "${SMTPPROC[1]}" "EHLO localhost"
    smtp_read_response "${SMTPPROC[0]}" || { rm -f "${tmp_body}"; return 1; }
    case "${SMTP_LAST_CODE}" in
        250) ;;
        *) rm -f "${tmp_body}"; return 1 ;;
    esac

    # AUTH LOGIN
    if [ "${SMTP_AUTH:-false}" = "true" ]; then
        smtp_send_line "${SMTPPROC[1]}" "auth login"
        smtp_read_response "${SMTPPROC[0]}" || { rm -f "${tmp_body}"; return 1; }
        case "${SMTP_LAST_CODE}" in
            334) ;;
            *) rm -f "${tmp_body}"; return 1 ;;
        esac

        smtp_send_line "${SMTPPROC[1]}" "$(printf '%s' "${auth_user}" | base64 | tr -d '\n')"
        smtp_read_response "${SMTPPROC[0]}" || { rm -f "${tmp_body}"; return 1; }
        case "${SMTP_LAST_CODE}" in
            334) ;;
            *) rm -f "${tmp_body}"; return 1 ;;
        esac

        smtp_send_line "${SMTPPROC[1]}" "$(printf '%s' "${auth_pass}" | base64 | tr -d '\n')"
        smtp_read_response "${SMTPPROC[0]}" || { rm -f "${tmp_body}"; return 1; }
        case "${SMTP_LAST_CODE}" in
            235) ;;
            *) rm -f "${tmp_body}"; return 1 ;;
        esac
    fi

    # MAIL FROM
    smtp_send_line "${SMTPPROC[1]}" "${mail_from}"
    smtp_read_response "${SMTPPROC[0]}" || { rm -f "${tmp_body}"; return 1; }
    case "${SMTP_LAST_CODE}" in
        250) ;;
        *) rm -f "${tmp_body}"; return 1 ;;
    esac

    # RCPT TO
    smtp_send_line "${SMTPPROC[1]}" "${rcpt_to}"
    smtp_read_response "${SMTPPROC[0]}" || { rm -f "${tmp_body}"; return 1; }
    case "${SMTP_LAST_CODE}" in
        250|251) ;;
        *) rm -f "${tmp_body}"; return 1 ;;
    esac

    # DATA
    smtp_send_line "${SMTPPROC[1]}" "data"
    smtp_read_response "${SMTPPROC[0]}" || { rm -f "${tmp_body}"; return 1; }
    case "${SMTP_LAST_CODE}" in
        354) ;;
        *) rm -f "${tmp_body}"; return 1 ;;
    esac

    while IFS= read -r line; do
        case "${line}" in
            .*) line=".${line}" ;;
        esac
        smtp_send_line "${SMTPPROC[1]}" "${line}"
    done < "${tmp_body}"

    smtp_send_line "${SMTPPROC[1]}" "."
    smtp_read_response "${SMTPPROC[0]}" || { rm -f "${tmp_body}"; return 1; }
    case "${SMTP_LAST_CODE}" in
        250) ;;
        *) rm -f "${tmp_body}"; return 1 ;;
    esac

    smtp_send_line "${SMTPPROC[1]}" "quit"
    smtp_read_response "${SMTPPROC[0]}" || true

    rm -f "${tmp_body}"
    return 0
}

send_mail_send() {
    local session_file="$1"

    if [ -z "${session_file}" ] || [ ! -f "${session_file}" ]; then
        echo "ERROR: SMTP session file not found: ${session_file}" >&2
        return 1
    fi

    send_mail_send_session_file "${session_file}"
}
