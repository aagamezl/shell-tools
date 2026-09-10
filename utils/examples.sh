#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/cell.sh"
source "$SCRIPT_DIR/colors.sh"
source "$SCRIPT_DIR/commas.sh"
source "$SCRIPT_DIR/note.sh"
source "$SCRIPT_DIR/package_label.sh"
source "$SCRIPT_DIR/section.sh"
source "$SCRIPT_DIR/print_header.sh"
source "$SCRIPT_DIR/field.sh"
source "$SCRIPT_DIR/shorten_home.sh"

REPORT_WIDTH=76

section "Tables" "$REPORT_WIDTH"

name_width=30

# File/package name
file="users.csv"

# Row counts
rows=125430
active=120002
quoted=543
malformed=27
malformed_colour="$RED"
DRY_RUN=false
RELEASE_DIR="some/directory"
MONGODB_DB_NAME="mongodb://localhost:27017/refdata-scale"

printf '  %b%-*s %11s %11s %11s %8s %10s%b\n' \
  "$DIM" "$name_width" package rows active inactive quoted malformed "$NC"

printf '  %-*s %s %s %s %s %s\n' \
  "$name_width" "$(package_label "$file")" \
  "$(cell 11 "$(commas "$rows")" "$GREEN")" \
  "$(cell 11 "$(commas "$active")" "$GREEN")" \
  "$(cell 11 "$(commas "$((rows - active))")" "$ORANGE")" \
  "$(cell 8 "$(commas "$quoted")" "$YELLOW")" \
  "$(cell 10 "$(commas "$malformed")" "$malformed_colour")"

section "Notes" "$REPORT_WIDTH"

note "This is some note"
note "Second line of a note block"

# print_header "SNOMED build from TRUD — dry run"