#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/bash-commander.sh"

cli_create "split" "Split a string by separator"
cli_option "--first" "return first chunk only"
cli_option "-l, --last" "return last chunk only" "false"
cli_option "-s, --separator <char>" "separator character"
cli_argument "<string>"

cli_parse "$@" || exit $?

first="false"
last="false"
separator=""

cli_get_option "first" first || true
cli_get_option "last" last || true
cli_get_option "separator" separator || true

input="${CLI_GLOBAL_ARGS[0]}"

if [[ -z "$separator" ]]; then
  echo "separator is required (use -s or --separator)" >&2
  exit 1
fi

IFS="$separator" read -r -a parts <<<"$input"

if [[ "$first" == "true" ]]; then
  printf '%s\n' "${parts[0]}"
elif [[ "$last" == "true" ]]; then
  printf '%s\n' "${parts[${#parts[@]}-1]}"
else
  printf '%s\n' "${parts[@]}"
fi
