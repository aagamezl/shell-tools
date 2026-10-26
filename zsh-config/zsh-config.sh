#!/usr/bin/env bash
# Same tool as ../zsh-config.sh, for running from this directory.
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "${here}/../zsh-config.sh" "$@"
