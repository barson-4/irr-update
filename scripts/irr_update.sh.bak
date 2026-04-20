#!/bin/bash

#################################################################
##                                                             ##
##                    irr_update.sh                            ##
##                                                             ##
#################################################################

#------------------------------------------------------------------------------
#                    Version
#------------------------------------------------------------------------------

# Script version (also used in logs output)
SCRIPT_VERSION="1.0.0"

show_help() {
	local lang="${ARG_LANG}"
	local help_file=""
	local rootdir="${BASE_DIR:-${basedir:-}}"
	if [ -z "${rootdir}" ]; then rootdir="."; fi
	if [ -z "${lang}" ]; then
		case "${LANG:-}" in
			ja*|JA*|*ja_JP*|*ja_JP.*) lang="ja" ;;
			*) lang="en" ;;
		esac
	fi
	case "${lang}" in
		ja|jp) help_file="${rootdir}/docs/help.ja" ;;
		en)    help_file="${rootdir}/docs/help.en" ;;
		*)     help_file="${rootdir}/docs/help.en" ;;
	esac
	if [ -f "${help_file}" ]; then
		cat "${help_file}"
	else
		cat "${rootdir}/docs/help.en"
	fi
}


#------------------------------------------------------------------------------
# Credential and argument defaults
#------------------------------------------------------------------------------
# Date helpers
DATE_YMD="$(date +%Y%m%d)"
DATE_HYPHEN="$(date +%Y-%m-%d)"
# Normalized arguments (single source of truth)
ARG_PREFIX=""
ARG_DESCR=""
ARG_DELETE_REASON=""
ARG_ADD=""
ARG_DEL=""
ARG_CUSTOMER=""
ARG_NAME=""
FLAG_NAME="false"
FLAG_ADD="false"
FLAG_DEL="false"
FLAG_DELETE="false"
FLAG_ADDR="false"
FLAG_CUSTOMER="false"

# Reject deprecated options explicitly
for arg in "$@"; do
    if [ "$arg" = "--dry-run" ]; then
        echo "ERROR: '--dry-run' is deprecated. Use '--mode check'. See --help." >&2
        exit 2
    fi
    if [ "$arg" = "--dry-run-send" ] || [ "$arg" = "--dry-run-send-self" ]; then
        echo "ERROR: '--dry-run-send*' options are deprecated. Use '--mail-sender <address>'. See --help." >&2
        exit 2
    fi
done
# Default object selection
if [ -z "${ARG_OBJECT}" ]; then
	if [ "${FLAG_ROUTE}" == "true" ]; then
		ARG_OBJECT="route object"
	elif [ "${FLAG_MNTNER}" == "true" ] || [ "${FLAG_AUTNUM}" == "true" ] || [ "${FLAG_ASSET}" == "true" ]; then
		ARG_OBJECT="mntner object"
	fi
fi

## initialize mail_address
unset to_mail_address
unset from_mail_address
## Include General settings
# Use repository root as base (scripts/..), to support running from anywhere (cron-friendly)
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
basedir="$(cd -- "${script_dir}/.." && pwd)"
objects_ini_path() {
    # Allow cron runner (or tests) to override the INI file path.
    # Used for chunked cron sends: create a temporary INI and set OBJECTS_INI_OVERRIDE.
    if [ -n "${OBJECTS_INI_OVERRIDE:-}" ]; then
        echo "${OBJECTS_INI_OVERRIDE}"
        return 0
    fi
    case "$1" in
        route)   echo "${basedir}/objects/route.ini" ;;
        route6)  echo "${basedir}/objects/route6.ini" ;;
        mntner)  echo "${basedir}/objects/mntner.ini" ;;
        aut-num) echo "${basedir}/objects/aut-num.ini" ;;
        as-set)  echo "${basedir}/objects/as-set.ini" ;;
        *) return 1 ;;
    esac
}
# --- HOTFIX: early help handling (avoid loading mail.conf) ---
for arg in "$@"; do
    case "$arg" in
        --help|-h)
            show_help
            exit 0
            ;;
    esac
done

. "${basedir}/scripts/send_mail.sh"
# Load mail settings from new layout first; fallback to legacy layout
if [ -f "${basedir}/settings/mail.conf" ]; then
  source "${basedir}/settings/mail.conf"
else
  echo "ERROR: mail.conf not found under ${basedir}/settings" >&2
  exit 1
fi
date=$(date '+%Y%m%d')

