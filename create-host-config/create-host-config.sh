#!/usr/bin/env bash
# Add one Host entry to ~/.ssh/config and an ed25519 key for it.
# Existing aliases are never overwritten. A timestamped backup is written
# before the config file changes.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOX_UI="${SCRIPT_DIR}/../utils/box-ui.sh"
if [[ ! -f "$BOX_UI" ]]; then
  printf 'Missing %s\n' "$BOX_UI" >&2
  exit 1
fi
# Resolved from the repository root, which is where shellcheck is run.
# shellcheck source=utils/box-ui.sh
source "$BOX_UI"

readonly SCRIPT_NAME="create-host-config"
readonly EXIT_USAGE=1
readonly EXIT_MISSING_DEPENDENCY=2
readonly EXIT_FAILED=3

# ${HOME:-} so an unset HOME can be reported by prepare instead of set -u.
SSH_DIR="${HOME:-}/.ssh"
SSH_CONFIG="${SSH_DIR}/config"
KNOWN_HOSTS="${SSH_DIR}/known_hosts"

DRY_RUN=false
SHOW_HELP=0
PARSE_ERROR=""
WARNINGS=0
BACKUP_FILE=""
HOST_NAME=""
HOST_HOSTNAME=""
SSH_USER=""
SSH_PORT=""
IDENTITY_FILE=""
IDENTITY_FILE_PATH=""
IDENTITY_NOTE=""
IDENTITIES_ONLY=""
AGENT_STATUS=""
TMP_FILES=()
WILDCARDS=()

