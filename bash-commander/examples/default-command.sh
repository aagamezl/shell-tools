#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/bash-commander.sh"

cli_create "defaultCommand" "Example using a default command"

cli_command "build" "build web site for deployment"
cli_command "deploy" "deploy web site to production"
cli_command "serve" "launch web server" "true"
cli_command_option "serve" "-p, --port <port_number>" "web port"

cli_parse "$@" || exit $?

port=""
cli_get_option "port" port || true

echo "CLI_SELECTED_COMMAND: $CLI_SELECTED_COMMAND"


case "$CLI_SELECTED_COMMAND" in
  build)
    echo "build"
    ;;
  deploy)
    echo "deploy"
    ;;
  serve)
    printf 'server on port %s\n' "${port:-<unset>}"
    ;;
  *)
    printf 'unknown command: %s\n' "$CLI_SELECTED_COMMAND" >&2
    exit 1
    ;;
esac
