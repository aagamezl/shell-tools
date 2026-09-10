print_header() {
  local title="$1"

  printf '\n  %b%s%b\n' "$BOLD" "$title" "$NC"
  if [[ "$DRY_RUN" == true ]]; then
    printf '  %bReads the release files only. No database is contacted.%b\n' \
      "$DIM" "$NC"
  fi
  echo

  field release "$(basename "$RELEASE_DIR")"
  field location "$(shorten_home "$RELEASE_DIR")"
  # Never print the connection URI — it may contain credentials. The database
  # name is enough to know which target this run is aimed at.
  if [[ "$DRY_RUN" == true ]]; then
    field database "$MONGODB_DB_NAME  $(printf '%b(not contacted)%b' "$DIM" "$NC")"
  else
    field database "$MONGODB_DB_NAME"
  fi
}