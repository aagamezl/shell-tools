#!/usr/bin/env bash
# Configure zsh from a CachyOS zsh configuration bundle.
#
# Export (on CachyOS) copies only configuration: cachyos-zsh-config, /etc/zsh,
# /etc/skel, and the user dotfiles. It does not archive oh-my-zsh or plugins.
#
# Install writes that configuration under $HOME/.local/$ZSH_CONFIG_NAME and
# installs zsh, oh-my-zsh, and the zsh-users plugins from the target system
# and from upstream git. Nothing is written outside $HOME, and nothing is
# copied out of the bundle's /usr tree.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=utils/box-ui.sh
source "${SCRIPT_DIR}/utils/box-ui.sh"
# shellcheck source=utils/zsh-tool-paths.sh
source "${SCRIPT_DIR}/utils/zsh-tool-paths.sh"

readonly SCRIPT_NAME="zsh-config"
readonly EXIT_USAGE=1
readonly EXIT_MISSING_DEPENDENCY=2
readonly EXIT_FAILED=3

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
  /etc/skel/.zshenv
  /etc/skel/.zprofile
  /etc/skel/.p10k.zsh
)

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
PREP=""
PATHS_FILE=""
SOURCE_USER=""
SOURCE_HOME=""
COPIED_COUNT=0
SKIPPED_COUNT=0
TOOL_SKIP_COUNT=0
OTHER_SKIP_COUNT=0
BACKUP_COUNT=0
INSTALLED_COUNT=0

cleanup() {
  if [[ -n "${INSTALL_TEMP}" && -d "${INSTALL_TEMP}" ]]; then
    rm -rf "${INSTALL_TEMP}"
  fi
  if [[ -n "${PREP}" && -d "${PREP}" ]]; then
    rm -rf "${PREP}"
  fi
}
trap cleanup EXIT

usage() {
  section_open "Usage" "$C_YELLOW"
  box_row "$C_BOLD" "${SCRIPT_NAME} --export -d <path> [-a <file.tar.gz>] [-n]" "$BORDER"
  box_row "$C_BOLD" "${SCRIPT_NAME} --install -a <file.tar.gz> [-f] [-n]" "$BORDER"
  box_row "$C_BOLD" "${SCRIPT_NAME} --uninstall [-n]" "$BORDER"
  box_blank "$BORDER"
  box_row "" "Export, on the CachyOS machine:" "$BORDER"
  box_row "$C_DIM" "  Copy cachyos-zsh-config, /etc/zsh, /etc/skel, and the" "$BORDER"
  box_row "$C_DIM" "  user zsh dotfiles. oh-my-zsh and plugins are not archived." "$BORDER"
  box_blank "$BORDER"
  box_row "" "Install, on the new system:" "$BORDER"
  box_row "$C_DIM" "  Install zsh with the package manager. Clone oh-my-zsh," "$BORDER"
  box_row "$C_DIM" "  zsh-syntax-highlighting, zsh-autosuggestions," "$BORDER"
  box_row "$C_DIM" "  zsh-completions, and zsh-history-substring-search" "$BORDER"
  box_row "$C_DIM" "  from upstream into ~/${ZSH_TOOLS_REL}." "$BORDER"
  box_row "$C_DIM" "  powerlevel10k is cloned too: the CachyOS config sources it." "$BORDER"
  box_row "$C_DIM" "  Configuration is written only under ~/${ZSH_CONFIG_REL}." "$BORDER"
  box_row "$C_DIM" "  ~/.zshenv gains a ZDOTDIR block. /etc and /usr are untouched." "$BORDER"
  box_row "$C_DIM" "  Existing config is kept unless --force, which backups first." "$BORDER"
  box_blank "$BORDER"
  box_row "" "Uninstall:" "$BORDER"
  box_row "$C_DIM" "  Remove ~/${ZSH_ROOT_REL} and the ZDOTDIR block in ~/.zshenv." "$BORDER"
  box_row "$C_DIM" "  Restore ~/.zshenv from the pre-install backup when one exists." "$BORDER"
  box_row "$C_DIM" "  ~/.zshrc, the login shell, and the zsh package stay as they are." "$BORDER"
  box_blank "$BORDER"
  box_row "" "  -d, --destination <path>   Export directory" "$BORDER"
  box_row "" "  -a, --archive <file.tar.gz>  Archive to write or install" "$BORDER"
  box_row "" "  -n, --dry-run              Preview only" "$BORDER"
  box_row "" "  -f, --force                Replace existing config files" "$BORDER"
  box_row "" "  -h, --help                 Show this help" "$BORDER"
  section_close
}

parse_arguments() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --export)
        [[ -z "$MODE" || "$MODE" == export ]] || finish "$EXIT_USAGE" "$C_RED" "Result" "✗ Use only one of --export, --install, or --uninstall."
        MODE="export"
        shift
        ;;
      --install)
        [[ -z "$MODE" || "$MODE" == install ]] || finish "$EXIT_USAGE" "$C_RED" "Result" "✗ Use only one of --export, --install, or --uninstall."
        MODE="install"
        shift
        ;;
      --uninstall)
        [[ -z "$MODE" || "$MODE" == uninstall ]] || finish "$EXIT_USAGE" "$C_RED" "Result" "✗ Use only one of --export, --install, or --uninstall."
        MODE="uninstall"
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

manifest_append() {
  local kind="$1"
  local target="$2"
  local source_rel="$3"
  printf '%s\t%s\t%s\n' "$kind" "$target" "$source_rel" >> "$MANIFEST"
}

