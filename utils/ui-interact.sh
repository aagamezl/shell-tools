# shellcheck shell=bash
# Interactive prompts for scripts that already sourced utils/box-ui.sh.
# Input is read from the controlling terminal. Nothing here exits the process.
#
#   ui_trim <text>                 Print text with surrounding whitespace removed.
#   ui_fit <text> <width>          Print text padded or clipped to width columns.
#   ui_clear                       Clear the terminal when stdout is a terminal.
#   ui_alt_enter / ui_alt_leave    Use the alternate screen, then put it back.
#   ui_term_size                   Set UI_ROWS and UI_COLS from the terminal.
#   ui_fit_width [fallback]        Set WIDTH to the terminal, or fallback if not a tty.
#   ui_read [prompt]               Read one line into REPLY. Return 1 on EOF.
#   ui_read_key                    Read one key into UI_KEY and REPLY.
#   ui_prompt <label> [default]    Read a value into REPLY. Empty input uses default.
#   ui_keybar <text>               Full-width key strip. Call inside an open section.
#   ui_confirm <question> [yes|no] Arrow menu. Return 0 for yes, 1 for no, 2 on cancel.
#   ui_menu <title> <option>...    Arrow menu. UI_INDEX is from 0. q cancels.
#   ui_choose <title> <index> <option>...
#                                  Same as ui_menu with a starting highlight.
#                                  UI_REDRAW, when set, names a function drawn above the menu.
#                                  UI_CHOOSE_LEAD, when set, is a line under the title.

# Callers read these. They are set by the functions below.
# shellcheck disable=SC2034
UI_INDEX=0
UI_ERROR=""
UI_KEY=""
UI_ROWS=24
UI_COLS=80
UI_ALT_ON=0
UI_REDRAW=""
UI_CHOOSE_LEAD=""
UI_STTY_SAVED=""
UI_QUEUED_KEY=""

if [[ -n "${C_RESET:-}" ]]; then
  C_ITALIC=$'\033[3m'
  C_UNDER=$'\033[4m'
  C_MAGENTA=$'\033[35m'
  C_WHITE=$'\033[97m'
  C_BLACK=$'\033[30m'
  C_BG_RED=$'\033[41m'
  C_BG_GREEN=$'\033[42m'
  C_BG_YELLOW=$'\033[43m'
  C_BG_BLUE=$'\033[44m'
  C_BG_MAGENTA=$'\033[45m'
  C_BG_CYAN=$'\033[46m'
  C_BG_GRAY=$'\033[100m'
  C_BG_SELECT=$'\033[48;5;24m'
else
  C_ITALIC=""
  C_UNDER=""
  C_MAGENTA=""
  C_WHITE=""
  C_BLACK=""
  C_BG_RED=""
  C_BG_GREEN=""
  C_BG_YELLOW=""
  C_BG_BLUE=""
  C_BG_MAGENTA=""
  C_BG_CYAN=""
  C_BG_GRAY=""
  C_BG_SELECT=""
fi

ui_trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s\n' "$s"
}

