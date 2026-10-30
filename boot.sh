#!/usr/bin/env bash
# Fetch shell-tools from GitHub, then run install.sh.
#
#   bash -c "$(curl -fsSL https://raw.githubusercontent.com/aagamezl/shell-tools/master/boot.sh)"
#   bash -c "$(curl -fsSL https://raw.githubusercontent.com/aagamezl/shell-tools/master/boot.sh)" -- --help
#   bash -c "$(curl -fsSL https://raw.githubusercontent.com/aagamezl/shell-tools/master/boot.sh)" -- workdays
set -euo pipefail

repo="https://github.com/aagamezl/shell-tools.git"
dest="${HOME:-}/.local/share/shell-tools"

if [[ -z "${HOME:-}" || ! -d "$HOME" ]]; then
  printf '%s\n' "HOME is not set to a directory." >&2
  exit 1
fi
command -v git >/dev/null 2>&1 || {
  printf '%s\n' "git is required." >&2
  exit 1
}

if [[ ! -f "$dest/install.sh" ]]; then
  if [[ -e "$dest" ]]; then
    printf '%s\n' "Refusing to replace $dest." >&2
    exit 1
  fi
  mkdir -p "$(dirname "$dest")"
  git clone --depth 1 --branch master "$repo" "$dest"
fi

exec bash "$dest/install.sh" "$@"
