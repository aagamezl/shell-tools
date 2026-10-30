#!/usr/bin/env bash
# Install shell-tools from GitHub into ~/.local/share/shell-tools.
# Commands are symlinks in ~/.local/bin.
set -euo pipefail

if [[ -z "${HOME:-}" || ! -d "$HOME" ]]; then
  printf '%s\n' "HOME is not set to a directory." >&2
  exit 1
fi

SOURCE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$HOME/.local/share/shell-tools"
BIN_DIR="$HOME/.local/bin"
REPO="https://github.com/aagamezl/shell-tools.git"
BRANCH="master"

if [[ ! -f "${SOURCE}/utils/box-ui.sh" ]]; then
  printf 'Missing %s\n' "${SOURCE}/utils/box-ui.sh" >&2
  exit 1
fi
# shellcheck source=utils/box-ui.sh
source "${SOURCE}/utils/box-ui.sh"

# name:path, relative to the repository root.
TOOLS=(
  "workdays:workdays.sh"
  "create-host-config:create-host-config/create-host-config.sh"
  "zsh-config:zsh-config/zsh-config.sh"
  "list-recent-collaborators:list-recent-collaborators.sh"
  "minify-code:minify-code.sh"
  "profile-backup:profile-backup.sh"
  "http-server:http-server/http-server.sh"
  "bash-commander:bash-commander/bash-commander.sh"
  "port-view:port-view.sh"
)

usage() {
  section_open "Usage" "$C_YELLOW"
  box_row "$C_BOLD" "install.sh" "$BORDER"
  box_row "$C_BOLD" "install.sh --all" "$BORDER"
  box_row "$C_BOLD" "install.sh <name> [<name>...]" "$BORDER"
  box_row "$C_BOLD" "install.sh --list" "$BORDER"
  box_row "$C_BOLD" "install.sh --update [<name>...]" "$BORDER"
  box_row "$C_BOLD" "install.sh --uninstall" "$BORDER"
  box_blank "$BORDER"
  box_row "" "Install this repository from GitHub." "$BORDER"
  box_row "" "Files stay in ~/.local/share/shell-tools." "$BORDER"
  box_row "" "Each command is a symlink in ~/.local/bin." "$BORDER"
  box_blank "$BORDER"
  box_row "" "  (no arguments)     Install every tool. Same as --all." "$BORDER"
  box_row "" "  -a, --all          Install every tool." "$BORDER"
  box_row "" "  <name>             Install that tool. Repeat for more than one." "$BORDER"
  box_row "" "  -l, --list         Show each tool and whether it is installed." "$BORDER"
  box_row "" "  --update           Update from GitHub, then link the named tools." "$BORDER"
  box_row "$C_DIM" "                     With no names, link every tool." "$BORDER"
  box_row "" "  --uninstall        Remove the links and the install directory." "$BORDER"
  box_row "" "  -h, --help         Show this help." "$BORDER"
  box_blank "$BORDER"
  box_row "" "From GitHub:" "$BORDER"
  box_row "$C_DIM" "  bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/aagamezl/shell-tools/master/boot.sh)\"" "$BORDER"
  box_row "$C_DIM" "  bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/aagamezl/shell-tools/master/boot.sh)\" -- workdays" "$BORDER"
  box_blank "$BORDER"
  box_row "" "Examples:" "$BORDER"
  box_row "$C_DIM" "  ./install.sh" "$BORDER"
  box_row "$C_DIM" "  ./install.sh --all" "$BORDER"
  box_row "$C_DIM" "  ./install.sh workdays" "$BORDER"
  box_row "$C_DIM" "  ./install.sh workdays http-server" "$BORDER"
  box_row "$C_DIM" "  ./install.sh --list" "$BORDER"
  box_row "$C_DIM" "  ./install.sh --update" "$BORDER"
  box_row "$C_DIM" "  ./install.sh --uninstall" "$BORDER"
  box_blank "$BORDER"
  box_row "" "Add \$HOME/.local/bin to PATH if it is not there yet." "$BORDER"
  section_close
}

die() {
  finish 1 "$C_RED" "Failed" "$@"
}