cleanup() {
  local f
  if (( ${#TMP_FILES[@]} == 0 )); then
    return 0
  fi
  for f in "${TMP_FILES[@]}"; do
    if [[ -n "$f" && -f "$f" ]]; then
      rm -f "$f"
    fi
  done
}
trap cleanup EXIT

die() {
  finish "$1" "$C_RED" "Result" "${@:2}"
}

shorten_home() {
  local path="$1"
  local tilde="~"
  if [[ -z "${HOME:-}" ]]; then
    printf '%s\n' "$path"
    return 0
  fi
  case "$path" in
    "$HOME") printf '%s\n' "$tilde" ;;
    "$HOME"/*) printf '%s\n' "${tilde}/${path#"$HOME"/}" ;;
    *) printf '%s\n' "$path" ;;
  esac
}

trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s\n' "$s"
}

box_field() {
  local label="$1"
  local value="$2"
  box_row "" "$(printf '%-16s%s' "$label" "$value")" "$BORDER"
}

is_macos() {
  [[ "$(uname -s)" == Darwin ]]
}

usage() {
  section_open "Usage" "$C_YELLOW"
  box_row "$C_BOLD" "${SCRIPT_NAME} [--dry-run]" "$BORDER"
  box_blank "$BORDER"
  box_row "" "Add one Host entry to ~/.ssh/config." "$BORDER"
  box_row "" "Existing aliases are never overwritten." "$BORDER"
  box_row "" "A timestamped backup is written first." "$BORDER"
  box_blank "$BORDER"
  box_row "" "  -n, --dry-run       Show the host block and exit" "$BORDER"
  box_row "$C_DIM" "                      No backup, key, or config write" "$BORDER"
  box_row "" "  -h, --help          Show this help" "$BORDER"
  box_blank "$BORDER"
  box_row "" "Steps:" "$BORDER"
  box_row "$C_DIM" "  1. List Host aliases in ~/.ssh/config" "$BORDER"
  box_row "$C_DIM" "  2. Ask for the new host" "$BORDER"
  box_row "$C_DIM" "  3. Stop if that alias already exists" "$BORDER"
  box_row "$C_DIM" "  4. Back up to ~/.ssh/config.backup.<unix_ts>" "$BORDER"
  box_row "$C_DIM" "  5. Generate an ed25519 key in ~/.ssh" "$BORDER"
  box_row "$C_DIM" "  6. Add the key to the agent (ssh-add)" "$BORDER"
  box_row "$C_DIM" "  7. Scan the server into ~/.ssh/known_hosts" "$BORDER"
  box_row "$C_DIM" "  8. Append the Host block" "$BORDER"
  box_blank "$BORDER"
  box_row "" "Prompts (Enter accepts the default):" "$BORDER"
  box_row "$C_DIM" "  Host name        Alias for: ssh <alias>" "$BORDER"
  box_row "$C_DIM" "  HostName         github.com, gitlab.com, ..." "$BORDER"
  box_row "$C_DIM" "  User             Default: git" "$BORDER"
  box_row "$C_DIM" "  Port             Default: 22 (omitted when 22)" "$BORDER"
  box_row "$C_DIM" "  IdentityFile     File name. Always stored in ~/.ssh" "$BORDER"
  box_row "$C_DIM" "                   Default: id_ed25519_<Host name>" "$BORDER"
  box_row "$C_DIM" "  IdentitiesOnly   yes or no. Default: yes" "$BORDER"
  box_blank "$BORDER"
  box_row "" "An existing private key and its .pub file are left unchanged." "$BORDER"
  box_row "" "On macOS the block also sets UseKeychain yes." "$BORDER"
  box_blank "$BORDER"
  box_row "" "Examples:" "$BORDER"
  box_row "$C_DIM" "  ${SCRIPT_NAME}" "$BORDER"
  box_row "$C_DIM" "  ${SCRIPT_NAME} --dry-run" "$BORDER"
  section_close
}

parse_arguments() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h | --help)
        SHOW_HELP=1
        shift
        ;;
      -n | --dry-run)
        DRY_RUN=true
        shift
        ;;
      *)
        PARSE_ERROR="✗ Unknown argument '$1'."
        return 0
        ;;
    esac
  done
}

require_command() {
  command -v "$1" > /dev/null 2>&1 || die "$EXIT_MISSING_DEPENDENCY" \
    "✗ Required command not found: $1"
}

prepare() {
  [[ -n "${HOME:-}" ]] || die "$EXIT_FAILED" "✗ HOME is not set."
  require_command ssh-keygen
  if [[ "$DRY_RUN" == false ]]; then
    require_command ssh-add
    require_command ssh-keyscan
    if [[ ! -t 0 ]]; then
      die "$EXIT_USAGE" \
        "✗ A terminal is required so ssh-keygen can ask for a passphrase." \
        "  Re-run in a terminal, or pass --dry-run."
    fi
  fi
  if [[ -e "$SSH_DIR" && ! -d "$SSH_DIR" ]]; then
    die "$EXIT_FAILED" "✗ ~/.ssh exists and is not a directory."
  fi
  if [[ -L "$SSH_CONFIG" && ! -e "$SSH_CONFIG" ]]; then
    die "$EXIT_FAILED" "✗ $(shorten_home "$SSH_CONFIG") is a broken symlink."
  fi
  if [[ -e "$SSH_CONFIG" && ! -f "$SSH_CONFIG" ]]; then
    die "$EXIT_FAILED" "✗ $(shorten_home "$SSH_CONFIG") is not a file."
  fi
  if [[ -f "$SSH_CONFIG" && ! -r "$SSH_CONFIG" ]]; then
    die "$EXIT_FAILED" "✗ Cannot read $(shorten_home "$SSH_CONFIG")."
  fi
}

# '#' starts a comment in ssh_config, including inside a line, unless quoted.
strip_comment() {
  local line="$1"
  local i char quote out
  quote=""
  out=""
  for (( i = 0; i < ${#line}; i++ )); do
    char="${line:i:1}"
    if [[ -n "$quote" ]]; then
      out="${out}${char}"
      if [[ "$char" == "$quote" ]]; then
        quote=""
      fi
      continue
    fi
    if [[ "$char" == "#" ]]; then
      break
    fi
    if [[ "$char" == '"' || "$char" == "'" ]]; then
      quote="$char"
    fi
    out="${out}${char}"
  done
  printf '%s\n' "$out"
}

split_aliases() {
  local rest token q
  rest="$(trim "$1")"
  while [[ -n "$rest" ]]; do
    if [[ "$rest" == \"* || "$rest" == \'* ]]; then
      q="${rest:0:1}"
      rest="${rest:1}"
      if [[ "$rest" == *"$q"* ]]; then
        token="${rest%%"$q"*}"
        rest="${rest#*"$q"}"
      else
        token="$rest"
        rest=""
      fi
    else
      token="${rest%%[[:space:]]*}"
      rest="${rest#"$token"}"
    fi
    rest="$(trim "$rest")"
    [[ -n "$token" ]] || continue
    printf '%s\n' "$token"
  done
}

each_host_alias() {
  local line aliases
  [[ -f "$SSH_CONFIG" ]] || return 0
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    line="$(strip_comment "$line")"
    [[ "$line" =~ ^[[:space:]]*[Hh][Oo][Ss][Tt][[:space:]]*(=[[:space:]]*)?(.*)$ ]] || continue
    aliases="$(trim "${BASH_REMATCH[2]}")"
    [[ -n "$aliases" ]] || continue
    split_aliases "$aliases"
  done < "$SSH_CONFIG"
}

config_has_include() {
  local line
  [[ -f "$SSH_CONFIG" ]] || return 1
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    line="$(strip_comment "$line")"
    if [[ "$line" =~ ^[[:space:]]*[Ii][Nn][Cc][Ll][Uu][Dd][Ee][[:space:]]+ ]]; then
      return 0
    fi
  done < "$SSH_CONFIG"
  return 1
}

host_exists() {
  local name="$1"
  local alias
  while IFS= read -r alias; do
    [[ "$alias" == "$name" ]] && return 0
  done < <(each_host_alias)
  return 1
}

list_existing_hosts() {
  local found=0 alias has_include=0
  WILDCARDS=()
  section_open "1 · Existing hosts" "$C_BLUE"
  box_field "Config" "$(shorten_home "$SSH_CONFIG")"
  if [[ -f "$SSH_CONFIG" ]]; then
    while IFS= read -r alias; do
      box_row "$C_DIM" "  ${alias}" "$BORDER"
      found=1
      case "$alias" in
        *'*'* | *'?'* | *'!'* | *'['*)
          WILDCARDS+=("$alias")
          ;;
      esac
    done < <(each_host_alias)
  fi
  if [[ "$found" -eq 0 ]]; then
    box_row "$C_DIM" "  (none)" "$BORDER"
  fi
  if config_has_include; then
    has_include=1
  fi
  if [[ "$has_include" -eq 1 || ${#WILDCARDS[@]} -gt 0 ]]; then
    box_blank "$BORDER"
  fi
  if [[ "$has_include" -eq 1 ]]; then
    box_row "$C_YELLOW" "› Include directives are not scanned." "$BORDER"
    box_row "$C_DIM" "  Hosts in included files are not listed." "$BORDER"
  fi
  if (( ${#WILDCARDS[@]} > 0 )); then
    for alias in "${WILDCARDS[@]}"; do
      box_row "$C_YELLOW" "› Wildcard Host ${alias} may also match." "$BORDER"
    done
  fi
  section_close
}

require_token() {
  local label="$1"
  local value="$2"
  local pattern="$3"
  local hint="$4"
  [[ -n "$value" ]] || die "$EXIT_USAGE" "✗ ${label} is required."
  # The pattern is a regex, so it must stay unquoted.
  # shellcheck disable=SC2076
  if [[ ! "$value" =~ $pattern ]]; then
    die "$EXIT_USAGE" \
      "✗ ${label} contains characters that are not allowed." \
      "  ${hint}" \
      "  Got: ${value}"
  fi
}

prompt_value() {
  local label="$1"
  local default="${2:-}"
  local value=""
  if [[ -n "$default" ]]; then
    printf '%s%s%s [%s%s%s]: ' "$C_BOLD" "$label" "$C_RESET" "$C_DIM" "$default" "$C_RESET" >&2
  else
    printf '%s%s%s: ' "$C_BOLD" "$label" "$C_RESET" >&2
  fi
  if ! IFS= read -r value; then
    die "$EXIT_USAGE" "✗ No input for ${label}."
  fi
  value="$(trim "$value")"
  if [[ -z "$value" ]]; then
    value="$default"
  fi
  REPLY="$value"
}

default_hostname_for() {
  local name
  name="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  case "$name" in
    github | github.com) printf '%s\n' "github.com" ;;
    gitlab | gitlab.com) printf '%s\n' "gitlab.com" ;;
    bitbucket | bitbucket.org) printf '%s\n' "bitbucket.org" ;;
    *) printf '%s\n' "$1" ;;
  esac
}

normalize_port() {
  local value="$1"
  [[ "$value" =~ ^[0-9]+$ ]] || die "$EXIT_USAGE" \
    "✗ Port must be a number from 1 to 65535." \
    "  Got: ${value}"
  if (( 10#$value < 1 || 10#$value > 65535 )); then
    die "$EXIT_USAGE" \
      "✗ Port must be a number from 1 to 65535." \
      "  Got: ${value}"
  fi
  SSH_PORT="$((10#$value))"
}

expand_tilde() {
  # Match a literal leading tilde. The value is text from the prompt, not a path the shell expands.
  # shellcheck disable=SC2088
  case "$1" in
    '~') printf '%s\n' "$HOME" ;;
    '~/'*) printf '%s\n' "${HOME}/${1:2}" ;;
    *) printf '%s\n' "$1" ;;
  esac
}

normalize_identity_file() {
  local raw="$1"
  local expanded name parent lower
  expanded="$(expand_tilde "$raw")"
  if [[ -d "$expanded" ]]; then
    die "$EXIT_USAGE" "✗ IdentityFile must be a file name, not a directory."
  fi
  name="$(basename -- "$expanded")"
  if [[ -z "$name" || "$name" == "." || "$name" == ".." || "$name" == "/" ]]; then
    die "$EXIT_USAGE" "✗ IdentityFile must include a key file name."
  fi
  require_token "IdentityFile" "$name" '^[A-Za-z0-9][A-Za-z0-9._@+-]*$' \
    "Use a file name of letters, digits, and . _ @ + -."
  lower="$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]')"
  case "$lower" in
    *.pub)
      die "$EXIT_USAGE" "✗ IdentityFile must be the private key name, not the .pub file."
      ;;
    config | known_hosts | authorized_keys | environment)
      die "$EXIT_USAGE" "✗ IdentityFile cannot be named ${name}."
      ;;
  esac
  parent="$(dirname -- "$expanded")"
  IDENTITY_NOTE=""
  if [[ "$raw" == */* && "$parent" != "$SSH_DIR" && "$parent" != "." ]]; then
    IDENTITY_NOTE="Only the file name is used. The key is created in ~/.ssh."
  fi
  # ssh expands this tilde itself. Keep it literal in the config file.
  # shellcheck disable=SC2088
  IDENTITY_FILE="~/.ssh/${name}"
  IDENTITY_FILE_PATH="${SSH_DIR}/${name}"
}