# New flags (default)
MODE="check"               # --mode check|dry-run|production (default: check)
DRY_RUN="false"            # legacy --dry-run (alias for --mode check)
DRY_RUN_SEND_ADDR=""       # --dry-run-send <addr> (send only to addr, no Cc/Bcc)
DRY_RUN_SEND_SELF="false"  # --dry-run-send-self (send only to auth user or From)
NON_INTERACTIVE="${NON_INTERACTIVE:-false}"  # --non-interactive
FLAG_YES="${FLAG_YES:-false}"                # --yes
NO_INI_UPDATE="${NO_INI_UPDATE:-false}"      # --no-ini-update (read-only objects/*.ini)
SEND_VIA="auto"            # --send-via (reserved, not fully implemented yet)
SMTP_AUTH="true"           # --no-smtp-auth disables SMTP AUTH LOGIN
FORCE_PRODUCTION="false"   # internal (set by --mode production)
MAIL_SENDER_ADDR=""        # --mail-sender <address> (production From override)
SENDER_TO_ADDR=""          # --sender <address> (dry-run To override)
LOG_DIR=""                 # --log-dir (default decided at runtime)
pick_log_dir() {
        # Prefer: /opt/irr/logs if writable, else $HOME/.irr/logs, else /tmp/irr-logs
        local d
        d="${basedir}/logs/scripts"
        if mkdir -p "$d" 2>/dev/null && [ -w "$d" ]; then
                echo "$d"; return 0
        fi
        if [ -n "${HOME:-}" ]; then
                d="${HOME}/.irr/logs"
                if mkdir -p "$d" 2>/dev/null && [ -w "$d" ]; then
                        echo "$d"; return 0
                fi
        fi
        d="/tmp/irr-logs"
        mkdir -p "$d" 2>/dev/null || true
        echo "$d"
}
init_run_dir() {
        local ts
        ts="$(date '+%Y%m%d-%H%M%S')"
        # Allow caller (e.g., cron_runner.sh) to override log root directory.
        # - LOG_DIR: absolute/relative path (highest priority)
        # - LOG_ROOT: relative to basedir (e.g., "logs/cron")
        if [ -z "${LOG_DIR}" ] && [ -n "${LOG_ROOT}" ]; then
                case "${LOG_ROOT}" in
                        /*) LOG_DIR="${LOG_ROOT}" ;;
                        *)  LOG_DIR="${basedir}/${LOG_ROOT}" ;;
                esac
        fi
        [ -n "${LOG_DIR}" ] || LOG_DIR="$(pick_log_dir)"
        RUN_DIR="${LOG_DIR}/${ts}"
        mkdir -p "${RUN_DIR}" 2>/dev/null || true
        MAIL_OUT="${RUN_DIR}/mail.txt"
        OBJ_OUT="${RUN_DIR}/object.txt"
        SUMMARY_OUT="${RUN_DIR}/summary.txt"
}

# -----------------------------------------------------------------------------
# Helper functions (moved out of init_run_dir in v0.4.04; behavior unchanged)
# -----------------------------------------------------------------------------
# Generate RPSL mail body into a file (no SMTP wrapper)
generate_mail_body_to_file() {
	local out="$1"
	case "${OBJECT}" in
		route)
			if [ "${FLAG_UPDATE}" = "true" ]; then
				build_route_update_mail "route" > "${out}"
			else
				build_route_single_mail "route" > "${out}"
			fi
			;;
		route6)
			if [ "${FLAG_UPDATE}" = "true" ]; then
				build_route_update_mail "route6" > "${out}"
			else
				build_route_single_mail "route6" > "${out}"
			fi
			;;
		mntner)
			build_rpsl_update_mail "mntner" > "${out}"
			;;
		aut-num)
			build_rpsl_update_mail "aut-num" > "${out}"
			;;
		as-set)
			build_rpsl_update_mail "as-set" > "${out}"
			;;
        *)
			echo "ERROR: unsupported --object '${OBJECT}'" >&2
			return 2
			;;
	esac
}

ensure_smtp_auth() {
	local prompt_user=""
	prompt_user="${smtp_user:-${SMTP_USER:-${from_mail_address}}}"

	# 送信用SMTPユーザ
	SMTP_AUTH_USER="${SMTP_AUTH_USER:-$prompt_user}"

	# 送信用SMTPパスワード
	if [ -z "${SMTP_AUTH_PASS:-}" ]; then
		printf "Enter SMTP Password: " >&2
		stty -echo
		read -r SMTP_AUTH_PASS
		stty echo
		printf "\n" >&2
	fi

	export SMTP_AUTH_USER SMTP_AUTH_PASS
}

# Generate an SMTP session transcript for dry-run mode
generate_smtp_session_to_file() {
	local out="$1"
	local body_file="$2"

	# SMTP auth user/password
	local smtp_auth_user=""
	local smtp_auth_pass=""

	smtp_auth_user="${smtp_user:-${SMTP_USER:-${from_mail_address}}}"
	smtp_auth_pass="${SMTP_AUTH_PASS:-${smtp_pass:-${SMTP_PASS:-}}}"

	{
		echo "EHLO localhost"

		if [ "${SMTP_AUTH}" = "true" ]; then
			echo "auth login"
			printf '%s' "${smtp_auth_user}" | base64
			echo
			printf '%s' "${smtp_auth_pass}" | base64
			echo
		fi

		echo "mail from: <${from_mail_address}>"
		echo "rcpt to: <${to_mail_address}>"
		echo "data"
		echo "from: <${from_mail_address}>"
		echo "to: <${to_mail_address}>"
		echo "Subject: ${MAIL_SUBJECT}"
		echo
		echo
		cat "${body_file}"
		echo
		echo "."
		echo "quit"
	} > "${out}"
}

mask_smtp_auth_in_file() {
	local src="$1"
	local dst="$2"
	local auth_lines_to_mask=0 line
	: > "${dst}" || return 1
	while IFS= read -r line || [ -n "${line}" ]; do
		if [ "${auth_lines_to_mask}" -gt 0 ]; then
			case "${line}" in
				"")
					printf '%s
' "${line}" >> "${dst}" || return 1
					continue
					;;
				*)
					printf '********
' >> "${dst}" || return 1
					auth_lines_to_mask=$((auth_lines_to_mask - 1))
					continue
					;;
			esac
		fi
		printf '%s
' "${line}" >> "${dst}" || return 1
		case "${line}" in
			auth\ login|AUTH\ LOGIN)
				auth_lines_to_mask=2
				;;
		esac
	done < "${src}"
}

generate_and_save_smtp_session_files() {
	local body_file="$1"
	local raw_out="$2"
	local masked_out="$3"

	generate_smtp_session_to_file "${raw_out}" "${body_file}" || return 1
	mask_smtp_auth_in_file "${raw_out}" "${masked_out}" || return 1
}

mask_mail_body_secrets_in_file() {
	local src="$1"
	local dst="$2"
	local line rest
	: > "${dst}" || return 1
	while IFS= read -r line || [ -n "${line}" ]; do
		case "${line}" in
			password:*)
				printf 'password:   ********
' >> "${dst}" || return 1
				;;
			auth:*\ CRYPT-PW\ *)
				rest="${line#*CRYPT-PW }"
				printf '%s
' "${line%"${rest}"}********" >> "${dst}" || return 1
				;;
			*)
				printf '%s
' "${line}" >> "${dst}" || return 1
				;;
		esac
	done < "${src}"
}

save_masked_mail_body_log() {
	local src="$1"
	local dst
	dst="$(log_path_mail_body)"
	[ -n "${src}" ] || return 0
	[ -f "${src}" ] || return 0
	mask_mail_body_secrets_in_file "${src}" "${dst}" || return 1
	echo "Saved: ${dst}"
}

# Render extra lines that should be emitted after the target attribute block.
# Registry profiles may define, for example:
#   CONTINUATION_TARGET_DESCR_KEYS="X_Keiro"
#   CONTINUATION_TARGET_REMARKS_KEYS="NOTICE"
# Values for listed keys must be defined in "Organization Parameters".
# Underscore in keys is rendered as hyphen in output (X_Keiro -> X-Keiro).
trim_spaces() {
	local s="$1"
	s="${s#"${s%%[!$' \t']*}"}"
	s="${s%"${s##*[!$' \t']}"}"
	printf '%s' "${s}"
}

print_continuation_block() {
	local block="$1" line
	[ -n "${block}" ] || return 0
	while IFS= read -r line || [ -n "${line}" ]; do
		printf '%s\n' "${line}"
	done <<EOF
${block}
EOF
}

trim_trailing_blank_lines_file() {
	local src="$1"
	local dst="$2"
	local line last_nonblank=0 count=0
	local -a lines
	while IFS= read -r line || [ -n "${line}" ]; do
		count=$((count + 1))
		lines[count]="${line}"
		case "${line}" in
			''|$'\r') ;;
			*) last_nonblank=${count} ;;
		esac
	done < "${src}"
	: > "${dst}" || return 1
	count=1
	while [ "${count}" -le "${last_nonblank}" ]; do
		printf '%s\n' "${lines[count]}" >> "${dst}" || return 1
		count=$((count + 1))
	done
}

ini_section_matches_prefix_descr() {
	local ini="$1" section="$2" pfx="$3" dsc="$4"
	local line trimmed current="" in_sec=0 got_prefix=0 got_descr=0
	while IFS= read -r line || [ -n "${line}" ]; do
		line="${line%$'\r'}"
		trimmed="$(trim_spaces "${line}")"
		case "${trimmed}" in
			'['*']')
				current="${trimmed#[}"
				current="${current%]}"
				if [ "${current}" = "${section}" ]; then
					in_sec=1
				else
					in_sec=0
				fi
				;;
			prefix=*)
				[ "${in_sec}" -eq 1 ] && [ "${line#prefix=}" = "${pfx}" ] && got_prefix=1
				;;
			descr=*)
				[ "${in_sec}" -eq 1 ] && [ "${line#descr=}" = "${dsc}" ] && got_descr=1
				;;
		esac
	done < "${ini}"
	[ "${got_prefix}" -eq 1 ] && [ "${got_descr}" -eq 1 ]
}

remove_ini_section() {
	local ini="$1" section="$2" out="$3"
	local line trimmed current="" skip=0
	: > "${out}" || return 1
	while IFS= read -r line || [ -n "${line}" ]; do
		line="${line%$'\r'}"
		trimmed="$(trim_spaces "${line}")"
		case "${trimmed}" in
			'['*']')
				current="${trimmed#[}"
				current="${current%]}"
				if [ "${current}" = "${section}" ]; then
					skip=1
					continue
				fi
				skip=0
				;;
		esac
		[ "${skip}" -eq 0 ] && printf '%s\n' "${line}" >> "${out}" || return 1
	done < "${ini}"
}

render_target_continuations() {
	local target="$1" keys="" out="" key header_name val
	case "$target" in
		descr)   keys="${continuation_target_descr_keys:-${CONTINUATION_TARGET_DESCR_KEYS:-}}" ;;
		remarks) keys="${continuation_target_remarks_keys:-${CONTINUATION_TARGET_REMARKS_KEYS:-}}" ;;
		*)       keys="" ;;
	esac

	for key in $keys; do
		header_name="${key//_/-}"
		val="${!key-}"
		[ -n "$val" ] || continue
		out+="            ${header_name}:${val}\n"
	done
	printf '%b' "$out"
}

# Build route/route6 annual update mail body from objects INI (ALL entries -> one mail)
build_route_update_mail() {
	local obj="$1"
	local ini prefix="" origin="" mnt_by="" notify="" descr="" remarks=""
	local line trimmed key val descr_cont="" remarks_cont="" def_origin="" def_mnt_by="" def_notify="" def_remarks=""
	ini="$(objects_ini_path "${obj}")" || return 2
	[ -f "${ini}" ] || { echo "ERROR: objects file not found: ${ini}" >&2; return 2; }

	if [ "${execution_mode}" != "Check" ] && [ "${MODE}" != "check" ]; then
		printf 'password:   %s
' "${IRR_PASSWORD}"
	fi

	descr_cont="$(render_target_continuations descr)"
	remarks_cont="$(render_target_continuations remarks)"
	def_remarks="${rpsl_remarks:-}"
	if [ "${obj}" = "route" ]; then
		def_origin="${route_origin:-}"
		def_mnt_by="${route_mnt_by:-}"
		def_notify="${route_notify:-}"
	else
		def_origin="${route6_origin:-}"
		def_mnt_by="${route6_mnt_by:-}"
		def_notify="${route6_notify:-}"
	fi

	flush_route_record() {
		[ -n "${prefix}" ] || return 0
		[ -n "${origin}" ] || origin="${def_origin}"
		[ -n "${mnt_by}" ] || mnt_by="${def_mnt_by}"
		[ -n "${notify}" ] || notify="${def_notify}"
		[ -n "${remarks}" ] || remarks="${def_remarks}"
		if [ "${obj}" = "route" ]; then
			printf 'route:      %s
' "${prefix}"
		else
			printf 'route6:     %s
' "${prefix}"
		fi
		printf 'descr:      %s
' "${descr}"
		[ -n "${descr}" ] && [ -n "${descr_cont}" ] && print_continuation_block "${descr_cont}"
		if [ -n "${remarks}" ]; then
			printf 'remarks:    %s
' "${remarks}"
			[ -n "${remarks_cont}" ] && print_continuation_block "${remarks_cont}"
		fi
		[ -n "${notify}" ] && printf 'notify:     %s
' "${notify}"
		[ -n "${origin}" ] && printf 'origin:     %s
' "${origin}"
		[ -n "${mnt_by}" ] && printf 'mnt-by:     %s
' "${mnt_by}"
		printf 'changed:    %s %s
' "${from_mail_address}" "${DATE_YMD}"
		printf 'source:     %s

' "${IRR_SOURCE}"
		prefix=""; origin=""; mnt_by=""; notify=""; descr=""; remarks=""
	}

	while IFS= read -r line || [ -n "${line}" ]; do
		line="${line%$'
'}"
		trimmed="$(trim_spaces "${line}")"
		case "${trimmed}" in
			''|'#'*|';'*) continue ;;
			'['*']')
				flush_route_record
				continue
				;;
		esac
		case "${line}" in
			*=*)
				key="${line%%=*}"
				val="${line#*=}"
				key="$(trim_spaces "${key}")"
				val="${val%$'
'}"
				case "${key}" in
					prefix) prefix="${val}" ;;
					origin) origin="${val}" ;;
					mnt-by) mnt_by="${val}" ;;
					notify) notify="${val}" ;;
					descr) descr="${val}" ;;
					remarks) remarks="${val}" ;;
				esac
				;;
		esac
	done < "${ini}"
	flush_route_record
}

# Build route/route6 single add/delete mail body
build_route_single_mail() {
	local obj="$1"  # route or route6
	local prefix=""
	if [ "${FLAG_ADD}" = "true" ]; then prefix="${ARG_ADD}"; else prefix="${ARG_DEL}"; fi
	local descr="${ARG_CUSTOMER}" remarks="${rpsl_remarks:-}"
	local origin mnt_by notify descr_cont remarks_cont
	if [ "${obj}" = "route" ]; then
		origin="${route_origin}"
		mnt_by="${route_mnt_by}"
		notify="${route_notify}"
	else
		origin="${route6_origin}"
		mnt_by="${route6_mnt_by}"
		notify="${route6_notify}"
	fi
	descr_cont="$(render_target_continuations descr)"
	remarks_cont="$(render_target_continuations remarks)"
	if [ "${execution_mode}" != "Check" ] && [ "${MODE}" != "check" ]; then
		printf "password:   %s
" "${IRR_PASSWORD}"
	fi
	if [ "${obj}" = "route" ]; then
		printf "route:      %s
" "${prefix}"
	else
		printf "route6:     %s
" "${prefix}"
	fi
	printf "descr:      %s
" "${descr}"
	[ -n "${descr}" ] && [ -n "${descr_cont}" ] && printf '%b' "${descr_cont}"
	if [ -n "${remarks}" ]; then
		printf "remarks:    %s
" "${remarks}"
		[ -n "${remarks_cont}" ] && printf '%b' "${remarks_cont}"
	fi
	printf "notify:     %s
" "${notify}"
	printf "origin:     %s
" "${origin}"
	printf "mnt-by:     %s
" "${mnt_by}"
	printf "changed:    %s %s
" "${from_mail_address}" "${DATE_YMD}"
	printf "source:     %s

" "${IRR_SOURCE}"
}

append_line_block() {
	local cur="$1" val="$2"
	[ -n "${val}" ] || { printf '%s' "${cur}"; return 0; }
	if [ -n "${cur}" ]; then
		printf '%s
%s' "${cur}" "${val}"
	else
		printf '%s' "${val}"
	fi
}

normalize_object_ini_key() {
	local key="$1"
	key="$(trim_spaces "${key}")"
	key="${key//-/_}"
	printf '%s' "${key}" | tr '[:lower:]' '[:upper:]'
}

emit_rpsl_attr() {
	local attr="$1" value="$2"
	[ -n "${value}" ] || return 0
	printf '%-11s %s
' "${attr}:" "${value}"
}

emit_rpsl_block() {
	local attr="$1" block="$2" line
	[ -n "${block}" ] || return 0
	while IFS= read -r line || [ -n "${line}" ]; do
		line="$(trim_spaces "${line}")"
		[ -n "${line}" ] || continue
		emit_rpsl_attr "${attr}" "${line}"
	done <<EOF
${block}
EOF
}

build_object_ini_update_mail() {
	local obj="$1"
	local ini="${ARG_INI_FILE:-}"
	if [ -z "${ini}" ]; then
		ini="$(objects_ini_path "${obj}")" || return 2
	fi
	[ -f "${ini}" ] || { echo "ERROR: objects file not found: ${ini}" >&2; return 2; }

	if [ "${execution_mode}" != "Check" ] && [ "${MODE}" != "check" ]; then
		printf 'password:   %s
' "${IRR_PASSWORD}"
	fi

	local descr_cont remarks_cont target_name
	descr_cont="$(render_target_continuations descr)"
	remarks_cont="$(render_target_continuations remarks)"
	target_name="${ARG_NAME:-}"

	local current_section="" insec=0 emitted=0
	local primary="" as_name="" descr="" remarks="" notify="" admin_c="" tech_c="" upd_to="" mnt_by="" changed="" source="" auth="" mnt_nfy=""
	local import_block="" export_block="" mp_import_block="" mp_export_block="" members_block="" mbrs_by_ref_block="" member_of_block=""

	reset_object_ini_record() {
		primary=""; as_name=""; descr=""; remarks=""; notify=""; admin_c=""; tech_c=""; upd_to=""; mnt_by=""; changed=""; source=""; auth=""; mnt_nfy=""
		import_block=""; export_block=""; mp_import_block=""; mp_export_block=""; members_block=""; mbrs_by_ref_block=""; member_of_block=""
	}

	flush_object_ini_record() {
		local selected=1
		[ "${insec}" -eq 1 ] || return 0
		[ -n "${primary}" ] || { reset_object_ini_record; return 0; }
		if [ -n "${target_name}" ] && [ "${primary}" != "${target_name}" ]; then
			selected=0
		fi
		[ "${selected}" -eq 1 ] || { reset_object_ini_record; return 0; }

		[ -n "${remarks}" ] || remarks="${rpsl_remarks:-}"
		[ -n "${notify}" ] || notify="${rpsl_notify:-}"
		[ -n "${admin_c}" ] || admin_c="${rpsl_admin_c:-}"
		[ -n "${tech_c}" ] || tech_c="${rpsl_tech_c:-}"
		[ -n "${upd_to}" ] || upd_to="${rpsl_upd_to:-}"
		[ -n "${mnt_by}" ] || mnt_by="${rpsl_mnt_by:-}"
		[ -n "${changed}" ] || changed="${from_mail_address} ${DATE_YMD}"
		[ -n "${source}" ] || source="${IRR_SOURCE}"

		if [ "${obj}" = "aut-num" ]; then
			emit_rpsl_attr "aut-num" "${primary}"
			emit_rpsl_attr "as-name" "${as_name}"
		else
			emit_rpsl_attr "as-set" "${primary}"
		fi
		emit_rpsl_attr "descr" "${descr}"
		if [ -n "${descr}" ]; then
			print_continuation_block "${descr_cont}"
		fi
		emit_rpsl_attr "remarks" "${remarks}"
		if [ -n "${remarks}" ]; then
			print_continuation_block "${remarks_cont}"
		fi
		if [ "${obj}" = "aut-num" ]; then
			emit_rpsl_block "import" "${import_block}"
			emit_rpsl_block "export" "${export_block}"
			emit_rpsl_block "mp-import" "${mp_import_block}"
			emit_rpsl_block "mp-export" "${mp_export_block}"
			emit_rpsl_block "member-of" "${member_of_block}"
		else
			emit_rpsl_block "members" "${members_block}"
			emit_rpsl_block "mbrs-by-ref" "${mbrs_by_ref_block}"
		fi
		emit_rpsl_attr "notify" "${notify}"
		emit_rpsl_attr "admin-c" "${admin_c}"
		emit_rpsl_attr "tech-c" "${tech_c}"
		emit_rpsl_attr "upd-to" "${upd_to}"
		emit_rpsl_attr "mnt-nfy" "${mnt_nfy}"
		emit_rpsl_attr "mnt-by" "${mnt_by}"
		emit_rpsl_attr "changed" "${changed}"
		emit_rpsl_attr "source" "${source}"
		printf '
'
		emitted=1
		reset_object_ini_record
	}

	reset_object_ini_record
	while IFS= read -r line || [ -n "${line}" ]; do
		line="${line%$'
'}"
		trimmed="$(trim_spaces "${line}")"
		case "${trimmed}" in
			''|'#'*) continue ;;
			\[*\])
				flush_object_ini_record
				current_section="${trimmed#[}"
				current_section="${current_section%]}"
				insec=1
				reset_object_ini_record
				continue
				;;
		esac
		[ "${insec}" -eq 1 ] || continue
		case "${trimmed}" in
			*=*)
				key="${trimmed%%=*}"
				val="${trimmed#*=}"
				key="$(normalize_object_ini_key "${key}")"
				val="$(trim_spaces "${val}")"
				case "${key}" in
					AUT_NUM|AS_SET) primary="${val}" ;;
					AS_NAME) as_name="${val}" ;;
					DESCR) descr="${val}" ;;
					REMARKS) remarks="${val}" ;;
					NOTIFY) notify="${val}" ;;
					ADMIN_C) admin_c="${val}" ;;
					TECH_C) tech_c="${val}" ;;
					UPD_TO) upd_to="${val}" ;;
					MNT_BY) mnt_by="${val}" ;;
					CHANGED) changed="${val}" ;;
					SOURCE) source="${val}" ;;
					AUTH) auth="${val}" ;;
					MNT_NFY) mnt_nfy="${val}" ;;
					IMPORT) import_block="$(append_line_block "${import_block}" "${val}")" ;;
					EXPORT) export_block="$(append_line_block "${export_block}" "${val}")" ;;
					MP_IMPORT) mp_import_block="$(append_line_block "${mp_import_block}" "${val}")" ;;
					MP_EXPORT) mp_export_block="$(append_line_block "${mp_export_block}" "${val}")" ;;
					MEMBERS) members_block="$(append_line_block "${members_block}" "${val}")" ;;
					MBRS_BY_REF) mbrs_by_ref_block="$(append_line_block "${mbrs_by_ref_block}" "${val}")" ;;
					MEMBER_OF) member_of_block="$(append_line_block "${member_of_block}" "${val}")" ;;
					*) : ;;
				esac
				;;
		esac
	done < "${ini}"
	flush_object_ini_record

	if [ -n "${target_name}" ] && [ "${emitted}" -eq 0 ]; then
		echo "ERROR: ${obj} object not found in $(basename "${ini}"): ${target_name}" >&2
		return 2
	fi
}

# Build mntner/aut-num/as-set update mail body from objects/*.ini (RPSL-style: "key: value")
# - Reads ALL matching sections for the current registry (suffix: _jpirr / _radb etc)
# - Default: one mail per object (ini)
# - Chunking is done by cron_runner via --ini-file
# - password line must be first for real send
# - For mntner: always ensure "auth: CRYPT-PW <CRYPT_PW>" exists (plain text; hashing is RR-side)
build_rpsl_update_mail() {
	local obj="$1"   # mntner / aut-num / as-set
	if [ "${obj}" = "aut-num" ] || [ "${obj}" = "as-set" ]; then
		build_object_ini_update_mail "${obj}"
		return $?
	fi
	local ini="${ARG_INI_FILE:-}"
	if [ -z "${ini}" ]; then
		ini="$(objects_ini_path "${obj}")" || return 2
	fi
	[ -f "${ini}" ] || { echo "ERROR: objects file not found: ${ini}" >&2; return 2; }

	if [ "${execution_mode}" != "Check" ] && [ "${MODE}" != "check" ]; then
		printf 'password:   %s
' "${IRR_PASSWORD}"
	fi

	local rr_tag descr_cont remarks_cont
	rr_tag="${ARG_REGISTER_LOWER:-$(printf %s "${ARG_REGISTER:-}" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')}"
	descr_cont="$(render_target_continuations descr)"
	remarks_cont="$(render_target_continuations remarks)"

	local -a lines=() newlines=() final_lines=()
	local insec=0 sec_ok=0 sec_name="" line=""
	local has_changed=0 has_source=0 has_auth=0
	local has_notify=0 has_admin_c=0 has_tech_c=0 has_upd_to=0 has_mnt_by=0
	local has_descr=0 has_remarks=0

	_append_multiline_lines() {
		local block="$1" ml
		[ -n "$block" ] || return 0
		while IFS= read -r ml || [ -n "$ml" ]; do
			[ -n "$ml" ] || continue
			final_lines+=("$ml")
		done <<< "$block"
	}

	_reset_rpsl_state() {
		insec=0; sec_ok=0; sec_name=""
		lines=(); newlines=(); final_lines=()
		has_changed=0; has_source=0; has_auth=0
		has_notify=0; has_admin_c=0; has_tech_c=0; has_upd_to=0; has_mnt_by=0
		has_descr=0; has_remarks=0
	}

	_section_matches_rpsl() {
		local name="$1"
		[[ "$name" == *_"$rr_tag" ]]
	}

	_flush_rpsl_record() {
		local i inserted_auth=0 next_line="" inserted_descr_cont=0 inserted_remarks_cont=0
		if [ "$insec" -ne 1 ]; then return 0; fi
		if [ "$sec_ok" -ne 1 ]; then _reset_rpsl_state; return 0; fi

		if [ "$obj" = "mntner" ] && [ "$has_auth" -ne 1 ]; then
			if [ -z "${CRYPT_PW:-}" ]; then
				lines+=("ERROR: CRYPT_PW is required for mntner update")
			else
				newlines=()
				for ((i=0; i<${#lines[@]}; i++)); do
					newlines+=("${lines[i]}")
					if [[ ${lines[i]} =~ ^[[:space:]]*mnt-by:[[:space:]]* ]] && [ $inserted_auth -eq 0 ]; then
						newlines+=("auth:      CRYPT-PW ${CRYPT_PW}")
						inserted_auth=1
					fi
				done
				if [ $inserted_auth -eq 0 ]; then newlines+=("auth:      CRYPT-PW ${CRYPT_PW}"); fi
				lines=("${newlines[@]}")
			fi
		fi

		final_lines=()
		for ((i=0; i<${#lines[@]}; i++)); do
			line="${lines[i]}"
			final_lines+=("$line")
			next_line=""
			if [ $((i+1)) -lt ${#lines[@]} ]; then next_line="${lines[i+1]}"; fi
			if [ "$inserted_descr_cont" -eq 0 ] && [[ $line =~ ^[[:space:]]*descr:[[:space:]]* ]] && [[ ! $next_line =~ ^[[:space:]]*descr:[[:space:]]* ]]; then
				_append_multiline_lines "$descr_cont"
				inserted_descr_cont=1
			fi
			if [ "$inserted_remarks_cont" -eq 0 ] && [[ $line =~ ^[[:space:]]*remarks:[[:space:]]* ]] && [[ ! $next_line =~ ^[[:space:]]*remarks:[[:space:]]* ]]; then
				_append_multiline_lines "$remarks_cont"
				inserted_remarks_cont=1
			fi
		done

		if [ "$has_remarks" -ne 1 ] && [ -n "${rpsl_remarks:-}" ]; then
			final_lines+=("remarks:    ${rpsl_remarks}")
			_append_multiline_lines "$remarks_cont"
		fi
		if [ "$has_notify" -ne 1 ] && [ -n "${rpsl_notify:-}" ]; then final_lines+=("notify:    ${rpsl_notify}"); fi
		if [ "$has_admin_c" -ne 1 ] && [ -n "${rpsl_admin_c:-}" ]; then final_lines+=("admin-c:   ${rpsl_admin_c}"); fi
		if [ "$has_tech_c" -ne 1 ] && [ -n "${rpsl_tech_c:-}" ]; then final_lines+=("tech-c:    ${rpsl_tech_c}"); fi
		if [ "$has_upd_to" -ne 1 ] && [ -n "${rpsl_upd_to:-}" ]; then final_lines+=("upd-to:    ${rpsl_upd_to}"); fi
		if [ "$has_mnt_by" -ne 1 ] && [ -n "${rpsl_mnt_by:-}" ]; then final_lines+=("mnt-by:    ${rpsl_mnt_by}"); fi
		if [ "$has_changed" -ne 1 ]; then final_lines+=("changed:   ${from_mail_address} ${DATE_YMD}"); fi
		if [ "$has_source" -ne 1 ]; then final_lines+=("source:    ${IRR_SOURCE}"); fi

		printf '%s
' "${final_lines[@]}"
		printf '
'
		_reset_rpsl_state
	}

	_reset_rpsl_state
	while IFS= read -r line || [ -n "$line" ]; do
		line="${line%$'
'}"
		if [[ $line =~ ^[[:space:]]*\[([^]]+)\][[:space:]]*$ ]]; then
			_flush_rpsl_record
			insec=1; sec_name="${BASH_REMATCH[1]}"
			if _section_matches_rpsl "$sec_name"; then sec_ok=1; else sec_ok=0; fi
			continue
		fi
		[ "$insec" -eq 1 ] || continue
		[ "$sec_ok" -eq 1 ] || continue
		if [[ $line =~ ^[[:space:]]*changed:[[:space:]]* ]]; then has_changed=1; fi
		if [[ $line =~ ^[[:space:]]*source:[[:space:]]*  ]]; then has_source=1; fi
		if [ "$obj" = "mntner" ] && [[ $line =~ ^[[:space:]]*auth:[[:space:]]*CRYPT-PW[[:space:]]* ]]; then has_auth=1; fi
		if [[ $line =~ ^[[:space:]]*notify:[[:space:]]*  ]]; then has_notify=1; fi
		if [[ $line =~ ^[[:space:]]*admin-c:[[:space:]]* ]]; then has_admin_c=1; fi
		if [[ $line =~ ^[[:space:]]*tech-c:[[:space:]]*  ]]; then has_tech_c=1; fi
		if [[ $line =~ ^[[:space:]]*upd-to:[[:space:]]*  ]]; then has_upd_to=1; fi
		if [[ $line =~ ^[[:space:]]*mnt-by:[[:space:]]*  ]]; then has_mnt_by=1; fi
		if [[ $line =~ ^[[:space:]]*descr:[[:space:]]*   ]]; then has_descr=1; fi
		if [[ $line =~ ^[[:space:]]*remarks:[[:space:]]* ]]; then has_remarks=1; fi
		lines+=("$line")
	done < "$ini"
	_flush_rpsl_record
}


# Return objects ini path for a given object name
# Remove any INI section whose "prefix=" matches the given prefix.
# Append a new section for the given object/prefix and attributes.
# Update objects list after a production add/delete.
update_objects_list_production() {
    # Update objects/*.ini only in production add/delete.
    # - ADD: if entry already exists with same prefix+descr, do nothing (avoid duplicates when multiple RR processed).
    #        if section exists but differs, error.
    # - DELETE: after mail send, ask y/n whether to remove from objects list. If entry missing, warn and continue.
    if [ "${NO_INI_UPDATE}" = "true" ]; then
        echo "INFO: --no-ini-update: objects/*.ini will not be modified." >&2
        return 0
    fi
    local ini ts backup_dir backup_file
    local prefix descr section __p tmpdir tmpfile ans
    ini="$(objects_ini_path "${OBJECT}")"
    if [ -z "${ini}" ] || [ ! -f "${ini}" ]; then
        echo "ERROR: objects ini not found: ${ini}" >&2
        return 1
    fi
    prefix="${ARG_PREFIX}"
    descr="${ARG_DESCR}"
    if [ -z "${prefix}" ] || [ -z "${descr}" ]; then
        echo "ERROR: prefix/descr is empty. Skip objects update." >&2
        return 1
    fi
    # Compute section name for route/route6; for other objects, use "<object>_<sanitized>"
    if [ "${OBJECT}" = "route" ]; then
        section="route-v4_${prefix//\//_}"
    elif [ "${OBJECT}" = "route6" ]; then
        __p="${prefix//:/-}"
        section="route-v6_${__p//\//_}"
    else
        section="${OBJECT}_${prefix//\//_}"
    fi
    tmpdir="${LOG_DIR:-${log_dir}}/temp"
    mkdir -p "${tmpdir}"
    echo
    echo "---------------------------------------------------------"
    echo "       Update Objects/$(basename "${ini}")"
    echo "---------------------------------------------------------"
    # ADD: skip if already exists with same values (avoid duplicates across RR runs)
    if [ "${FLAG_ADD}" = "true" ]; then
        if ini_section_matches_prefix_descr "${ini}" "${section}" "${prefix}" "${descr}"; then
            echo "Skip: already exists: [${section}]"
            return 0
        fi
        # If section exists but differs -> error (safety)
        if grep -q -E "^[[:space:]]*\[${section//\[/\\[}\][[:space:]]*$" "${ini}"; then
            echo "ERROR: objects ini already has section but values differ: [${section}]" >&2
            echo "       prefix=${prefix}" >&2
            echo "       descr=${descr}" >&2
            echo "       Please fix objects ini manually or delete the old entry." >&2
            return 1
        fi
    fi
    # DELETE: ask after mail send whether to remove from objects list
    if [ "${FLAG_DEL}" = "true" ]; then
        printf "Remove from objects list? [%s] (y/n) : " "${section}"
        if [ -t 0 ]; then
            read ans
        else
            ans="n"
        fi
        case "${ans}" in
            y|Y) : ;;
            *)
                echo "Skip: objects list not changed."
                return 0
                ;;
        esac
    fi
    ts="$(date +%Y%m%d%H%M%S)"
    backup_dir="$(dirname "${ini}")/old"
    mkdir -p "${backup_dir}"
    backup_file="${backup_dir}/$(basename "${ini}")_${ts}"
    cp -p "${ini}" "${backup_file}" || return 1
    echo "Backup: ${backup_file}"
    tmpfile="${tmpdir}/objects_ini.tmp"
    if [ "${FLAG_ADD}" = "true" ]; then
        # Append fresh section at end (no upsert needed because we already error if it exists differently)
        # Trim trailing blank lines first so repeated runs don't accumulate extra spacing.
        trim_trailing_blank_lines_file "${ini}" "${tmpfile}" || return 1
        {
            printf "\n"
            echo "[${section}]"
            echo "prefix=${prefix}"
            echo "descr=${descr}"
        } >> "${tmpfile}" || return 1
        mv "${tmpfile}" "${ini}" || return 1

        # Trim trailing blank lines after add
        trim_trailing_blank_lines_file "${ini}" "${tmpfile}.trim" || return 1
        mv "${tmpfile}.trim" "${ini}" || return 1

        echo "Updated objects list: ${ini}"
    elif [ "${FLAG_DEL}" = "true" ]; then
        # If missing, warn and continue (multi-RR friendly)
        if ! grep -q -E "^[[:space:]]*\[${section//\[/\\[}\][[:space:]]*$" "${ini}"; then
            echo "WARN: objects ini has no such entry. Skip remove: [${section}]"
            return 0
        fi
        remove_ini_section "${ini}" "${section}" "${tmpfile}" || return 1
        mv "${tmpfile}" "${ini}" || return 1

        # Trim trailing blank lines after delete
        trim_trailing_blank_lines_file "${ini}" "${tmpfile}.trim" || return 1
        mv "${tmpfile}.trim" "${ini}" || return 1

        echo "Updated objects list: ${ini}"
    else
        echo "ERROR: update_objects_list_production called without add/delete" >&2
        return 1
    fi
    echo
    echo "---------------------------------------------------------"
    echo "       diff -u (Objects/$(basename "${ini}"))"
    echo "---------------------------------------------------------"
    diff -u "${backup_file}" "${ini}" || true
    echo
}
# Pre-parse long options (keep existing short options via getopts)
# Lookup a single route record from INI by prefix.
# Outputs: prefix<TAB>origin<TAB>mnt-by<TAB>notify<TAB>descr
# Read all route records from INI.
# Outputs: prefix<TAB>origin<TAB>mnt-by<TAB>notify<TAB>descr
# Return INI file path for an object.
# Prefer ${basedir}/objects/<name>.ini, fallback to legacy ${basedir}/state/routes/<name>.ini when present.
get_object_ini_path() {
	local obj="$1"
	# Allow cron runner to override INI path (chunked sends).
	if [ -n "${OBJECTS_INI_OVERRIDE:-}" ]; then
		echo "${OBJECTS_INI_OVERRIDE}"
		return 0
	fi
	if [ -f "${basedir}/objects/${obj}.ini" ]; then
		echo "${basedir}/objects/${obj}.ini"
	elif [ -f "${basedir}/state/routes/${obj}.ini" ]; then
		echo "${basedir}/state/routes/${obj}.ini"
	else
		echo "${basedir}/objects/${obj}.ini"
	fi
}
read_routes_ini_to_records() {
	local ini_file="$1"
	local def_origin="${2:-}"
	local def_mnt="${3:-}"
	local def_notify="${4:-}"
	local prefix="" origin="" mnt="" notify="" descr="" remarks="" line trimmed key val

	flush_route_ini_record() {
		[ -n "${prefix}" ] || return 0
		[ -n "${origin}" ] || origin="${def_origin}"
		[ -n "${mnt}" ] || mnt="${def_mnt}"
		[ -n "${notify}" ] || notify="${def_notify}"
		printf '%s	%s	%s	%s	%s	%s
' "${prefix}" "${origin}" "${mnt}" "${notify}" "${descr}" "${remarks}"
		prefix=""; origin=""; mnt=""; notify=""; descr=""; remarks=""
	}

	while IFS= read -r line || [ -n "${line}" ]; do
		line="${line%$'
'}"
		trimmed="$(trim_spaces "${line}")"
		case "${trimmed}" in
			''|'#'*|';'*) continue ;;
			'['*']')
				flush_route_ini_record
				continue
				;;
		esac
		case "${line}" in
			*=*)
				key="$(trim_spaces "${line%%=*}")"
				val="${line#*=}"
				val="${val%$'
'}"
				case "${key}" in
					prefix) prefix="${val}" ;;
					origin) origin="${val}" ;;
					mnt-by) mnt="${val}" ;;
					notify) notify="${val}" ;;
					descr) descr="${val}" ;;
					remarks) remarks="${val}" ;;
				esac
				;;
		esac
	done < "${ini_file}"
	flush_route_ini_record
}

read_routes_ini_lookup_by_prefix() {
	local ini_file="$1"
	local want_prefix="$2"
	local def_origin="${3:-}"
	local def_mnt="${4:-}"
	local def_notify="${5:-}"
	local rec prefix origin mnt notify descr remarks
	while IFS=$'	' read -r prefix origin mnt notify descr remarks; do
		[ "${prefix}" = "${want_prefix}" ] || continue
		printf '%s	%s	%s	%s	%s	%s
' "${prefix}" "${origin}" "${mnt}" "${notify}" "${descr}" "${remarks}"
		return 0
	done <<EOF
$(read_routes_ini_to_records "${ini_file}" "${def_origin}" "${def_mnt}" "${def_notify}")
EOF
	return 0
}

read_routes_ini_lookup_by_section() {
	local ini_file="$1"
	local want_section="$2"
	local line trimmed current_section="" prefix="" origin="" mnt="" notify="" descr="" remarks="" key val
	while IFS= read -r line || [ -n "${line}" ]; do
		line="${line%$'
'}"
		trimmed="$(trim_spaces "${line}")"
		case "${trimmed}" in
			''|'#'*|';'*) continue ;;
			'['*']')
				current_section="${trimmed#[}"
				current_section="${current_section%]}"
				if [ "${current_section}" != "${want_section}" ]; then
					prefix=""; origin=""; mnt=""; notify=""; descr=""; remarks=""
				fi
				continue
				;;
		esac
		[ "${current_section}" = "${want_section}" ] || continue
		case "${line}" in
			*=*)
				key="$(trim_spaces "${line%%=*}")"
				val="${line#*=}"
				val="${val%$'
'}"
				case "${key}" in
					prefix) prefix="${val}" ;;
					origin) origin="${val}" ;;
					mnt-by) mnt="${val}" ;;
					notify) notify="${val}" ;;
					descr) descr="${val}" ;;
					remarks) remarks="${val}" ;;
				esac
				;;
		esac
	done < "${ini_file}"
	if [ -n "${current_section}" ] && [ "${current_section}" = "${want_section}" ]; then
		printf '%s	%s	%s	%s	%s	%s
' "${prefix}" "${origin}" "${mnt}" "${notify}" "${descr}" "${remarks}"
	fi
}

read_routes_ini_value_by_prefix() {
	local ini_file="$1"
	local want_prefix="$2"
	local want_key="$3"
	local prefix origin mnt notify descr remarks
	while IFS=$'	' read -r prefix origin mnt notify descr remarks; do
		[ "${prefix}" = "${want_prefix}" ] || continue
		case "${want_key}" in
			prefix) printf '%s
' "${prefix}" ;;
			origin) printf '%s
' "${origin}" ;;
			mnt-by) printf '%s
' "${mnt}" ;;
			notify) printf '%s
' "${notify}" ;;
			descr) printf '%s
' "${descr}" ;;
			remarks) printf '%s
' "${remarks}" ;;
		esac
		return 0
	done <<EOF
$(read_routes_ini_to_records "${ini_file}")
EOF
	return 0
}

#------------------------------------------------------------------------------
# Long-option setters (no legacy option_* functions)
#------------------------------------------------------------------------------
set_add() {
	ARG_ADD="$1"
	if [ -n "${ARG_ADD}" ]; then
		FLAG_ADD="true"
		FLAG_ADDR="true"
		# Normalize prefix
		ARG_PREFIX="${ARG_ADD}"
	else
		FLAG_ADD="false"
	fi
}
set_delete() {
	ARG_DEL="$1"
	if [ -n "${ARG_DEL}" ]; then
		FLAG_DEL="true"
		FLAG_ADDR="true"
		# Normalize prefix
		ARG_PREFIX="${ARG_DEL}"
	else
		FLAG_DEL="false"
	fi
}
set_customer() {
	ARG_CUSTOMER="$1"
	if [ -n "${ARG_CUSTOMER}" ]; then
		FLAG_CUSTOMER="true"
		# Normalize descr/customer
		ARG_DESCR="${ARG_CUSTOMER}"
	else
		FLAG_CUSTOMER="false"
	fi
}
set_lang() {
	ARG_LANG="$1"
}
validate_required_args() {
	# --customer must not be used alone
	if [ "${FLAG_CUSTOMER}" = "true" ] && [ "${FLAG_ADD}" != "true" ] && [ "${FLAG_DEL}" != "true" ]; then
		echo "ERROR: --customer must be used with --add or --delete." >&2
		exit 2
	fi
	# --add/--delete requires --customer (route/route6 add/delete policy)
	if ( [ "${FLAG_ADD}" = "true" ] || [ "${FLAG_DEL}" = "true" ] ) && [ "${FLAG_CUSTOMER}" != "true" ]; then
		echo "ERROR: --customer is required with --add/--delete." >&2
		exit 2
	fi
	# Disallow add and delete together
	if [ "${FLAG_ADD}" = "true" ] && [ "${FLAG_DEL}" = "true" ]; then
		echo "ERROR: --add and --delete cannot be used together." >&2
		exit 2
	fi
	# Normalize prefix/descr must exist for add/delete
	if ( [ "${FLAG_ADD}" = "true" ] || [ "${FLAG_DEL}" = "true" ] ) && [ -z "${ARG_PREFIX}" ]; then
		echo "ERROR: prefix is required." >&2
		exit 2
	fi
	if ( [ "${FLAG_ADD}" = "true" ] || [ "${FLAG_DEL}" = "true" ] ) && [ -z "${ARG_DESCR}" ]; then
		echo "ERROR: customer/descr is required." >&2
		exit 2
	fi
}

validate_registry_credentials_required() {
	# credential.conf is mandatory when an actual email is sent (dry-run/production).
	# NOTE: "cron" runs should use --mode dry-run or production, so this covers cron as well.
	[ "${MODE}" = "check" ] && return 0

	if [ -z "${ARG_REGISTER_LOWER:-}" ]; then
		echo "ERROR: registry is not set. Use --registry <RR>." >&2
		exit 2
	fi

	local cred_file="${basedir}/settings/registries/${ARG_REGISTER_LOWER}/credential.conf"
	if [ ! -f "${cred_file}" ]; then
		echo "ERROR: credential.conf is required for mode '${MODE}': ${cred_file}" >&2
		exit 2
	fi

	# shellcheck disable=SC1090
	. "${cred_file}"

	# Canonical variable name is IRR_PASSWORD.
	password="${IRR_PASSWORD:-}"

	if [ -z "${IRR_PASSWORD:-}" ]; then
		echo "ERROR: IRR_PASSWORD is required in ${cred_file} for mode '${MODE}'." >&2
		exit 2
	fi

	# CRYPT_PW is only required when generating mntner object updates (auth: CRYPT-PW ...)
	if [ "${ARG_OBJECT_KEY_LOWER:-}" = "mntner" ] && [ -z "${CRYPT_PW:-}" ]; then
		echo "ERROR: CRYPT_PW is required in ${cred_file} when --object mntner is used." >&2
		exit 2
	fi
}

validate_route_ini_required_keys() {
	local obj="$1"
	local ini_file
	ini_file="$(objects_ini_path "${obj}")" || return 0
	[ -f "${ini_file}" ] || return 0
	local line trimmed section="" have_prefix=0 have_descr=0 err=0 key val
	while IFS= read -r line || [ -n "${line}" ]; do
		line="${line%$'
'}"
		trimmed="$(trim_spaces "${line}")"
		case "${trimmed}" in
			''|'#'*|';'*) continue ;;
			'['*']')
				if [ -n "${section}" ] && { [ "${have_prefix}" -eq 0 ] || [ "${have_descr}" -eq 0 ]; }; then
					printf 'ERROR: %s [%s] missing required key(s):' "${ini_file}" "${section}" >&2
					[ "${have_prefix}" -eq 0 ] && printf ' prefix' >&2
					[ "${have_descr}" -eq 0 ] && printf ' descr' >&2
					printf '\n' >&2
					err=1
				fi
				section="${trimmed#[}"
				section="${section%]}"
				have_prefix=0
				have_descr=0
				continue
				;;
		esac
		case "${line}" in
			*=*)
				key="$(trim_spaces "${line%%=*}")"
				val="${line#*=}"
				[ -n "${val}" ] || continue
				[ "${key}" = "prefix" ] && have_prefix=1
				[ "${key}" = "descr" ] && have_descr=1
				;;
		esac
	done < "${ini_file}"
	if [ -n "${section}" ] && { [ "${have_prefix}" -eq 0 ] || [ "${have_descr}" -eq 0 ]; }; then
		printf 'ERROR: %s [%s] missing required key(s):' "${ini_file}" "${section}" >&2
		[ "${have_prefix}" -eq 0 ] && printf ' prefix' >&2
		[ "${have_descr}" -eq 0 ] && printf ' descr' >&2
		printf '\n' >&2
		err=1
	fi
	[ "${err}" -eq 0 ] || exit 2
}
validate_delete_consistency_with_ini() {
	# For --delete: ensure target exists in ini and descr matches ini
	[ "${FLAG_DEL}" = "true" ] || return 0
	case "${OBJECT}" in
		route|route6) ;;
		*) return 0 ;;
	esac
	local ini rec ini_prefix ini_origin ini_mnt ini_notify ini_descr
	ini="$(objects_ini_path "${OBJECT}")" || return 0
	[ -f "${ini}" ] || { echo "ERROR: objects file not found: ${ini}" >&2; exit 2; }
	rec="$(read_routes_ini_lookup_by_prefix "${ini}" "${ARG_PREFIX}")"
	if [ -z "${rec}" ]; then
		echo "ERROR: delete target prefix not found in ${ini}: ${ARG_PREFIX}" >&2
		exit 2
	fi
	ini_descr="$(read_routes_ini_value_by_prefix "${ini}" "${ARG_PREFIX}" "descr")"
	
if [ -z "${ini_descr}" ]; then
    # Fallback: try section-based lookup (handles rare parsing/format edge cases)
    local sec __p rec2
    if [ "${OBJECT}" = "route" ]; then
        sec="route-v4_${ARG_PREFIX//\//_}"
    elif [ "${OBJECT}" = "route6" ]; then
        __p="${ARG_PREFIX//:/-}"
        sec="route-v6_${__p//\//_}"
    else
        sec=""
    fi
    if [ -n "${sec}" ]; then
        rec2="$(read_routes_ini_lookup_by_section "${ini}" "${sec}")"
        if [ -n "${rec2}" ]; then
            ini_descr="$(printf '%s
' "${rec2}" | cut -f5)"
        fi
    fi
fi
if [ -z "${ini_descr}" ]; then
    echo "ERROR: ${ini} has no descr for prefix ${ARG_PREFIX}" >&2
    exit 2
fi
	if [ "${ini_descr}" != "${ARG_DESCR}" ]; then
		echo "ERROR: descr mismatch for ${ARG_PREFIX}" >&2
		echo "       ini : ${ini_descr}" >&2
		echo "       arg : ${ARG_DESCR}" >&2
		exit 2
	fi
}
set_object() {
	ARG_OBJECT_KEY="$1"
	ARG_OBJECT_KEY_LOWER="$(echo "${ARG_OBJECT_KEY}" | tr '[:upper:]' '[:lower:]')"
	FLAG_OBJECT="true"
	FLAG_ROUTE="false"
	FLAG_ALL="false"
	FLAG_MNTNER="false"
	FLAG_AUTNUM="false"
	FLAG_ASSET="false"
	case "${ARG_OBJECT_KEY_LOWER}" in
		route)
			FLAG_ROUTE="true"
			ARG_OBJECT="route object"
			;;
		route6)
			FLAG_ROUTE="true"
			ARG_OBJECT="route6 object"
			;;
		mntner)
			FLAG_MNTNER="true"
			ARG_OBJECT="mntner object"
			;;
		aut-num)
			FLAG_AUTNUM="true"
			ARG_OBJECT="aut-num object"
			;;
		as-set)
			FLAG_ASSET="true"
			ARG_OBJECT="as-set object"
			;;
		*)
			echo "ERROR: invalid --object '${ARG_OBJECT_KEY}'. Use route, route6, mntner, aut-num, or as-set." >&2
			exit 2
			;;
	esac
}
set_update() {
	FLAG_UPDATE="true"
}
set_name() {
	ARG_NAME="$1"
	FLAG_NAME="true"
}
set_registry() {
	ARG_REGISTER="$1"
	# Normalize (accept JPIRR/jpirr etc.)
	ARG_REGISTER_UPPER="$(echo "${ARG_REGISTER}" | tr '[:lower:]' '[:upper:]')"
	ARG_REGISTER_LOWER="$(echo "${ARG_REGISTER}" | tr '[:upper:]' '[:lower:]')"
	# Keep legacy flags ONLY inside the script
	FLAG_JPIRR="false"
	FLAG_RADB="false"
	FLAG_NTTCOM="false"
	if [ "${ARG_REGISTER_UPPER}" = "JPIRR" ]; then
		FLAG_JPIRR="true"
	elif [ "${ARG_REGISTER_UPPER}" = "RADB" ]; then
		FLAG_RADB="true"
	elif [ "${ARG_REGISTER_UPPER}" = "NTTCOM" ]; then
		FLAG_NTTCOM="true"
	fi
	if [ -z "${ARG_REGISTER}" ]; then
		FLAG_REGISTER="false"
	else
		FLAG_REGISTER="true"
		# Load global defaults for registry profiles first (optional)
		# shellcheck disable=SC1090
		GLOBAL_REGISTRY_PROFILE="${basedir}/settings/registries/common.conf"
		if [ -f "${GLOBAL_REGISTRY_PROFILE}" ]; then
			. "${GLOBAL_REGISTRY_PROFILE}"
		fi
		# Profile-based loading (preferred)
		REGISTRY_PROFILE="${basedir}/settings/registries/${ARG_REGISTER_LOWER}/common.conf"
		if [ -f "${REGISTRY_PROFILE}" ]; then
			# Reset registry-derived values before loading a specific profile.
			IRR_SOURCE=""
			rpsl_origin=""
			rpsl_mnt_by=""
			rpsl_notify=""
			rpsl_admin_c=""
			rpsl_tech_c=""
			rpsl_upd_to=""
			rpsl_remarks=""
			route_origin=""
			route_mnt_by=""
			route_notify=""
			route6_origin=""
			route6_mnt_by=""
			route6_notify=""
			continuation_target_descr_keys=""
			continuation_target_remarks_keys=""
			. "${REGISTRY_PROFILE}"
			# Load credentials if present (kept separate from common.conf)
			REGISTRY_CRED_PROFILE="${basedir}/settings/registries/${ARG_REGISTER_LOWER}/credential.conf"
			if [ -f "${REGISTRY_CRED_PROFILE}" ]; then
				# shellcheck disable=SC1090
				. "${REGISTRY_CRED_PROFILE}"
			fi
			# Normalize registry profile variables into internal names.
			# Preferred common.conf keys:
			#   SOURCE, ORIGIN, MNT_BY, NOTIFY, ADMIN_C, TECH_C, UPD_TO, REMARKS,
			#   CONTINUATION_TARGET_DESCR_KEYS, CONTINUATION_TARGET_REMARKS_KEYS
			IRR_SOURCE="${SOURCE:-${IRR_SOURCE:-}}"
			rpsl_origin="${ORIGIN:-${rpsl_origin:-}}"
			rpsl_mnt_by="${MNT_BY:-${rpsl_mnt_by:-}}"
			rpsl_notify="${NOTIFY:-${rpsl_notify:-}}"
			rpsl_admin_c="${ADMIN_C:-${rpsl_admin_c:-}}"
			rpsl_tech_c="${TECH_C:-${rpsl_tech_c:-}}"
			rpsl_upd_to="${UPD_TO:-${rpsl_upd_to:-}}"
			rpsl_remarks="${REMARKS:-${rpsl_remarks:-}}"

			route_origin="${rpsl_origin:-${route_origin:-}}"
			route_mnt_by="${rpsl_mnt_by:-${route_mnt_by:-}}"
			route_notify="${rpsl_notify:-${route_notify:-}}"
			route6_origin="${rpsl_origin:-${route6_origin:-}}"
			route6_mnt_by="${rpsl_mnt_by:-${route6_mnt_by:-}}"
			route6_notify="${rpsl_notify:-${route6_notify:-}}"

			# Object body extra lines are configured with CONTINUATION_TARGET_*_KEYS.
			continuation_target_descr_keys="${CONTINUATION_TARGET_DESCR_KEYS:-${continuation_target_descr_keys:-}}"
			continuation_target_remarks_keys="${CONTINUATION_TARGET_REMARKS_KEYS:-${continuation_target_remarks_keys:-}}"
			return 0
		fi
		# Backward-compatible: old style registries/<name>.conf
		LEGACY_REGISTRY_PROFILE="${basedir}/settings/registries/${ARG_REGISTER_LOWER}.conf"
		if [ -f "${LEGACY_REGISTRY_PROFILE}" ]; then
			. "${LEGACY_REGISTRY_PROFILE}"
			return 0
		fi
	fi
	echo "ERROR: unknown registry '${ARG_REGISTER}'. Check settings/registries/." >&2
	exit 2
}
set_mail_sender() {
	ARG_SENDER="$1"
	if [ -n "${ARG_SENDER}" ]; then
		FLAG_SENDER="true"
	else
		FLAG_SENDER="false"
	fi
	if [ "${FLAG_SENDER}" = "false" ]; then
		NEED_SENDER="true"
	fi
}
set_mail_smtp_user() {
	ARG_USER="$1"
	if [ -n "${ARG_USER}" ]; then
		FLAG_USER="true"
		smtp_user_address="${ARG_USER}"
	fi
}
set_smtp_no_check() {
	FLAG_SMTP_NO_CHECK="true"
}
set_yes() {
	FLAG_Y="true"
}


build_mail_subject() {
    local body_file="$1"
    local subject_prefix=""
    local subject_date=""
    local object_label=""

    subject_date="$(date '+%Y-%m-%d')"
    object_label="${OBJECT} object"

    # IMPORTANT: use ONLY mail_body mnt-by, never global vars
    if [ -n "${body_file:-}" ] && [ -f "${body_file}" ]; then
        while IFS= read -r __line || [ -n "${__line}" ]; do
            case "${__line}" in
                mnt-by:*)
                    subject_prefix="${__line#*:}"
                    subject_prefix="$(trim_spaces "${subject_prefix}")"
                    break
                    ;;
            esac
        done < "${body_file}"
    fi

    [ -n "${subject_prefix}" ] || subject_prefix="MAINT"

    if [ "${execution_mode}" = "Production" ]; then
        printf '%s %s %s' "${subject_prefix}" "${object_label}" "${subject_date}"
    else
        printf '[TEST %s] %s %s %s' "${ARG_REGISTER_UPPER}" "${subject_prefix}" "${object_label}" "${subject_date}"
    fi
}

function check_whois {
	# add/delete: prefix based
	if [ "${FLAG_ADD}" = "true" ]; then
		query="${ARG_ADD}"
		echo "whois -h ${whois_address} -s ${IRR_SOURCE} ${query}"
		echo
		bash "${basedir}/scripts/whois.sh" --host "${whois_address}" --source "${IRR_SOURCE}" --query "${query}"
		echo
		echo "done."
		return 0
	fi

	if [ "${FLAG_DEL}" = "true" ]; then
		query="${ARG_DEL}"
		echo "whois -h ${whois_address} -s ${IRR_SOURCE} ${query}"
		echo
		bash "${basedir}/scripts/whois.sh" --host "${whois_address}" --source "${IRR_SOURCE}" --query "${query}"
		echo
		echo "done."
		return 0
	fi

	# annual update: origin-based (single query)
	if [ "${FLAG_UPDATE}" = "true" ] && { [ "${OBJECT}" = "route" ] || [ "${OBJECT}" = "route6" ]; }; then
		if [ "${OBJECT}" = "route" ]; then
			query="-- -i origin ${route_origin}"
		else
			query="-- -i origin ${route6_origin}"
		fi
		echo "whois -h ${whois_address} -s ${IRR_SOURCE} ${query}"
		echo
		bash "${basedir}/scripts/whois.sh" --host "${whois_address}" --source "${IRR_SOURCE}" --query "${query}"
		echo
		echo "done."
		return 0
	fi

	return 0
}
count_ini_entries() {
	# Count INI sections (records). Returns 0 if file missing.
	ini="$1"
	[ -f "${ini}" ] || { echo "0"; return 0; }
	# section headers: [xxx]
	grep -E '^[[:space:]]*\[[^]]+\][[:space:]]*$' "${ini}" 2>/dev/null | wc -l | tr -d ' '
}
count_selected_entries() {
	local ini="$1" obj="$2" target_name="$3" count=0 insec=0 primary="" line trimmed key val
	[ -f "${ini}" ] || { echo "0"; return 0; }
	flush_selected_count_record() {
		[ "${insec}" -eq 1 ] || return 0
		[ -n "${primary}" ] || return 0
		if [ -z "${target_name}" ] || [ "${primary}" = "${target_name}" ]; then
			count=$((count+1))
		fi
	}
	while IFS= read -r line || [ -n "${line}" ]; do
		trimmed="$(trim_spaces "${line}")"
		case "${trimmed}" in
			''|'#'*) continue ;;
			\[*\])
				flush_selected_count_record
				insec=1
				primary=""
				continue
				;;
		esac
		[ "${insec}" -eq 1 ] || continue
		case "${trimmed}" in
			*=*)
				key="${trimmed%%=*}"
				val="${trimmed#*=}"
				key="$(normalize_object_ini_key "${key}")"
				val="$(trim_spaces "${val}")"
				case "${obj}:${key}" in
				aut-num:AUT_NUM|as-set:AS_SET|mntner:MNTNER)
					primary="${val}"
					;;
				esac
				;;
		esac
	done < "${ini}"
	flush_selected_count_record
	echo "${count}"
}
display_mode_label() {
	case "${execution_mode}" in
		Dry-run|DryRunSend) echo "Dry-run" ;;
		Check) echo "Check" ;;
		Production) echo "Production" ;;
		*) echo "${execution_mode}" ;;
	esac
}
operation_label() {
	if [ "${FLAG_ADD}" = "true" ]; then echo "ADD"; return 0; fi
	if [ "${FLAG_DEL}" = "true" ]; then echo "DELETE"; return 0; fi
	if [ "${FLAG_UPDATE}" = "true" ]; then
		# route/route6 update is annual update
		if [ "${OBJECT}" = "route" -o "${OBJECT}" = "route6" ]; then
			echo "ANNUAL UPDATE"
		else
			echo "UPDATE"
		fi
		return 0
	fi
	echo "UNKNOWN"
}
print_execution_summary() {
	op="$(operation_label)"
	echo
	echo "Execution Summary"
	echo "----------------------------------------------------"
	echo "Mode        : $(display_mode_label)"
	echo "Registry    : ${ARG_REGISTER_LOWER}"
	echo "Object      : ${OBJECT}"
	echo "Operation   : ${op}"
	echo
	# add/delete targets
	if [ "${FLAG_ADD}" = "true" ]; then
		echo "Add Target"
		echo "  Prefix    : ${ARG_ADD}"
		echo "  Customer  : ${ARG_CUSTOMER}"
		echo
	elif [ "${FLAG_DEL}" = "true" ]; then
		echo "Delete Target"
		echo "  Prefix    : ${ARG_DEL}"
		echo "  Customer  : ${ARG_CUSTOMER}"
		echo
	fi
	# mail routing
	echo "Mail"
	echo "  From : ${from_mail_address}"
	echo "  To   : ${to_mail_address}"
	if [ -n "${cc_mail_address}" ]; then
		echo "  Cc   : ${cc_mail_address}"
	fi
	echo
	# objects file info (if applicable)
	ini_path=""
	ini_entries="0"
	if [ -n "${OBJECT}" ]; then
		ini_path="$(objects_ini_path "${OBJECT}" 2>/dev/null || true)"
	fi
	selected_entries=""
	if [ -n "${ini_path}" ] && [ -f "${ini_path}" ]; then
		ini_entries="$(count_ini_entries "${ini_path}")"
		if [ "${FLAG_UPDATE}" = "true" ] && [ -n "${ARG_NAME:-}" ] && { [ "${OBJECT}" = "aut-num" ] || [ "${OBJECT}" = "as-set" ] || [ "${OBJECT}" = "mntner" ]; }; then
			selected_entries="$(count_selected_entries "${ini_path}" "${OBJECT}" "${ARG_NAME}")"
		fi
	fi
	if [ -n "${ini_path}" ]; then
		echo "Objects File"
		echo "  Path    : ${ini_path}"
		if [ "${FLAG_UPDATE}" = "true" ]; then
			if [ -n "${selected_entries}" ]; then
				echo "  Entries : ${selected_entries} selected / ${ini_entries} total"
			else
				echo "  Entries : ${ini_entries}"
			fi
		fi
		# ini write behavior per mode
		case "${execution_mode}" in
			Check)
				echo "  Action  : NOT modified in this mode"
				;;
			Dry-run|DryRunSend)
				echo "  Action  : NOT modified in this mode"
				;;
			Production)
				# production writes only when add/delete or update normalization
				echo "  Action  : WILL be modified in this mode"
				;;
		esac
		echo
	fi
	# mode-specific notices
	if [ "${execution_mode}" = "Dry-run" ] || [ "${execution_mode}" = "DryRunSend" ]; then
		echo "----------------------------------------------------"
		echo "DRY-RUN MODE NOTICE"
		echo "----------------------------------------------------"
		echo "- This mode WILL send an email."
		echo "- This mode WILL authenticate to the SMTP server."
		echo "- This mode WILL include IRR password in the mail body."
		echo
		echo "- This mode WILL NOT modify:"
		echo "    * IRR registry data"
		echo "    * objects/*.ini files"
		echo
		echo "This is a final verification step before PRODUCTION."
		echo
	fi
}
production_safety_prompt() {
	[ "${MODE}" = "production" ] || return 0
	echo "!!! DANGEROUS OPERATION (PRODUCTION) !!!"
	echo "----------------------------------------------------"
	echo 'Type "PRODUCTION" to continue.'
	echo 'To cancel, press Enter or type anything else.'
	printf "> "
	read confirm_word
	if [ "${confirm_word}" != "PRODUCTION" ]; then
		echo "Canceled."
		exit 2
	fi
}


log_path_execution_summary() { echo "${RUN_DIR}/execution_summary.txt"; }
log_path_mail_body()         { echo "${RUN_DIR}/mail_body.txt"; }
log_path_smtp_session()      { echo "${RUN_DIR}/smtp_session.log"; }
log_path_objects_diff()      { echo "${RUN_DIR}/objects_diff.patch"; }
log_registry_archive_dir() {
	local reg_lc obj
	reg_lc="$(printf '%s' "${IRR_SOURCE:-${ARG_REGISTER_UPPER}}" | tr 'A-Z' 'a-z')"
	obj="${OBJECT:-${ARG_OBJECT_KEY_LOWER}}"
	echo "${basedir}/logs/registry/${reg_lc}/${obj}"
}
archive_registry_logs() {
	local archive_dir ts src dst_name
	archive_dir="$(log_registry_archive_dir)"
	ts="$(basename "${RUN_DIR}")"
	mkdir -p "${archive_dir}" 2>/dev/null || true
	for src in "${RUN_DIR}/mail.txt" "${RUN_DIR}/mail_body.txt" "${RUN_DIR}/smtp_session.log"; do
		[ -f "${src}" ] || continue
		dst_name="${ts}_$(basename "${src}")"
		cp "${src}" "${archive_dir}/${dst_name}" 2>/dev/null || true
	done
}

mail_send_summary() {
	# $1 result string
	local result="$1"
	echo
	echo "Mail Send Summary"
	echo "----------------------------------------------------"
	echo "Mode   : $(display_mode_label)"
	echo "From   : ${from_mail_address}"
	echo "To     : ${to_mail_address}"
	if [ -n "${cc_mail_address}" ]; then
		echo "Cc     : ${cc_mail_address}"
	fi
	echo "Result : ${result}"
	echo "----------------------------------------------------"
	echo
}
mail_send_detail_path() {
	log_path_smtp_session
}

mail_send_with_logging_send_smtp_mail() {
    # $1: SMTP session file (mail.txt)
    local session_file="$1"
    local logf
    logf="$(mail_send_detail_path)"
    : > "${logf}"

if send_mail_send_session_file "${session_file}" >"${logf}" 2>&1; then
	if grep -Eq '^(4|5)[0-9][0-9][ -]' "${logf}"; then
		echo "SMTP session: FAILED" >&2
		echo "Detailed SMTP session saved to: ${logf}" >&2
		mail_send_summary "FAILED"
		return 1
	fi

	if grep -Eq '^354[ -]' "${logf}" && grep -Eq '^250[ -]' "${logf}"; then
		echo "SMTP session: completed"
		echo "Detailed SMTP session saved to: ${logf}"
		mail_send_summary "SENT"
		return 0
	fi

	echo "SMTP session: FAILED (incomplete SMTP response)" >&2
	echo "Detailed SMTP session saved to: ${logf}" >&2
	mail_send_summary "FAILED"
	return 1
else
	echo "SMTP session: FAILED" >&2
	echo "Detailed SMTP session saved to: ${logf}" >&2
	mail_send_summary "FAILED"
	return 1
fi
}

send_generated_mail_body_with_logging() {
    local body_file="$1"
    local raw_mail_out=""

    if [ -z "${MAIL_SUBJECT:-}" ]; then
        MAIL_SUBJECT="$(build_mail_subject "${body_file}")"
    fi

    if [ "${SMTP_AUTH}" = "true" ]; then
        ensure_smtp_auth
    fi

    raw_mail_out="${TEMP_DIR:-${RUN_DIR}/temp}/mail.raw.txt"
    mkdir -p "$(dirname "${raw_mail_out}")" 2>/dev/null || true

    generate_and_save_smtp_session_files "${body_file}" "${raw_mail_out}" "${MAIL_OUT}" || return 1
    printf 'Saved: %s\n' "${MAIL_OUT}"
    mail_send_with_logging_send_smtp_mail "${raw_mail_out}"
}

extract_prefixes_from_ini() {
	local file="$1" line key val
	while IFS= read -r line || [ -n "${line}" ]; do
		line="${line%$'
'}"
		case "${line}" in
			prefix=*)
				val="${line#*=}"
				printf '%s
' "${val}"
				;;
		esac
	done < "${file}" | sort -u
}
extract_prefixes_from_whois() {
	local obj="$1" line
	while IFS= read -r line || [ -n "${line}" ]; do
		case "${line}" in
			route:\ *) [ "${obj}" = "route" ] && printf '%s
' "${line#route: }" ;;
			route6:\ *) [ "${obj}" = "route6" ] && printf '%s
' "${line#route6: }" ;;
		esac
	done | sort -u
}
annual_update_consistency_check() {
    [ "${FLAG_UPDATE}" = "true" ] || return 0
    [ "${OBJECT}" = "route" -o "${OBJECT}" = "route6" ] || return 0
	ini="$(objects_ini_path "${OBJECT}")" || return 2
	[ -f "${ini}" ] || { echo "ERROR: objects file not found: ${ini}" >&2; return 2; }
	if [ "${OBJECT}" = "route" ]; then
		query="-- -i origin ${route_origin}"
	else
		query="-- -i origin ${route6_origin}"
	fi
	whois_out="$(bash "${basedir}/scripts/whois.sh" --host "${whois_address}" --source "${IRR_SOURCE}" --query "${query}" || true)"
	ini_set="$(mktemp)"
	whois_set="$(mktemp)"
	printf '%s\n' "${whois_out}" | extract_prefixes_from_whois "${OBJECT}" > "${whois_set}"
	extract_prefixes_from_ini "${ini}" > "${ini_set}"
	missing="$(comm -23 "${ini_set}" "${whois_set}" || true)"
	extra="$(comm -13 "${ini_set}" "${whois_set}" || true)"
	rm -f "${ini_set}" "${whois_set}"
	if [ -n "${missing}" ] || [ -n "${extra}" ]; then
		echo "ERROR: annual update consistency check failed (ini vs whois origin set)." >&2
		if [ -n "${missing}" ]; then
			echo "  Missing in whois (present in ini):" >&2
			printf '%s\n' "${missing}" | sed 's/^/    /' >&2
		fi
		if [ -n "${extra}" ]; then
			echo "  Extra in whois (not in ini):" >&2
			printf '%s\n' "${extra}" | sed 's/^/    /' >&2
		fi
		return 2
	fi
	echo "Consistency check OK: no missing/extra prefixes (ini vs whois origin set)."
	return 0
}


# First, handle long options and runtime flags, then continue with getopts.
#------------------------------------------------------------------------------
# Long option only parsing (legacy short options removed)
#------------------------------------------------------------------------------
# Supported options:
#   --help [--lang en|ja]
#   --registry <name>
#   --object <route|route6|mntner|aut-num|as-set>
#   --mode <check|dry-run|production>
#   --add <prefix> / --delete <prefix> / --customer "<descr>" / --update
#   --name <primary-key>   (manual update for aut-num/as-set)
#   --mail-sender <addr> / --mail-smtp-user <addr>
#   --smtp-no-check
#   --yes
#
# Notes:
# - Any short option (e.g. -R, -u, -r) is rejected.
# - Typos are rejected with guidance:
#     --registory -> --registry
#     --send-mail -> --mail-sender
#------------------------------------------------------------------------------

ARG_LANG="${ARG_LANG:-}"
parse_args_long_only() {
	# reject short options
	for a in "$@"; do
		case "$a" in
			--*) : ;;
			-*)  echo "ERROR: short options are no longer supported. Use --help." >&2; exit 2 ;;
			*)   : ;;
		esac
	done
	while [ $# -gt 0 ]; do
		case "$1" in
			--lang)
				shift
				set_lang "${1:-}"
				shift
				;;
			--registry)
				shift
				set_registry "${1:-}"
				shift
				;;
			--registory)
				echo "ERROR: unknown option: --registory (did you mean --registry?)" >&2
				exit 2
				;;
			--object)
				shift
				set_object "${1:-}"
				shift
				;;
			--mode)
				shift
				MODE="${1:-check}"
				MODE=$(printf "%s" "${MODE}" | tr 'A-Z' 'a-z')
				case "${MODE}" in
					check|dry-run|production)
						;;
					*)
						echo "ERROR: invalid --mode '${MODE}'. Use check, dry-run, or production." >&2
						exit 1
						;;
				esac
				shift
				;;
			--add)
				shift
				set_add "${1:-}"
				shift
				;;
			--delete)
				shift
				set_delete "${1:-}"
				shift
				;;
			--customer)
				shift
				set_customer "${1:-}"
				shift
				;;
			--update)
				set_update
				shift
				;;
			--name)
				shift
				set_name "${1:-}"
				shift
				;;
			--mail-sender|--sender)
				shift
				set_mail_sender "${1:-}"
				shift
				;;
			--send-mail)
				echo "ERROR: unknown option: --send-mail (use --mail-sender)" >&2
				exit 2
				;;
			--mail-smtp-user)
				shift
				set_mail_smtp_user "${1:-}"
				shift
				;;
			--smtp-no-check)
				set_smtp_no_check
				shift
				;;
			--yes)
				set_yes
				shift
				;;
			--no-ini-update)
				NO_INI_UPDATE="true"
				shift
				;;
			--non-interactive)
				NON_INTERACTIVE="true"
				shift
				;;
			--no-smtp-auth)
				SMTP_AUTH="false"
				shift
				;;
			--log-dir)
				shift
				LOG_DIR="${1:-}"
				shift
				;;
			--send-via)
				shift
				SEND_VIA="${1:-auto}"
				shift
				;;
			--)
				shift
				break
				;;
			*)
				echo "ERROR: unknown option: $1 (use --help)" >&2
				exit 2
				;;
		esac
	done
}
# Parse arguments now
parse_args_long_only "$@"
# Apply --mode mapping (check/dry-run/production)
case "${MODE}" in
	check|"")
		FORCE_CHECK="true"
		;;
	dry-run|dryrun)
		FORCE_CHECK="false"
		DRY_RUN_SEND_ADDR="__FROM__"
		DRY_RUN_SEND_SELF="false"
		;;
	production|prod)
		FORCE_CHECK="false"
		DRY_RUN_SEND_ADDR=""
		DRY_RUN_SEND_SELF="false"
		;;
	*)
		echo "ERROR: invalid --mode '${MODE}'. Use check, dry-run, or production." >&2
		exit 2
		;;
esac

if [ -z "${ARG_REGISTER}" ]; then
	echo "ERROR: Please specify the registry with '--registry <name>' (e.g. jpirr, radb, nttcom). Use --help."
	exit 1
elif [ -n "${ARG_REGISTER}" ]; then
        echo
fi
# --------------------------------------------------------------------
# New interface validation (--object ...)
# --------------------------------------------------------------------
if [ "${FLAG_OBJECT}" == "true" ]; then
	# --object is required (already true here) and operations are required per object type.
	if [ "${FLAG_ROUTE}" == "true" ]; then
		# route/route6 require exactly one of add/delete/update
		op_count=0
		[ "${FLAG_ADD}" == "true" ] && op_count=$((op_count+1))
		[ "${FLAG_DEL}" == "true" ] && op_count=$((op_count+1))
		[ "${FLAG_UPDATE}" == "true" ] && op_count=$((op_count+1))
		if [ "${op_count}" -ne 1 ]; then
			echo "ERROR: For --object route/route6, specify exactly one of: --add + --customer, --delete + --customer, or --update." >&2
			exit 2
		fi
		if [ "${FLAG_ADD}" == "true" ] || [ "${FLAG_DEL}" == "true" ]; then
			if [ "${FLAG_CUSTOMER}" != "true" ]; then
				echo "ERROR: --customer is required with --add/--delete." >&2
				exit 2
			fi
		else
			# update: customer must not be provided
			if [ "${FLAG_CUSTOMER}" == "true" ]; then
				echo "ERROR: --customer is not used with --update." >&2
				exit 2
			fi
		fi
	else
		# mntner/aut-num/as-set: require --update only
		if [ "${FLAG_UPDATE}" != "true" ]; then
			echo "ERROR: For --object mntner/aut-num/as-set, --update is required." >&2
			exit 2
		fi
		if [ "${FLAG_ADD}" == "true" ] || [ "${FLAG_DEL}" == "true" ] || [ "${FLAG_CUSTOMER}" == "true" ]; then
			echo "ERROR: --add/--delete/--customer are not valid for this object type." >&2
			exit 2
		fi
		if { [ "${FLAG_AUTNUM}" == "true" ] || [ "${FLAG_ASSET}" == "true" ]; } \
		   && [ "${IRR_CRON:-0}" != "1" ] && [ -z "${OBJECTS_INI_OVERRIDE:-}" ] \
		   && [ -z "${ARG_NAME:-}" ]; then
			echo "ERROR: For manual --object aut-num/as-set update, specify --name <primary-key>." >&2
			exit 2
		fi
	fi
fi
##
## Check Flag Option -r or Option -m Value Null
##
if [ "${FLAG_MNTNER}" == "true" ] || [ "${FLAG_AUTNUM}" == "true" ] || [ "${FLAG_ASSET}" == "true" ]; then
	echo
elif [ "${FLAG_ROUTE}" == "true" ]; then
	##	
	## Check Flag Option -a and Option -c Value Null
	##
	if [ "${FLAG_ADD}" == "true" ]; then
		if [ -z "${ARG_ADD}" ]; then
			echo "ERROR: Please specify the Add IP address range with the '-a' option"
			echo "for example : sh ./irr_update.sh -r v4 -a '203.0.113.3/24' -c 'TEST-NET-3' '<ENTER>'"
			exit 1
		elif [ "${FLAG_ALL}" == "true" ]; then
			echo "ERROR: Please specify the '-r' option Value [ v4 or v6 ]"
			exit 1
		elif [ "${FLAG_CUSTOMER}" == "true" ]; then
			ARG_ADDR="${ARG_ADD}"
			ARG_DESCR="${ARG_CUSTOMER}"
		else
			echo "ERROR: Please specify the Add IP address range with the '-a' option and Customer name with the '-c' option"
			echo "for example : sh ./irr_update.sh -r v4 -a '203.0.113.3/24' -c 'TEST-NET-3' '<ENTER>'"
			exit 1
		fi
	##
	## Check Flag Option -d and Option -c Value Null
	##
	elif [ "${FLAG_DEL}" == "true" ]; then
		if [ -z "${ARG_DEL}" ]; then
                        echo "ERROR: Please specify the Delete IP address range with the '-d' option"
                        echo "for example : sh ./irr_update.sh -r v4 -d '203.0.113.3/24' -c 'TEST-NET-3' '<ENTER>'"
                        exit 1
		elif [ "${FLAG_ALL}" == "true" ]; then
			echo "ERROR: Please specify the '-r' option Value [ v4 or v6 ]"
			exit 1
		elif [ "${FLAG_CUSTOMER}" == "true" ]; then
			ARG_ADDR="${ARG_DEL}"
			ARG_DESCR="${ARG_CUSTOMER}"
		else
			echo "ERROR: Please specify the Delete IP address range with the '-d' option"
			echo "for example : sh ./irr_update.sh -r v4 -d '203.0.113.3/24' -c 'TEST-NET-3' '<ENTER>'"
			exit 1
		fi
	fi	
else
        # Legacy -m/-r requirement should apply ONLY to old interactive route operations.
        # For --update (cron) and non-route objects (aut-num/as-set), skip this check.
        if [ "${FLAG_UPDATE}" = "true" ]; then
                :
        else
                echo "ERROR: Please specify an object with --object (route/route6/mntner/aut-num/as-set) and an operation (--add/--del/--update)." >&2
                exit 1
        fi
fi
##
## Check Flag Option -s Source E-mail Address
##
if [ -z "${ARG_SENDER}" ]; then
	echo "ERROR: Please specify the source email address with the '-s' option"
	echo "for example : sh ./irr_update.sh -s user@example.com '<ENTER>'"
	exit 1
elif [ -n "${ARG_SENDER}" ]; then
	
# Default SMTP AUTH user: if not specified, use From address
from_mail_address="${ARG_SENDER}"
fi
##
## Select execution mode and destination
##
# Priority:
#   1) --dry-run-send <addr>  -> send ONLY to <addr>, no Cc/Bcc
#   2) --dry-run-send-self    -> send ONLY to auth user (if SMTP_AUTH=true && -u provided), else From; no Cc/Bcc

ask_yesno() {
	local prompt="$1"
	local yn

	# cron/non-interactive: auto-YES if --yes was given
	if [ "${NON_INTERACTIVE:-false}" = "true" ]; then
		[ "${FLAG_YES:-false}" = "true" ] && return 0
		return 1
	fi

	# interactive
	while true; do
		read -r -p "${prompt}" yn
		case "${yn}" in
			y|Y) return 0 ;;
			n|N) return 1 ;;
			*) echo "Please answer y or n." ;;
		esac
	done
}

decide_execution_mode_and_recipient() {
    # Sets: execution_mode, from_mail_address, to_mail_address, cc_mail_address
    # New behavior (no legacy compatibility):
    #   --mode check      : no send (to/cc empty)
    #   --mode dry-run    : send to From only, no Cc
    #   --mode production : send to registry (To/cc from registry config)
    #
    # From is always --mail-sender (already validated upstream)
    from_mail_address="${MAIL_SENDER_ADDR}"
    if [ -z "${from_mail_address}" ]; then
        from_mail_address="${ARG_SENDER}"
    fi
    case "${MODE}" in
        check)
            execution_mode="Check"
            to_mail_address=""
            cc_mail_address=""
            ;;
        dry-run)
            execution_mode="Dry-run"
            to_mail_address="${from_mail_address}"
            cc_mail_address=""
            ;;
        production)
            execution_mode="Production"
            to_mail_address="${irr_mail_address}"
            cc_mail_address="${cc_mail_address}"
            ;;
        *)
            echo "ERROR: invalid --mode '${MODE}'. Use check, dry-run, or production." >&2
            exit 2
            ;;
    esac
    return 0
}
# Decide execution mode and final recipient (refactored)
decide_execution_mode_and_recipient

# Normalized object key for internal dispatch
OBJECT="${ARG_OBJECT_KEY_LOWER}"
# Argument validations (normalized ARG_PREFIX/ARG_DESCR)
validate_required_args
# Require credential.conf + IRR_PASSWORD for modes that actually send mail
validate_registry_credentials_required
# Validate required keys in route/route6 ini (cron-like reads)
if [ "${OBJECT}" = "route" ] || [ "${OBJECT}" = "route6" ]; then
	validate_route_ini_required_keys "$(objects_ini_path "${OBJECT}")" "${OBJECT}"
fi
# For delete: ensure ini consistency (exists + descr matches)
validate_delete_consistency_with_ini
init_run_dir
echo "Log directory: ${RUN_DIR}"
TEMP_DIR="${RUN_DIR}/temp"
mkdir -p "${TEMP_DIR}" 2>/dev/null || true
trap_cleanup_temp_v0377() {
	[ -n "${TEMP_DIR:-}" ] && [ -d "${TEMP_DIR}" ] && rm -rf "${TEMP_DIR}" 2>/dev/null || true
}
trap trap_cleanup_temp_v0377 EXIT
echo "----------------------------------------------------"

# execution summary (options/mail/objects visibility)
print_execution_summary

# production safety prompt (requires typing PRODUCTION)
# In non-interactive mode, production is refused unless explicit --yes is provided.

if [ "${execution_mode}" = "Production" ] && [ "${NON_INTERACTIVE}" = "true" ] && [ "${FLAG_YES}" != "true" ]; then
	echo "ERROR: Production mode requires interactive confirmation (or use --yes for batch/cron)."
	exit 2
fi

if [ "${MODE}" = "production" ]; then
	if [ "${NON_INTERACTIVE}" = "true" ] && [ "${FLAG_YES}" != "true" ]; then
		echo "ERROR: Production mode requires interactive confirmation." >&2
		exit 2
	fi
	if [ "${FLAG_YES}" = "true" ]; then
		yn="y"
	else
		annual_update_consistency_check || exit 2
	echo "----------------------------------------------------"
	
	if ! ask_yesno 'Do you want to Continue? (y/n) :'; then
		echo "Script has cancel"
		exit 1
	fi
	fi
elif [ "${NON_INTERACTIVE}" = "true" ] || [ "${FLAG_YES}" = "true" ]; then
	yn="y"
else
	annual_update_consistency_check || exit 2
echo "----------------------------------------------------"
	if ! ask_yesno 'Do you want to Continue? (y/n) :'; then
		echo "Script has cancel"
		echo
		exit 1
	fi
fi
# Production double-confirmation keyword (after y/n)
if [ "${MODE}" = "production" ] && [ "${NON_INTERACTIVE}" != "true" ] && [ "${FLAG_YES}" != "true" ]; then
	echo
	echo "----------------------------------------------------"
	production_safety_prompt
fi
echo

#------------------------------------------------------------------------------
# Check mode: generate artifacts only (no SMTP, no send)
#------------------------------------------------------------------------------

if [ "${execution_mode}" == "Check" ]; then
	echo "[CHECK] No mail will be sent. Generating mail body and whois output..."
	MAIL_BODY_RAW="${TEMP_DIR:-${RUN_DIR}/temp}/mail_body.raw.txt"
	MAIL_BODY="${RUN_DIR}/mail_body.txt"
	WHOIS_BEFORE="${RUN_DIR}/whois_before.txt"
	mkdir -p "$(dirname "${MAIL_BODY_RAW}")" 2>/dev/null || true
	generate_mail_body_to_file "${MAIL_BODY_RAW}" || exit 2
	save_masked_mail_body_log "${MAIL_BODY_RAW}" || exit 2
	# Whois before (best-effort). Output is not required to be stored permanently.
	{
		check_whois
	} > "${WHOIS_BEFORE}" 2>&1
	echo "Saved: ${MAIL_BODY}"
	echo "Saved: ${WHOIS_BEFORE}"
	exit 0
fi
#------------------------------------------------------------------------------
# Dry-run: send to sender only via nc/send_mail.sh
#------------------------------------------------------------------------------

# Execution mode normalization (new)
#   --mode check      : generate artifacts only, do not send (default)
#   --mode dry-run    : send only to From address, never to registry
#   --mode production : send to registry (explicit)

#------------------------------------------------------------------------------
# Ensure credentials are present when required.
#------------------------------------------------------------------------------

if [ "${execution_mode}" = "Dry-run" ]; then
	echo "[DRY-RUN] Mail will be sent to the sender address for final SMTP/auth check."
	# In dry-run, always send to sender and do not CC
	to_mail_address="${from_mail_address}"
	cc_mail_address=""
	MAIL_BODY_TMP="${TEMP_DIR:-${RUN_DIR}/temp}/mail_body.raw.txt"
	MAIL_RAW_OUT="${TEMP_DIR:-${RUN_DIR}/temp}/mail.raw.txt"
	mkdir -p "$(dirname "${MAIL_BODY_TMP}")" 2>/dev/null || true
	generate_mail_body_to_file "${MAIL_BODY_TMP}" || exit 2
	save_masked_mail_body_log "${MAIL_BODY_TMP}" || exit 2
	# Ensure subject exists (legacy code sets it earlier; fall back if empty)
	if [ -z "${MAIL_SUBJECT}" ]; then
		MAIL_SUBJECT="$(build_mail_subject "${MAIL_BODY_TMP}")"
	fi
	# Keep an SMTP transcript for evidence/debug
	ensure_smtp_auth
	mkdir -p "$(dirname "${MAIL_RAW_OUT}")" 2>/dev/null || true
	generate_and_save_smtp_session_files "${MAIL_BODY_TMP}" "${MAIL_RAW_OUT}" "${MAIL_OUT}" || exit 2
	printf 'Saved: %s\n' "${MAIL_OUT}"

	# Always send using nc-based SMTP sender
	mail_send_with_logging_send_smtp_mail "${MAIL_RAW_OUT}" || exit 2
	archive_registry_logs
	exit 0
fi

#------------------------------------------------------------------------------
#                       Mail Script
#------------------------------------------------------------------------------

##
## Authentication SMTP Server
##

# send_mail.sh 用のログ出力先（必須）
log_dir="${RUN_DIR}"
export log_dir
mkdir -p "${RUN_DIR}" || exit 1

# SMTP: move SMTP auth/check logic to scripts/send_mail.sh
# - In dry-run/production: perform internal SMTP pre-check unless --smtp-no-check
# - Then actual mail send happens below (nc/send_mail.sh session)

send_mail_init || exit 1

##
## Update Object
##

should_skip_whois() {
    [ "${SKIP_WHOIS:-}" = "1" ] && return 0
    [ "${IRR_CRON:-}" = "1" ] && return 0
    return 1
}

	echo
	echo "----------------------------------------------------------"
	echo "       ${ARG_OBJECT} Update start.                        "
	echo "----------------------------------------------------------"
	echo
	sleep 2
	echo
	echo
	echo "----------------------------------------------------------"
	echo "       Whois (before)"
	echo "----------------------------------------------------------"
	echo
	if should_skip_whois; then
		echo "Whois check skipped (cron mode)."
	else
		check_whois
	fi
	sleep 2
	echo
	echo
	echo "----------------------------------------------------------"
	echo "       Send E-mail IRR Register start.                    "
	echo "----------------------------------------------------------"
	echo
MAIL_SENT_OK="true"
MAIL_BODY_TMP="${TEMP_DIR:-${RUN_DIR}/temp}/mail_body.raw.txt"
mkdir -p "$(dirname "${MAIL_BODY_TMP}")" 2>/dev/null || true
generate_mail_body_to_file "${MAIL_BODY_TMP}" || MAIL_SENT_OK="false"
if [ "${MAIL_SENT_OK}" = "true" ]; then
	save_masked_mail_body_log "${MAIL_BODY_TMP}" || MAIL_SENT_OK="false"
fi
if [ "${MAIL_SENT_OK}" = "true" ]; then
	send_generated_mail_body_with_logging "${MAIL_BODY_TMP}" || MAIL_SENT_OK="false"
fi
echo
if [ "${MAIL_SENT_OK}" = "true" ]; then
	archive_registry_logs
	echo "Mail submitted. Please check the registry response email."
else
	echo "ERROR: mail submission failed. See logs under: ${RUN_DIR}" >&2
fi
echo
if [ "${MAIL_SENT_OK}" = "true" ]; then
	echo
	echo "---------------------------------------------------------"
	echo "       Whois (after)"
	echo "---------------------------------------------------------"
	echo
	if should_skip_whois; then
		echo "Whois check skipped (cron mode)."
	else
		check_whois
	fi
	sleep 2
	echo
	echo
fi
# Update objects/*.ini only for production add/delete, and only if mail submission succeeded
if [ "${MAIL_SENT_OK}" = "true" ] && [ "${MODE}" = "production" ] && { [ "${FLAG_ADD}" = "true" ] || [ "${FLAG_DEL}" = "true" ] || [ "${FLAG_DELETE}" = "true" ]; }; then
	update_objects_list_production
	# Step7/8: annual update post-send ini update + diff output
fi
	sleep 2
	echo
	echo "----------------------------------------------------------"
	echo "       ${ARG_OBJECT} Update Complete !!                   "
	echo "----------------------------------------------------------"
	echo
## script end
exit 0