show_banner() {
  if [[ ! -f "${SOURCE}/ascii-logo.sh" ]]; then
    printf 'Missing %s\n' "${SOURCE}/ascii-logo.sh" >&2
    exit 1
  fi
  # shellcheck source=ascii-logo.sh
  source "${SOURCE}/ascii-logo.sh"
  box_banner "shell-tools" $'\nA collection of lightweight shell-based tools for everyday development and system tasks.\nBuilt entirely with Bash to stay portable, minimal, and dependency-free.'
}

repo_name() {
  local url=${1%.git}
  url=${url%/}

  case "$url" in
    git@github.com:*) url=${url#git@github.com:} ;;
    https://github.com/*) url=${url#https://github.com/} ;;
    ssh://git@github.com/*) url=${url#ssh://git@github.com/} ;;
  esac

  printf '%s' "$url"
}

sync_repo() {
  command -v git >/dev/null 2>&1 || die "git is required."

  if [[ -d "$INSTALL_DIR/.git" ]]; then
    local origin
    origin="$(git -C "$INSTALL_DIR" remote get-url origin 2>/dev/null || true)"

    [[ "$(repo_name "$origin")" == "aagamezl/shell-tools" ]] || die "Refusing to update ~/.local/share/shell-tools (origin is ${origin:-unknown})."

    git -C "$INSTALL_DIR" fetch --depth 1 -q origin "$BRANCH" || die "Could not update $INSTALL_DIR from GitHub."
    git -C "$INSTALL_DIR" reset --hard -q "origin/${BRANCH}" || die "Could not update $INSTALL_DIR from GitHub."

    return
  fi

  if [[ -e "$INSTALL_DIR" ]]; then
    die "$INSTALL_DIR exists and is not a git checkout."
  fi

  mkdir -p "$(dirname "$INSTALL_DIR")"

  git clone --depth 1 --branch "$BRANCH" -q "$REPO" "$INSTALL_DIR" || die "Could not clone $REPO."
}

tool_script() {
  local name="$1" tool

  for tool in "${TOOLS[@]}"; do
    if [[ "${tool%%:*}" == "$name" ]]; then
      printf '%s\n' "${tool#*:}"
      return 0
    fi
  done

  return 1
}

list_tools() {
  local tool name target link

  section_open "Tools" "$C_BLUE"

  for tool in "${TOOLS[@]}"; do
    name="${tool%%:*}"
    target="$INSTALL_DIR/${tool#*:}"
    link="$BIN_DIR/$name"

    if [[ -L "$link" && "$(readlink "$link")" == "$INSTALL_DIR/"* ]]; then
      target="$(readlink "$link")"
      box_row "$C_GREEN" "$(printf '%-28s%s' "$name" "installed")" "$BORDER"
      box_row "$C_DIM" "  ~/${link#"$HOME"/} -> ~/${target#"$HOME"/}" "$BORDER"
    elif [[ -e "$link" ]]; then
      box_row "$C_YELLOW" "$(printf '%-28s%s' "$name" "not installed")" "$BORDER"
      box_row "$C_DIM" "  ~/${link#"$HOME"/} is not a link to this install." "$BORDER"
    else
      box_row "" "$(printf '%-28s%s' "$name" "not installed")" "$BORDER"
    fi
  done

  section_close
}