normalize_identities_only() {
  local value
  value="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  case "$value" in
    yes | y | true | 1) IDENTITIES_ONLY="yes" ;;
    no | n | false | 0) IDENTITIES_ONLY="no" ;;
    *)
      die "$EXIT_USAGE" \
        "✗ IdentitiesOnly must be yes or no." \
        "  Got: $1"
      ;;
  esac
}

ask_host_information() {
  local default_identity
  prompt_value "Host name"
  HOST_NAME="$REPLY"
  require_token "Host name" "$HOST_NAME" '^[A-Za-z0-9][A-Za-z0-9._@+-]*$' \
    "Use letters, digits, and . _ @ + -."

  prompt_value "HostName" "$(default_hostname_for "$HOST_NAME")"
  HOST_HOSTNAME="$REPLY"
  require_token "HostName" "$HOST_HOSTNAME" '^[A-Za-z0-9][A-Za-z0-9._:-]*$' \
    "Use a hostname or an IP address."

  prompt_value "User" "git"
  SSH_USER="$REPLY"
  require_token "User" "$SSH_USER" '^[A-Za-z0-9_][A-Za-z0-9._@+-]*$' \
    "Use letters, digits, and . _ @ + -."

  prompt_value "Port" "22"
  normalize_port "$REPLY"

  # Shown as the prompt default and stored with a literal tilde for ssh.
  # shellcheck disable=SC2088
  default_identity="~/.ssh/id_ed25519_${HOST_NAME}"
  prompt_value "IdentityFile" "$default_identity"
  [[ -n "$REPLY" ]] || die "$EXIT_USAGE" "✗ IdentityFile is required."
  normalize_identity_file "$REPLY"

  prompt_value "IdentitiesOnly" "yes"
  normalize_identities_only "$REPLY"
}

