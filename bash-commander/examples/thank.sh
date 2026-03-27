#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/bash-commander.sh"

cli_create "thank" "Simple thank-you tool"
cli_argument "<name>"
cli_option "-t, --title <honorific>" "title to use before name"
cli_option "-d, --debug" "display some debugging"

cli_parse "$@" || exit $?

debug="false"
title=""
cli_get_option "debug" debug || true
cli_get_option "title" title || true

if [[ "$debug" == "true" ]]; then
  printf 'Called %s with options:\n' "$CLI_NAME" >&2
  cli_dump_result >&2
fi

name="${CLI_GLOBAL_ARGS[0]}"
printf 'Thank-you %s%s\n' "${title:+$title }" "$name"