copy_config_file() {
  local source_file="$1"
  local dest_rel="$2"
  local source_rel="$3"

  if [[ ! -f "$source_file" && ! -L "$source_file" ]]; then
    box_row "$C_DIM" "  absent ${source_file}" "$BORDER"
    return 0
  fi

  if [[ "$DRY_RUN" == true ]]; then
    box_row "$C_DIM" "  ${source_file} → ~/${ZSH_CONFIG_REL}/${dest_rel}" "$BORDER"
    COPIED_COUNT=$((COPIED_COUNT + 1))
    return 0
  fi

  local dest_path="${STAGING}/${source_rel}"
  mkdir -p "$(dirname "$dest_path")"
  cp -p "$source_file" "$dest_path"
  manifest_append config "$dest_rel" "$source_rel"
  box_row "$C_GREEN" "  copied ${source_file}" "$BORDER"
  COPIED_COUNT=$((COPIED_COUNT + 1))
}

export_cachyos_package() {
  local package_file rel

  if ! command -v pacman > /dev/null 2>&1 || ! pacman -Qq cachyos-zsh-config > /dev/null 2>&1; then
    box_row "$C_YELLOW" "  package not installed: cachyos-zsh-config" "$BORDER"
    return 0
  fi

  while IFS= read -r package_file; do
    [[ -f "$package_file" || -L "$package_file" ]] || continue
    [[ "$package_file" == *.zwc ]] && continue
    [[ "$package_file" == /usr/share/cachyos-zsh-config/* ]] || continue
    rel="${package_file#/usr/share/cachyos-zsh-config/}"
    copy_config_file "$package_file" "$rel" "config/cachyos/${rel}"
  done < <(pacman -Qlq cachyos-zsh-config)
}

export_system_file() {
  local source_file="$1"
  local rest dest_rel source_rel

  case "$source_file" in
    /etc/zsh/*)
      rest="${source_file#/etc/zsh/}"
      if [[ "$rest" == */* ]]; then
        dest_rel="host-etc/${rest}"
      else
        dest_rel=".${rest}"
      fi
      source_rel="config/host-etc/zsh/${rest}"
      ;;
    /etc/skel/*)
      rest="${source_file#/etc/skel/}"
      dest_rel="${rest}"
      source_rel="config/host-etc/skel/${rest}"
      ;;
    *)
      return 0
      ;;
  esac
  copy_config_file "$source_file" "$dest_rel" "$source_rel"
}

discover_export_path() {
  local key="$1"
  local found=""

  command -v pacman > /dev/null 2>&1 || {
    default_source_path "$key"
    return 0
  }

  case "$key" in
    OMZ_ROOT)
      found="$(pacman -Qlq oh-my-zsh-git 2>/dev/null | grep -E '/oh-my-zsh\.sh$' | head -n 1 || true)"
      [[ -n "$found" ]] && dirname "$found" && return 0
      ;;
    AUTOSUGGESTIONS)
      found="$(pacman -Qlq zsh-autosuggestions 2>/dev/null | grep -E '/zsh-autosuggestions\.zsh$' | head -n 1 || true)"
      [[ -n "$found" ]] && printf '%s\n' "$found" && return 0
      ;;
    SYNTAX_HIGHLIGHTING)
      found="$(pacman -Qlq zsh-syntax-highlighting 2>/dev/null | grep -E '/zsh-syntax-highlighting\.zsh$' | head -n 1 || true)"
      [[ -n "$found" ]] && printf '%s\n' "$found" && return 0
      ;;
    HISTORY_SUBSTRING)
      found="$(pacman -Qlq zsh-history-substring-search 2>/dev/null | grep -E '/zsh-history-substring-search\.zsh$' | head -n 1 || true)"
      [[ -n "$found" ]] && printf '%s\n' "$found" && return 0
      ;;
    COMPLETIONS_DIR)
      found="$(pacman -Qlq zsh-completions 2>/dev/null | grep -E '/site-functions/' | head -n 1 || true)"
      [[ -n "$found" ]] && dirname "$found" && return 0
      ;;
    POWERLEVEL10K)
      found="$(pacman -Qlq zsh-theme-powerlevel10k 2>/dev/null | grep -E '/powerlevel10k\.zsh-theme$' | head -n 1 || true)"
      [[ -n "$found" ]] && dirname "$found" && return 0
      ;;
    CACHYOS_ZSH_CONFIG)
      found="$(pacman -Qlq cachyos-zsh-config 2>/dev/null | grep -E '/cachyos-config\.zsh$' | head -n 1 || true)"
      [[ -n "$found" ]] && dirname "$found" && return 0
      ;;
  esac
  default_source_path "$key"
}

write_tool_paths_export() {
  local paths_file="${STAGING}/tool-paths.source.tsv"
  local key path

  if [[ "$DRY_RUN" == true ]]; then
    box_row "$C_DIM" "  would write tool-paths.source.tsv" "$BORDER"
    return 0
  fi

  : > "$paths_file"
  while IFS= read -r key; do
    [[ -n "$key" ]] || continue
    path="$(discover_export_path "$key")"
    printf '%s\t%s\n' "$key" "$path" >> "$paths_file"
  done < <(zsh_tool_keys)
  box_row "$C_DIM" "  tool-paths.source.tsv ($(wc -l < "$paths_file" | tr -d ' ') entries)" "$BORDER"
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
    printf 'source_home=%s\n' "$HOME"
    printf 'layout=home-local\n'
    printf 'tools=upstream-git\n'
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
  tar -czf "$ARCHIVE_PATH" -C "$STAGING" config manifest.tsv bundle.meta tool-paths.source.tsv
  box_row "$C_GREEN" "✓ ${ARCHIVE_PATH}" "$BORDER"
}

run_export() {
  local rel zsh_file key

  [[ -n "$DESTINATION" ]] || finish "$EXIT_USAGE" "$C_RED" "Result" "✗ --destination is required for export."
  command -v pacman > /dev/null 2>&1 || finish "$EXIT_MISSING_DEPENDENCY" "$C_RED" "Result" \
    "✗ pacman not found. Export runs on Arch or CachyOS."

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
    mkdir -p "${STAGING}/config"
    : > "$MANIFEST"
  else
    box_row "$C_DIM" "  would create ${STAGING}" "$BORDER"
  fi
  section_close

  section_open "3 · CachyOS configuration" "$C_CYAN"
  export_cachyos_package
  for zsh_file in "${SYSTEM_ZSH_FILES[@]}"; do
    export_system_file "$zsh_file"
  done
  section_close

  section_open "4 · User configuration" "$C_CYAN"
  for rel in "${USER_ZSH_RELATIVE[@]}"; do
    copy_config_file "${HOME}/${rel}" "$rel" "config/user/${rel}"
  done
  section_close

  section_open "5 · Tools (not copied)" "$C_CYAN"
  box_row "$C_DIM" "  Installed on the target from upstream, not from this host." "$BORDER"
  while IFS= read -r key; do
    [[ -n "$key" ]] || continue
    [[ "$key" == CACHYOS_ZSH_CONFIG ]] && continue
    box_row "$C_DIM" "  $(tool_label "$key")" "$BORDER"
  done < <(clone_tool_keys)
  section_close

  section_open "6 · Metadata" "$C_CYAN"
  if [[ "$DRY_RUN" == false && -f "$MANIFEST" ]]; then
    sort -u -o "$MANIFEST" "$MANIFEST"
    box_row "$C_DIM" "  manifest: $(wc -l < "$MANIFEST" | tr -d ' ') path(s)" "$BORDER"
  fi
  write_bundle_metadata
  write_tool_paths_export
  section_close

  section_open "7 · Compress" "$C_CYAN"
  create_archive_export
  section_close

  if [[ "$DRY_RUN" == true ]]; then
    finish 0 "$C_GREEN" "Result" \
      "✓ Dry run complete." \
      "  ${COPIED_COUNT} config file(s) would be collected." \
      "  Archive would be ${ARCHIVE_PATH:-${DESTINATION%/}/zsh-config-<timestamp>.tar.gz}."
  fi

  finish 0 "$C_GREEN" "Result" \
    "✓ Exported ${COPIED_COUNT} config file(s)." \
    "  Staging: ${STAGING}" \
    "  Archive: ${ARCHIVE_PATH}"
}

detect_pkg_manager() {
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
  elif command -v brew > /dev/null 2>&1; then
    printf '%s\n' brew
  else
    return 1
  fi
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

install_formulas() {
  local mgr="$1"
  shift
  local pkg

  [[ $# -gt 0 ]] || return 0
  if [[ "$DRY_RUN" == true ]]; then
    for pkg in "$@"; do
      box_row "$C_YELLOW" "› would install ${pkg} via ${mgr}" "$BORDER"
    done
    return 0
  fi

  for pkg in "$@"; do
    box_row "$C_CYAN" "› installing ${pkg} via ${mgr}" "$BORDER"
  done
  case "$mgr" in
    apt)
      run_privileged apt-get update -qq
      run_privileged apt-get install -y "$@"
      ;;
    dnf) run_privileged dnf install -y "$@" ;;
    yum) run_privileged yum install -y "$@" ;;
    zypper) run_privileged zypper --non-interactive install "$@" ;;
    pacman) run_privileged pacman -Sy --noconfirm "$@" ;;
    brew) brew install "$@" ;;
    *)
      finish "$EXIT_MISSING_DEPENDENCY" "$C_RED" "Result" "✗ Unsupported package manager '${mgr}'."
      ;;
  esac
}

ensure_command() {
  local cmd="$1"
  local mgr="$2"

  if command -v "$cmd" > /dev/null 2>&1; then
    box_row "$C_GREEN" "✓ ${cmd}" "$BORDER"
    return 0
  fi
  if [[ -z "$mgr" ]]; then
    finish "$EXIT_MISSING_DEPENDENCY" "$C_RED" "Result" \
      "✗ ${cmd} is missing and no package manager was found."
  fi
  install_formulas "$mgr" "$cmd"
  if [[ "$DRY_RUN" == true ]]; then
    return 0
  fi
  command -v "$cmd" > /dev/null 2>&1 || finish "$EXIT_MISSING_DEPENDENCY" "$C_RED" "Result" \
    "✗ ${cmd} is still not available."
  box_row "$C_GREEN" "✓ ${cmd}" "$BORDER"
}

load_install_bundle() {
  local input="$1"

  [[ -n "$input" ]] || finish "$EXIT_USAGE" "$C_RED" "Result" "✗ --archive is required for install."

  if [[ -d "$input" ]]; then
    finish "$EXIT_USAGE" "$C_RED" "Result" \
      "✗ Install reads a .tar.gz archive, not a directory." \
      "  Pass the archive, for example ${input%/}.tar.gz"
  fi

  if [[ ! -f "$input" ]]; then
    finish "$EXIT_FAILED" "$C_RED" "Result" "✗ Archive not found: ${input}"
  fi

  case "$input" in
    *.tar.gz | *.tgz) ;;
    *)
      finish "$EXIT_USAGE" "$C_RED" "Result" "✗ --archive must be a .tar.gz file: ${input}"
      ;;
  esac

  if ! tar -tzf "$input" manifest.tsv > /dev/null 2>&1; then
    finish "$EXIT_FAILED" "$C_RED" "Result" "✗ Archive missing manifest.tsv: ${input}"
  fi

  INSTALL_TEMP="$(mktemp -d "${TMPDIR:-/tmp}/zsh-config.XXXXXX")"
  tar -xzf "$input" -C "$INSTALL_TEMP"
  STAGING="$INSTALL_TEMP"
  MANIFEST="${STAGING}/manifest.tsv"
  box_row "$C_GREEN" "✓ Loaded ${input}" "$BORDER"
}

read_bundle_identity() {
  local meta="${STAGING}/bundle.meta"
  PATHS_FILE="${STAGING}/tool-paths.source.tsv"
  [[ -f "$PATHS_FILE" ]] || PATHS_FILE=""
  SOURCE_USER=""
  SOURCE_HOME=""
  [[ -f "$meta" ]] || return 0
  SOURCE_USER="$(awk -F= '$1 == "source_user" { print substr($0, index($0, "=") + 1); exit }' "$meta")"
  SOURCE_HOME="$(awk -F= '$1 == "source_home" { print substr($0, index($0, "=") + 1); exit }' "$meta")"
}

priority_for_source() {
  case "$1" in
    config/host-etc/skel/* | */skel/*) printf '1\n' ;;
    config/host-etc/*) printf '2\n' ;;
    *) printf '3\n' ;;
  esac
}

legacy_dest_rel() {
  local target="$1"
  local rest

  case "$target" in
    /usr/share/cachyos-zsh-config/*)
      printf '%s\n' "${target#/usr/share/cachyos-zsh-config/}"
      ;;
    /etc/zsh/*)
      rest="${target#/etc/zsh/}"
      if [[ "$rest" == */* ]]; then
        printf '%s\n' "host-etc/${rest}"
      else
        printf '%s\n' ".${rest}"
      fi
      ;;
    /etc/skel/*)
      printf '%s\n' "${target#/etc/skel/}"
      ;;
    .zshrc | .zshenv | .zprofile | .zlogin | .zlogout | .p10k.zsh)
      printf '%s\n' "$target"
      ;;
    *)
      return 1
      ;;
  esac
}

legacy_priority() {
  case "$1" in
    /etc/skel/*) printf '1\n' ;;
    /etc/zsh/*) printf '2\n' ;;
    *) printf '3\n' ;;
  esac
}

stage_config() {
  local pri="$1"
  local dest_rel="$2"
  local source_path="$3"
  local current=""
  local staged

  if [[ ! -f "$source_path" && ! -L "$source_path" ]]; then
    box_row "$C_YELLOW" "  missing in bundle: ${source_path#"${STAGING}"/}" "$BORDER"
    OTHER_SKIP_COUNT=$((OTHER_SKIP_COUNT + 1))
    return 0
  fi

  if [[ -f "$PREP/index.tsv" ]]; then
    current="$(awk -F '\t' -v d="$dest_rel" '$1 == d { print $2; exit }' "$PREP/index.tsv")"
  fi
  if [[ -n "$current" && "$current" -ge "$pri" ]]; then
    return 0
  fi

  staged="${PREP}/files/${dest_rel}"
  mkdir -p "$(dirname "$staged")"
  cp -p "$source_path" "$staged"

  if [[ -n "$current" ]]; then
    awk -F '\t' -v d="$dest_rel" 'BEGIN { OFS = "\t" } $1 != d { print }' "$PREP/index.tsv" > "$PREP/index.tmp"
    mv "$PREP/index.tmp" "$PREP/index.tsv"
  fi
  printf '%s\t%s\t%s\n' "$dest_rel" "$pri" "$staged" >> "$PREP/index.tsv"
}

stage_bundle_files() {
  local kind target source_rel source_path dest_rel pri
  local use_config=false

  if grep -q '^config	' "$MANIFEST"; then
    use_config=true
  fi

  : > "$PREP/index.tsv"
  while IFS=$'\t' read -r kind target source_rel || [[ -n "${kind:-}" ]]; do
    [[ -z "${kind:-}" || "$kind" == \#* || "$kind" == kind ]] && continue
    source_path="${STAGING}/${source_rel}"

    if [[ "$use_config" == true ]]; then
      [[ "$kind" == config ]] || continue
      pri="$(priority_for_source "$source_rel")"
      stage_config "$pri" "$target" "$source_path"
      continue
    fi

    if [[ "$kind" == system ]]; then
      if is_bundled_tool_path "$target"; then
        TOOL_SKIP_COUNT=$((TOOL_SKIP_COUNT + 1))
        continue
      fi
      dest_rel="$(legacy_dest_rel "$target" || true)"
      if [[ -z "$dest_rel" ]]; then
        OTHER_SKIP_COUNT=$((OTHER_SKIP_COUNT + 1))
        continue
      fi
      pri="$(legacy_priority "$target")"
      stage_config "$pri" "$dest_rel" "$source_path"
      continue
    fi

    if [[ "$kind" == user ]]; then
      dest_rel="$(legacy_dest_rel "$target" || true)"
      if [[ -z "$dest_rel" ]]; then
        OTHER_SKIP_COUNT=$((OTHER_SKIP_COUNT + 1))
        continue
      fi
      stage_config 3 "$dest_rel" "$source_path"
      continue
    fi

    OTHER_SKIP_COUNT=$((OTHER_SKIP_COUNT + 1))
  done < "$MANIFEST"
}

path_will_exist() {
  local expanded="$1"
  [[ -e "$expanded" ]] && return 0
  case "$expanded" in
    "${HOME}/${ZSH_ROOT_REL}/"*) return 0 ;;
  esac
  return 1
}

expand_install_path() {
  local path="$1"
  case "$path" in
    '$HOME'/*) printf '%s\n' "${HOME}/${path#\$HOME/}" ;;
    '~'/*) printf '%s\n' "${HOME}/${path#\~/}" ;;
    /*) printf '%s\n' "$path" ;;
    *) return 1 ;;
  esac
}

guard_missing_sources() {
  local file="$1"
  local tmp="${file}.guard"
  local line path expanded

  : > "$tmp"
  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" =~ ^[[:space:]]*source[[:space:]]+([^[:space:]]+)[[:space:]]*$ ]]; then
      path="${BASH_REMATCH[1]}"
      path="${path#\"}"
      path="${path%\"}"
      path="${path#\'}"
      path="${path%\'}"
      if expanded="$(expand_install_path "$path")"; then
        if ! path_will_exist "$expanded"; then
          line="[[ -r \"${path}\" ]] && ${line}"
        fi
      fi
    fi
    printf '%s\n' "$line" >> "$tmp"
  done < "$file"
  mv "$tmp" "$file"
}

inject_paths_source() {
  local file="$1"
  local tmp="${file}.inject"
  local line inserted=0
  local paths_ref snippet
  paths_ref="$(zsh_file_path CACHYOS_ZSH_CONFIG)/paths.generated.zsh"
  snippet="[[ -f \"${paths_ref}\" ]] && source \"${paths_ref}\""

  grep -q 'oh-my-zsh.sh' "$file" || return 0
  grep -q 'zsh-config completions' "$file" && return 0

  : > "$tmp"
  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$inserted" -eq 0 && "$line" == *source* && "$line" == *oh-my-zsh.sh* ]]; then
      printf '%s\n' '# >>> zsh-config completions >>>' >> "$tmp"
      printf '%s\n' "$snippet" >> "$tmp"
      printf '%s\n' '# <<< zsh-config completions >>>' >> "$tmp"
      inserted=1
    fi
    printf '%s\n' "$line" >> "$tmp"
  done < "$file"
  mv "$tmp" "$file"
}

prepare_staged_files() {
  local dest_rel pri staged

  [[ -s "$PREP/index.tsv" ]] || finish "$EXIT_FAILED" "$C_RED" "Result" \
    "✗ Bundle has no zsh configuration to install."

  while IFS=$'\t' read -r dest_rel pri staged || [[ -n "${dest_rel:-}" ]]; do
    [[ -n "${dest_rel:-}" ]] || continue
    rewrite_config_file "$staged" "$PATHS_FILE" "$SOURCE_USER" "$SOURCE_HOME"
    inject_paths_source "$staged"
    guard_missing_sources "$staged"
  done < "$PREP/index.tsv"
}

backup_file() {
  local dest_path="$1"
  local backup_path
  backup_path="${dest_path}.backup.$(date +%s)"

  if [[ "$DRY_RUN" == true ]]; then
    box_row "$C_YELLOW" "  would backup ${dest_path}" "$BORDER"
    box_row "$C_YELLOW" "    → ${backup_path}" "$BORDER"
    BACKUP_COUNT=$((BACKUP_COUNT + 1))
    return 0
  fi
  cp -p "$dest_path" "$backup_path"
  BACKUP_COUNT=$((BACKUP_COUNT + 1))
}

refuse_outside_home() {
  local dest_path="$1"
  case "$dest_path" in
    "${HOME}/"*) return 0 ;;
  esac
  finish "$EXIT_FAILED" "$C_RED" "Result" "✗ Refusing to write outside home: ${dest_path}"
}

install_prepared_file() {
  local dest_rel="$1"
  local source_path="$2"
  local dest_path="${HOME}/${ZSH_CONFIG_REL}/${dest_rel}"

  refuse_outside_home "$dest_path"

  if [[ -e "$dest_path" ]] && cmp -s "$dest_path" "$source_path"; then
    box_row "$C_DIM" "  unchanged ~/${ZSH_CONFIG_REL}/${dest_rel}" "$BORDER"
    SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
    return 0
  fi
  if [[ -e "$dest_path" ]]; then
    if [[ -d "$dest_path" ]]; then
      box_row "$C_RED" "  cannot replace directory ~/${ZSH_CONFIG_REL}/${dest_rel}" "$BORDER"
      SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
      return 0
    fi
    if [[ "$FORCE" != true ]]; then
      box_row "$C_YELLOW" "  exists, skip ~/${ZSH_CONFIG_REL}/${dest_rel}" "$BORDER"
      SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
      return 0
    fi
    backup_file "$dest_path"
  fi

  if [[ "$DRY_RUN" == true ]]; then
    box_row "$C_GREEN" "  would install ~/${ZSH_CONFIG_REL}/${dest_rel}" "$BORDER"
    INSTALLED_COUNT=$((INSTALLED_COUNT + 1))
    return 0
  fi

  mkdir -p "$(dirname "$dest_path")"
  cp -p "$source_path" "$dest_path"
  box_row "$C_GREEN" "  installed ~/${ZSH_CONFIG_REL}/${dest_rel}" "$BORDER"
  INSTALLED_COUNT=$((INSTALLED_COUNT + 1))
}

install_staged_tree() {
  local dest_rel pri staged
  while IFS=$'\t' read -r dest_rel pri staged || [[ -n "${dest_rel:-}" ]]; do
    [[ -n "${dest_rel:-}" ]] || continue
    install_prepared_file "$dest_rel" "$staged"
  done < "$PREP/index.tsv"
}

write_paths_generated() {
  local dest_path="${HOME}/${ZSH_CONFIG_REL}/paths.generated.zsh"
  local tmp="${PREP}/paths.generated.zsh"

  refuse_outside_home "$dest_path"
  {
    printf '%s\n' '# Generated by zsh-config. Regenerated on each install.'
    printf '%s\n' '# >>> zsh-config paths >>>'
    printf 'export ZSH="%s"\n' "$(zsh_file_path OMZ_ROOT)"
    printf '%s\n' 'typeset -U fpath'
    printf 'fpath=("%s" $fpath)\n' "$(zsh_file_path COMPLETIONS_DIR)"
    printf '# oh-my-zsh: %s\n' "$(zsh_file_path OMZ_ROOT)"
    printf '# zsh-syntax-highlighting: %s\n' "$(zsh_file_path SYNTAX_HIGHLIGHTING)"
    printf '# zsh-autosuggestions: %s\n' "$(zsh_file_path AUTOSUGGESTIONS)"
    printf '# zsh-history-substring-search: %s\n' "$(zsh_file_path HISTORY_SUBSTRING)"
    printf '# zsh-completions: %s\n' "$(zsh_file_path COMPLETIONS_DIR)"
    printf '# powerlevel10k: %s\n' "$(zsh_file_path POWERLEVEL10K)"
    printf '%s\n' '# <<< zsh-config paths <<<'
  } > "$tmp"

  if [[ -f "$dest_path" ]] && cmp -s "$dest_path" "$tmp"; then
    box_row "$C_DIM" "  unchanged ~/${ZSH_CONFIG_REL}/paths.generated.zsh" "$BORDER"
    return 0
  fi
  if [[ -f "$dest_path" ]]; then
    backup_file "$dest_path"
  fi
  if [[ "$DRY_RUN" == true ]]; then
    box_row "$C_GREEN" "  would write ~/${ZSH_CONFIG_REL}/paths.generated.zsh" "$BORDER"
    return 0
  fi
  mkdir -p "$(dirname "$dest_path")"
  cp -p "$tmp" "$dest_path"
  box_row "$C_GREEN" "  wrote ~/${ZSH_CONFIG_REL}/paths.generated.zsh" "$BORDER"
}

ensure_marked_block() {
  local dest_path="$1"
  local block="$2"
  local label="$3"

  refuse_outside_home "$dest_path"
  if [[ -f "$dest_path" ]] && grep -q "^# >>> ${ZSH_CONFIG_MARKER} >>>" "$dest_path"; then
    box_row "$C_DIM" "  unchanged ${label}" "$BORDER"
    return 0
  fi
  if [[ -f "$dest_path" ]] && grep -q '^# >>> copy-zsh-config >>>' "$dest_path"; then
    box_row "$C_DIM" "  unchanged ${label}" "$BORDER"
    return 0
  fi

  if [[ -f "$dest_path" ]]; then
    backup_file "$dest_path"
  fi
  if [[ "$DRY_RUN" == true ]]; then
    box_row "$C_GREEN" "  would update ${label}" "$BORDER"
    return 0
  fi

  mkdir -p "$(dirname "$dest_path")"
  if [[ -f "$dest_path" ]]; then
    printf '\n%s\n' "$block" >> "$dest_path"
  else
    printf '%s\n' "$block" > "$dest_path"
  fi
  box_row "$C_GREEN" "  updated ${label}" "$BORDER"
}

install_zshenv_files() {
  local config_block bootstrap_block

  config_block="$(cat <<EOF
# >>> ${ZSH_CONFIG_MARKER} >>>
[[ -f "\${ZDOTDIR}/paths.generated.zsh" ]] && source "\${ZDOTDIR}/paths.generated.zsh"
# <<< ${ZSH_CONFIG_MARKER} <<<
EOF
)"
  bootstrap_block="$(cat <<EOF
# >>> ${ZSH_CONFIG_MARKER} >>>
export ZDOTDIR="\${HOME}/${ZSH_CONFIG_REL}"
# <<< ${ZSH_CONFIG_MARKER} <<<
EOF
)"

  section_open "6 · ZDOTDIR bootstrap" "$C_CYAN"
  box_row "" "ZDOTDIR      \${HOME}/${ZSH_CONFIG_REL}" "$BORDER"
  ensure_marked_block "${HOME}/${ZSH_CONFIG_REL}/.zshenv" "$config_block" "~/${ZSH_CONFIG_REL}/.zshenv"
  ensure_marked_block "${HOME}/.zshenv" "$bootstrap_block" "~/.zshenv"
  box_row "$C_DIM" "  zsh reads ~/.zshenv before ZDOTDIR exists, so this" "$BORDER"
  box_row "$C_DIM" "  one file stays in the home directory itself." "$BORDER"
  section_close
}

clone_one_tool() {
  local key="$1"
  local label url dest marker

  label="$(tool_label "$key")"
  url="$(tool_git_url "$key")"
  dest="$(tool_clone_dir "$HOME" "$key")"
  marker="$(tool_marker "$HOME" "$key")"
  refuse_outside_home "$dest"

  if [[ -e "$marker" ]]; then
    box_row "$C_GREEN" "✓ ${label}" "$BORDER"
    box_row "$C_DIM" "→ ${dest}" "$BORDER"
    return 0
  fi

  if [[ "$DRY_RUN" == true ]]; then
    box_row "$C_YELLOW" "› would clone ${label}" "$BORDER"
    box_row "$C_DIM" "→ ${url}" "$BORDER"
    box_row "$C_DIM" "→ ${dest}" "$BORDER"
    return 0
  fi

  if [[ -d "$dest" ]] && [[ -n "$(ls -A "$dest" 2>/dev/null)" ]]; then
    finish "$EXIT_FAILED" "$C_RED" "Result" \
      "✗ ${dest} exists but ${label} is incomplete." \
      "  Move that directory aside and run the install again."
  fi

  mkdir -p "$(dirname "$dest")"
  box_row "$C_CYAN" "› cloning ${label}" "$BORDER"
  if ! GIT_TERMINAL_PROMPT=0 git clone --depth 1 "$url" "$dest" > "${PREP}/git-${key}.log" 2>&1; then
    box_row "$C_RED" "✗ git clone failed for ${label}" "$BORDER"
    if [[ -f "${PREP}/git-${key}.log" ]]; then
      tail -n 5 "${PREP}/git-${key}.log" | while IFS= read -r line; do
        box_row "$C_DIM" "  ${line}" "$BORDER"
      done
    fi
    finish "$EXIT_FAILED" "$C_RED" "Result" "✗ Could not clone ${label}."
  fi
  if [[ ! -e "$marker" ]]; then
    finish "$EXIT_FAILED" "$C_RED" "Result" "✗ ${label} clone is missing ${marker}."
  fi
  box_row "$C_GREEN" "✓ ${label}" "$BORDER"
  box_row "$C_DIM" "→ ${dest}" "$BORDER"
}

install_tools() {
  local key
  section_open "4 · Tools from upstream" "$C_CYAN"
  box_row "$C_DIM" "  Cloned into ~/${ZSH_TOOLS_REL}. Not copied from the bundle." "$BORDER"
  while IFS= read -r key; do
    [[ -n "$key" ]] || continue
    clone_one_tool "$key"
  done < <(clone_tool_keys)
  section_close
}

run_install() {
  local mgr="" dest_rel

  [[ -n "$ARCHIVE" ]] || finish "$EXIT_USAGE" "$C_RED" "Result" "✗ --archive is required for install."

  section_open "1 · Parameters" "$C_BLUE"
  box_row "" "Mode         install" "$BORDER"
  box_row "" "Archive      ${ARCHIVE}" "$BORDER"
  box_row "" "Dry run      ${DRY_RUN}" "$BORDER"
  box_row "" "Force        ${FORCE}" "$BORDER"
  box_row "" "HOME         ${HOME}" "$BORDER"
  box_row "" "Config       ~/${ZSH_CONFIG_REL}" "$BORDER"
  box_row "" "Tools        ~/${ZSH_TOOLS_REL}" "$BORDER"
  section_close

  section_open "2 · Load bundle" "$C_BLUE"
  load_install_bundle "$ARCHIVE"
  read_bundle_identity
  [[ -n "$SOURCE_USER" ]] && box_row "$C_DIM" "  source user  ${SOURCE_USER}" "$BORDER"
  [[ -n "$SOURCE_HOME" ]] && box_row "$C_DIM" "  source home  ${SOURCE_HOME}" "$BORDER"
  section_close

  section_open "3 · Shell and git" "$C_CYAN"
  if ! command -v zsh > /dev/null 2>&1 || ! command -v git > /dev/null 2>&1; then
    mgr="$(detect_pkg_manager || true)"
    box_row "" "Package mgr  ${mgr:-none}" "$BORDER"
  else
    box_row "" "Package mgr  not needed" "$BORDER"
  fi
  ensure_command zsh "$mgr"
  ensure_command git "$mgr"
  if command -v zsh > /dev/null 2>&1; then
    box_row "$C_GREEN" "✓ $(zsh --version 2>/dev/null | head -n 1)" "$BORDER"
  fi
  section_close

  PREP="$(mktemp -d "${TMPDIR:-/tmp}/zsh-config-prep.XXXXXX")"
  install_tools

  section_open "5 · Configuration" "$C_CYAN"
  box_row "$C_DIM" "  Home only. System paths in the bundle are not restored." "$BORDER"
  stage_bundle_files
  if [[ "$TOOL_SKIP_COUNT" -gt 0 ]]; then
    box_row "$C_DIM" "  left ${TOOL_SKIP_COUNT} bundled tool file(s) unused" "$BORDER"
  fi
  if [[ "$OTHER_SKIP_COUNT" -gt 0 ]]; then
    box_row "$C_DIM" "  ignored ${OTHER_SKIP_COUNT} other bundle path(s)" "$BORDER"
  fi
  prepare_staged_files
  install_staged_tree
  write_paths_generated
  section_close

  install_zshenv_files

  if [[ "$DRY_RUN" == true ]]; then
    finish 0 "$C_GREEN" "Result" \
      "✓ Dry run complete." \
      "  Would install ${INSTALLED_COUNT} config file(s) under ~/${ZSH_CONFIG_REL}." \
      "  Would skip ${SKIPPED_COUNT}." \
      "  Would backup ${BACKUP_COUNT} file(s)." \
      "  Start zsh with: chsh -s \"\$(command -v zsh)\""
  fi

  finish 0 "$C_GREEN" "Result" \
    "✓ Installed ${INSTALLED_COUNT} config file(s) under ~/${ZSH_CONFIG_REL}." \
    "  Skipped ${SKIPPED_COUNT}. Backups ${BACKUP_COUNT}." \
    "  Open a new terminal. If the login shell is not zsh:" \
    "  chsh -s \"\$(command -v zsh)\""
}

zshenv_has_marker() {
  local path="$1"
  [[ -f "$path" ]] || return 1
  grep -q "^# >>> ${ZSH_CONFIG_MARKER} >>>" "$path" && return 0
  grep -q '^# >>> copy-zsh-config >>>' "$path"
}

oldest_backup() {
  local path="$1"
  local candidate ts best best_ts

  best=""
  best_ts=""
  for candidate in "${path}".backup.[0-9]*; do
    [[ -f "$candidate" ]] || continue
    ts="${candidate##*.backup.}"
    [[ "$ts" =~ ^[0-9]+$ ]] || continue
    if [[ -z "$best_ts" || "$ts" -lt "$best_ts" ]]; then
      best="$candidate"
      best_ts="$ts"
    fi
  done
  printf '%s\n' "$best"
}

remove_our_backups() {
  local path="$1"
  local candidate ts

  for candidate in "${path}".backup.[0-9]*; do
    [[ -f "$candidate" ]] || continue
    ts="${candidate##*.backup.}"
    [[ "$ts" =~ ^[0-9]+$ ]] || continue
    if [[ "$DRY_RUN" == true ]]; then
      box_row "$C_YELLOW" "  would remove ${candidate}" "$BORDER"
    else
      rm -f "$candidate"
      box_row "$C_GREEN" "  removed ${candidate}" "$BORDER"
    fi
  done
}

strip_marker_blocks() {
  local file="$1"
  local tmp="$2"
  local line skipping=0

  : > "$tmp"
  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" == "# >>> ${ZSH_CONFIG_MARKER} >>>" || "$line" == "# >>> copy-zsh-config >>>" ]]; then
      skipping=1
      continue
    fi
    if [[ "$skipping" -eq 1 && ( "$line" == "# <<< ${ZSH_CONFIG_MARKER} <<<" || "$line" == "# <<< copy-zsh-config <<<" ) ]]; then
      skipping=0
      continue
    fi
    if [[ "$skipping" -eq 1 ]]; then
      continue
    fi
    printf '%s\n' "$line" >> "$tmp"
  done < "$file"
}

file_has_text() {
  local file="$1"
  [[ -f "$file" ]] && grep -q '[^[:space:]]' "$file"
}

restore_home_zshenv() {
  local zshenv="${HOME}/.zshenv"
  local backup tmp

  refuse_outside_home "$zshenv"
  backup="$(oldest_backup "$zshenv")"

  if [[ -n "$backup" ]] && zshenv_has_marker "$zshenv"; then
    if [[ "$DRY_RUN" == true ]]; then
      box_row "$C_YELLOW" "  would restore ~/.zshenv from ${backup}" "$BORDER"
    else
      cp -p "$backup" "$zshenv" || finish "$EXIT_FAILED" "$C_RED" "Result" "✗ Could not restore ~/.zshenv."
      box_row "$C_GREEN" "  restored ~/.zshenv from the pre-install backup" "$BORDER"
    fi
    remove_our_backups "$zshenv"
    return 0
  fi

  if zshenv_has_marker "$zshenv"; then
    tmp="$(mktemp "${TMPDIR:-/tmp}/zsh-config-zshenv.XXXXXX")"
    strip_marker_blocks "$zshenv" "$tmp"
    if file_has_text "$tmp"; then
      if [[ "$DRY_RUN" == true ]]; then
        box_row "$C_YELLOW" "  would remove the ZDOTDIR block from ~/.zshenv" "$BORDER"
      else
        cp -p "$tmp" "$zshenv"
        box_row "$C_GREEN" "  removed the ZDOTDIR block from ~/.zshenv" "$BORDER"
      fi
    else
      if [[ "$DRY_RUN" == true ]]; then
        box_row "$C_YELLOW" "  would delete ~/.zshenv" "$BORDER"
      else
        rm -f "$zshenv"
        box_row "$C_GREEN" "  deleted ~/.zshenv" "$BORDER"
      fi
    fi
    rm -f "$tmp"
    remove_our_backups "$zshenv"
    return 0
  fi

  box_row "$C_DIM" "  ~/.zshenv has no zsh-config block" "$BORDER"
  remove_our_backups "$zshenv"
}

assert_tree_removable() {
  local root="${HOME}/${ZSH_ROOT_REL}"

  refuse_outside_home "$root"
  if [[ ! -e "$root" && ! -L "$root" ]]; then
    return 0
  fi
  if [[ -L "$root" ]]; then
    finish "$EXIT_FAILED" "$C_RED" "Result" \
      "✗ ~/${ZSH_ROOT_REL} is a symlink. Refusing to remove it."
  fi
  if [[ ! -d "$root" ]]; then
    finish "$EXIT_FAILED" "$C_RED" "Result" \
      "✗ ~/${ZSH_ROOT_REL} is not a directory. Refusing to remove it."
  fi
}

remove_install_tree() {
  local root="${HOME}/${ZSH_ROOT_REL}"

  if [[ ! -e "$root" && ! -L "$root" ]]; then
    box_row "$C_DIM" "  absent ~/${ZSH_ROOT_REL}" "$BORDER"
    return 0
  fi
  if [[ "$DRY_RUN" == true ]]; then
    box_row "$C_YELLOW" "  would remove ~/${ZSH_ROOT_REL}" "$BORDER"
    return 0
  fi
  rm -rf "$root"
  box_row "$C_GREEN" "  removed ~/${ZSH_ROOT_REL}" "$BORDER"
}

run_uninstall() {
  local root="${HOME}/${ZSH_ROOT_REL}"
  local had_tree=false
  local had_marker=false

  section_open "1 · Parameters" "$C_BLUE"
  box_row "" "Mode         uninstall" "$BORDER"
  box_row "" "Dry run      ${DRY_RUN}" "$BORDER"
  box_row "" "HOME         ${HOME}" "$BORDER"
  box_row "" "Tree         ~/${ZSH_ROOT_REL}" "$BORDER"
  section_close

  assert_tree_removable
  if [[ -d "$root" && ! -L "$root" ]]; then
    had_tree=true
  fi
  if zshenv_has_marker "${HOME}/.zshenv"; then
    had_marker=true
  fi

  if [[ "$had_tree" == false && "$had_marker" == false ]]; then
    finish 0 "$C_GREEN" "Result" \
      "✓ Nothing to uninstall." \
      "  ~/${ZSH_ROOT_REL} is absent and ~/.zshenv has no zsh-config block."
  fi

  section_open "2 · Restore ~/.zshenv" "$C_CYAN"
  box_row "$C_DIM" "  ~/.zshrc is not changed." "$BORDER"
  restore_home_zshenv
  section_close

  section_open "3 · Remove ~/${ZSH_ROOT_REL}" "$C_CYAN"
  remove_install_tree
  section_close

  if [[ "$DRY_RUN" == true ]]; then
    finish 0 "$C_GREEN" "Result" \
      "✓ Dry run complete." \
      "  zsh and git packages are not removed." \
      "  Open a new terminal after a real uninstall."
  fi

  finish 0 "$C_GREEN" "Result" \
    "✓ Removed the zsh-config installation." \
    "  zsh and git packages were left installed." \
    "  Open a new terminal. The previous ~/.zshrc is read again."
}

main() {
  choose_box_width 72
  parse_arguments "$@"

  if (( SHOW_HELP )); then
    box_banner "$SCRIPT_NAME" "Portable zsh and oh-my-zsh from a CachyOS config."
    usage
    exit 0
  fi

  if [[ -z "$MODE" && -n "$DESTINATION" ]]; then
    MODE="export"
  fi

  [[ -n "$MODE" ]] || {
    box_banner "$SCRIPT_NAME" "Portable zsh and oh-my-zsh from a CachyOS config."
    usage
    finish "$EXIT_USAGE" "$C_RED" "Result" "✗ Use --export, --install, or --uninstall."
  }

  box_banner "$SCRIPT_NAME" "Portable zsh and oh-my-zsh from a CachyOS config."

  case "$MODE" in
    export) run_export ;;
    install) run_install ;;
    uninstall) run_uninstall ;;
    *) finish "$EXIT_USAGE" "$C_RED" "Result" "✗ Unknown mode '${MODE}'." ;;
  esac
}

main "$@"