key_state() {
  if [[ -e "$IDENTITY_FILE_PATH" && ! -f "$IDENTITY_FILE_PATH" ]]; then
    printf 'invalid\n'
    return 0
  fi
  if [[ -e "${IDENTITY_FILE_PATH}.pub" && ! -f "${IDENTITY_FILE_PATH}.pub" ]]; then
    printf 'invalid\n'
    return 0
  fi
  if [[ -f "$IDENTITY_FILE_PATH" && -f "${IDENTITY_FILE_PATH}.pub" ]]; then
    printf 'exists\n'
  elif [[ -e "$IDENTITY_FILE_PATH" || -e "${IDENTITY_FILE_PATH}.pub" ]]; then
    printf 'partial\n'
  else
    printf 'missing\n'
  fi
}

reject_unsafe_state() {
  local state
  if host_exists "$HOST_NAME"; then
    die "$EXIT_FAILED" \
      "✗ Host '${HOST_NAME}' already exists in $(shorten_home "$SSH_CONFIG")." \
      "  Existing entries are not overwritten." \
      "  Nothing was changed."
  fi
  state="$(key_state)"
  case "$state" in
    invalid)
      die "$EXIT_FAILED" \
        "✗ IdentityFile path is not a regular file." \
        "  ${IDENTITY_FILE}" \
        "  Nothing was changed."
      ;;
    partial)
      die "$EXIT_FAILED" \
        "✗ Identity file pair is incomplete." \
        "  ${IDENTITY_FILE} and ${IDENTITY_FILE}.pub must both exist, or neither." \
        "  Nothing was changed."
      ;;
  esac
}

