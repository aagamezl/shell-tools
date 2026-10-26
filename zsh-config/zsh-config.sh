#!/usr/bin/env bash
# Export CachyOS/Arch zsh configuration into a portable tar.gz bundle, or install
# it on another Linux system from that archive.
#
# Original install model: restore manifest paths (system + user home).
# See copy-zsh-config.sh for the user-local (.local/etc/zsh) variant.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=utils/box-ui.sh
source "${SCRIPT_DIR}/../utils/box-ui.sh"

readonly SCRIPT_NAME="copy-zsh-config"
readonly EXIT_USAGE=1
readonly EXIT_MISSING_DEPENDENCY=2
readonly EXIT_FAILED=3
readonly SOURCE_PKG_MANAGER="pacman"

readonly ZSH_PACKAGES=(
  cachyos-zsh-config
  zsh-autosuggestions
  zsh-syntax-highlighting
  zsh-history-substring-search
  zsh-completions
  zsh-theme-powerlevel10k
  oh-my-zsh-git
)

readonly USER_ZSH_RELATIVE=(
  .zshrc
  .zshenv
  .zprofile
  .zlogin
  .zlogout
  .p10k.zsh
)

readonly SYSTEM_ZSH_FILES=(
  /etc/zsh/zshenv
  /etc/zsh/zprofile
  /etc/zsh/zshrc
  /etc/zsh/zlogin
  /etc/zsh/zlogout
  /etc/skel/.zshrc
)

readonly INSTALL_PACKAGES=(zsh)

MODE=""
DESTINATION=""
ARCHIVE=""
DRY_RUN=false
FORCE=false
SHOW_HELP=0

STAGING=""
MANIFEST=""
ARCHIVE_PATH=""
INSTALL_TEMP=""
COPIED_COUNT=0
SKIPPED_COUNT=0
BACKUP_COUNT=0
INSTALLED_COUNT=0

cleanup() {
  if [[ -n "${INSTALL_TEMP}" && -d "${INSTALL_TEMP}" ]]; then
    rm -rf "${INSTALL_TEMP}"
  fi
}
trap cleanup EXIT

usage() {
  section_open "Usage" "$C_YELLOW"
  box_row "$C_BOLD" "${SCRIPT_NAME} --export -d <path> [-a <file.tar.gz>] [-n]" "$BORDER"
  box_row "$C_BOLD" "${SCRIPT_NAME} --install -a <file.tar.gz|dir> [-f] [-n]" "$BORDER"
  box_blank "$BORDER"
  box_row "" "Export (Arch/CachyOS source):" "$BORDER"
  box_row "$C_DIM" "  Collect pacman package files and zsh dotfiles," "$BORDER"
  box_row "$C_DIM" "  write manifest.tsv, then compress to tar.gz." "$BORDER"
  box_blank "$BORDER"
  box_row "" "Install (target Linux system):" "$BORDER"
  box_row "$C_DIM" "  Install zsh if missing (idempotent)." "$BORDER"
  box_row "$C_DIM" "  Restore system paths and user files under \$HOME." "$BORDER"
  box_row "$C_DIM" "  Never replaces existing files without --force." "$BORDER"
  box_row "$C_DIM" "  With --force, backup to <path>.backup.<unix_ts> first." "$BORDER"
  box_blank "$BORDER"
  box_row "$C_DIM" "Dry-run lists every file, dependency, backup," "$BORDER"
  box_row "$C_DIM" "and archive action without changing the system." "$BORDER"
  box_blank "$BORDER"
  box_row "" "  -d, --destination <path>   Export directory (required for export)" "$BORDER"
  box_row "" "  -a, --archive <path>       tar.gz to write (export) or read (install)" "$BORDER"
  box_row "" "  -n, --dry-run              Preview actions only" "$BORDER"
  box_row "" "  -f, --force                Replace existing files on install" "$BORDER"
  box_row "" "  -h, --help                 Show this help" "$BORDER"
  section_close
}

