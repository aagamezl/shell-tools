#!/usr/bin/env bash
# List local TCP and UDP ports and stop the process that holds one of them.
# The default list is TCP listeners and UDP ports with no remote peer.
# --all adds every other socket that has a local port.

set -uo pipefail

resolve_script_dir() {
  local script_path="${BASH_SOURCE[0]}"
  local script_link

  while [[ -L "$script_path" ]]; do
    script_link="$(readlink "$script_path")"
    if [[ "$script_link" == /* ]]; then
      script_path="$script_link"
    else
      script_path="$(cd "$(dirname "$script_path")" && pwd)/${script_link}"
    fi
  done

  cd "$(dirname "$script_path")" && pwd
}

SCRIPT_DIR="$(resolve_script_dir)"
if [[ ! -f "${SCRIPT_DIR}/utils/box-ui.sh" ]]; then
  printf 'Missing %s\n' "${SCRIPT_DIR}/utils/box-ui.sh" >&2
  exit 1
fi
if [[ ! -f "${SCRIPT_DIR}/utils/ui-interact.sh" ]]; then
  printf 'Missing %s\n' "${SCRIPT_DIR}/utils/ui-interact.sh" >&2
  exit 1
fi
# shellcheck source=utils/box-ui.sh
source "${SCRIPT_DIR}/utils/box-ui.sh"
# shellcheck source=utils/ui-interact.sh
source "${SCRIPT_DIR}/utils/ui-interact.sh"

readonly SCRIPT_NAME="port-view"

MODE="listen"
PROTO_FILTER="all"
USER_FILTER=""
LIST_ONLY=0
SHOW_HELP=0
PARSE_ERROR=""
HIDDEN_NOTE=""
NOTICE=""
NOTICE_COLOR=""
STOPPED=0
SEEN=""
SELECTED=0
SCROLL=0
FILTER=""
PAGE=8
COMPACT=0
ME=""
HOLD_PID=""
HOLD_PORT=""
STOP_INDEX=0
TCP_N=0
UDP_N=0
LISTEN_N=0
OPEN_N=0
ESTAB_N=0
EXTRA_STATES=""
VIEW=()
COL_INNER=0
COL_ICON=1
COL_PORT=5
COL_PROTO=5
COL_STATE=11
COL_PID=7
COL_USER=14
COL_ADDR=16
COL_APP=12
ROW_PLAIN=""
ROW_COLOR=""
ROW_BG=""

PORTS=()
PROTOS=()
STATES=()
ADDRS=()
PIDS=()
USERS=()
COMMANDS=()
RAW=()
TMP_FILES=()

PROC_PID=""
PROC_CMD=""
PROC_USER=""
FILE_PROTO=""
FILE_NAME=""
FILE_STATE=""

cleanup() {
  local f
  [[ "${#TMP_FILES[@]}" -eq 0 ]] && return 0
  for f in "${TMP_FILES[@]}"; do
    [[ -n "$f" ]] && rm -f "$f"
  done
  TMP_FILES=()
}

on_exit() {
  ui_input_raw_off
  ui_alt_leave
  cleanup
}
trap on_exit EXIT

die() {
  ui_alt_leave
  finish 1 "$C_RED" "Failed" "$@"
}

usage() {
  section_open "Usage" "$C_YELLOW"
  box_row "$C_BOLD" "${SCRIPT_NAME}" "$BORDER"
  box_row "$C_BOLD" "${SCRIPT_NAME} --all" "$BORDER"
  box_row "$C_BOLD" "${SCRIPT_NAME} --list [--all] [--proto tcp|udp] [--user name]" "$BORDER"
  box_blank "$BORDER"
  box_row "" "Show ports in use and stop the process that holds one." "$BORDER"
  box_row "" "The default list is TCP listeners and bound UDP ports." "$BORDER"
  box_blank "$BORDER"
  box_row "" "  --all              Include established and connected sockets." "$BORDER"
  box_row "" "  --listen           Only listeners and bound UDP ports." "$BORDER"
  box_row "" "  --proto tcp|udp    Limit the list to one protocol." "$BORDER"
  box_row "" "  --user <name>      Limit the list to one user." "$BORDER"
  box_row "" "  --list             Print the list and exit." "$BORDER"
  box_row "" "  -h, --help         Show this help." "$BORDER"
  box_blank "$BORDER"
  box_row "" "Keys in the interactive list:" "$BORDER"
  box_row "" "  ↑ ↓ j k        Move the highlight." "$BORDER"
  box_row "" "  enter          Stop the highlighted process." "$BORDER"
  box_row "" "  r              Refresh from the system." "$BORDER"
  box_row "" "  /              Filter by port, app, user, or address." "$BORDER"
  box_row "" "  esc            Clear the filter." "$BORDER"
  box_row "" "  ?              Show the keys." "$BORDER"
  box_row "" "  q              Quit." "$BORDER"
  box_blank "$BORDER"
  box_row "$C_DIM" "SIGTERM is sent first. SIGKILL is a second choice." "$BORDER"
  box_blank "$BORDER"
  box_row "" "lsof is required." "$BORDER"
  section_close
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help)
        SHOW_HELP=1
        shift
        ;;
      --list)
        LIST_ONLY=1
        shift
        ;;
      --all)
        MODE="all"
        shift
        ;;
      --listen)
        MODE="listen"
        shift
        ;;
      --proto)
        if [[ -z "${2:-}" ]]; then
          PARSE_ERROR="--proto needs tcp, udp, or all."
          return 1
        fi
        case "$2" in
          tcp|udp|all) PROTO_FILTER="$2" ;;
          *)
            PARSE_ERROR="--proto must be tcp, udp, or all."
            return 1
            ;;
        esac
        shift 2
        ;;
      --user)
        if [[ -z "${2:-}" ]]; then
          PARSE_ERROR="--user needs a name."
          return 1
        fi
        USER_FILTER="$2"
        shift 2
        ;;
      *)
        PARSE_ERROR="Unknown argument: $1"
        return 1
        ;;
    esac
  done
  return 0
}

reset_rows() {
  PORTS=()
  PROTOS=()
  STATES=()
  ADDRS=()
  PIDS=()
  USERS=()
  COMMANDS=()
}

split_local() {
  local endpoint="$1"
  local localpart="${endpoint%%->*}"
  END_ADDR=""
  END_PORT=""
  if [[ "$localpart" == \[* ]]; then
    END_ADDR="${localpart#\[}"
    END_ADDR="${END_ADDR%%\]*}"
    END_PORT="${localpart##*:}"
    return 0
  fi
  if [[ "$localpart" == *:* ]]; then
    END_PORT="${localpart##*:}"
    END_ADDR="${localpart%:*}"
    return 0
  fi
  END_ADDR="$localpart"
  END_PORT=""
}

consider_socket() {
  local pid="$1"
  local cmd="$2"
  local user="$3"
  local proto="$4"
  local name="$5"
  local state="$6"
  local key=""

  [[ -n "$pid" && -n "$name" ]] || return 0
  proto="$(printf '%s' "$proto" | tr '[:upper:]' '[:lower:]')"
  [[ "$proto" == "tcp" || "$proto" == "udp" ]] || return 0
  split_local "$name"
  [[ "$END_PORT" =~ ^[0-9]+$ ]] || return 0
  if (( 10#$END_PORT < 1 || 10#$END_PORT > 65535 )); then
    return 0
  fi
  if [[ "$PROTO_FILTER" != "all" && "$proto" != "$PROTO_FILTER" ]]; then
    return 0
  fi
  if [[ -n "$USER_FILTER" && "$user" != "$USER_FILTER" ]]; then
    return 0
  fi
  if [[ "$MODE" == "listen" ]]; then
    case "$proto" in
      tcp) [[ "$state" == "LISTEN" ]] || return 0 ;;
      udp) [[ "$name" != *'->'* ]] || return 0 ;;
      *) return 0 ;;
    esac
  fi
  if [[ -z "$state" ]]; then
    state="OPEN"
  fi
  cmd="${cmd//$'\t'/ }"
  cmd="${cmd//$'\037'/ }"
  user="${user//$'\t'/ }"
  user="${user//$'\037'/ }"
  [[ -n "$cmd" ]] || cmd="?"
  [[ -n "$user" ]] || user="?"
  key=$'\n'"${proto}|${END_PORT}|${END_ADDR}|${pid}|${state}"$'\n'
  case "$SEEN" in
    *"$key"*) return 0 ;;
  esac
  SEEN="${SEEN}${key}"
  RAW+=("$(printf '%05d\037%s\037%s\037%s\037%s\037%s\037%s' \
    "$((10#$END_PORT))" "$proto" "$state" "$END_ADDR" "$pid" "$user" "$cmd")")
}

flush_file() {
  [[ -n "$FILE_NAME" ]] || return 0
  consider_socket "$PROC_PID" "$PROC_CMD" "$PROC_USER" "$FILE_PROTO" "$FILE_NAME" "$FILE_STATE"
  FILE_NAME=""
  FILE_PROTO=""
  FILE_STATE=""
}

ingest_lsof() {
  local line tag val
  PROC_PID=""
  PROC_CMD=""
  PROC_USER=""
  FILE_PROTO=""
  FILE_NAME=""
  FILE_STATE=""
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -n "$line" ]] || continue
    tag="${line:0:1}"
    val="${line:1}"
    case "$tag" in
      p)
        flush_file
        PROC_PID="$val"
        PROC_CMD=""
        PROC_USER=""
        FILE_PROTO=""
        FILE_NAME=""
        FILE_STATE=""
        ;;
      c) PROC_CMD="$val" ;;
      L) PROC_USER="$val" ;;
      f)
        flush_file
        ;;
      P) FILE_PROTO="$val" ;;
      n)
        FILE_NAME="$val"
        FILE_STATE=""
        ;;
      T)
        case "$val" in
          ST=*) FILE_STATE="${val#ST=}" ;;
        esac
        ;;
      *) ;;
    esac
  done
  flush_file
}

apply_sorted() {
  local line port proto state addr pid user cmd
  reset_rows
  [[ "${#RAW[@]}" -gt 0 ]] || return 0
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    IFS=$'\037' read -r port proto state addr pid user cmd <<<"$line"
    port=$((10#${port:-0}))
    PORTS+=("$port")
    PROTOS+=("$proto")
    STATES+=("$state")
    ADDRS+=("$addr")
    PIDS+=("$pid")
    USERS+=("$user")
    COMMANDS+=("$cmd")
  done < <(printf '%s\n' "${RAW[@]}" | LC_ALL=C sort -t $'\037' -k1,1n -k5,5n -k2,2)
}

load_sockets() {
  local out err
  SEEN=$'\n'
  RAW=()
  HIDDEN_NOTE=""
  reset_rows
  command -v lsof >/dev/null 2>&1 || die "lsof is required to list ports."
  out="$(mktemp "${TMPDIR:-/tmp}/port-view.XXXXXX")" || die "Could not create a temporary file."
  TMP_FILES+=("$out")
  err="$(mktemp "${TMPDIR:-/tmp}/port-view.XXXXXX")" || die "Could not create a temporary file."
  TMP_FILES+=("$err")
  lsof -nP -iTCP -iUDP -F pcfLPnT >"$out" 2>"$err" || true
  if [[ -s "$err" ]]; then
    HIDDEN_NOTE="Some processes could not be inspected, so the list may be incomplete."
  fi
  ingest_lsof <"$out"
  apply_sorted
  rm -f "$out" "$err"
  TMP_FILES=()
}


layout_columns() {
  COL_INNER=$((WIDTH - 4))
  if (( COL_INNER < 1 )); then
    COL_INNER=1
  fi
  COL_ICON=1
  COL_PORT=5
  COL_PROTO=5
  COL_STATE=11
  COL_PID=7
  COL_USER=16
  if (( COL_INNER < 120 )); then
    COL_USER=12
  fi
  if (( COL_INNER < 100 )); then
    COL_USER=10
    COL_PID=6
  fi
  local base=$((COL_ICON + COL_PORT + COL_PROTO + COL_STATE + COL_PID + COL_USER))
  local rest=$((COL_INNER - base - 6))
  COL_ADDR=0
  COL_APP=$rest
  if (( rest >= 24 )); then
    COL_ADDR=$(((rest - 1) / 3))
    if (( COL_ADDR < 12 )); then
      COL_ADDR=12
    fi
    COL_APP=$((rest - 1 - COL_ADDR))
    if (( COL_APP < 8 )); then
      COL_APP=8
      COL_ADDR=$((rest - 1 - COL_APP))
    fi
    if (( COL_ADDR < 8 )); then
      COL_ADDR=0
      COL_APP=$rest
    fi
  fi
  if (( COL_APP < 1 )); then
    COL_APP=1
  fi
}

begin_row() {
  ROW_PLAIN=""
  ROW_COLOR=""
  if [[ "$1" == "1" && -n "$C_BG_SELECT" ]]; then
    ROW_BG="${C_BG_SELECT}${C_WHITE}"
  else
    ROW_BG=""
  fi
}

add_field() {
  local text="$1"
  local width="$2"
  local style="$3"
  local fitted
  if (( width <= 0 )); then
    return 0
  fi
  fitted="$(ui_fit "$text" "$width")"
  ROW_PLAIN="${ROW_PLAIN}${fitted}"
  if [[ -n "$ROW_BG" ]]; then
    ROW_COLOR="${ROW_COLOR}${C_RESET}${ROW_BG}${style}${fitted}"
  else
    ROW_COLOR="${ROW_COLOR}${style}${fitted}${C_RESET}"
  fi
}

add_gap() {
  add_field " " 1 ""
}

end_row() {
  local len=${#ROW_PLAIN}
  local gap
  if (( len < COL_INNER )); then
    gap=$((COL_INNER - len))
    ROW_PLAIN="${ROW_PLAIN}$(printf '%*s' "$gap" "")"
    ROW_COLOR="${ROW_COLOR}$(printf '%*s' "$gap" "")"
  fi
  ROW_COLOR="${ROW_COLOR}${C_RESET}"
  box_vis_row "${#ROW_PLAIN}" "$ROW_COLOR"
}

state_icon() {
  case "$1" in
    LISTEN) printf '%s' "●" ;;
    ESTABLISHED) printf '%s' "↔" ;;
    OPEN) printf '%s' "○" ;;
    *) printf '%s' "·" ;;
  esac
}

state_style() {
  case "$1" in
    LISTEN) printf '%s' "${C_BG_GREEN}${C_BLACK}${C_BOLD}" ;;
    ESTABLISHED) printf '%s' "${C_BG_BLUE}${C_WHITE}${C_BOLD}" ;;
    OPEN) printf '%s' "${C_BG_YELLOW}${C_BLACK}${C_BOLD}" ;;
    *) printf '%s' "${C_DIM}" ;;
  esac
}

icon_style() {
  case "$1" in
    LISTEN) printf '%s' "${C_GREEN}${C_BOLD}" ;;
    ESTABLISHED) printf '%s' "${C_BLUE}${C_BOLD}" ;;
    OPEN) printf '%s' "${C_YELLOW}${C_BOLD}" ;;
    *) printf '%s' "${C_DIM}" ;;
  esac
}

proto_style() {
  case "$1" in
    tcp) printf '%s' "${C_CYAN}${C_BOLD}" ;;
    udp) printf '%s' "${C_MAGENTA}${C_BOLD}" ;;
    *) printf '%s' "${C_DIM}" ;;
  esac
}

user_style() {
  local user="$1"
  if [[ "$user" == "$ME" ]]; then
    printf '%s' "${C_BOLD}"
  else
    printf '%s' "${C_ITALIC}${C_YELLOW}"
  fi
}

emit_columns() {
  local on="$1"
  local icon="$2"
  local icon_s="$3"
  local port="$4"
  local port_s="$5"
  local proto="$6"
  local proto_s="$7"
  local state="$8"
  local state_s="$9"
  local pid="${10}"
  local pid_s="${11}"
  local user="${12}"
  local user_s="${13}"
  local addr="${14}"
  local addr_s="${15}"
  local app="${16}"
  local app_s="${17}"
  begin_row "$on"
  add_field "$icon" "$COL_ICON" "$icon_s"
  add_gap
  add_field "$port" "$COL_PORT" "$port_s"
  add_gap
  add_field "$proto" "$COL_PROTO" "$proto_s"
  add_gap
  add_field "$state" "$COL_STATE" "$state_s"
  add_gap
  add_field "$pid" "$COL_PID" "$pid_s"
  add_gap
  add_field "$user" "$COL_USER" "$user_s"
  if (( COL_ADDR > 0 )); then
    add_gap
    add_field "$addr" "$COL_ADDR" "$addr_s"
  fi
  add_gap
  add_field "$app" "$COL_APP" "$app_s"
  end_row
}

head_style() {
  printf '%s' "${C_BOLD}${C_UNDER}${C_CYAN}"
}

paint_header() {
  local addr_label="Address"
  if (( COL_ADDR > 0 && COL_ADDR < 8 )); then
    addr_label="Addr"
  fi
  emit_columns 0 \
    "#" "$(head_style)" \
    "Port" "$(head_style)" \
    "Proto" "$(head_style)" \
    "State" "$(head_style)" \
    "PID" "$(head_style)" \
    "User" "$(head_style)" \
    "$addr_label" "$(head_style)" \
    "App" "$(head_style)"
}

paint_socket() {
  local index="$1"
  local on="$2"
  local mark style pid_s addr_s
  if (( on )); then
    mark="▶"
    style="${C_YELLOW}${C_BOLD}"
    pid_s="${C_BOLD}"
    addr_s="${C_ITALIC}"
  else
    mark="$(state_icon "${STATES[$index]}")"
    style="$(icon_style "${STATES[$index]}")"
    pid_s="${C_DIM}"
    addr_s="${C_ITALIC}${C_DIM}"
  fi
  emit_columns "$on" \
    "$mark" "$style" \
    "${PORTS[$index]}" "${C_BOLD}" \
    "${PROTOS[$index]}" "$(proto_style "${PROTOS[$index]}")" \
    "${STATES[$index]}" "$(state_style "${STATES[$index]}")" \
    "${PIDS[$index]}" "$pid_s" \
    "${USERS[$index]}" "$(user_style "${USERS[$index]}")" \
    "${ADDRS[$index]}" "$addr_s" \
    "${COMMANDS[$index]}" "${C_BOLD}"
}

row_match() {
  local i="$1"
  local q="" blob=""
  [[ -n "$FILTER" ]] || return 0
  q="$(printf '%s' "$FILTER" | tr '[:upper:]' '[:lower:]')"
  blob="$(printf '%s %s %s %s %s %s' \
    "${PORTS[$i]}" "${PROTOS[$i]}" "${STATES[$i]}" \
    "${USERS[$i]}" "${ADDRS[$i]}" "${COMMANDS[$i]}" | tr '[:upper:]' '[:lower:]')"
  case "$blob" in
    *"$q"*) return 0 ;;
  esac
  return 1
}

rebuild_view() {
  local i=0
  local count="${#PIDS[@]}"
  VIEW=()
  TCP_N=0
  UDP_N=0
  LISTEN_N=0
  OPEN_N=0
  ESTAB_N=0
  EXTRA_STATES=""
  while [[ "$i" -lt "$count" ]]; do
    if row_match "$i"; then
      VIEW+=("$i")
      case "${PROTOS[$i]}" in
        tcp) TCP_N=$((TCP_N + 1)) ;;
        udp) UDP_N=$((UDP_N + 1)) ;;
      esac
      case "${STATES[$i]}" in
        LISTEN) LISTEN_N=$((LISTEN_N + 1)) ;;
        OPEN) OPEN_N=$((OPEN_N + 1)) ;;
        ESTABLISHED) ESTAB_N=$((ESTAB_N + 1)) ;;
        *) note_extra_state "${STATES[$i]}" ;;
      esac
    fi
    i=$((i + 1))
  done
  local n="${#VIEW[@]}"
  if (( n == 0 )); then
    SELECTED=0
    SCROLL=0
    return 0
  fi
  if (( SELECTED >= n )); then
    SELECTED=$((n - 1))
  fi
  if (( SELECTED < 0 )); then
    SELECTED=0
  fi
}

capture_hold() {
  local n="${#VIEW[@]}"
  local real
  if (( n == 0 )); then
    return 0
  fi
  real="${VIEW[$SELECTED]}"
  HOLD_PID="${PIDS[$real]}"
  HOLD_PORT="${PORTS[$real]}"
}

restore_hold() {
  local i=0
  local n="${#VIEW[@]}"
  local real
  [[ -n "$HOLD_PID" ]] || return 0
  while [[ "$i" -lt "$n" ]]; do
    real="${VIEW[$i]}"
    if [[ "${PIDS[$real]}" == "$HOLD_PID" && "${PORTS[$real]}" == "$HOLD_PORT" ]]; then
      SELECTED=$i
      return 0
    fi
    i=$((i + 1))
  done
}

refresh_data() {
  capture_hold
  load_sockets
  rebuild_view
  restore_hold
}

apply_filter() {
  capture_hold
  rebuild_view
  restore_hold
}

tune_page() {
  local overhead note_h=0
  if [[ -n "$NOTICE" ]]; then
    note_h=4
  fi
  if (( UI_ROWS < 36 )); then
    COMPACT=1
    overhead=$((14 + note_h))
  else
    COMPACT=0
    overhead=$((20 + note_h))
  fi
  if [[ -n "$HIDDEN_NOTE" ]]; then
    overhead=$((overhead + 1))
  fi
  # Leave the last row unused. A newline there scrolls the whole screen,
  # and the next highlight paints one row too low, leaving the old marker.
  PAGE=$((UI_ROWS - overhead - 1))
  if (( PAGE < 3 )); then
    PAGE=3
  fi
  local n="${#VIEW[@]}"
  if (( n > 0 && PAGE > n )); then
    PAGE=$n
  fi
}

tune_scroll() {
  local n="${#VIEW[@]}"
  if (( n == 0 )); then
    SCROLL=0
    return 0
  fi
  if (( SELECTED < 0 )); then
    SELECTED=0
  fi
  if (( SELECTED >= n )); then
    SELECTED=$((n - 1))
  fi
  if (( SELECTED < SCROLL )); then
    SCROLL=$SELECTED
  fi
  if (( SELECTED >= SCROLL + PAGE )); then
    SCROLL=$((SELECTED - PAGE + 1))
  fi
  if (( SCROLL < 0 )); then
    SCROLL=0
  fi
  if (( SCROLL + PAGE > n )); then
    SCROLL=$((n - PAGE))
    if (( SCROLL < 0 )); then
      SCROLL=0
    fi
  fi
}

note_extra_state() {
  local st="$1"
  local parts=() i name n found=0
  [[ -n "$st" ]] || st="?"
  if [[ -n "$EXTRA_STATES" ]]; then
    IFS='|' read -r -a parts <<<"$EXTRA_STATES"
  fi
  EXTRA_STATES=""
  for ((i = 0; i < ${#parts[@]}; i++)); do
    name="${parts[$i]%%=*}"
    n="${parts[$i]#*=}"
    if [[ "$name" == "$st" ]]; then
      n=$((n + 1))
      found=1
    fi
    if [[ -n "$EXTRA_STATES" ]]; then
      EXTRA_STATES="${EXTRA_STATES}|${name}=${n}"
    else
      EXTRA_STATES="${name}=${n}"
    fi
  done
  if (( found == 0 )); then
    if [[ -n "$EXTRA_STATES" ]]; then
      EXTRA_STATES="${EXTRA_STATES}|${st}=1"
    else
      EXTRA_STATES="${st}=1"
    fi
  fi
}

# Summary chips. STAT_ICON may be empty for the protocol counts.
push_stat() {
  STAT_ICON+=("$1")
  STAT_TEXT+=("$2")
  STAT_STYLE+=("$3")
}

stats_width() {
  local w=0 i
  for ((i = 0; i < ${#STAT_TEXT[@]}; i++)); do
    if (( i > 0 )); then
      w=$((w + 2))
    fi
    if [[ -n "${STAT_ICON[$i]}" ]]; then
      w=$((w + 2))
    fi
    w=$((w + ${#STAT_TEXT[$i]}))
  done
  printf '%s' "$w"
}

fill_stats() {
  local mode="$1"
  local with_extra="$2"
  local with_proto="$3"
  local listen_w="" open_w="" estab_w=""
  local parts=() pair name n
  STAT_ICON=()
  STAT_TEXT=()
  STAT_STYLE=()
  case "$mode" in
    long)
      listen_w="Listening"
      open_w="Open"
      estab_w="Established"
      ;;
    short)
      listen_w="listen"
      open_w="open"
      estab_w="estab"
      ;;
  esac
  if [[ -n "$listen_w" ]]; then
    push_stat "●" "${LISTEN_N} ${listen_w}" "$(icon_style LISTEN)"
    push_stat "○" "${OPEN_N} ${open_w}" "$(icon_style OPEN)"
    push_stat "↔" "${ESTAB_N} ${estab_w}" "$(icon_style ESTABLISHED)"
  else
    push_stat "●" "$LISTEN_N" "$(icon_style LISTEN)"
    push_stat "○" "$OPEN_N" "$(icon_style OPEN)"
    push_stat "↔" "$ESTAB_N" "$(icon_style ESTABLISHED)"
  fi
  if (( with_extra )) && [[ -n "$EXTRA_STATES" ]]; then
    IFS='|' read -r -a parts <<<"$EXTRA_STATES"
    for pair in "${parts[@]}"; do
      name="${pair%%=*}"
      n="${pair#*=}"
      push_stat "·" "${n} ${name}" "${C_DIM}"
    done
  fi
  if (( with_proto )); then
    push_stat "" "tcp ${TCP_N}" "${C_CYAN}${C_BOLD}"
    push_stat "" "udp ${UDP_N}" "${C_MAGENTA}${C_BOLD}"
  fi
}

paint_stats() {
  local i
  for ((i = 0; i < ${#STAT_TEXT[@]}; i++)); do
    if (( i > 0 )); then
      add_field "  " 2 ""
    fi
    if [[ -n "${STAT_ICON[$i]}" ]]; then
      add_field "${STAT_ICON[$i]}" 1 "${STAT_STYLE[$i]}"
      add_gap
    fi
    add_field "${STAT_TEXT[$i]}" "${#STAT_TEXT[$i]}" "${STAT_STYLE[$i]}"
  done
}

paint_summary() {
  local paging="$1"
  local n="${#VIEW[@]}"
  local range="" shown from to room fw used
  local mode extra proto width=0 picked=0
  if (( paging == 1 && n > 0 )); then
    shown=$PAGE
    if (( SCROLL + shown > n )); then
      shown=$((n - SCROLL))
    fi
    if (( shown < 1 )); then
      shown=1
    fi
    from=$((SCROLL + 1))
    to=$((SCROLL + shown))
    range="$(printf '%d–%d of %d' "$from" "$to" "$n")"
  else
    range="$(printf '%d total' "$n")"
  fi
  for mode in long short num; do
    for extra in 1 0; do
      if (( extra == 1 )) && [[ -z "$EXTRA_STATES" ]]; then
        continue
      fi
      for proto in 1 0; do
        fill_stats "$mode" "$extra" "$proto"
        width="$(stats_width)"
        if (( width + 1 + ${#range} <= COL_INNER )); then
          picked=1
          break 3
        fi
      done
    done
  done
  if (( picked == 0 )); then
    fill_stats num 0 0
  fi
  begin_row 0
  paint_stats
  used=${#ROW_PLAIN}
  room=$((COL_INNER - used - ${#range}))
  if [[ -n "$FILTER" && "$room" -gt 6 ]]; then
    fw=$((room - 4))
    if (( fw > 28 )); then
      fw=28
    fi
    add_gap
    add_field "/" 1 "${C_YELLOW}${C_BOLD}"
    add_gap
    add_field "$FILTER" "$fw" "${C_UNDER}${C_ITALIC}${C_YELLOW}"
    used=${#ROW_PLAIN}
    room=$((COL_INNER - used - ${#range}))
  fi
  if (( room >= 1 )); then
    add_field "" "$room" ""
    add_field "$range" "${#range}" "${C_DIM}${C_ITALIC}"
  fi
  end_row
}

banner_subtitle() {
  local text
  if [[ "$MODE" == "all" ]]; then
    text="Every TCP and UDP socket with a local port."
  else
    text="TCP listeners and bound UDP ports."
  fi
  if [[ "$PROTO_FILTER" != "all" ]]; then
    text="${text} ${PROTO_FILTER} only."
  fi
  if [[ -n "$USER_FILTER" ]]; then
    text="${text} User ${USER_FILTER}."
  fi
  printf '%s\n' "$text"
}

show_notice() {
  [[ -n "$NOTICE" ]] || return 0
  section_open "Last action" "$NOTICE_COLOR"
  box_row "$NOTICE_COLOR" "$(ui_fit "$NOTICE" $((WIDTH - 4)))" "$BORDER"
  section_close
}

show_table() {
  local paging="$1"
  local n i real end title
  tune_scroll
  n="${#VIEW[@]}"
  title="Listening sockets"
  if [[ "$MODE" == "all" ]]; then
    title="Sockets"
  fi
  section_open "${title}  ·  ${n}" "$C_BLUE"
  paint_summary "$paging"
  if (( n == 0 )); then
    if [[ -n "$FILTER" ]]; then
      box_row "$C_YELLOW" "$(ui_fit "No sockets match this filter. Press esc to clear it." $((WIDTH - 4)))" "$BORDER"
    else
      box_row "$C_DIM" "$(ui_fit "No matching sockets." $((WIDTH - 4)))" "$BORDER"
    fi
  else
    paint_header
    if (( paging == 1 )); then
      i=$SCROLL
      end=$((SCROLL + PAGE))
      if (( end > n )); then
        end=$n
      fi
      while [[ "$i" -lt "$end" ]]; do
        real="${VIEW[$i]}"
        if (( i == SELECTED )); then
          paint_socket "$real" 1
        else
          paint_socket "$real" 0
        fi
        i=$((i + 1))
      done
    else
      i=0
      while [[ "$i" -lt "$n" ]]; do
        real="${VIEW[$i]}"
        paint_socket "$real" 0
        i=$((i + 1))
      done
    fi
  fi
  if [[ -n "$HIDDEN_NOTE" ]]; then
    box_row "$C_ITALIC" "$(ui_fit "$HIDDEN_NOTE" $((WIDTH - 4)))" "$BORDER"
  fi
  section_close
}

show_detail() {
  local n="${#VIEW[@]}"
  local real pid cmd user state port proto addr title
  local app_w addr_w
  if (( n == 0 )); then
    title="Selected"
  else
    real="${VIEW[$SELECTED]}"
    title="Selected  ·  ${COMMANDS[$real]}"
  fi
  section_open "$title" "$C_CYAN"
  if (( n == 0 )); then
    box_row "$C_DIM" "$(ui_fit "Nothing is selected." $((WIDTH - 4)))" "$BORDER"
    box_blank "$BORDER"
    box_blank "$BORDER"
  else
    real="${VIEW[$SELECTED]}"
    pid="${PIDS[$real]}"
    cmd="${COMMANDS[$real]}"
    user="${USERS[$real]}"
    state="${STATES[$real]}"
    port="${PORTS[$real]}"
    proto="${PROTOS[$real]}"
    addr="${ADDRS[$real]}"
    app_w=$((COL_INNER - 16 - COL_USER))
    if (( app_w < 1 )); then
      app_w=1
    fi
    begin_row 0
    add_field "▶" 1 "${C_YELLOW}${C_BOLD}"
    add_gap
    add_field "$cmd" "$app_w" "${C_BOLD}"
    add_gap
    add_field "pid ${pid}" 12 "${C_DIM}"
    add_gap
    add_field "$user" "$COL_USER" "$(user_style "$user")"
    end_row
    addr_w=$((COL_INNER - 16 - COL_STATE))
    if (( addr_w < 1 )); then
      addr_w=1
    fi
    begin_row 0
    add_field "$(state_icon "$state")" 1 "$(icon_style "$state")"
    add_gap
    add_field "${port}/${proto}" 12 "${C_BOLD}$(proto_style "$proto")"
    add_gap
    add_field "$state" "$COL_STATE" "$(state_style "$state")"
    add_gap
    add_field "$addr" "$addr_w" "${C_ITALIC}"
    end_row
    if [[ "$user" != "$ME" ]]; then
      begin_row 0
      ROW_BG="${C_BG_YELLOW}${C_BLACK}"
      add_field "!" 1 "${C_BOLD}"
      add_gap
      add_field "Owned by ${user}. Stopping it may be refused." $((COL_INNER - 2)) "${C_BOLD}"
      end_row
    else
      begin_row 0
      add_field "$(sibling_text "$pid" "$real")" "$COL_INNER" "${C_DIM}${C_ITALIC}"
      end_row
    fi
  fi
  section_close
}

sibling_text() {
  local pid="$1"
  local skip="$2"
  local i=0
  local out=""
  local n=0
  local piece
  while [[ "$i" -lt "${#PIDS[@]}" ]]; do
    if [[ "${PIDS[$i]}" == "$pid" && "$i" != "$skip" ]]; then
      piece="$(state_icon "${STATES[$i]}") ${PROTOS[$i]} ${PORTS[$i]}"
      if [[ -n "$out" ]]; then
        out="${out}    ${piece}"
      else
        out="$piece"
      fi
      n=$((n + 1))
      if (( n >= 4 )); then
        out="${out}  …"
        break
      fi
    fi
    i=$((i + 1))
  done
  if [[ -z "$out" ]]; then
    printf '%s' "Only this socket."
  else
    printf '%s' "Also ${out}"
  fi
}

add_key() {
  local key="$1"
  local label="$2"
  local need=$((${#key} + ${#label}))
  if (( ${#ROW_PLAIN} + need > COL_INNER )); then
    return 1
  fi
  add_field "$key" "${#key}" "${C_BOLD}${C_UNDER}"
  add_field "$label" "${#label}" ""
}

show_keys() {
  local title="Keys"
  local n="${#VIEW[@]}"
  local real
  if (( COMPACT )) && (( n > 0 )); then
    real="${VIEW[$SELECTED]}"
    title="▶ ${COMMANDS[$real]}  ${PORTS[$real]}/${PROTOS[$real]}"
  fi
  section_open "$title" "$C_CYAN"
  begin_row 0
  ROW_BG="${C_BG_GRAY}${C_WHITE}"
  add_key " ↑↓ " "move  "
  add_key "⏎ " "stop  " || true
  add_key "r " "refresh  " || true
  add_key "/ " "filter  " || true
  add_key "? " "help  " || true
  add_key "q " "quit" || true
  end_row
  section_close
}

show_legend() {
  section_open "Marks" "$C_DIM"
  begin_row 0
  add_field "●" 1 "${C_GREEN}${C_BOLD}"
  add_gap
  add_field "LISTEN" 8 "${C_BOLD}"
  add_gap
  add_field "○" 1 "${C_YELLOW}${C_BOLD}"
  add_gap
  add_field "OPEN" 6 "${C_BOLD}"
  add_gap
  add_field "↔" 1 "${C_BLUE}${C_BOLD}"
  add_gap
  add_field "ESTABLISHED" 12 "${C_BOLD}"
  end_row
  section_close
}

show_stop_plan() {
  local index="$1"
  local pid="${PIDS[$index]}"
  local i=0
  local shown=0
  local user_w=$((COL_INNER - 26))
  if (( user_w < 1 )); then
    user_w=1
  fi
  section_open "Stop  ·  ${COMMANDS[$index]}" "$C_YELLOW"
  begin_row 0
  add_field "App" 8 "${C_DIM}${C_UNDER}"
  add_field "${COMMANDS[$index]}" $((COL_INNER - 8)) "${C_BOLD}"
  end_row
  begin_row 0
  add_field "PID" 8 "${C_DIM}${C_UNDER}"
  add_field "$pid" 10 "${C_BOLD}"
  add_field "User" 8 "${C_DIM}${C_UNDER}"
  add_field "${USERS[$index]}" "$user_w" "$(user_style "${USERS[$index]}")"
  end_row
  box_blank "$BORDER"
  box_row "$C_UNDER" "$(ui_fit "Sockets that close with this process" $((WIDTH - 4)))" "$BORDER"
  while [[ "$i" -lt "${#PIDS[@]}" ]]; do
    if [[ "${PIDS[$i]}" == "$pid" ]]; then
      paint_socket "$i" 0
      shown=$((shown + 1))
      if (( shown >= 6 )); then
        box_row "$C_DIM" "$(ui_fit "…" $((WIDTH - 4)))" "$BORDER"
        break
      fi
    fi
    i=$((i + 1))
  done
  box_blank "$BORDER"
  box_row "$C_ITALIC" "$(ui_fit "SIGTERM is sent first." $((WIDTH - 4)))" "$BORDER"
  if [[ "${USERS[$index]}" != "$ME" ]]; then
    begin_row 0
    ROW_BG="${C_BG_YELLOW}${C_BLACK}"
    add_field "!" 1 "${C_BOLD}"
    add_gap
    add_field "This process belongs to ${USERS[$index]}." $((COL_INNER - 2)) "${C_BOLD}"
    end_row
  fi
  section_close
}

draw_stop_context() {
  ui_fit_width
  layout_columns
  box_banner "$SCRIPT_NAME" "Confirm before the process is signaled."
  show_stop_plan "$STOP_INDEX"
}

draw_still_context() {
  ui_fit_width
  layout_columns
  box_banner "$SCRIPT_NAME" "The process ignored SIGTERM."
  show_stop_plan "$STOP_INDEX"
  section_open "Still running" "$C_RED"
  box_row "$C_RED" "$(ui_fit "✗  SIGTERM did not stop it." $((WIDTH - 4)))" "$BORDER"
  section_close
}

stop_selected() {
  local index="$1"
  local pid="${PIDS[$index]}"
  local port="${PORTS[$index]}"
  local cmd="${COMMANDS[$index]}"
  local err=""
  local n=0
  DID_SIGNAL=0
  if [[ "$pid" -le 1 || "$pid" -eq $$ ]]; then
    NOTICE_COLOR="$C_YELLOW"
    NOTICE="!  Refusing to signal pid ${pid}."
    return 0
  fi
  STOP_INDEX=$index
  UI_REDRAW=draw_stop_context
  UI_CHOOSE_LEAD="Stop ${cmd} (pid ${pid}) on port ${port}?"
  if ! ui_choose "Send SIGTERM?" 1 "Yes, stop ${cmd}" "No, leave it running"; then
    return 0
  fi
  if [[ "$UI_INDEX" -ne 0 ]]; then
    return 0
  fi
  if ! lsof -nP -a -p "$pid" -i ":${port}" >/dev/null 2>&1; then
    NOTICE_COLOR="$C_YELLOW"
    NOTICE="!  pid ${pid} is no longer using port ${port}."
    return 0
  fi
  DID_SIGNAL=1
  err="$(kill -TERM "$pid" 2>&1)" || {
    NOTICE_COLOR="$C_RED"
    if [[ -n "$err" ]]; then
      NOTICE="✗  Could not signal pid ${pid}. ${err}"
    else
      NOTICE="✗  Could not signal pid ${pid}."
    fi
    return 0
  }
  while [[ "$n" -lt 5 ]]; do
    if ! kill -0 "$pid" 2>/dev/null; then
      STOPPED=$((STOPPED + 1))
      NOTICE_COLOR="$C_GREEN"
      NOTICE="✓  Stopped ${cmd} (pid ${pid})."
      return 0
    fi
    sleep 0.2
    n=$((n + 1))
  done
  UI_REDRAW=draw_still_context
  UI_CHOOSE_LEAD="${cmd} is still running."
  if ! ui_choose "Still running" 1 "Send SIGKILL" "Leave it running"; then
    NOTICE_COLOR="$C_YELLOW"
    NOTICE="○  Left ${cmd} running (pid ${pid})."
    return 0
  fi
  if [[ "$UI_INDEX" -ne 0 ]]; then
    NOTICE_COLOR="$C_YELLOW"
    NOTICE="○  Left ${cmd} running (pid ${pid})."
    return 0
  fi
  err="$(kill -KILL "$pid" 2>&1)" || {
    NOTICE_COLOR="$C_RED"
    if [[ -n "$err" ]]; then
      NOTICE="✗  Could not kill pid ${pid}. ${err}"
    else
      NOTICE="✗  Could not kill pid ${pid}."
    fi
    return 0
  }
  STOPPED=$((STOPPED + 1))
  NOTICE_COLOR="$C_GREEN"
  NOTICE="✓  Killed ${cmd} (pid ${pid})."
}

show_help() {
  ui_clear
  ui_fit_width
  box_banner "$SCRIPT_NAME" "Move, filter, and stop."
  section_open "Keys" "$C_CYAN"
  box_row "" "$(ui_fit "  ↑  k          Previous socket" $((WIDTH - 4)))" "$BORDER"
  box_row "" "$(ui_fit "  ↓  j          Next socket" $((WIDTH - 4)))" "$BORDER"
  box_row "" "$(ui_fit "  PgUp PgDn     Move a page" $((WIDTH - 4)))" "$BORDER"
  box_row "" "$(ui_fit "  g  G          First and last" $((WIDTH - 4)))" "$BORDER"
  box_row "$C_BOLD" "$(ui_fit "  enter         Stop the highlighted process" $((WIDTH - 4)))" "$BORDER"
  box_row "" "$(ui_fit "  r             Refresh from the system" $((WIDTH - 4)))" "$BORDER"
  box_row "" "$(ui_fit "  /             Filter by port, app, user, or address" $((WIDTH - 4)))" "$BORDER"
  box_row "" "$(ui_fit "  esc           Clear the filter" $((WIDTH - 4)))" "$BORDER"
  box_row "" "$(ui_fit "  ?             Show this help" $((WIDTH - 4)))" "$BORDER"
  box_row "" "$(ui_fit "  q             Quit" $((WIDTH - 4)))" "$BORDER"
  box_blank "$BORDER"
  box_row "$C_ITALIC" "$(ui_fit "SIGTERM is sent first. SIGKILL is offered only if it stays up." $((WIDTH - 4)))" "$BORDER"
  box_blank "$BORDER"
  ui_keybar "any other key returns to the list"
  section_close
  ui_read_key || true
}

move_sel() {
  local delta="$1"
  local n="${#VIEW[@]}"
  if (( n == 0 )); then
    return 0
  fi
  SELECTED=$((SELECTED + delta))
  if (( SELECTED < 0 )); then
    SELECTED=0
  fi
  if (( SELECTED >= n )); then
    SELECTED=$((n - 1))
  fi
}

# Screen rows of the pieces redrawn when the highlight moves.
# Banner is 5 lines. A notice is 4. The table then has a top, a summary,
# and a header before the first socket.
place_lines() {
  local notice_h=0
  local hidden_h=0
  if [[ -n "$NOTICE" ]]; then
    notice_h=4
  fi
  if [[ -n "$HIDDEN_NOTE" ]]; then
    hidden_h=1
  fi
  SOCK_ORIGIN=$((5 + notice_h + 4))
  SUMMARY_LINE=$((SOCK_ORIGIN - 2))
  DETAIL_ORIGIN=$((SOCK_ORIGIN + PAGE + hidden_h + 2))
  if (( COMPACT )); then
    KEY_ORIGIN=$DETAIL_ORIGIN
  else
    KEY_ORIGIN=$((DETAIL_ORIGIN + 6))
  fi
}

paint_socket_line() {
  local view_index="$1"
  local on="$2"
  local line=$((SOCK_ORIGIN + view_index - SCROLL))
  ui_goto "$line"
  BORDER="$C_BLUE"
  paint_socket "${VIEW[$view_index]}" "$on"
}

repaint_focus() {
  SECTION_OPEN=0
  if (( COMPACT )); then
    local real="${VIEW[$SELECTED]}"
    ui_goto "$KEY_ORIGIN"
    BORDER="$C_CYAN"
    box_top "▶ ${COMMANDS[$real]}  ${PORTS[$real]}/${PROTOS[$real]}" "$BORDER"
    return 0
  fi
  ui_goto "$DETAIL_ORIGIN"
  show_detail
}

repaint_list() {
  local i="$SCROLL"
  local end=$((SCROLL + PAGE))
  local n="${#VIEW[@]}"
  local real
  if (( end > n )); then
    end=$n
  fi
  ui_goto "$SUMMARY_LINE"
  BORDER="$C_BLUE"
  paint_summary 1
  paint_header
  while [[ "$i" -lt "$end" ]]; do
    real="${VIEW[$i]}"
    if (( i == SELECTED )); then
      paint_socket "$real" 1
    else
      paint_socket "$real" 0
    fi
    i=$((i + 1))
  done
  repaint_focus
}

reveal_move() {
  local prev="$1"
  local prev_scroll="$2"
  tune_scroll
  if (( SELECTED == prev && SCROLL == prev_scroll )); then
    return 0
  fi
  if (( SCROLL != prev_scroll )); then
    repaint_list
    return 0
  fi
  paint_socket_line "$prev" 0
  paint_socket_line "$SELECTED" 1
  repaint_focus
}

apply_move_key() {
  local n="${#VIEW[@]}"
  case "$1" in
    up|k) move_sel -1 ;;
    down|j) move_sel 1 ;;
    pageup) move_sel "-${PAGE}" ;;
    pagedown) move_sel "$PAGE" ;;
    home|g) SELECTED=0 ;;
    end|G)
      if (( n > 0 )); then
        SELECTED=$((n - 1))
      fi
      ;;
  esac
}

move_key() {
  case "$1" in
    up|k|down|j|pageup|pagedown|home|end|g|G) return 0 ;;
    *) return 1 ;;
  esac
}

nudge() {
  local prev=$SELECTED
  local prev_scroll=$SCROLL
  apply_move_key "$1"
  while ui_read_key_nowait; do
    if ! move_key "$UI_KEY"; then
      UI_QUEUED_KEY="$UI_KEY"
      break
    fi
    apply_move_key "$UI_KEY"
  done
  reveal_move "$prev" "$prev_scroll"
}

draw_screen() {
  box_banner "$SCRIPT_NAME" "$(banner_subtitle)"
  show_notice
  show_table 1
  if (( COMPACT == 0 )); then
    show_detail
  fi
  show_keys
}

quit() {
  ui_alt_leave
  if [[ "$STOPPED" -eq 1 ]]; then
    finish 0 "$C_GREEN" "Done" "✓  Stopped 1 process."
  fi
  if [[ "$STOPPED" -gt 1 ]]; then
    finish 0 "$C_GREEN" "Done" "✓  Stopped ${STOPPED} processes."
  fi
  finish 0 "$C_GREEN" "Done" "Left every process running."
}

run_interactive() {
  local real
  local full=1
  local last_cols=0
  local last_rows=0
  DID_SIGNAL=0
  UI_QUEUED_KEY=""
  ui_alt_enter
  ui_input_raw_on
  refresh_data
  while true; do
    ui_fit_width
    layout_columns
    tune_page
    place_lines
    if (( full || UI_COLS != last_cols || UI_ROWS != last_rows )); then
      ui_clear
      draw_screen
      full=0
      last_cols=$UI_COLS
      last_rows=$UI_ROWS
    fi
    if [[ -n "$UI_QUEUED_KEY" ]]; then
      UI_KEY="$UI_QUEUED_KEY"
      UI_QUEUED_KEY=""
    else
      ui_read_key || quit
    fi
    case "$UI_KEY" in
      q|Q)
        quit
        ;;
      r|R)
        NOTICE=""
        refresh_data
        full=1
        ;;
      /)
        if ui_read "Filter (empty clears) [${FILTER}]"; then
          FILTER="$(ui_trim "$REPLY")"
          apply_filter
        fi
        full=1
        ;;
      esc)
        if [[ -n "$FILTER" ]]; then
          FILTER=""
          apply_filter
          full=1
        fi
        ;;
      '?')
        show_help
        full=1
        ;;
      up|k|down|j|pageup|pagedown|home|end|g|G)
        nudge "$UI_KEY"
        ;;
      enter)
        if (( ${#VIEW[@]} > 0 )); then
          real="${VIEW[$SELECTED]}"
          stop_selected "$real"
          if (( DID_SIGNAL )); then
            refresh_data
          fi
        fi
        full=1
        ;;
    esac
  done
}

main() {
  parse_args "$@" || {
    ui_fit_width 100
    box_banner "$SCRIPT_NAME" "Ports in use on this machine."
    usage
    die "$PARSE_ERROR"
  }
  ui_fit_width 100
  if [[ "$SHOW_HELP" -eq 1 ]]; then
    box_banner "$SCRIPT_NAME" "Ports in use on this machine."
    usage
    exit 0
  fi
  if ! command -v lsof >/dev/null 2>&1; then
    box_banner "$SCRIPT_NAME" "Ports in use on this machine."
    die "lsof is required to list ports."
  fi
  ME="$(id -un 2>/dev/null || printf '%s' "?")"
  if [[ "$LIST_ONLY" -eq 1 || ! -t 1 || ! -r /dev/tty || ! -w /dev/tty ]]; then
    refresh_data
    layout_columns
    box_banner "$SCRIPT_NAME" "$(banner_subtitle)"
    show_table 0
    show_legend
    if [[ "$LIST_ONLY" -eq 0 ]]; then
      finish 0 "$C_GREEN" "Listed" \
        "Stopping a process needs a terminal." \
        "Run ${SCRIPT_NAME} from a terminal, or pass --list."
    fi
    exit 0
  fi
  run_interactive
}

main "$@"