link_tools() {
  local name target link rel
  local -a names=("$@")

  if [[ ${#names[@]} -eq 0 ]]; then
    for name in "${TOOLS[@]}"; do
      names+=("${name%%:*}")
    done
  fi

  mkdir -p "$BIN_DIR"

  section_open "Commands" "$C_CYAN"

  for name in "${names[@]}"; do
    rel="$(tool_script "$name")" || die "Unknown tool: $name"
    target="$INSTALL_DIR/$rel"
    link="$BIN_DIR/$name"

    [[ -f "$target" ]] || die "Missing tool: $target"

    if [[ -e "$link" && ! -L "$link" ]]; then
      die "$link exists and is not a symlink."
    fi

    chmod +x "$target"

    ln -sfn "$target" "$link"

    box_row "$C_GREEN" "✓ ${name}" "$BORDER"
    box_row "$C_DIM" "  ~/${link#"$HOME"/} -> ~/${target#"$HOME"/}" "$BORDER"
  done

  section_close
}

uninstall_tools() {
  local tool name link
  section_open "Remove" "$C_CYAN"

  for tool in "${TOOLS[@]}"; do
    name="${tool%%:*}"
    link="$BIN_DIR/$name"

    if [[ -L "$link" && "$(readlink "$link")" == "$INSTALL_DIR/"* ]]; then
      rm "$link"

      box_row "$C_GREEN" "✓ ${name}" "$BORDER"
      box_row "$C_DIM" "  removed ~/${link#"$HOME"/}" "$BORDER"
    fi
  done

  if [[ -d "$INSTALL_DIR" ]]; then
    rm -rf "$INSTALL_DIR"

    box_row "$C_GREEN" "✓ ~/.local/share/shell-tools" "$BORDER"
  else
    box_row "$C_DIM" "  ~/.local/share/shell-tools is already absent." "$BORDER"
  fi

  section_close
  finish 0 "$C_GREEN" "Uninstalled" "The tools are no longer on PATH."
}

main() {
  local arg name
  local action="install"
  local install_all=0
  local -a selected=()

  choose_box_width "${BOX_UI_WIDTH:-100}"

  if [[ $# -eq 0 ]]; then
    install_all=1
  fi

  for arg in "$@"; do
    case "$arg" in
      -h|--help|help)
        [[ $# -eq 1 ]] || { show_banner; usage; finish 1 "$C_RED" "Failed" "Too many arguments."; }
        show_banner
        usage
        exit 0
        ;;
      -l|--list|list)
        [[ $# -eq 1 ]] || { show_banner; usage; finish 1 "$C_RED" "Failed" "Too many arguments."; }
        show_banner
        list_tools
        exit 0
        ;;
      --uninstall|uninstall)
        action="uninstall"
        ;;
      --update|update)
        ;;
      -a|--all|all)
        install_all=1
        ;;
      -*)
        show_banner
        usage
        finish 1 "$C_RED" "Failed" "Unknown argument: $arg"
        ;;
      *)
        selected+=("$arg")
        ;;
    esac
  done

  if [[ "$action" == "uninstall" ]]; then
    if [[ $# -ne 1 ]]; then
      show_banner
      usage
      finish 1 "$C_RED" "Failed" "Uninstall does not take other arguments."
    fi

    show_banner
    uninstall_tools
  fi

  if [[ "$install_all" -eq 1 && ${#selected[@]} -gt 0 ]]; then
    show_banner
    usage
    finish 1 "$C_RED" "Failed" "Name the tools or pass --all, not both."
  fi

  if [[ ${#selected[@]} -eq 0 ]]; then
    install_all=1
  fi

  if [[ "$install_all" -eq 0 ]]; then
    for name in "${selected[@]}"; do
      tool_script "$name" >/dev/null || { show_banner; usage; finish 1 "$C_RED" "Failed" "Unknown tool: $name"; }
    done
  fi

  # If this file is not the installed copy, update ~/.local/share/shell-tools
  # from GitHub, then continue with the install.sh in that directory.
  if [[ "$SOURCE" != "$INSTALL_DIR" ]]; then
    sync_repo

    exec bash "$INSTALL_DIR/install.sh" "$@"
  fi

  show_banner

  sync_repo

  section_open "Repository" "$C_BLUE"

  box_row "" "$(git -C "$INSTALL_DIR" rev-parse --short HEAD)  ${BRANCH}" "$BORDER"

  box_row "$C_DIM" "  ~/${INSTALL_DIR#"$HOME"/}" "$BORDER"

  section_close

  if [[ "$install_all" -eq 1 ]]; then
    link_tools
  else
    link_tools "${selected[@]}"
  fi

  finish 0 "$C_GREEN" "Installed" \
    "Tools are in ~/.local/share/shell-tools." \
    "Commands are linked in ~/.local/bin."
}

main "$@"
