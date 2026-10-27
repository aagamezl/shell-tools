#!/bin/sh
# Install tools from this repository onto the machine.
# Run it from a checkout, or from GitHub:
#   sh -c "$(curl -fsSL https://raw.githubusercontent.com/aagamezl/shell-tools/master/install.sh)" -- --help
#
# The catalog in tools_list is the set of tools this script can install.
# utils/ is not a command. It is installed with every selection because the
# tools source it from next to their own files.

set -eu

REPO_OWNER="aagamezl"
REPO_NAME="shell-tools"
REPO_REF="master"
DEFAULT_PREFIX="$HOME/.local/shell-tools"
SYSTEM_BIN_DEFAULT="/usr/local/bin"
PATH_BEGIN="# >>> shell-tools >>>"
PATH_END="# <<< shell-tools <<<"

PREFIX="${SHELL_TOOLS_PREFIX:-$DEFAULT_PREFIX}"
SYSTEM_BIN="${SHELL_TOOLS_SYSTEM_BIN:-$SYSTEM_BIN_DEFAULT}"
SYSTEM_BIN_EXPLICIT=0
DO_ALL=0
DO_LIST=0
REQUESTED=""
FETCH_TMP=""
SOURCE_ROOT=""
BIN_DIR=""
HOME_PHYS=""
LINKED_SYSTEM=0
SKIPPED_LINKS=""
SYSTEM_LINK_NOTE=""

# name|path relative to the repo root|extra paths, comma-separated|exec or link|description
# exec: bin/name runs the real file, so SCRIPT_DIR still sees utils beside that file.
# link: bin/name is a symlink. Use this for libraries that are sourced.
tools_list() {
  cat <<'EOF'
workdays|workdays.sh||exec|Count billable days in a month and draw them on a calendar
create-host-config|create-host-config/create-host-config.sh||exec|Add one Host entry to ~/.ssh/config
zsh-config|zsh-config.sh|zsh-config|exec|Set up zsh from a CachyOS configuration bundle
list-recent-collaborators|list-recent-collaborators.sh||exec|List recent git authors for a directory
minify-code|minify-code.sh||exec|Remove comments from TypeScript files
profile-backup|profile-backup.sh||exec|Back up shell and SSH profile files
run-and-report|run-and-report.sh||exec|Log whether the editor is active or idle
bpm|bpm||exec|Keep a local package.bpm manifest and dependency list
http-server|http-server/http-server.sh|http-server/public|exec|Serve a directory over HTTP
bash-commander|bash-commander/bash-commander.sh|bash-commander/examples,bash-commander/BASH_COMMANDER.md|link|Bash 3.2 command-line parser library
EOF
}

die() {
  printf '%s\n' "$*" >&2
  exit 1
}

usage() {
  cat <<EOF
Usage:
  install.sh --all
  install.sh [--prefix DIR] <tool> [<tool> ...]
  install.sh --list
  install.sh --help

Install tools from ${REPO_OWNER}/${REPO_NAME}. utils/ is always installed
with the tools you name. Each tool is placed on PATH.

Options:
  -h, --help           Show this usage
  -a, --all            Install every tool in the catalog
  -l, --list           List tools the catalog can install
  -p, --prefix DIR     Install directory (default: \$HOME/.local/shell-tools)
      --system-bin DIR Directory for system-wide links (default: ${SYSTEM_BIN_DEFAULT})
      --ref REF        Git branch downloaded when not running from a checkout

The install directory can also be set with SHELL_TOOLS_PREFIX.
SHELL_TOOLS_SYSTEM_BIN overrides the system link directory.

From GitHub:
  sh -c "\$(curl -fsSL https://raw.githubusercontent.com/${REPO_OWNER}/${REPO_NAME}/${REPO_REF}/install.sh)" -- --help
  sh -c "\$(curl -fsSL https://raw.githubusercontent.com/${REPO_OWNER}/${REPO_NAME}/${REPO_REF}/install.sh)" -- --all
  sh -c "\$(curl -fsSL https://raw.githubusercontent.com/${REPO_OWNER}/${REPO_NAME}/${REPO_REF}/install.sh)" -- workdays
  sh -c "\$(curl -fsSL https://raw.githubusercontent.com/${REPO_OWNER}/${REPO_NAME}/${REPO_REF}/install.sh)" -- --prefix ~/.local/shell-tools create-host-config

The "--" is required in that form. It becomes the command name, and the
words after it are the options and tool names.

From a checkout:
  ./install.sh --list
  ./install.sh --all
  ./install.sh workdays
  ./install.sh --prefix ~/.local/shell-tools bpm http-server
EOF
}

