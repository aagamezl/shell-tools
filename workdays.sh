#!/usr/bin/env bash
# Count billable days in a month and draw them on a calendar.
# Monday-Friday is the base. --off subtracts days you did not work.
# --extra adds days you worked outside that, such as a weekend.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ ! -f "${SCRIPT_DIR}/utils/box-ui.sh" ]]; then
  printf 'Missing %s\n' "${SCRIPT_DIR}/utils/box-ui.sh" >&2
  exit 1
fi
# shellcheck source=utils/box-ui.sh
source "${SCRIPT_DIR}/utils/box-ui.sh"

readonly SCRIPT_NAME="workdays"
readonly EXIT_USAGE=1
readonly EXIT_FAILED=3

MONTH=""
YEAR=""
YEAR_DEFAULTED=0
OFF_SPEC=""
EXTRA_SPEC=""
HAS_OFF=0
HAS_EXTRA=0
SHOW_HELP=0
PARSE_TARGET=""
PARSE_LABEL=""

DATE_IMPL=""
MONTH_NAME=""
TOTAL_DAYS=0
FIRST_DOW0=0
WEEKDAYS=0
OFF_COUNT=0
EXTRA_COUNT=0
BILLABLE=0
OFF_SHOWN=0
EXTRA_SHOWN=0
TODAY_DAY=0
CELL_W=0
OFF_LIST=""
EXTRA_LIST=""
OFF_SKIP_LIST=""
EXTRA_SKIP_LIST=""

# Sparse marks. DAY_KIND[day]=weekday|weekend|off|extra
DAY_KIND=()
OFF_DAYS=()
OFF_DOW=()
EXTRA_DAYS=()
EXTRA_DOW=()
OFF_ON=()
EXTRA_ON=()
CELL_LINE=("" "" "" "" "" "" "")

FULL_DOW=(Monday Tuesday Wednesday Thursday Friday Saturday Sunday)
SHORT_DOW=(Mon Tue Wed Thu Fri Sat Sun)
NARROW_DOW=(Mo Tu We Th Fr Sa Su)

# Bold white keeps the day number readable on the colored wash.
BG_WEEKDAY=$'\033[1;97;42m'
BG_EXTRA=$'\033[1;97;46m'
BG_OFF=$'\033[1;97;41m'
# 227 is a fixed light yellow. Theme yellow (43 and 103) is gray in some terminals.
# The number is near-black so it stays readable on that light background.
BG_TODAY=$'\033[38;5;232;48;5;227m'

die() {
  finish "$1" "$C_RED" "Result" "${@:2}"
}

color_on() {
  [[ -n "$C_RESET" ]]
}

usage() {
  section_open "Usage" "$C_YELLOW"
  box_row "$C_BOLD" "${SCRIPT_NAME} <month> [year] [--off <list>] [--extra <list>]" "$BORDER"
  box_row "$C_BOLD" "${SCRIPT_NAME} --month <1-12> [--year <yyyy>] [--off <list>]" "$BORDER"
  box_blank "$BORDER"
  box_row "" "Counts Monday-Friday, then adjusts that total." "$BORDER"
  box_row "" "--off subtracts weekdays you did not work." "$BORDER"
  box_row "" "--extra adds days you worked outside Monday-Friday." "$BORDER"
  box_blank "$BORDER"
  box_row "" "  month                 1-12. Also -m, --month." "$BORDER"
  box_row "" "  year                  Defaults to this year. Also -y, --year." "$BORDER"
  box_row "" "  -o, --off <list>      Days off. Subtracted from weekdays." "$BORDER"
  box_row "$C_DIM" "                        3,10,22    fri    5-9" "$BORDER"
  box_row "" "  -e, --extra <list>    Extra days worked, such as a weekend." "$BORDER"
  box_row "$C_DIM" "                        4,11    sat    sat,sun" "$BORDER"
  box_row "" "  -h, --help            Show this help." "$BORDER"
  box_blank "$BORDER"
  box_row "" "Dates, ranges, and weekday names can be combined." "$BORDER"
  box_row "" "A weekend in --off is shown, and not subtracted." "$BORDER"
  box_row "" "A weekday in --extra is already counted." "$BORDER"
  box_blank "$BORDER"
  box_row "" "Examples:" "$BORDER"
  box_row "$C_DIM" "  ${SCRIPT_NAME} 10" "$BORDER"
  box_row "$C_DIM" "  ${SCRIPT_NAME} 10 2026 --off 3,10,22" "$BORDER"
  box_row "$C_DIM" "  ${SCRIPT_NAME} 10 2026 --off fri --extra 4,11" "$BORDER"
  box_row "$C_DIM" "  ${SCRIPT_NAME} --month 10 --extra sat" "$BORDER"
  section_close
}