print_host_block() {
  printf 'Host %s\n' "$HOST_NAME"
  printf '  HostName %s\n' "$HOST_HOSTNAME"
  printf '  User %s\n' "$SSH_USER"
  if [[ "$SSH_PORT" != "22" ]]; then
    printf '  Port %s\n' "$SSH_PORT"
  fi
  printf '  IdentityFile %s\n' "$IDENTITY_FILE"
  printf '  IdentitiesOnly %s\n' "$IDENTITIES_ONLY"
  printf '  AddKeysToAgent yes\n'
  if is_macos; then
    printf '  IgnoreUnknown UseKeychain\n'
    printf '  UseKeychain yes\n'
  fi
}

known_hosts_name() {
  if [[ "$HOST_HOSTNAME" == *:* || "$SSH_PORT" != "22" ]]; then
    printf '[%s]:%s\n' "$HOST_HOSTNAME" "$SSH_PORT"
  else
    printf '%s\n' "$HOST_HOSTNAME"
  fi
}

host_key_present() {
  local query
  [[ -f "$KNOWN_HOSTS" ]] || return 1
  query="$(known_hosts_name)"
  ssh-keygen -F "$query" -f "$KNOWN_HOSTS" > /dev/null 2>&1
}

show_plan() {
  local state
  section_open "2 · New host" "$C_BLUE"
  box_field "Host name" "$HOST_NAME"
  box_field "HostName" "$HOST_HOSTNAME"
  box_field "User" "$SSH_USER"
  box_field "Port" "$SSH_PORT"
  box_field "IdentityFile" "$IDENTITY_FILE"
  box_field "IdentitiesOnly" "$IDENTITIES_ONLY"
  box_field "Dry run" "$DRY_RUN"
  if [[ -n "$IDENTITY_NOTE" ]]; then
    box_blank "$BORDER"
    box_row "$C_YELLOW" "› ${IDENTITY_NOTE}" "$BORDER"
  fi
  if [[ "$SSH_PORT" == "22" ]]; then
    box_row "$C_DIM" "  Port 22 is omitted from the block." "$BORDER"
  fi
  box_blank "$BORDER"
  if [[ "$DRY_RUN" == true ]]; then
    box_row "" "Would append:" "$BORDER"
  else
    box_row "" "Will append:" "$BORDER"
  fi
  box_lines "$C_DIM" "$(print_host_block)" "$BORDER"
  box_blank "$BORDER"
  box_row "$C_DIM" "  Backup: ~/.ssh/config.backup.<unix timestamp>" "$BORDER"
  state="$(key_state)"
  if [[ "$state" == exists ]]; then
    box_row "$C_DIM" "  Key exists and will be left unchanged." "$BORDER"
  else
    box_row "$C_DIM" "  Key: new ed25519 ${IDENTITY_FILE}" "$BORDER"
  fi
  if host_key_present; then
    box_row "$C_DIM" "  known_hosts already has $(known_hosts_name)." "$BORDER"
  else
    box_row "$C_DIM" "  known_hosts: scan $(known_hosts_name)." "$BORDER"
  fi
  if [[ "$SSH_USER" == git ]]; then
    box_row "$C_DIM" "  Test: ssh -T git@${HOST_NAME}" "$BORDER"
  else
    box_row "$C_DIM" "  Test: ssh ${HOST_NAME}" "$BORDER"
  fi
  section_close
}

confirm_apply() {
  local value
  printf '%sProceed?%s [%sY%s/n]: ' "$C_BOLD" "$C_RESET" "$C_GREEN" "$C_RESET" >&2
  if ! IFS= read -r value; then
    die "$EXIT_USAGE" "✗ No input for confirmation."
  fi
  value="$(printf '%s' "$(trim "$value")" | tr '[:upper:]' '[:lower:]')"
  case "$value" in
    "" | y | yes) return 0 ;;
    n | no) return 1 ;;
    *) die "$EXIT_USAGE" "✗ Answer yes or no." ;;
  esac
}