parse_arguments() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --export)
        MODE="export"
        shift
        ;;
      --install)
        MODE="install"
        shift
        ;;
      -d | --destination)
        [[ $# -ge 2 && "$2" != -* ]] || finish "$EXIT_USAGE" "$C_RED" "Result" "✗ --destination requires a path."
        DESTINATION="$2"
        shift 2
        ;;
      -d=* | --destination=*)
        DESTINATION="${1#*=}"
        [[ -n "$DESTINATION" ]] || finish "$EXIT_USAGE" "$C_RED" "Result" "✗ --destination requires a path."
        shift
        ;;
      -a | --archive)
        [[ $# -ge 2 && "$2" != -* ]] || finish "$EXIT_USAGE" "$C_RED" "Result" "✗ --archive requires a path."
        ARCHIVE="$2"
        shift 2
        ;;
      -a=* | --archive=*)
        ARCHIVE="${1#*=}"
        [[ -n "$ARCHIVE" ]] || finish "$EXIT_USAGE" "$C_RED" "Result" "✗ --archive requires a path."
        shift
        ;;
      -n | --dry-run)
        DRY_RUN=true
        shift
        ;;
      -f | --force)
        FORCE=true
        shift
        ;;
      -h | --help)
        SHOW_HELP=1
        shift
        ;;
      *)
        finish "$EXIT_USAGE" "$C_RED" "Result" "✗ Unknown argument '$1'."
        ;;
    esac
  done
}

require_linux_for_install() {
  [[ "$(uname -s)" == Linux ]] || finish "$EXIT_FAILED" "$C_RED" "Result" "✗ Install mode targets Linux systems."
}

detect_target_pkg_manager() {
  if command -v apt-get > /dev/null 2>&1; then
    printf '%s\n' apt
  elif command -v dnf > /dev/null 2>&1; then
    printf '%s\n' dnf
  elif command -v yum > /dev/null 2>&1; then
    printf '%s\n' yum
  elif command -v zypper > /dev/null 2>&1; then
    printf '%s\n' zypper
  elif command -v pacman > /dev/null 2>&1; then
    printf '%s\n' pacman
  else
    return 1
  fi
}

pkg_installed() {
  local mgr="$1"
  local pkg="$2"

  case "$mgr" in
    apt)
      dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "install ok installed"
      ;;
    dnf | yum | zypper)
      rpm -q "$pkg" > /dev/null 2>&1
      ;;
    pacman)
      pacman -Qq "$pkg" > /dev/null 2>&1
      ;;
    *)
      return 1
      ;;
  esac
}

run_privileged() {
  if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    "$@"
  elif command -v sudo > /dev/null 2>&1; then
    sudo "$@"
  else
    finish "$EXIT_MISSING_DEPENDENCY" "$C_RED" "Result" \
      "✗ Root privileges required." \
      "  Re-run as root or install sudo."
  fi
}

ensure_packages() {
  local mgr="$1"
  shift
  local pkg

  for pkg in "$@"; do
    if pkg_installed "$mgr" "$pkg"; then
      box_row "$C_GREEN" "✓ ${pkg} already installed" "$BORDER"
      continue
    fi

    if [[ "$DRY_RUN" == true ]]; then
      box_row "$C_YELLOW" "› would install ${pkg} via ${mgr}" "$BORDER"
      continue
    fi

    box_row "$C_CYAN" "› installing ${pkg} via ${mgr}" "$BORDER"
    case "$mgr" in
      apt)
        run_privileged apt-get update -qq
        run_privileged apt-get install -y "$pkg"
        ;;
      dnf) run_privileged dnf install -y "$pkg" ;;
      yum) run_privileged yum install -y "$pkg" ;;
      zypper) run_privileged zypper --non-interactive install "$pkg" ;;
      pacman) run_privileged pacman -Sy --noconfirm "$pkg" ;;
    esac
  done
}