append_spec() {
  local which="$1"
  local spec="$2"
  local flag="$3"
  [[ -n "$spec" ]] || die "$EXIT_USAGE" "✗ ${flag} requires a list." \
    "  Example: 3,10,22 or fri or sat,sun"
  if [[ "$which" == off ]]; then
    if [[ -n "$OFF_SPEC" ]]; then
      OFF_SPEC="${OFF_SPEC}, ${spec}"
    else
      OFF_SPEC="$spec"
    fi
    HAS_OFF=1
  else
    if [[ -n "$EXTRA_SPEC" ]]; then
      EXTRA_SPEC="${EXTRA_SPEC}, ${spec}"
    else
      EXTRA_SPEC="$spec"
    fi
    HAS_EXTRA=1
  fi
}

parse_arguments() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h | --help)
        SHOW_HELP=1
        shift
        ;;
      -m | --month)
        [[ $# -ge 2 && "$2" != -* ]] || die "$EXIT_USAGE" "✗ --month requires a number from 1 to 12."
        MONTH="$2"
        shift 2
        ;;
      -m=* | --month=*)
        MONTH="${1#*=}"
        [[ -n "$MONTH" ]] || die "$EXIT_USAGE" "✗ --month requires a number from 1 to 12."
        shift
        ;;
      -y | --year)
        [[ $# -ge 2 && "$2" != -* ]] || die "$EXIT_USAGE" "✗ --year requires a year."
        YEAR="$2"
        shift 2
        ;;
      -y=* | --year=*)
        YEAR="${1#*=}"
        [[ -n "$YEAR" ]] || die "$EXIT_USAGE" "✗ --year requires a year."
        shift
        ;;
      -o | --off)
        [[ $# -ge 2 && "$2" != -* ]] || die "$EXIT_USAGE" "✗ --off requires a list." \
          "  Example: 3,10,22 or fri"
        append_spec off "$2" "--off"
        shift 2
        ;;
      -o=* | --off=*)
        append_spec off "${1#*=}" "--off"
        shift
        ;;
      -e | --extra)
        [[ $# -ge 2 && "$2" != -* ]] || die "$EXIT_USAGE" "✗ --extra requires a list." \
          "  Example: 4,11 or sat,sun"
        append_spec extra "$2" "--extra"
        shift 2
        ;;
      -e=* | --extra=*)
        append_spec extra "${1#*=}" "--extra"
        shift
        ;;
      --)
        shift
        break
        ;;
      -*)
        die "$EXIT_USAGE" "✗ Unknown argument '$1'."
        ;;
      *)
        if [[ -z "$MONTH" ]]; then
          MONTH="$1"
        elif [[ -z "$YEAR" ]]; then
          YEAR="$1"
        else
          die "$EXIT_USAGE" "✗ Unexpected argument '$1'."
        fi
        shift
        ;;
    esac
  done

  if [[ $# -gt 0 ]]; then
    die "$EXIT_USAGE" "✗ Unexpected argument '$1'."
  fi
}

# Prints nothing. Assigns the decimal value to the named variable.
# Must not run inside $(...) — die/exit would only leave that subshell.
assign_decimal() {
  local _name="$1"
  local label="$2"
  local value="$3"
  local min="$4"
  local max="$5"
  local number

  if [[ ! "$value" =~ ^[0-9]+$ ]]; then
    die "$EXIT_USAGE" "✗ ${label} must be a number from ${min} to ${max}."
  fi
  # 10# forces decimal. Otherwise 08 and 09 are invalid octal.
  number=$((10#$value))
  if (( number < min || number > max )); then
    die "$EXIT_USAGE" "✗ ${label} must be a number from ${min} to ${max}."
  fi
  printf -v "$_name" '%s' "$number"
}

detect_date() {
  if date -j -f "%Y-%m-%d" "2000-01-01" "+%Y" >/dev/null 2>&1; then
    DATE_IMPL="bsd"
  elif date -d "2000-01-01" "+%Y" >/dev/null 2>&1; then
    DATE_IMPL="gnu"
  else
    die "$EXIT_FAILED" "✗ This system's date command cannot parse a calendar date."
  fi
}

fmt_date() {
  local iso="$1"
  local fmt="$2"
  if [[ "$DATE_IMPL" == bsd ]]; then
    LC_TIME=C date -j -f "%Y-%m-%d" "$iso" "+${fmt}" 2>/dev/null
  else
    LC_TIME=C date -d "$iso" "+${fmt}" 2>/dev/null
  fi
}

days_in_month() {
  local iso="$1"
  local raw
  if [[ "$DATE_IMPL" == bsd ]]; then
    raw=$(LC_TIME=C date -j -v+1m -v-1d -f "%Y-%m-%d" "$iso" "+%d" 2>/dev/null) || return 1
  else
    raw=$(LC_TIME=C date -d "${iso} +1 month -1 day" "+%d" 2>/dev/null) || return 1
  fi
  [[ "$raw" =~ ^[0-9]+$ ]] || return 1
  printf '%s\n' "$((10#$raw))"
}

weekday_index() {
  case "$1" in
    mon | monday) printf '1\n' ;;
    tue | tues | tuesday) printf '2\n' ;;
    wed | wednesday) printf '3\n' ;;
    thu | thur | thurs | thursday) printf '4\n' ;;
    fri | friday) printf '5\n' ;;
    sat | saturday) printf '6\n' ;;
    sun | sunday) printf '7\n' ;;
    *) return 1 ;;
  esac
}