ensure_ssh_dir() {
  if ! mkdir -p "$SSH_DIR"; then
    die "$EXIT_FAILED" "✗ Could not create ~/.ssh."
  fi
  if ! chmod 700 "$SSH_DIR"; then
    die "$EXIT_FAILED" "✗ Could not set ~/.ssh to mode 700."
  fi
  if [[ ! -e "$SSH_CONFIG" ]]; then
    if ! touch "$SSH_CONFIG"; then
      die "$EXIT_FAILED" "✗ Could not create ~/.ssh/config."
    fi
    if ! chmod 600 "$SSH_CONFIG"; then
      die "$EXIT_FAILED" "✗ Could not set ~/.ssh/config to mode 600."
    fi
  fi
}

backup_path() {
  printf '%s\n' "${SSH_DIR}/config.backup.$(date +%s)"
}

create_backup() {
  local tries=0
  # Two runs in the same second would otherwise share one backup path.
  while (( tries < 5 )); do
    BACKUP_FILE="$(backup_path)"
    if [[ ! -e "$BACKUP_FILE" ]]; then
      break
    fi
    tries=$((tries + 1))
    sleep 1
  done
  if [[ -e "$BACKUP_FILE" ]]; then
    die "$EXIT_FAILED" \
      "✗ Backup was not created." \
      "  $(shorten_home "$BACKUP_FILE") already exists." \
      "  Host config entry was not created."
  fi
  if ! cp -p "$SSH_CONFIG" "$BACKUP_FILE"; then
    die "$EXIT_FAILED" \
      "✗ Backup was not created." \
      "  Host config entry was not created."
  fi
  if ! chmod 600 "$BACKUP_FILE"; then
    die "$EXIT_FAILED" \
      "✗ Backup was not created successfully." \
      "  Host config entry was not created."
  fi
  box_row "$C_GREEN" "✓ Backup created: $(shorten_home "$BACKUP_FILE")" "$BORDER"
}

generate_ssh_key_step() {
  local state
  state="$(key_state)"
  if [[ "$state" == exists ]]; then
    section_open "4 · SSH key" "$C_CYAN"
    box_row "$C_GREEN" "✓ SSH key already exists: ${IDENTITY_FILE}" "$BORDER"
    box_row "$C_DIM" "  Left unchanged." "$BORDER"
    section_close
    return 0
  fi
  printf '\n%s\n\n' "${C_CYAN}ssh-keygen will ask for a passphrase. Press Enter twice for none.${C_RESET}"
  if ! ssh-keygen -t ed25519 -f "$IDENTITY_FILE_PATH" -C "$HOST_NAME"; then
    die "$EXIT_FAILED" \
      "✗ SSH key was not generated." \
      "  Host config entry was not created." \
      "  Backup: $(shorten_home "$BACKUP_FILE")"
  fi
  printf '\n'
  section_open "4 · SSH key" "$C_CYAN"
  box_row "$C_GREEN" "✓ SSH key generated: ${IDENTITY_FILE}" "$BORDER"
  section_close
}

run_ssh_add() {
  AGENT_STATUS="skipped"
  if [[ ! -f "$IDENTITY_FILE_PATH" ]]; then
    AGENT_STATUS="missing"
    return 0
  fi
  if [[ -z "${SSH_AUTH_SOCK:-}" ]]; then
    AGENT_STATUS="no-agent"
    return 0
  fi
  printf '\n%s\n\n' "${C_CYAN}Adding the key to the SSH agent.${C_RESET}"
  if is_macos && ssh-add --apple-use-keychain "$IDENTITY_FILE_PATH" 2> /dev/null; then
    AGENT_STATUS="added"
    return 0
  fi
  if ssh-add "$IDENTITY_FILE_PATH"; then
    AGENT_STATUS="added"
    return 0
  fi
  AGENT_STATUS="failed"
}

report_agent() {
  case "$AGENT_STATUS" in
    added)
      box_row "$C_GREEN" "✓ SSH key added to the agent: ${IDENTITY_FILE}" "$BORDER"
      ;;
    no-agent)
      box_row "$C_YELLOW" "› SSH agent is not running; skipped ssh-add" "$BORDER"
      box_row "$C_DIM" "  ssh-add ${IDENTITY_FILE}" "$BORDER"
      WARNINGS=$((WARNINGS + 1))
      ;;
    failed)
      box_row "$C_YELLOW" "› Could not add ${IDENTITY_FILE} to the agent" "$BORDER"
      box_row "$C_DIM" "  ssh-add ${IDENTITY_FILE}" "$BORDER"
      WARNINGS=$((WARNINGS + 1))
      ;;
    missing)
      box_row "$C_YELLOW" "› No private key at ${IDENTITY_FILE}; skipped ssh-add" "$BORDER"
      WARNINGS=$((WARNINGS + 1))
      ;;
  esac
}