manifest_append() {
  local kind="$1"
  local target="$2"
  local source_rel="$3"
  printf '%s\t%s\t%s\n' "$kind" "$target" "$source_rel" >> "$MANIFEST"
}

copy_root_file_export() {
  local source_file="$1"

  [[ -f "$source_file" || -L "$source_file" ]] || return 0

  local rel="${source_file#/}"
  local dest_path="${STAGING}/root/${rel}"

  if [[ "$DRY_RUN" == true ]]; then
    box_row "$C_DIM" "  ${source_file}" "$BORDER"
  else
    mkdir -p "$(dirname "$dest_path")"
    cp --no-dereference --preserve=mode,timestamps "$source_file" "$dest_path"
    manifest_append system "/${rel}" "root/${rel}"
    box_row "$C_GREEN" "  copied ${source_file}" "$BORDER"
  fi
  COPIED_COUNT=$((COPIED_COUNT + 1))
}

copy_user_file_export() {
  local rel="$1"
  local source_file="${HOME}/${rel}"

  [[ -f "$source_file" || -L "$source_file" ]] || return 0

  local dest_path="${STAGING}/user/${rel}"

  if [[ "$DRY_RUN" == true ]]; then
    box_row "$C_DIM" "  ~/${rel}" "$BORDER"
  else
    mkdir -p "$(dirname "$dest_path")"
    cp --no-dereference --preserve=mode,timestamps "$source_file" "$dest_path"
    manifest_append user "${rel}" "user/${rel}"
    box_row "$C_GREEN" "  copied ~/${rel}" "$BORDER"
  fi
  COPIED_COUNT=$((COPIED_COUNT + 1))
}

copy_package_files_export() {
  local package_name="$1"
  local package_file

  if ! "$SOURCE_PKG_MANAGER" -Qq "$package_name" > /dev/null 2>&1; then
    box_row "$C_YELLOW" "  package not installed: ${package_name}" "$BORDER"
    return 0
  fi

  while IFS= read -r package_file; do
    if [[ -f "$package_file" || -L "$package_file" ]]; then
      copy_root_file_export "$package_file"
    fi
  done < <("$SOURCE_PKG_MANAGER" -Qlq "$package_name")
}

write_bundle_metadata() {
  if [[ "$DRY_RUN" == true ]]; then
    box_row "$C_DIM" "  would write bundle.meta" "$BORDER"
    return 0
  fi

  {
    printf 'created_at=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf 'source_host=%s\n' "$(hostname)"
    printf 'source_user=%s\n' "$(id -un)"
    printf 'packages:\n'
    local pkg
    for pkg in "${ZSH_PACKAGES[@]}"; do
      printf '  - %s\n' "$pkg"
    done
  } > "${STAGING}/bundle.meta"
}

create_archive_export() {
  local ts
  ts="$(date +%Y%m%d-%H%M%S)"

  if [[ -n "$ARCHIVE" ]]; then
    ARCHIVE_PATH="$ARCHIVE"
  else
    ARCHIVE_PATH="${DESTINATION%/}/zsh-config-${ts}.tar.gz"
  fi

  if [[ "$DRY_RUN" == true ]]; then
    box_row "$C_YELLOW" "› would create ${ARCHIVE_PATH}" "$BORDER"
    return 0
  fi

  mkdir -p "$(dirname "$ARCHIVE_PATH")"
  tar -czf "$ARCHIVE_PATH" -C "$STAGING" root user manifest.tsv bundle.meta
  box_row "$C_GREEN" "✓ ${ARCHIVE_PATH}" "$BORDER"
}