cleanup() {
  if [ -n "$FETCH_TMP" ] && [ -d "$FETCH_TMP" ]; then
    rm -rf "$FETCH_TMP"
  fi
  FETCH_TMP=""
}

trap cleanup EXIT
trap 'cleanup; exit 130' INT
trap 'cleanup; exit 143' TERM

# shellcheck disable=SC2088
expand_tilde() {
  case "$1" in
    "~")
      printf '%s\n' "$HOME"
      ;;
    "~/"*)
      printf '%s\n' "$HOME/${1#"~/"}"
      ;;
    *)
      printf '%s\n' "$1"
      ;;
  esac
}

absolute_existing() {
  CDPATH='' cd -P "$1" && pwd
}

normalize_path() {
  path=$1
  case "$path" in
    /*) ;;
    *) path="$(pwd)/$path" ;;
  esac

  old_ifs=$IFS
  IFS='/'
  set -f
  out=""
  for part in $path; do
    case "$part" in
      ""|.)
        ;;
      ..)
        if [ "$out" = "/" ] || [ -z "$out" ]; then
          out="/"
        else
          out=${out%/*}
          [ -n "$out" ] || out="/"
        fi
        ;;
      *)
        if [ "$out" = "/" ]; then
          out="/$part"
        else
          out="$out/$part"
        fi
        ;;
    esac
  done
  set +f
  IFS=$old_ifs
  [ -n "$out" ] || out="/"
  printf '%s\n' "$out"
}

reject_unsafe_path() {
  case "$1" in
    *'
'*|*[\"\`\$\\:]*)
      die "Install directory contains a character that cannot be added to PATH safely: $1"
      ;;
  esac
}

each_tool() {
  while IFS='|' read -r name executable extras mode description; do
    [ -n "${name:-}" ] || continue
    "$@"
  done <<EOF
$(tools_list)
EOF
}

tool_known() {
  wanted=$1
  found=0
  match_name() {
    if [ "$name" = "$wanted" ]; then
      found=1
    fi
  }
  each_tool match_name
  [ "$found" -eq 1 ]
}

list_tools() {
  printf '%s\n' "Tools:"
  # Invoked by name from each_tool.
  # shellcheck disable=SC2329
  show_one() {
    printf '  %-28s %s\n' "$name" "$description"
  }
  each_tool show_one
  printf '%s\n' "utils is always installed with a tool and is not a command."
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

resolve_source() {
  if [ -f "$0" ]; then
    root=$(CDPATH='' cd "$(dirname "$0")" && pwd)
    if [ -f "$root/utils/box-ui.sh" ] && [ -f "$root/install.sh" ]; then
      SOURCE_ROOT=$root
      printf 'Source: %s\n' "$SOURCE_ROOT"
      return 0
    fi
  fi

  require_command curl
  require_command tar
  FETCH_TMP=$(mktemp -d "${TMPDIR:-/tmp}/shell-tools.XXXXXX")
  archive="$FETCH_TMP/src.tar.gz"
  url="https://github.com/${REPO_OWNER}/${REPO_NAME}/archive/refs/heads/${REPO_REF}.tar.gz"
  printf 'Downloading %s\n' "$url"
  curl -fsSL "$url" -o "$archive" || die "Could not download $url"
  tar -xzf "$archive" -C "$FETCH_TMP" || die "Could not extract $url"

  count=0
  SOURCE_ROOT=""
  for dir in "$FETCH_TMP"/*; do
    [ -d "$dir" ] || continue
    count=$((count + 1))
    SOURCE_ROOT=$dir
  done
  [ "$count" -eq 1 ] || die "Expected one directory in the downloaded archive"
  [ -f "$SOURCE_ROOT/utils/box-ui.sh" ] || die "Downloaded archive is missing utils/box-ui.sh"
  printf 'Source: %s\n' "$url"
}

refuse_prefix_overlap() {
  source_phys=$(absolute_existing "$SOURCE_ROOT")
  case "$1" in
    "$source_phys"|"$source_phys"/*)
      die "Install directory must be outside the source tree ($source_phys)"
      ;;
  esac
  case "$source_phys" in
    "$1"/*)
      die "Source tree must be outside the install directory ($1)"
      ;;
  esac
}

prepare_prefix() {
  PREFIX=$(normalize_path "$(expand_tilde "$PREFIX")")
  reject_unsafe_path "$PREFIX"

  case "$PREFIX" in
    /|/usr|/usr/local|/bin|/sbin|/etc|/var|/tmp|/Users|/home|"$HOME"|"$HOME_PHYS")
      die "Refusing to install into $PREFIX. This is a system directory. Please choose a different installation directory."
      ;;
  esac

  refuse_prefix_overlap "$PREFIX"
  mkdir -p "$PREFIX"
  PREFIX=$(absolute_existing "$PREFIX")
  refuse_prefix_overlap "$PREFIX"
  BIN_DIR="$PREFIX/bin"
}

install_rel() {
  rel=$1
  [ -n "$rel" ] || die "Empty install path"
  case "$rel" in
    /*|*..*) die "Refusing path $rel" ;;
  esac

  src="$SOURCE_ROOT/$rel"
  dest="$PREFIX/$rel"
  [ -e "$src" ] || die "Missing $rel in $SOURCE_ROOT"
  case "$dest" in
    "$PREFIX"/*) ;;
    *) die "Refusing to write $dest" ;;
  esac

  mkdir -p "$(dirname "$dest")"
  if [ -d "$src" ]; then
    rm -rf "$dest"
    cp -R "$src" "$dest"
  else
    cp "$src" "$dest"
  fi
}

shell_quote() {
  printf "'"
  printf '%s' "$1" | sed "s/'/'\\\\''/g"
  printf "'"
}

path_export_value() {
  case "$BIN_DIR" in
    "$HOME_PHYS"/*)
      # Keep a literal $HOME in the startup file. HOME_PHYS follows symlinks
      # such as macOS /var -> /private/var.
      # shellcheck disable=SC2016
      printf '$HOME/%s' "${BIN_DIR#"$HOME_PHYS"/}"
      ;;
    "$HOME"/*)
      # shellcheck disable=SC2016
      printf '$HOME/%s' "${BIN_DIR#"$HOME"/}"
      ;;
    *)
      printf '%s' "$BIN_DIR"
      ;;
  esac
}

write_path_block() {
  value=$1
  printf '%s\n' "$PATH_BEGIN"
  # $PATH must stay literal so the startup file prepends the directory later.
  # shellcheck disable=SC2016
  printf 'export PATH="%s:$PATH"\n' "$value"
  printf '%s\n' "$PATH_END"
}

ensure_shell_path() {
  file=$1
  value=$(path_export_value)
  if [ -f "$file" ] && grep -q "^${PATH_BEGIN}$" "$file"; then
    tmp=$(mktemp "${TMPDIR:-/tmp}/shell-tools-path.XXXXXX")
    awk -v begin="$PATH_BEGIN" -v end="$PATH_END" -v value="$value" '
      $0 == begin {
        print begin
        print "export PATH=\"" value ":$PATH\""
        print end
        skip = 1
        next
      }
      skip && $0 == end { skip = 0; next }
      skip { next }
      { print }
    ' "$file" > "$tmp" || {
      rm -f "$tmp"
      die "Could not update $file"
    }
    mv "$tmp" "$file"
    return 0
  fi

  if [ -f "$file" ] && [ -s "$file" ]; then
    printf '\n' >> "$file"
  fi
  write_path_block "$value" >> "$file"
}

shell_rc_files() {
  printf '%s\n' \
    "$HOME/.zshenv" \
    "$HOME/.zprofile" \
    "$HOME/.zshrc" \
    "$HOME/.bashrc"
  if [ -f "$HOME/.bash_profile" ]; then
    printf '%s\n' "$HOME/.bash_profile"
  else
    printf '%s\n' "$HOME/.profile"
  fi
}

install_path_blocks() {
  printf '%s\n' "PATH updated in:"
  while IFS= read -r rc; do
    [ -n "$rc" ] || continue
    ensure_shell_path "$rc"
    printf '  %s\n' "$rc"
  done <<EOF
$(shell_rc_files)
EOF
}

prepare_system_bin() {
  requested=$SYSTEM_BIN
  if [ "$SYSTEM_BIN_EXPLICIT" -eq 1 ]; then
    SYSTEM_BIN=$(expand_tilde "$SYSTEM_BIN")
    case "$SYSTEM_BIN" in
      /*) ;;
      *) SYSTEM_BIN="$(pwd)/$SYSTEM_BIN" ;;
    esac
    requested=$SYSTEM_BIN
    mkdir -p "$SYSTEM_BIN"
  fi

  if [ ! -d "$SYSTEM_BIN" ] || [ ! -w "$SYSTEM_BIN" ]; then
    SYSTEM_LINK_NOTE="$requested is not writable, so commands were not linked there."
    SYSTEM_BIN=""
    return 0
  fi
  SYSTEM_BIN=$(absolute_existing "$SYSTEM_BIN")
  if [ "$SYSTEM_BIN" = "$BIN_DIR" ]; then
    SYSTEM_BIN=""
  fi
}

link_system_command() {
  command_name=$1
  wrapper=$2
  [ -n "$SYSTEM_BIN" ] || return 0

  dest="$SYSTEM_BIN/$command_name"
  if [ -L "$dest" ] || [ ! -e "$dest" ]; then
    ln -sfn "$wrapper" "$dest"
    LINKED_SYSTEM=1
    return 0
  fi

  printf 'Left existing file %s in place\n' "$dest" >&2
  SKIPPED_LINKS="$SKIPPED_LINKS $command_name"
}

install_command() {
  command_name=$1
  executable=$2
  mode=$3
  target="$PREFIX/$executable"
  wrapper="$BIN_DIR/$command_name"
  mkdir -p "$BIN_DIR"
  chmod 755 "$target"

  case "$mode" in
    exec)
      tmpwrap="$BIN_DIR/.$command_name.new"
      {
        printf '%s\n' '#!/bin/sh'
        printf 'exec %s "$@"\n' "$(shell_quote "$target")"
      } > "$tmpwrap"
      chmod 755 "$tmpwrap"
      mv "$tmpwrap" "$wrapper"
      ;;
    link)
      ln -sfn "$target" "$wrapper"
      ;;
    *)
      die "Bad catalog mode for $command_name"
      ;;
  esac

  link_system_command "$command_name" "$wrapper"
}

install_one() {
  wanted=$1
  installed=0
  install_match() {
    [ "$name" = "$wanted" ] || return 0
    installed=1
    case "$mode" in
      exec|link) ;;
      *) die "Bad catalog mode for $name" ;;
    esac
    install_rel "$executable"
    if [ -n "$extras" ]; then
      old_ifs=$IFS
      IFS=','
      set -f
      for extra in $extras; do
        [ -n "$extra" ] || continue
        install_rel "$extra"
      done
      set +f
      IFS=$old_ifs
    fi
    install_command "$name" "$executable" "$mode"
    printf '  %s\n' "$name"
  }
  each_tool install_match
  [ "$installed" -eq 1 ] || die "Unknown tool: $wanted"
}

install_selected() {
  printf '%s\n' "Installing into $PREFIX"
  install_rel "utils"
  printf '%s\n' "Installed utils/"
  printf '%s\n' "Commands:"
  if [ "$DO_ALL" -eq 1 ]; then
    ALL_NAMES=""
    collect_name() {
      ALL_NAMES="$ALL_NAMES $name"
    }
    each_tool collect_name
    set -f
    for wanted in $ALL_NAMES; do
      install_one "$wanted"
    done
    set +f
  else
    set -f
    for wanted in $REQUESTED; do
      install_one "$wanted"
    done
    set +f
  fi
}

parse_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      -h|--help|help)
        usage
        exit 0
        ;;
      -l|--list)
        DO_LIST=1
        ;;
      -a|--all)
        DO_ALL=1
        ;;
      -p|--prefix)
        [ $# -ge 2 ] || die "--prefix requires a directory"
        shift
        PREFIX=$1
        ;;
      --prefix=*)
        PREFIX=${1#--prefix=}
        [ -n "$PREFIX" ] || die "--prefix requires a directory"
        ;;
      --system-bin)
        [ $# -ge 2 ] || die "--system-bin requires a directory"
        shift
        SYSTEM_BIN=$1
        SYSTEM_BIN_EXPLICIT=1
        ;;
      --system-bin=*)
        SYSTEM_BIN=${1#--system-bin=}
        [ -n "$SYSTEM_BIN" ] || die "--system-bin requires a directory"
        SYSTEM_BIN_EXPLICIT=1
        ;;
      --ref)
        [ $# -ge 2 ] || die "--ref requires a branch name"
        shift
        REPO_REF=$1
        ;;
      --ref=*)
        REPO_REF=${1#--ref=}
        [ -n "$REPO_REF" ] || die "--ref requires a branch name"
        ;;
      --)
        shift
        while [ $# -gt 0 ]; do
          REQUESTED="$REQUESTED $1"
          shift
        done
        break
        ;;
      -*)
        die "Unknown option: $1 (see --help)"
        ;;
      *)
        REQUESTED="$REQUESTED $1"
        ;;
    esac
    shift
  done
}

main() {
  [ -n "${HOME:-}" ] && [ -d "$HOME" ] || die "HOME is not set to a directory"
  HOME_PHYS=$(absolute_existing "$HOME")
  umask 022
  parse_args "$@"

  if [ "$DO_LIST" -eq 1 ]; then
    list_tools
    exit 0
  fi

  if [ "$DO_ALL" -eq 0 ] && [ -z "$REQUESTED" ]; then
    usage >&2
    exit 1
  fi

  if [ "$DO_ALL" -eq 1 ] && [ -n "$REQUESTED" ]; then
    die "Pass tool names or --all, not both."
  fi

  if [ -n "$REQUESTED" ]; then
    set -f
    for wanted in $REQUESTED; do
      tool_known "$wanted" || die "Unknown tool: $wanted (see --list)"
    done
    set +f
  fi

  resolve_source
  prepare_prefix
  prepare_system_bin
  install_selected
  install_path_blocks

  printf '%s\n' "Commands live in $BIN_DIR"
  if [ "$LINKED_SYSTEM" -eq 1 ]; then
    printf 'Linked into %s\n' "$SYSTEM_BIN"
  elif [ -n "$SYSTEM_LINK_NOTE" ]; then
    printf '%s\n' "$SYSTEM_LINK_NOTE"
    printf '%s\n' "New shells take commands from the PATH block above."
  fi
  if [ -n "$SKIPPED_LINKS" ]; then
    printf 'Not linked:%s\n' "$SKIPPED_LINKS"
  fi
  printf '%s\n' "Open a new terminal, then run a command by its name."
}

main "$@"