ui_fit() {
  local text="$1"
  local width="$2"
  local len
  if (( width <= 0 )); then
    return 0
  fi
  len=${#text}
  if (( len > width )); then
    if (( width == 1 )); then
      printf '…'
    else
      printf '%s…' "${text:0:$((width - 1))}"
    fi
    return 0
  fi
  printf '%s%*s' "$text" $((width - len)) ""
}

ui_clear() {
  [[ -t 1 && "${TERM:-}" != "dumb" ]] || return 0
  printf '\033[H\033[2J'
}

ui_goto() {
  printf '\033[%s;1H\033[2K' "$1"
}

ui_input_raw_on() {
  [[ -n "${UI_STTY_SAVED:-}" ]] && return 0
  ui_tty_ok || return 0
  UI_STTY_SAVED=$(stty -g </dev/tty 2>/dev/null || true)
  stty -echo -icanon min 1 time 0 </dev/tty 2>/dev/null || true
}

ui_input_raw_off() {
  [[ -n "${UI_STTY_SAVED:-}" ]] || return 0
  stty "$UI_STTY_SAVED" </dev/tty 2>/dev/null || true
  UI_STTY_SAVED=""
}

ui_alt_enter() {
  [[ -t 1 && -n "${C_RESET:-}" ]] || return 0
  printf '\033[?1049h\033[H\033[?25l\033[?7l'
  UI_ALT_ON=1
}

ui_alt_leave() {
  [[ "${UI_ALT_ON:-0}" -eq 1 ]] || return 0
  printf '\033[?25h\033[?7h\033[?1049l'
  UI_ALT_ON=0
}

ui_tty_ok() {
  [[ -r /dev/tty && -w /dev/tty ]]
}

ui_term_size() {
  local size="" rows="" cols=""
  UI_ROWS=24
  UI_COLS=80
  if [[ ! -t 1 ]]; then
    return 0
  fi
  exec 3>&1
  size=$(stty size <&3 2>/dev/null || true)
  exec 3>&-
  rows="${size%% *}"
  cols="${size##* }"
  if [[ "$rows" =~ ^[0-9]+$ ]] && (( rows > 0 )); then
    UI_ROWS=$rows
  fi
  if [[ "$cols" =~ ^[0-9]+$ ]] && (( cols > 0 )); then
    UI_COLS=$cols
  fi
}

ui_fit_width() {
  local fallback="${1:-100}"
  if ! command -v choose_box_width >/dev/null 2>&1; then
    UI_ERROR="Source utils/box-ui.sh before utils/ui-interact.sh."
    return 1
  fi
  ui_term_size
  if [[ -t 1 && "$UI_COLS" -ge 40 ]]; then
    choose_box_width "$UI_COLS"
  else
    choose_box_width "$fallback"
  fi
}

ui_read() {
  local prompt="${1:-}"
  REPLY=""
  if ! ui_tty_ok; then
    UI_ERROR="No terminal is available for input."
    return 1
  fi
  if [[ -n "$prompt" ]]; then
    printf '%s%s%s ' "${C_BOLD:-}" "$prompt" "${C_RESET:-}" >/dev/tty
  fi
  # Line editing needs echo and canonical mode. Put the raw keyboard back after.
  if [[ -n "${UI_STTY_SAVED:-}" ]]; then
    stty "$UI_STTY_SAVED" </dev/tty 2>/dev/null || true
  fi
  if ! IFS= read -r REPLY </dev/tty; then
    printf '\n' >/dev/tty
    if [[ -n "${UI_STTY_SAVED:-}" ]]; then
      stty -echo -icanon min 1 time 0 </dev/tty 2>/dev/null || true
    fi
    UI_ERROR="No input."
    REPLY=""
    return 1
  fi
  if [[ -n "${UI_STTY_SAVED:-}" ]]; then
    stty -echo -icanon min 1 time 0 </dev/tty 2>/dev/null || true
  fi
  return 0
}

# Bytes that follow Escape. bash 3.2 rejects fractional read -t, so the
# wait uses stty time (tenths of a second) instead.
ui_read_byte() {
  local wait_tenth="${1:-0}"
  local piece=""
  stty -echo -icanon min 0 time "$wait_tenth" </dev/tty 2>/dev/null || true
  piece=$(dd bs=1 count=1 </dev/tty 2>/dev/null || true)
  printf '%s' "$piece"
}

ui_read_escape_tail() {
  local saved="" rest="" piece=""
  saved=$(stty -g </dev/tty 2>/dev/null || true)
  # First byte: up to a tenth of a second. Anything after that is already
  # queued, so it must not wait or the next key gets swallowed.
  piece=$(ui_read_byte 1)
  if [[ -n "$piece" ]]; then
    rest="$piece"
    case "$piece" in
      '[')
        while true; do
          piece=$(ui_read_byte 0)
          [[ -n "$piece" ]] || break
          rest="${rest}${piece}"
          case "$piece" in
            [A-Za-z~]) break ;;
          esac
        done
        ;;
      O)
        # Application cursor keys are ESC O A, not ESC [ A.
        piece=$(ui_read_byte 0)
        rest="${rest}${piece}"
        ;;
    esac
  fi
  if [[ -n "$saved" ]]; then
    stty "$saved" </dev/tty 2>/dev/null || true
  fi
  printf '%s' "$rest"
}

