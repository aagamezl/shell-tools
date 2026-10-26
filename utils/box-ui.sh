# Box-drawn terminal UI (same style as rebase-push).

WIDTH="${BOX_UI_WIDTH:-68}"
SECTION_OPEN=0
BORDER=""
TABLE_COLS=0
TABLE_CELL_W=0
TABLE_GRID_W=0

if [[ -t 1 && -z "${NO_COLOR:-}" && "${TERM:-}" != "dumb" ]]; then
  C_RESET=$'\033[0m'
  C_BOLD=$'\033[1m'
  C_DIM=$'\033[2m'
  C_RED=$'\033[31m'
  C_GREEN=$'\033[32m'
  C_YELLOW=$'\033[33m'
  C_BLUE=$'\033[34m'
  C_CYAN=$'\033[36m'
else
  C_RESET=""
  C_BOLD=""
  C_DIM=""
  C_RED=""
  C_GREEN=""
  C_YELLOW=""
  C_BLUE=""
  C_CYAN=""
fi

repeat_char() {
  local char="$1"
  local count="$2"
  local out=""
  local i=0
  while (( i < count )); do
    out="${out}${char}"
    i=$((i + 1))
  done
  printf '%s' "$out"
}

box_top() {
  local title="$1"
  local border="$2"
  local max_title=$((WIDTH - 6))
  local dashes

  if (( max_title < 1 )); then
    max_title=1
  fi
  if (( ${#title} > max_title )); then
    if (( max_title == 1 )); then
      title="…"
    else
      title="${title:0:$((max_title - 1))}…"
    fi
  fi
  dashes=$((WIDTH - ${#title} - 5))
  if (( dashes < 1 )); then
    dashes=1
  fi
  printf '%s╭─ %s%s%s %s╮%s\n' \
    "$border" "$C_BOLD" "$title" "$C_RESET$border" "$(repeat_char "─" "$dashes")" "$C_RESET"
}

box_bottom() {
  local border="$1"
  printf '%s╰%s╯%s\n' "$border" "$(repeat_char "─" $((WIDTH - 2)))" "$C_RESET"
}

box_row() {
  local color="$1"
  local text="$2"
  local border="$3"
  local max=$((WIDTH - 4))
  local pad
  local chunk
  local room
  local trimmed
  local prefix=""

  if [[ -z "$text" ]]; then
    printf '%s│%s %*s %s│%s\n' "$border" "$C_RESET" "$((WIDTH - 4))" "" "$border" "$C_RESET"
    return 0
  fi

  while [[ -n "$text" ]]; do
    room=$((max - ${#prefix}))
    if (( ${#text} <= room )); then
      chunk="${prefix}${text}"
      text=""
    else
      chunk="${text:0:room}"
      if [[ "$chunk" == *" "* ]]; then
        trimmed="${chunk% *}"
        if [[ -n "$trimmed" ]]; then
          chunk="$trimmed"
        fi
      fi
      text="${text:${#chunk}}"
      text="${text# }"
      chunk="${prefix}${chunk}"
    fi
    pad=$((max - ${#chunk}))
    printf '%s│%s %s%s%s%*s %s│%s\n' \
      "$border" "$C_RESET" "$color" "$chunk" "$C_RESET" "$pad" "" "$border" "$C_RESET"
    prefix="  "
  done
}

box_blank() {
  box_row "" "" "$1"
}

box_lines() {
  local color="$1"
  local text="$2"
  local border="$3"
  local line

  if [[ -z "$text" ]]; then
    return 0
  fi
  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ -n "$line" ]]; then
      line="  $line"
    fi
    box_row "$color" "$line" "$border"
  done < <(printf '%s\n' "$text")
}

section_open() {
  local title="$1"
  local border="$2"
  if (( SECTION_OPEN )); then
    section_close
  fi
  BORDER="$border"
  box_top "$title" "$border"
  SECTION_OPEN=1
}

section_close() {
  if (( SECTION_OPEN )); then
    box_bottom "$BORDER"
    SECTION_OPEN=0
    printf '\n'
  fi
}

finish() {
  local code="$1"
  local border="$2"
  local title="$3"
  shift 3
  local line

  section_close
  section_open "$title" "$border"
  for line in "$@"; do
    box_row "$border" "$line" "$border"
  done
  section_close
  exit "$code"
}

banner_row() {
  local color="$1"
  local text="$2"
  local max=$((WIDTH - 4))
  local pad

  if (( ${#text} > max )); then
    text="${text:0:$((max - 1))}…"
  fi
  pad=$((max - ${#text}))
  printf '%s┃%s %s%s%s%*s %s┃%s\n' \
    "$C_CYAN" "$C_RESET" "$color" "$text" "$C_RESET" "$pad" "" "$C_CYAN" "$C_RESET"
}

box_banner() {
  local title="$1"
  local subtitle="$2"
  local dashes
  dashes="$(repeat_char "━" $((WIDTH - 2)))"
  printf '%s┏%s┓%s\n' "$C_CYAN" "$dashes" "$C_RESET"
  banner_row "$C_BOLD" "$title"
  if [[ -n "$subtitle" ]]; then
    banner_row "" "$subtitle"
  fi
  printf '%s┗%s┛%s\n\n' "$C_CYAN" "$dashes" "$C_RESET"
}

choose_box_width() {
  local min="${1:-68}"
  local needed="$min"
  if [[ -t 1 ]]; then
    local cols
    exec 3>&1
    cols=$(stty size <&3 2>/dev/null | awk '{print $2}')
    exec 3>&-
    if [[ "$cols" =~ ^[0-9]+$ ]] && (( cols >= 2 )); then
      cols=$((cols - 1))
      if (( cols < needed )); then
        needed=$cols
      fi
    fi
  fi
  WIDTH=$needed
}

# Row whose visible width is known. ANSI codes inside `colored` are not
# part of `visible`, so the right border stays on the WIDTH column.
box_vis_row() {
  local visible="$1"
  local colored="$2"
  local max=$((WIDTH - 4))
  local pad=$((max - visible))
  if (( pad < 0 )); then
    pad=0
  fi
  printf '%s│%s %s%*s %s│%s\n' \
    "$BORDER" "$C_RESET" "$colored" "$pad" "" "$BORDER" "$C_RESET"
}

# Center a colored run inside the open section. `visible` is the column
# count of `colored` with ANSI codes ignored.
box_center_row() {
  local colored="$1"
  local visible="$2"
  local max=$((WIDTH - 4))
  local left=$(((max - visible) / 2))
  local spaces
  if (( left < 0 )); then
    left=0
  fi
  spaces="$(repeat_char " " "$left")"
  box_vis_row $((left + visible)) "${spaces}${colored}"
}

# Center `text` in a cell of `width` columns. `open` is an ANSI sequence
# applied to the padding and the text, then closed with C_RESET.
# Prints the cell with no newline. Visible width is `width`.
table_cell() {
  local width="$1"
  local open="$2"
  local text="$3"
  local len left right
  len=${#text}
  if (( len > width )); then
    text="${text:0:width}"
    len=${#text}
  fi
  left=$(((width - len) / 2))
  right=$((width - len - left))
  if [[ -n "$open" ]]; then
    printf '%s%*s%s%*s%s' "$open" "$left" "" "$text" "$right" "" "$C_RESET"
  else
    printf '%*s%s%*s' "$left" "" "$text" "$right" ""
  fi
}

# Fit `cols` equal columns into the open box.
# `min_cell` is the narrowest cell accepted (default 3).
# Sets TABLE_COLS, TABLE_CELL_W, and TABLE_GRID_W.
# Returns 1 when the grid cannot fit.
table_layout() {
  local cols="$1"
  local min_cell="${2:-3}"
  local max=$((WIDTH - 4))
  local seps=$((cols + 1))
  local cell_w

  TABLE_COLS=$cols
  if (( cols < 1 )); then
    TABLE_CELL_W=0
    TABLE_GRID_W=0
    return 1
  fi
  cell_w=$(((max - seps) / cols))
  if (( cell_w < min_cell )); then
    TABLE_CELL_W=0
    TABLE_GRID_W=0
    return 1
  fi
  TABLE_GRID_W=$((cell_w * cols + seps))
  if (( TABLE_GRID_W > max )); then
    TABLE_CELL_W=0
    TABLE_GRID_W=0
    return 1
  fi
  TABLE_CELL_W=$cell_w
  return 0
}

# Horizontal rule of the open table. Junctions are the left, middle, and
# right characters (┏ ┳ ┓, ┣ ╋ ┫, or ┗ ┻ ┛). Drawn in C_DIM when color is on.
table_rule() {
  local left_c="$1"
  local mid_c="$2"
  local right_c="$3"
  local body="" i colored
  body+="$left_c"
  for ((i = 0; i < TABLE_COLS; i++)); do
    body+="$(repeat_char "━" "$TABLE_CELL_W")"
    if (( i < TABLE_COLS - 1 )); then
      body+="$mid_c"
    fi
  done
  body+="$right_c"
  if [[ -n "$C_DIM" ]]; then
    colored="${C_DIM}${body}${C_RESET}"
  else
    colored="$body"
  fi
  box_center_row "$colored" "${#body}"
}

# One row of the open table. Each argument is a cell already rendered by
# table_cell, so its visible width is TABLE_CELL_W. A missing cell is blank.
table_row() {
  local out="" i cell
  local -a cells=("$@")
  for ((i = 0; i < TABLE_COLS; i++)); do
    if [[ -n "$C_DIM" ]]; then
      out+="${C_DIM}┃${C_RESET}"
    else
      out+="┃"
    fi
    cell="${cells[$i]:-}"
    if [[ -z "$cell" ]]; then
      cell="$(table_cell "$TABLE_CELL_W" "" "")"
    fi
    out+="$cell"
  done
  if [[ -n "$C_DIM" ]]; then
    out+="${C_DIM}┃${C_RESET}"
  else
    out+="┃"
  fi
  box_center_row "$out" "$TABLE_GRID_W"
}

# One text row. Every cell uses the same color. Extra arguments are ignored.
# Missing arguments are blank cells.
table_texts() {
  local color="$1"
  shift
  local -a src=("$@") cells=()
  local i
  for ((i = 0; i < TABLE_COLS; i++)); do
    cells+=("$(table_cell "$TABLE_CELL_W" "$color" "${src[$i]:-}")")
  done
  table_row "${cells[@]}"
}
