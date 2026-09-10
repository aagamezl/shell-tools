source "$SCRIPT_DIR/repeat.sh"

section() {
  local title="$1"
  local REPORT_WIDTH="$2"
  local pad=$((REPORT_WIDTH - ${#title} - 4))
  [[ $pad -lt 0 ]] && pad=0
  printf '\n%b──%b %b%s%b %b%s%b\n\n' \
    "$CYAN" "$NC" "$BOLD" "$title" "$NC" "$DIM" "$(repeat '─' "$pad")" "$NC"
}