ui_key_from_bytes() {
  local seq="$1"
  local last=""
  REPLY="$seq"
  if [[ "$seq" != $'\033'* ]]; then
    case "$seq" in
      $'\n'|$'\r'|' ') UI_KEY=enter ;;
      *) UI_KEY="$seq" ;;
    esac
    return 0
  fi
  if [[ "$seq" == $'\033' ]]; then
    UI_KEY=esc
    return 0
  fi
  last="${seq: -1}"
  case "$last" in
    A) UI_KEY=up ;;
    B) UI_KEY=down ;;
    C) UI_KEY=right ;;
    D) UI_KEY=left ;;
    H) UI_KEY=home ;;
    F) UI_KEY=end ;;
    '~')
      case "$seq" in
        *'5~') UI_KEY=pageup ;;
        *'6~') UI_KEY=pagedown ;;
        *'1~'|*7~) UI_KEY=home ;;
        *'4~'|*8~) UI_KEY=end ;;
        *) UI_KEY=esc ;;
      esac
      ;;
    *) UI_KEY=esc ;;
  esac
}

ui_read_key() {
  local k=""
  UI_KEY=""
  REPLY=""
  if ! ui_tty_ok; then
    UI_ERROR="No terminal is available for input."
    return 1
  fi
  if ! IFS= read -rsn1 k </dev/tty; then
    UI_ERROR="No input."
    return 1
  fi
  # Enter is the line delimiter, so read stores it as an empty string.
  if [[ -z "$k" ]]; then
    UI_KEY=enter
    REPLY=""
    return 0
  fi
  if [[ "$k" == $'\033' ]]; then
    ui_key_from_bytes $'\033'"$(ui_read_escape_tail)"
  else
    ui_key_from_bytes "$k"
  fi
  return 0
}

ui_read_key_nowait() {
  local saved="" k=""
  UI_KEY=""
  REPLY=""
  if ! ui_tty_ok; then
    return 1
  fi
  saved=$(stty -g </dev/tty 2>/dev/null || true)
  k=$(ui_read_byte 0)
  if [[ -n "$saved" ]]; then
    stty "$saved" </dev/tty 2>/dev/null || true
  fi
  [[ -n "$k" ]] || return 1
  if [[ "$k" == $'\033' ]]; then
    ui_key_from_bytes $'\033'"$(ui_read_escape_tail)"
  else
    ui_key_from_bytes "$k"
  fi
  return 0
}

ui_prompt() {
  local label="$1"
  local default="${2:-}"
  local shown="$label"
  if [[ -n "$default" ]]; then
    shown="${label} [${default}]"
  fi
  ui_read "$shown" || return 1
  REPLY="$(ui_trim "$REPLY")"
  if [[ "$REPLY" == "" ]]; then
    REPLY="$default"
  fi
  return 0
}

ui_keybar() {
  local text="$1"
  local inner=$((WIDTH - 4))
  local fitted
  if (( inner < 1 )); then
    return 0
  fi
  if ! command -v box_vis_row >/dev/null 2>&1; then
    printf '%s\n' "$text" >/dev/tty
    return 0
  fi
  fitted="$(ui_fit " ${text}" "$inner")"
  box_vis_row "$inner" "${C_BG_GRAY}${C_WHITE}${C_BOLD}${fitted}${C_RESET}"
}

ui_choose_style() {
  local label="$1"
  local on="$2"
  case "$label" in
    Yes*|*"SIGKILL"*)
      if (( on )); then
        printf '%s' "${C_BG_RED}${C_WHITE}${C_BOLD}"
      else
        printf '%s' "${C_RED}${C_BOLD}"
      fi
      ;;
    No*|Leave*)
      if (( on )); then
        printf '%s' "${C_BG_GREEN}${C_BLACK}${C_BOLD}"
      else
        printf '%s' "${C_GREEN}${C_BOLD}"
      fi
      ;;
    *)
      if (( on )); then
        printf '%s' "${C_BG_SELECT}${C_WHITE}${C_BOLD}"
      else
        printf '%s' ""
      fi
      ;;
  esac
}