lower_token() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

reject_long_token() {
  local token="$1"
  if (( ${#token} > 40 )); then
    die "$EXIT_USAGE" "✗ Invalid day '${token:0:20}…'."
  fi
}

remember_day() {
  local day="$1"
  case "$PARSE_TARGET" in
    off) OFF_DAYS+=("$day") ;;
    extra) EXTRA_DAYS+=("$day") ;;
    *) die "$EXIT_FAILED" "✗ Internal error while reading ${PARSE_LABEL}." ;;
  esac
}

remember_dow() {
  local dow="$1"
  case "$PARSE_TARGET" in
    off) OFF_DOW[$dow]=1 ;;
    extra) EXTRA_DOW[$dow]=1 ;;
    *) die "$EXIT_FAILED" "✗ Internal error while reading ${PARSE_LABEL}." ;;
  esac
}

add_explicit_day() {
  local day="$1"
  local number
  if (( ${#day} > 4 )); then
    die "$EXIT_USAGE" "✗ Invalid day '${day}' in ${PARSE_LABEL}."
  fi
  number=$((10#$day))
  remember_day "$number"
}

add_dow_range() {
  local start="$1"
  local end="$2"
  local i
  if (( start > end )); then
    die "$EXIT_USAGE" "✗ Weekday range in ${PARSE_LABEL} is reversed." \
      "  Use an ascending range such as mon-fri."
  fi
  for ((i = start; i <= end; i++)); do
    remember_dow "$i"
  done
}

parse_one_token() {
  local token raw start end start_idx end_idx
  token="$(lower_token "$1")"
  [[ -n "$token" ]] || return 0
  reject_long_token "$token"

  if [[ "$token" =~ ^([0-9]+)-([0-9]+)$ ]]; then
    start="${BASH_REMATCH[1]}"
    end="${BASH_REMATCH[2]}"
    local start_n end_n day
    start_n=$((10#$start))
    end_n=$((10#$end))
    if (( start_n > end_n )); then
      die "$EXIT_USAGE" "✗ Range ${start}-${end} in ${PARSE_LABEL} is reversed."
    fi
    if (( end_n > 31 )); then
      die "$EXIT_USAGE" "✗ Day ${end_n} in ${PARSE_LABEL} is outside a month (1-31)."
    fi
    for ((day = start_n; day <= end_n; day++)); do
      remember_day "$day"
    done
    return 0
  fi

  if [[ "$token" =~ ^[0-9]+$ ]]; then
    add_explicit_day "$token"
    return 0
  fi

  if [[ "$token" =~ ^([a-z]+)-([a-z]+)$ ]]; then
    start_idx="$(weekday_index "${BASH_REMATCH[1]}")" || start_idx=""
    end_idx="$(weekday_index "${BASH_REMATCH[2]}")" || end_idx=""
    if [[ -n "$start_idx" && -n "$end_idx" ]]; then
      add_dow_range "$start_idx" "$end_idx"
      return 0
    fi
  fi

  if start_idx="$(weekday_index "$token")"; then
    remember_dow "$start_idx"
    return 0
  fi

  die "$EXIT_USAGE" "✗ Invalid day '${token}' in ${PARSE_LABEL}." \
    "  Use dates (1, 5-9), weekdays (mon, wed), or both."
}

parse_spec() {
  local spec="$1"
  local flag="$2"
  local token
  local -a tokens
  spec="${spec//,/ }"
  read -r -a tokens <<< "$spec"
  if (( ${#tokens[@]} == 0 )); then
    die "$EXIT_USAGE" "✗ ${flag} did not include any days."
  fi
  PARSE_LABEL="$flag"
  for token in "${tokens[@]}"; do
    parse_one_token "$token"
  done
}

apply_target() {
  local target="$1"
  local flag="$2"
  local day dow i any_dow=0
  local -a explicit bad
  local bad_keys=""
  explicit=()
  bad=()

  if [[ "$target" == off ]]; then
    if (( ${#OFF_DAYS[@]} > 0 )); then
      explicit=("${OFF_DAYS[@]}")
    fi
  elif (( ${#EXTRA_DAYS[@]} > 0 )); then
    explicit=("${EXTRA_DAYS[@]}")
  fi

  if (( ${#explicit[@]} > 0 )); then
    for day in "${explicit[@]}"; do
      if (( day < 1 || day > TOTAL_DAYS )); then
        case "$bad_keys" in
          *"|${day}|"*) ;;
          *)
            bad_keys+="|${day}|"
            bad+=("$day")
            ;;
        esac
      fi
    done
  fi

  if (( ${#bad[@]} > 0 )); then
    die "$EXIT_USAGE" \
      "✗ ${flag}: outside ${MONTH_NAME} ${YEAR} (1-${TOTAL_DAYS}): ${bad[*]}."
  fi

  if (( ${#explicit[@]} > 0 )); then
    for day in "${explicit[@]}"; do
      if [[ "$target" == off ]]; then
        OFF_ON[$day]=1
      else
        EXTRA_ON[$day]=1
      fi
    done
  fi

  for ((i = 1; i <= 7; i++)); do
    if [[ "$target" == off && -n "${OFF_DOW[$i]:-}" ]]; then
      any_dow=1
      break
    fi
    if [[ "$target" == extra && -n "${EXTRA_DOW[$i]:-}" ]]; then
      any_dow=1
      break
    fi
  done

  if (( any_dow )); then
    for ((day = 1; day <= TOTAL_DAYS; day++)); do
      dow=$(((FIRST_DOW0 + day - 1) % 7 + 1))
      if [[ "$target" == off && -n "${OFF_DOW[$dow]:-}" ]]; then
        OFF_ON[$day]=1
      fi
      if [[ "$target" == extra && -n "${EXTRA_DOW[$dow]:-}" ]]; then
        EXTRA_ON[$day]=1
      fi
    done
  fi
}

append_csv() {
  local dest="$1"
  local value="$2"
  case "$dest" in
    OFF_LIST)
      if [[ -n "$OFF_LIST" ]]; then OFF_LIST+=", ${value}"; else OFF_LIST="$value"; fi
      ;;
    EXTRA_LIST)
      if [[ -n "$EXTRA_LIST" ]]; then EXTRA_LIST+=", ${value}"; else EXTRA_LIST="$value"; fi
      ;;
    OFF_SKIP_LIST)
      if [[ -n "$OFF_SKIP_LIST" ]]; then OFF_SKIP_LIST+=", ${value}"; else OFF_SKIP_LIST="$value"; fi
      ;;
    EXTRA_SKIP_LIST)
      if [[ -n "$EXTRA_SKIP_LIST" ]]; then EXTRA_SKIP_LIST+=", ${value}"; else EXTRA_SKIP_LIST="$value"; fi
      ;;
  esac
}

load_month() {
  local iso raw dow
  detect_date

  printf -v iso '%04d-%02d-01' "$YEAR" "$MONTH"
  MONTH_NAME="$(fmt_date "$iso" "%B")" || MONTH_NAME=""
  [[ -n "$MONTH_NAME" ]] || die "$EXIT_FAILED" "✗ Could not read ${YEAR}-$(printf '%02d' "$MONTH")."

  TOTAL_DAYS="$(days_in_month "$iso")" || TOTAL_DAYS=""
  [[ "$TOTAL_DAYS" =~ ^[0-9]+$ ]] || die "$EXIT_FAILED" "✗ Could not count the days in ${MONTH_NAME} ${YEAR}."
  if (( TOTAL_DAYS < 28 || TOTAL_DAYS > 31 )); then
    die "$EXIT_FAILED" "✗ Could not count the days in ${MONTH_NAME} ${YEAR}."
  fi

  raw="$(fmt_date "$iso" "%u")" || raw=""
  [[ "$raw" =~ ^[1-7]$ ]] || die "$EXIT_FAILED" "✗ Could not place ${MONTH_NAME} 1 on the calendar."
  dow=$((10#$raw))
  FIRST_DOW0=$((dow - 1))

  local now_year now_month now_day
  now_year=$((10#$(date +%Y)))
  now_month=$((10#$(date +%m)))
  now_day=$((10#$(date +%d)))
  TODAY_DAY=0
  if (( YEAR == now_year && MONTH == now_month )); then
    TODAY_DAY=$now_day
  fi

  if (( HAS_OFF )); then
    PARSE_TARGET="off"
    parse_spec "$OFF_SPEC" "--off"
    apply_target off "--off"
  fi
  if (( HAS_EXTRA )); then
    PARSE_TARGET="extra"
    parse_spec "$EXTRA_SPEC" "--extra"
    apply_target extra "--extra"
  fi

  WEEKDAYS=0
  OFF_COUNT=0
  EXTRA_COUNT=0
  OFF_SHOWN=0
  EXTRA_SHOWN=0
  BILLABLE=0
  local day kind weekday clash_keys=""
  local -a clashes
  clashes=()
  for ((day = 1; day <= TOTAL_DAYS; day++)); do
    if [[ -n "${OFF_ON[$day]:-}" && -n "${EXTRA_ON[$day]:-}" ]]; then
      case "$clash_keys" in
        *"|${day}|"*) ;;
        *)
          clash_keys+="|${day}|"
          clashes+=("$day")
          ;;
      esac
    fi
  done
  if (( ${#clashes[@]} > 0 )); then
    die "$EXIT_USAGE" \
      "✗ Listed as both a day off and an extra day: ${clashes[*]}."
  fi

  for ((day = 1; day <= TOTAL_DAYS; day++)); do
    dow=$(((FIRST_DOW0 + day - 1) % 7 + 1))
    if (( dow <= 5 )); then
      weekday=1
      WEEKDAYS=$((WEEKDAYS + 1))
    else
      weekday=0
    fi

    if [[ -n "${OFF_ON[$day]:-}" ]]; then
      kind="off"
      OFF_SHOWN=1
      if (( weekday )); then
        OFF_COUNT=$((OFF_COUNT + 1))
        append_csv OFF_LIST "$day"
      else
        append_csv OFF_SKIP_LIST "$day"
      fi
    elif [[ -n "${EXTRA_ON[$day]:-}" ]]; then
      if (( weekday )); then
        kind="weekday"
        append_csv EXTRA_SKIP_LIST "$day"
      else
        kind="extra"
        EXTRA_SHOWN=1
        EXTRA_COUNT=$((EXTRA_COUNT + 1))
        append_csv EXTRA_LIST "$day"
      fi
    elif (( weekday )); then
      kind="weekday"
    else
      kind="weekend"
    fi
    DAY_KIND[$day]="$kind"
  done

  BILLABLE=$((WEEKDAYS - OFF_COUNT + EXTRA_COUNT))
}

layout_calendar() {
  table_layout 7 3 || return 1
  CELL_W=$TABLE_CELL_W
  return 0
}

header_name() {
  local index="$1"
  if (( CELL_W >= 9 )); then
    printf '%s' "${FULL_DOW[$index]}"
  elif (( CELL_W >= 5 )); then
    printf '%s' "${SHORT_DOW[$index]}"
  else
    printf '%s' "${NARROW_DOW[$index]}"
  fi
}

open_for() {
  local day="$1"
  if ! color_on; then
    printf ''
    return 0
  fi
  if (( day == TODAY_DAY )); then
    printf '%s' "$BG_TODAY"
    return 0
  fi
  case "${DAY_KIND[$day]}" in
    off) printf '%s' "$BG_OFF" ;;
    extra) printf '%s' "$BG_EXTRA" ;;
    weekday) printf '%s' "$BG_WEEKDAY" ;;
    *) printf '' ;;
  esac
}

label_for() {
  local day="$1"
  local text="$day"
  local marked
  if ! color_on && (( day == TODAY_DAY && ${#text} + 1 <= CELL_W )); then
    text="●${text}"
  fi
  if ! color_on && [[ "${DAY_KIND[$day]}" == extra ]]; then
    marked="[${text}]"
    if (( ${#marked} <= CELL_W )); then
      text="$marked"
    fi
  fi
  if ! color_on && [[ "${DAY_KIND[$day]}" == off ]]; then
    marked="-${text}"
    if (( ${#marked} <= CELL_W )); then
      text="$marked"
    fi
  fi
  printf '%s' "$text"
}

label_open() {
  local day="$1"
  if color_on; then
    if (( day == TODAY_DAY )); then
      printf '%s' "$BG_TODAY"
      return 0
    fi
    case "${DAY_KIND[$day]}" in
      off | extra | weekday) open_for "$day" ;;
      *) printf '%s' "$C_DIM" ;;
    esac
    return 0
  fi
  if [[ "${DAY_KIND[$day]}" == weekend ]]; then
    printf '%s' "$C_DIM"
  fi
}

bar_for() {
  local day="$1"
  local glyph width
  case "${DAY_KIND[$day]}" in
    off) glyph="x" ;;
    extra) glyph="█" ;;
    weekday) glyph="▓" ;;
    *)
      printf ''
      return 0
      ;;
  esac
  width=$((CELL_W - 2))
  if (( width < 1 )); then
    width=$CELL_W
  fi
  repeat_char "$glyph" "$width"
}

emit_headers() {
  local col open
  for ((col = 0; col < 7; col++)); do
    if (( col >= 5 )); then
      open="$C_DIM"
    else
      open="$C_BOLD"
    fi
    CELL_LINE[$col]="$(table_cell "$CELL_W" "$open" "$(header_name "$col")")"
  done
  table_row "${CELL_LINE[@]}"
}

emit_slot_row() {
  local row_kind="$1"
  shift
  local -a days
  local col day text open
  days=("$@")
  for ((col = 0; col < 7; col++)); do
    day=${days[$col]}
    text=""
    open=""
    if (( day > 0 )); then
      case "$row_kind" in
        number)
          text="$(label_for "$day")"
          open="$(label_open "$day")"
          ;;
        bar)
          if color_on; then
            open="$(open_for "$day")"
          else
            text="$(bar_for "$day")"
          fi
          ;;
        *)
          open="$(open_for "$day")"
          ;;
      esac
    fi
    CELL_LINE[$col]="$(table_cell "$CELL_W" "$open" "$text")"
  done
  table_row "${CELL_LINE[@]}"
}

emit_week() {
  emit_slot_row fill "$@"
  emit_slot_row number "$@"
  emit_slot_row bar "$@"
}

render_weeks() {
  local -a slot
  local day col
  slot=(0 0 0 0 0 0 0)
  day=1
  col=$FIRST_DOW0
  while (( day <= TOTAL_DAYS )); do
    slot[$col]=$day
    day=$((day + 1))
    col=$((col + 1))
    if (( col == 7 )); then
      emit_week "${slot[@]}"
      slot=(0 0 0 0 0 0 0)
      col=0
    fi
  done
  if (( col != 0 )); then
    emit_week "${slot[@]}"
  fi
}

render_calendar() {
  table_rule "┏" "┳" "┓"
  emit_headers
  table_rule "┣" "╋" "┫"
  render_weeks
  table_rule "┗" "┻" "┛"
}

add_legend_item() {
  local plain="$1"
  local colored="$2"
  LEGEND_PLAIN+=("$plain")
  LEGEND_COLORED+=("$colored")
}

render_legend() {
  local -a LEGEND_PLAIN LEGEND_COLORED
  local sw combined_plain combined_colored i max
  LEGEND_PLAIN=()
  LEGEND_COLORED=()

  if color_on; then
    # Two colored columns, then a space, then the label. Plain text must
    # use the same number of columns or the box border drifts.
    sw="$(printf '%s  %s' "$BG_WEEKDAY" "$C_RESET")"
    add_legend_item "$(printf '   %s' "Weekday")" "${sw} Weekday"
    if (( OFF_SHOWN )); then
      sw="$(printf '%s  %s' "$BG_OFF" "$C_RESET")"
      add_legend_item "$(printf '   %s' "Day off")" "${sw} Day off"
    fi
    if (( EXTRA_SHOWN )); then
      sw="$(printf '%s  %s' "$BG_EXTRA" "$C_RESET")"
      add_legend_item "$(printf '   %s' "Extra")" "${sw} Extra"
    fi
  else
    add_legend_item "▓▓ Weekday" "▓▓ Weekday"
    if (( OFF_SHOWN )); then
      add_legend_item "xx Day off" "xx Day off"
    fi
    if (( EXTRA_SHOWN )); then
      add_legend_item "██ Extra" "██ Extra"
    fi
  fi

  if (( TODAY_DAY > 0 )); then
    if color_on; then
      sw="$(printf '%s  %s' "$BG_TODAY" "$C_RESET")"
      add_legend_item "$(printf '   %s' "Today")" "${sw} Today"
    else
      add_legend_item "● Today" "● Today"
    fi
  fi

  combined_plain=""
  combined_colored=""
  for ((i = 0; i < ${#LEGEND_PLAIN[@]}; i++)); do
    if [[ -n "$combined_plain" ]]; then
      combined_plain+="    "
      combined_colored+="    "
    fi
    combined_plain+="${LEGEND_PLAIN[$i]}"
    combined_colored+="${LEGEND_COLORED[$i]}"
  done

  max=$((WIDTH - 4))
  if (( ${#combined_plain} <= max )); then
    box_center_row "$combined_colored" "${#combined_plain}"
    return 0
  fi

  for ((i = 0; i < ${#LEGEND_PLAIN[@]}; i++)); do
    box_center_row "${LEGEND_COLORED[$i]}" "${#LEGEND_PLAIN[$i]}"
  done
}

field_row() {
  local color="$1"
  local label="$2"
  local value="$3"
  box_row "$color" "$(printf '%-16s%s' "$label" "$value")" "$BORDER"
}

show_summary() {
  section_open "1 · Month" "$C_BLUE"
  field_row "" "Month" "${MONTH_NAME} ($(printf '%02d' "$MONTH"))"
  if (( YEAR_DEFAULTED )); then
    field_row "" "Year" "${YEAR} (current)"
  else
    field_row "" "Year" "$YEAR"
  fi
  field_row "" "Schedule" "Mon-Fri"
  if (( HAS_OFF )); then
    field_row "" "Days off" "$OFF_SPEC"
  fi
  if (( HAS_EXTRA )); then
    field_row "" "Extra days" "$EXTRA_SPEC"
  fi
  section_close

  section_open "2 · Summary" "$C_BLUE"
  field_row "" "Days in month" "$TOTAL_DAYS"
  field_row "" "Weekdays" "$WEEKDAYS"
  if (( HAS_OFF )); then
    field_row "" "Days off" "$OFF_COUNT"
  fi
  if (( HAS_EXTRA )); then
    field_row "" "Extra" "$EXTRA_COUNT"
  fi
  field_row "$C_GREEN" "Billable" "$BILLABLE"
  section_close
}

plural() {
  local n="$1"
  local singular="$2"
  local plural_word="$3"
  if (( n == 1 )); then
    printf '1 %s' "$singular"
  else
    printf '%s %s' "$n" "$plural_word"
  fi
}

show_calendar() {
  section_open "3 · ${MONTH_NAME} ${YEAR}" "$C_CYAN"
  if layout_calendar; then
    box_blank "$BORDER"
    render_calendar
    box_blank "$BORDER"
    render_legend
  else
    box_row "$C_YELLOW" "This terminal is too narrow to draw the calendar." "$BORDER"
    if [[ -n "$OFF_LIST" ]]; then
      box_row "" "Days off: ${OFF_LIST}" "$BORDER"
    fi
    if [[ -n "$EXTRA_LIST" ]]; then
      box_row "" "Extra: ${EXTRA_LIST}" "$BORDER"
    fi
  fi
  section_close
}

report() {
  local -a lines
  local detail
  lines=("✓ $(plural "$BILLABLE" "billable day" "billable days") in ${MONTH_NAME} ${YEAR}.")
  if (( HAS_OFF || HAS_EXTRA )); then
    detail="  $(plural "$WEEKDAYS" "weekday" "weekdays")"
    if (( OFF_COUNT > 0 )); then
      detail+=", minus $(plural "$OFF_COUNT" "day off" "days off")"
    fi
    if (( EXTRA_COUNT > 0 )); then
      detail+=", plus $(plural "$EXTRA_COUNT" "extra day" "extra days")"
    fi
    lines+=("${detail}.")
    if [[ -n "$OFF_LIST" ]]; then
      lines+=("  Off: ${OFF_LIST}")
    fi
    if [[ -n "$EXTRA_LIST" ]]; then
      lines+=("  Extra: ${EXTRA_LIST}")
    fi
    if [[ -n "$OFF_SKIP_LIST" ]]; then
      lines+=("  Not subtracted (already weekends): ${OFF_SKIP_LIST}")
    fi
    if [[ -n "$EXTRA_SKIP_LIST" ]]; then
      lines+=("  Not added (already weekdays): ${EXTRA_SKIP_LIST}")
    fi
  else
    lines+=("  Counted Monday-Friday.")
  fi
  finish 0 "$C_GREEN" "Result" "${lines[@]}"
}

main() {
  choose_box_width 100
  parse_arguments "$@"

  if (( SHOW_HELP )); then
    box_banner "$SCRIPT_NAME" "Contractor workday calculator."
    usage
    exit 0
  fi

  if [[ -z "$MONTH" ]]; then
    box_banner "$SCRIPT_NAME" "Contractor workday calculator."
    usage
    die "$EXIT_USAGE" "✗ Month is required."
  fi

  assign_decimal MONTH "Month" "$MONTH" 1 12

  if [[ -z "$YEAR" ]]; then
    YEAR="$(date +%Y)"
    YEAR_DEFAULTED=1
  fi
  assign_decimal YEAR "Year" "$YEAR" 1 9999

  box_banner "$SCRIPT_NAME" "Contractor workday calculator."
  load_month
  show_summary
  show_calendar
  report
}

main "$@"