append_scan_lines() {
  local line wrote=0
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" || "$line" == \#* ]] && continue
    printf '%s\n' "$line" >> "$KNOWN_HOSTS" || return 1
    wrote=1
  done < "$1"
  [[ "$wrote" -eq 1 ]]
}

add_known_host() {
  local created=0 tmp query
  local -a scan_args
  query="$(known_hosts_name)"
  if host_key_present; then
    box_row "$C_DIM" "  Host key already present for ${query}" "$BORDER"
    return 0
  fi
  if [[ -e "$KNOWN_HOSTS" && ! -w "$KNOWN_HOSTS" ]]; then
    box_row "$C_YELLOW" "› known_hosts is not writable" "$BORDER"
    box_row "$C_DIM" "  $(shorten_home "$KNOWN_HOSTS")" "$BORDER"
    WARNINGS=$((WARNINGS + 1))
    return 0
  fi
  if [[ ! -e "$KNOWN_HOSTS" ]]; then
    if ! touch "$KNOWN_HOSTS"; then
      box_row "$C_YELLOW" "› Could not create $(shorten_home "$KNOWN_HOSTS")" "$BORDER"
      WARNINGS=$((WARNINGS + 1))
      return 0
    fi
    created=1
  fi
  tmp="$(mktemp "${TMPDIR:-/tmp}/create-host-config.XXXXXX")" || {
    box_row "$C_YELLOW" "› Could not scan ${HOST_HOSTNAME}" "$BORDER"
    WARNINGS=$((WARNINGS + 1))
    if [[ "$created" -eq 1 ]]; then
      rm -f "$KNOWN_HOSTS"
    fi
    return 0
  }
  TMP_FILES+=("$tmp")
  scan_args=(-T 5 -t "ed25519,ecdsa,rsa")
  if [[ "$SSH_PORT" != "22" ]]; then
    scan_args+=(-p "$SSH_PORT")
  fi
  ssh-keyscan "${scan_args[@]}" "$HOST_HOSTNAME" > "$tmp" 2> /dev/null || true
  if ! append_scan_lines "$tmp"; then
    if [[ "$created" -eq 1 ]]; then
      rm -f "$KNOWN_HOSTS"
    fi
    box_row "$C_YELLOW" "› Could not scan ${HOST_HOSTNAME}" "$BORDER"
    box_row "$C_DIM" "  ssh-keyscan ${HOST_HOSTNAME} >> ~/.ssh/known_hosts" "$BORDER"
    WARNINGS=$((WARNINGS + 1))
    return 0
  fi
  box_row "$C_GREEN" "✓ Added ${query} to $(shorten_home "$KNOWN_HOSTS")" "$BORDER"
}