run_export() {
  local package_name rel

  [[ -n "$DESTINATION" ]] || finish "$EXIT_USAGE" "$C_RED" "Result" "✗ --destination is required for export."
  command -v "$SOURCE_PKG_MANAGER" > /dev/null 2>&1 || finish "$EXIT_MISSING_DEPENDENCY" "$C_RED" "Result" \
    "✗ pacman not found. Export requires Arch/CachyOS."

  STAGING="${DESTINATION%/}/staging"
  MANIFEST="${STAGING}/manifest.tsv"

  section_open "1 · Parameters" "$C_BLUE"
  box_row "" "Mode         export" "$BORDER"
  box_row "" "Destination  ${DESTINATION}" "$BORDER"
  box_row "" "Dry run      ${DRY_RUN}" "$BORDER"
  [[ -n "$ARCHIVE" ]] && box_row "" "Archive      ${ARCHIVE}" "$BORDER"
  section_close

  section_open "2 · Preflight" "$C_BLUE"
  box_row "$C_GREEN" "✓ pacman available" "$BORDER"
  if [[ "$DRY_RUN" == false ]]; then
    mkdir -p "${STAGING}/root" "${STAGING}/user"
    : > "$MANIFEST"
  else
    box_row "$C_DIM" "  would create ${STAGING}" "$BORDER"
  fi
  section_close

  section_open "3 · Package files" "$C_CYAN"
  for package_name in "${ZSH_PACKAGES[@]}"; do
    box_row "$C_CYAN" "› ${package_name}" "$BORDER"
    copy_package_files_export "$package_name"
  done
  section_close

  section_open "4 · System zsh files" "$C_CYAN"
  local zsh_file
  for zsh_file in "${SYSTEM_ZSH_FILES[@]}"; do
    copy_root_file_export "$zsh_file"
  done
  section_close

  section_open "5 · User zsh files" "$C_CYAN"
  for rel in "${USER_ZSH_RELATIVE[@]}"; do
    copy_user_file_export "$rel"
  done
  section_close

  section_open "6 · Metadata" "$C_CYAN"
  if [[ "$DRY_RUN" == false && -f "$MANIFEST" ]]; then
    sort -u -o "$MANIFEST" "$MANIFEST"
    box_row "$C_DIM" "  manifest: $(wc -l < "$MANIFEST" | tr -d ' ') unique path(s)" "$BORDER"
  fi
  write_bundle_metadata
  section_close

  section_open "7 · Compress" "$C_CYAN"
  create_archive_export
  section_close

  if [[ "$DRY_RUN" == true ]]; then
    finish 0 "$C_GREEN" "Result" \
      "✓ Dry run complete." \
      "  ${COPIED_COUNT} file(s) would be collected." \
      "  Archive would be written to ${ARCHIVE_PATH:-${DESTINATION%/}/zsh-config-<timestamp>.tar.gz}."
  fi

  finish 0 "$C_GREEN" "Result" \
    "✓ Exported ${COPIED_COUNT} file(s)." \
    "  Staging: ${STAGING}" \
    "  Archive: ${ARCHIVE_PATH}"
}

resolve_install_target() {
  local target="$1"
  local kind="$2"
  if [[ "$kind" == user ]]; then
    printf '%s/%s\n' "$HOME" "$target"
  else
    printf '%s\n' "$target"
  fi
}

files_equal() {
  local a="$1"
  local b="$2"
  [[ -f "$a" && -f "$b" ]] && cmp -s "$a" "$b"
}