ui_choose_pick() {
  local want="$1"
  shift
  local -a options=("$@")
  local i=0
  local count="${#options[@]}"
  while [[ "$i" -lt "$count" ]]; do
    # $want is a glob such as Yes* or *SIGKILL*, so it must stay unquoted.
    # shellcheck disable=SC2254
    case "${options[$i]}" in
      $want)
        UI_INDEX=$i
        REPLY="${options[$i]}"
        return 0
        ;;
    esac
    i=$((i + 1))
  done
  return 1
}

ui_choose() {
  local title="$1"
  local current="$2"
  shift 2
  local -a options=("$@")
  local count="${#options[@]}"
  local redraw="${UI_REDRAW:-}"
  local lead="${UI_CHOOSE_LEAD:-}"
  local i=0
  local inner style mark label fitted
  UI_REDRAW=""
  UI_CHOOSE_LEAD=""
  if [[ "$count" -lt 1 ]]; then
    UI_ERROR="ui_choose needs at least one option."
    return 1
  fi
  if ! command -v section_open >/dev/null 2>&1; then
    UI_ERROR="Source utils/box-ui.sh before utils/ui-interact.sh."
    return 1
  fi
  if [[ ! "$current" =~ ^[0-9]+$ ]] || (( current < 0 || current >= count )); then
    current=0
  fi
  while true; do
    ui_clear
    if [[ -n "$redraw" ]]; then
      "$redraw"
    fi
    section_open "$title" "${C_YELLOW:-}"
    if [[ -n "$lead" ]]; then
      box_row "${C_BOLD:-}" "$(ui_fit "$lead" $((WIDTH - 4)))" "$BORDER"
      box_blank "$BORDER"
    fi
    i=0
    inner=$((WIDTH - 4))
    while [[ "$i" -lt "$count" ]]; do
      if (( i == current )); then
        mark="▶"
        style="$(ui_choose_style "${options[$i]}" 1)"
      else
        mark=" "
        style="$(ui_choose_style "${options[$i]}" 0)"
      fi
      label="$(printf '%s  %s' "$mark" "${options[$i]}")"
      fitted="$(ui_fit "$label" "$inner")"
      box_vis_row "$inner" "${style}${fitted}${C_RESET}"
      i=$((i + 1))
    done
    box_blank "$BORDER"
    ui_keybar "↑↓ move    enter choose    y/n jump    q cancel"
    section_close
    ui_read_key || return 2
    case "$UI_KEY" in
      up|k)
        current=$((current - 1))
        (( current < 0 )) && current=$((count - 1))
        ;;
      down|j)
        current=$((current + 1))
        (( current >= count )) && current=0
        ;;
      home|g) current=0 ;;
      end|G) current=$((count - 1)) ;;
      enter)
        UI_INDEX=$current
        REPLY="${options[$current]}"
        return 0
        ;;
      q|Q|esc)
        UI_ERROR="Cancelled."
        return 1
        ;;
      y|Y)
        ui_choose_pick 'Yes*' "${options[@]}" && return 0
        ui_choose_pick '*SIGKILL*' "${options[@]}" && return 0
        ;;
      n|N)
        ui_choose_pick 'No*' "${options[@]}" && return 0
        ui_choose_pick 'Leave*' "${options[@]}" && return 0
        ;;
      *)
        if [[ "$UI_KEY" =~ ^[0-9]$ ]] && (( 10#$UI_KEY >= 1 && 10#$UI_KEY <= count )); then
          UI_INDEX=$((10#$UI_KEY - 1))
          REPLY="${options[$UI_INDEX]}"
          return 0
        fi
        ;;
    esac
  done
}

ui_confirm() {
  local question="$1"
  local default="${2:-no}"
  local start=1
  if [[ "$default" == "yes" ]]; then
    start=0
  fi
  UI_CHOOSE_LEAD="$question"
  if ! ui_choose "Confirm" "$start" "Yes" "No"; then
    return 2
  fi
  [[ "$UI_INDEX" -eq 0 ]]
}

ui_menu() {
  local title="$1"
  shift
  ui_choose "$title" 0 "$@"
}