resolve_existing_file() {
  local path="$1"
  local i=0 dir link
  while [[ -L "$path" ]]; do
    if (( i >= 8 )); then
      return 1
    fi
    dir="$(cd "$(dirname "$path")" && pwd)" || return 1
    link="$(readlink "$path")" || return 1
    case "$link" in
      /*) path="$link" ;;
      *) path="${dir}/${link}" ;;
    esac
    i=$((i + 1))
  done
  printf '%s\n' "$path"
}

ensure_blank_line_before_append() {
  local file="$1"
  local last
  [[ -s "$file" ]] || return 0
  if [[ "$(tail -c 1 "$file")" != $'\n' ]]; then
    printf '\n' >> "$file"
  fi
  last="$(tail -n 1 "$file")"
  last="${last%$'\r'}"
  if [[ ! "$last" =~ ^[[:space:]]*$ ]]; then
    printf '\n' >> "$file"
  fi
}

append_failed() {
  die "$EXIT_FAILED" \
    "✗ Host config entry was not created." \
    "  Backup: $(shorten_home "$BACKUP_FILE")"
}

append_host_entry() {
  local tmp_file dest
  tmp_file="$(mktemp "${SSH_DIR}/config.tmp.XXXXXX")" || append_failed
  TMP_FILES+=("$tmp_file")
  if ! cp -p "$SSH_CONFIG" "$tmp_file"; then
    append_failed
  fi
  ensure_blank_line_before_append "$tmp_file"
  print_host_block >> "$tmp_file" || append_failed
  if [[ -L "$SSH_CONFIG" ]]; then
    dest="$(resolve_existing_file "$SSH_CONFIG")" || append_failed
    if [[ ! -f "$dest" ]]; then
      append_failed
    fi
    if ! mv "$tmp_file" "$dest"; then
      append_failed
    fi
  else
    if ! mv "$tmp_file" "$SSH_CONFIG"; then
      append_failed
    fi
  fi
  if ! chmod 600 "$SSH_CONFIG"; then
    die "$EXIT_FAILED" \
      "✗ Host config entry was created, but mode 600 could not be set." \
      "  $(shorten_home "$SSH_CONFIG")"
  fi
}

apply_changes() {
  umask 077
  ensure_ssh_dir
  section_open "3 · Backup" "$C_CYAN"
  create_backup
  section_close
  generate_ssh_key_step
  run_ssh_add
  section_open "5 · Agent and known hosts" "$C_CYAN"
  report_agent
  add_known_host
  section_close
  append_host_entry
  section_open "6 · Config" "$C_CYAN"
  box_row "$C_GREEN" "✓ Host config entry created: ${HOST_NAME}" "$BORDER"
  box_row "$C_DIM" "  $(shorten_home "$SSH_CONFIG")" "$BORDER"
  section_close
}

show_next_steps() {
  section_open "7 · Next steps" "$C_BLUE"
  if [[ "$SSH_USER" == git ]]; then
    box_row "" "Add the public key to the git provider." "$BORDER"
    box_row "$C_DIM" "  GitHub, GitLab, Bitbucket, or another host." "$BORDER"
  else
    box_row "" "Install the public key for ${SSH_USER} on the server." "$BORDER"
  fi
  box_blank "$BORDER"
  box_field "Public key" "${IDENTITY_FILE}.pub"
  box_row "$C_DIM" "  Printed below so it stays on one line." "$BORDER"
  box_blank "$BORDER"
  box_row "" "Test the connection:" "$BORDER"
  if [[ "$SSH_USER" == git ]]; then
    box_row "$C_DIM" "  ssh -T git@${HOST_NAME}" "$BORDER"
    box_blank "$BORDER"
    box_row "" "Remote URL:" "$BORDER"
    box_row "$C_DIM" "  git@${HOST_NAME}:org/repo.git" "$BORDER"
  else
    box_row "$C_DIM" "  ssh ${HOST_NAME}" "$BORDER"
  fi
  section_close
}

main() {
  local pub
  choose_box_width 68
  parse_arguments "$@"

  if [[ -n "$PARSE_ERROR" ]]; then
    box_banner "$SCRIPT_NAME" "Add one Host entry to ~/.ssh/config."
    usage
    die "$EXIT_USAGE" "$PARSE_ERROR"
  fi

  if (( SHOW_HELP )); then
    box_banner "$SCRIPT_NAME" "Add one Host entry to ~/.ssh/config."
    usage
    exit 0
  fi

  box_banner "$SCRIPT_NAME" "Add one Host entry to ~/.ssh/config."
  prepare
  list_existing_hosts
  printf '%s\n\n' "${C_DIM}Press Enter to accept a default. The key is always created in ~/.ssh.${C_RESET}" >&2
  ask_host_information
  reject_unsafe_state
  show_plan

  if [[ "$DRY_RUN" == true ]]; then
    finish 0 "$C_GREEN" "Result" \
      "✓ Dry run complete." \
      "  No backup, key, known_hosts, or config changes were made."
  fi

  if ! confirm_apply; then
    finish 0 "$C_GREEN" "Result" \
      "✓ Cancelled." \
      "  No files were changed."
  fi

  apply_changes
  show_next_steps
  pub="${IDENTITY_FILE_PATH}.pub"
  if [[ -s "$pub" ]]; then
    printf '%s\n\n' "$(< "$pub")"
  fi
  if (( WARNINGS > 0 )); then
    finish 0 "$C_GREEN" "Result" \
      "✓ Host config entry created: ${HOST_NAME}" \
      "  Backup: $(shorten_home "$BACKUP_FILE")" \
      "  Key: ${IDENTITY_FILE}" \
      "  Agent or known_hosts needs a manual step. See above."
  fi
  finish 0 "$C_GREEN" "Result" \
    "✓ Host config entry created: ${HOST_NAME}" \
    "  Backup: $(shorten_home "$BACKUP_FILE")" \
    "  Key: ${IDENTITY_FILE}"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