needs_privilege_for() {
  local path="$1"
  [[ "$path" == "$HOME"/* ]] && return 1
  [[ -w "$(dirname "$path")" ]] 2>/dev/null && return 1
  return 0
}

install_copy_to() {
  local source_path="$1"
  local dest_path="$2"

  if needs_privilege_for "$dest_path"; then
    run_privileged mkdir -p "$(dirname "$dest_path")"
    run_privileged cp --no-dereference --preserve=mode,timestamps "$source_path" "$dest_path"
  else
    mkdir -p "$(dirname "$dest_path")"
    cp --no-dereference --preserve=mode,timestamps "$source_path" "$dest_path"
  fi
}

backup_file() {
  local dest_path="$1"
  local ts backup_path

  ts="$(date +%s)"
  backup_path="${dest_path}.backup.${ts}"

  if [[ "$DRY_RUN" == true ]]; then
    box_row "$C_YELLOW" "  would backup ${dest_path}" "$BORDER"
    box_row "$C_YELLOW" "    → ${backup_path}" "$BORDER"
    BACKUP_COUNT=$((BACKUP_COUNT + 1))
    return 0
  fi

  if needs_privilege_for "$dest_path"; then
    run_privileged cp -a "$dest_path" "$backup_path"
  else
    cp -a "$dest_path" "$backup_path"
  fi
  BACKUP_COUNT=$((BACKUP_COUNT + 1))
}

install_one_file() {
  local kind="$1"
  local target="$2"
  local source_rel="$3"
  local source_path="${STAGING}/${source_rel}"
  local dest_path
  dest_path="$(resolve_install_target "$target" "$kind")"

  if [[ ! -f "$source_path" && ! -L "$source_path" ]]; then
    box_row "$C_YELLOW" "  skip (missing in bundle): ${source_rel}" "$BORDER"
    SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
    return 0
  fi

  if [[ -e "$dest_path" ]]; then
    if files_equal "$dest_path" "$source_path"; then
      box_row "$C_DIM" "  unchanged ${dest_path}" "$BORDER"
      SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
      return 0
    fi
    if [[ "$FORCE" != true ]]; then
      box_row "$C_YELLOW" "  exists, skip ${dest_path}" "$BORDER"
      SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
      return 0
    fi
    if [[ -d "$dest_path" ]]; then
      box_row "$C_RED" "  cannot replace directory ${dest_path}" "$BORDER"
      SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
      return 0
    fi
    backup_file "$dest_path"
  fi

  if [[ "$DRY_RUN" == true ]]; then
    box_row "$C_GREEN" "  would install ${dest_path}" "$BORDER"
    INSTALLED_COUNT=$((INSTALLED_COUNT + 1))
    return 0
  fi

  install_copy_to "$source_path" "$dest_path"
  box_row "$C_GREEN" "  installed ${dest_path}" "$BORDER"
  INSTALLED_COUNT=$((INSTALLED_COUNT + 1))
}

load_install_bundle() {
  local input="$1"

  [[ -n "$input" ]] || finish "$EXIT_USAGE" "$C_RED" "Result" "✗ --archive is required for install."

  if [[ -f "$input" ]]; then
    if ! tar -tzf "$input" manifest.tsv > /dev/null 2>&1; then
      finish "$EXIT_FAILED" "$C_RED" "Result" "✗ Archive missing manifest.tsv: ${input}"
    fi
    INSTALL_TEMP="$(mktemp -d "${TMPDIR:-/tmp}/copy-zsh-config.XXXXXX")"
    tar -xzf "$input" -C "$INSTALL_TEMP"
    STAGING="$INSTALL_TEMP"
    MANIFEST="${STAGING}/manifest.tsv"
    box_row "$C_GREEN" "✓ Loaded ${input}" "$BORDER"
    return 0
  fi

  if [[ -d "$input" ]]; then
    STAGING="${input%/}"
    MANIFEST="${STAGING}/manifest.tsv"
    [[ -f "$MANIFEST" ]] || finish "$EXIT_FAILED" "$C_RED" "Result" "✗ Missing manifest.tsv in ${input}"
    box_row "$C_GREEN" "✓ Using directory ${STAGING}" "$BORDER"
    return 0
  fi

  finish "$EXIT_FAILED" "$C_RED" "Result" "✗ Archive not found: ${input}"
}

run_install() {
  local mgr kind target source_rel

  require_linux_for_install
  [[ -n "$ARCHIVE" ]] || finish "$EXIT_USAGE" "$C_RED" "Result" "✗ --archive is required for install."

  section_open "1 · Parameters" "$C_BLUE"
  box_row "" "Mode         install" "$BORDER"
  box_row "" "Archive      ${ARCHIVE}" "$BORDER"
  box_row "" "Dry run      ${DRY_RUN}" "$BORDER"
  box_row "" "Force        ${FORCE}" "$BORDER"
  box_row "" "HOME         ${HOME}" "$BORDER"
  section_close

  section_open "2 · Load bundle" "$C_BLUE"
  if [[ "$DRY_RUN" == true ]]; then
    box_row "$C_DIM" "  would extract/read ${ARCHIVE}" "$BORDER"
    if [[ -f "$ARCHIVE" ]]; then
      INSTALL_TEMP="$(mktemp -d "${TMPDIR:-/tmp}/copy-zsh-config.XXXXXX")"
      tar -xzf "$ARCHIVE" -C "$INSTALL_TEMP"
      STAGING="$INSTALL_TEMP"
      MANIFEST="${STAGING}/manifest.tsv"
    elif [[ -d "$ARCHIVE" ]]; then
      STAGING="${ARCHIVE%/}"
      MANIFEST="${STAGING}/manifest.tsv"
    fi
    [[ -f "${MANIFEST:-}" ]] || finish "$EXIT_FAILED" "$C_RED" "Result" "✗ Cannot read manifest for dry-run."
  else
    load_install_bundle "$ARCHIVE"
  fi
  section_close

  section_open "3 · Dependencies" "$C_CYAN"
  mgr="$(detect_target_pkg_manager)" || finish "$EXIT_MISSING_DEPENDENCY" "$C_RED" "Result" \
    "✗ No supported package manager (apt, dnf, yum, zypper, pacman)."
  box_row "" "Package mgr  ${mgr}" "$BORDER"
  ensure_packages "$mgr" "${INSTALL_PACKAGES[@]}"
  if command -v zsh > /dev/null 2>&1; then
    box_row "$C_GREEN" "✓ $(zsh --version 2>/dev/null | head -n1)" "$BORDER"
  elif [[ "$DRY_RUN" == true ]]; then
    box_row "$C_YELLOW" "› zsh would be required after package install" "$BORDER"
  else
    finish "$EXIT_MISSING_DEPENDENCY" "$C_RED" "Result" "✗ zsh is not available."
  fi
  section_close

  section_open "4 · Install files" "$C_CYAN"
  while IFS=$'\t' read -r kind target source_rel || [[ -n "${kind:-}" ]]; do
    [[ -z "${kind:-}" || "$kind" == kind ]] && continue
    install_one_file "$kind" "$target" "$source_rel"
  done < "$MANIFEST"
  section_close

  if [[ "$DRY_RUN" == true ]]; then
    finish 0 "$C_GREEN" "Result" \
      "✓ Dry run complete." \
      "  Would install ${INSTALLED_COUNT} file(s)." \
      "  Would skip ${SKIPPED_COUNT} (missing, unchanged, or existing)." \
      "  Would create ${BACKUP_COUNT} backup(s) with --force."
  fi

  finish 0 "$C_GREEN" "Result" \
    "✓ Installed ${INSTALLED_COUNT} file(s)." \
    "  Skipped ${SKIPPED_COUNT}." \
    "  Backups ${BACKUP_COUNT}."
}

main() {
  choose_box_width 68
  parse_arguments "$@"

  if (( SHOW_HELP )); then
    box_banner "$SCRIPT_NAME" "Export or install a portable zsh configuration bundle."
    usage
    exit 0
  fi

  if [[ -z "$MODE" && -n "$DESTINATION" ]]; then
    MODE="export"
  fi

  [[ -n "$MODE" ]] || {
    box_banner "$SCRIPT_NAME" "Export or install a portable zsh configuration bundle."
    usage
    finish "$EXIT_USAGE" "$C_RED" "Result" "✗ Use --export or --install."
  }

  box_banner "$SCRIPT_NAME" "Export or install a portable zsh configuration bundle."

  case "$MODE" in
    export) run_export ;;
    install) run_install ;;
    *) finish "$EXIT_USAGE" "$C_RED" "Result" "✗ Unknown mode '${MODE}'." ;;
  esac
}

main "$@"
