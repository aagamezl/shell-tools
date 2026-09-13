#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/utils/colors.sh"
source "$SCRIPT_DIR/utils/field.sh"
source "$SCRIPT_DIR/utils/note.sh"
source "$SCRIPT_DIR/utils/section.sh"
source "$SCRIPT_DIR/utils/shorten_home.sh"

SCRIPT_NAME="$(basename "$0")"
SSH_DIR="${HOME}/.ssh"
SSH_CONFIG="${SSH_DIR}/config"
KNOWN_HOSTS="${SSH_DIR}/known_hosts"
REPORT_WIDTH=72
DRY_RUN=false

success() {
  green "$1"
}

fail() {
  red "Error: $1" >&2
  exit 1
}

require() {
  [[ -n "$2" ]] || fail "$1 is required"
}

is_macos() {
  [[ "$(uname)" == Darwin ]]
}

usage() {
  echo "$SCRIPT_NAME"
  echo
  echo "Add a new Host entry to ~/.ssh/config without overwriting existing entries."
  echo "A timestamped backup is created first, then a new SSH key is generated"
  echo "for the host."
  echo
  echo "Usage:"
  echo "  ./$SCRIPT_NAME"
  echo "  ./$SCRIPT_NAME -n"
  echo "  ./$SCRIPT_NAME --dry-run"
  echo "  ./$SCRIPT_NAME -h"
  echo "  ./$SCRIPT_NAME --help"
  echo
  echo "Options:"
  echo "  -n, --dry-run    Show the changes that would be made and exit"
  echo "                   without writing to ~/.ssh/config, creating a"
  echo "                   backup, or generating an SSH key"
  echo "  -h, --help       Show this usage guide and exit"
  echo
  echo "What the script does:"
  echo "  1. Lists existing Host entries in ~/.ssh/config"
  echo "  2. Prompts for the new host information"
  echo "  3. Refuses to continue if that Host alias already exists"
  echo "  4. Copies ~/.ssh/config to ~/.ssh/config.backup.<timestamp>"
  echo "     where <timestamp> is a Unix timestamp (seconds since epoch)"
  echo "  5. Generates an ed25519 SSH key in ~/.ssh"
  echo "     (existing keys are left unchanged)"
  echo "  6. Adds the private key to the SSH agent (ssh-add)"
  echo "  7. Adds the provider host key to ~/.ssh/known_hosts"
  echo "     if it is not already present (ssh-keyscan)"
  echo "  8. Appends the new Host block to ~/.ssh/config"
  echo
  echo "Prompts:"
  echo "  Host name        SSH alias used as: ssh <Host name>"
  echo "  HostName         Real hostname (github.com, gitlab.com,"
  echo "                   bitbucket.org, ...)"
  echo "  User             SSH user (default: git)"
  echo "  IdentityFile     Key file name or path; the key is always"
  echo "                   created in ~/.ssh (default:"
  echo "                   ~/.ssh/id_ed25519_<Host name>)"
  echo "  IdentitiesOnly   yes or no (default: yes)"
  echo
  echo "Messages:"
  echo "  Success and error messages are printed for the backup and for"
  echo "  the new host config entry."
  echo
  echo "Examples:"
  echo "  ./$SCRIPT_NAME"
  echo "  ./$SCRIPT_NAME --dry-run"
  echo "  ./$SCRIPT_NAME --help"
}

# An unquoted ~/* is expanded by the shell to $HOME/*. A value typed as
# ~/.ssh/... must be expanded here or ssh-keygen creates a "~" directory.
expand_tilde() {
  case "$1" in
    '~')   printf '%s\n' "$HOME" ;;
    '~/'*) printf '%s\n' "${HOME}/${1:2}" ;;
    *)     printf '%s\n' "$1" ;;
  esac
}

# Keys always live in ~/.ssh. Only the basename of a user path is kept.
normalize_identity_file() {
  local name
  name="$(basename "$(expand_tilde "$1")")"

  if [[ -z "$name" || "$name" == "." || "$name" == "/" ]]; then
    fail "IdentityFile must include a key file name"
  fi

  IDENTITY_FILE="~/.ssh/${name}"
  IDENTITY_FILE_PATH="${SSH_DIR}/${name}"
}

ensure_ssh_dir() {
  mkdir -p "$SSH_DIR"
  chmod 700 "$SSH_DIR"

  if [[ ! -f "$SSH_CONFIG" ]]; then
    touch "$SSH_CONFIG"
    chmod 600 "$SSH_CONFIG"
  fi
}

each_host_alias() {
  local line aliases alias

  [[ -f "$SSH_CONFIG" ]] || return 0

  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" =~ ^[[:space:]]*Host[[:space:]]+(.+)$ ]] || continue
    aliases="${BASH_REMATCH[1]}"
    # shellcheck disable=SC2086
    for alias in $aliases; do
      printf '%s\n' "$alias"
    done
  done < "$SSH_CONFIG"
}

list_existing_hosts() {
  section "Existing SSH hosts" "$REPORT_WIDTH"
  field "config" "$(shorten_home "$SSH_CONFIG")"
  echo

  local found=0 alias
  while IFS= read -r alias; do
    note "- ${alias}"
    found=1
  done < <(each_host_alias)

  [[ "$found" -eq 1 ]] || note "(none)"
  echo
}

host_exists() {
  local name="$1" alias

  while IFS= read -r alias; do
    [[ "$alias" == "$name" ]] && return 0
  done < <(each_host_alias)

  return 1
}

prompt() {
  local label="$1"
  local default="${2:-}"
  local value=""

  if [[ -n "$default" ]]; then
    read -r -p "${label} [${default}]: " value
    printf '%s\n' "${value:-$default}"
  else
    read -r -p "${label}: " value
    printf '%s\n' "$value"
  fi
}

default_hostname_for() {
  local name
  name="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"

  case "$name" in
    github|github.com)       printf '%s\n' "github.com" ;;
    gitlab|gitlab.com)       printf '%s\n' "gitlab.com" ;;
    bitbucket|bitbucket.org) printf '%s\n' "bitbucket.org" ;;
    *)                       printf '%s\n' "$1" ;;
  esac
}

normalize_identities_only() {
  local value
  value="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"

  case "$value" in
    yes|y|true|1) echo "yes" ;;
    no|n|false|0) echo "no" ;;
    *) fail "IdentitiesOnly must be yes or no (got: $1)" ;;
  esac
}

ask_host_information() {
  HOST_NAME="$(prompt "Host name")"
  require "Host name" "$HOST_NAME"
  [[ "$HOST_NAME" != *" "* ]] || fail "Host name must be a single alias (no spaces)"

  HOST_HOSTNAME="$(prompt "HostName" "$(default_hostname_for "$HOST_NAME")")"
  require "HostName" "$HOST_HOSTNAME"

  SSH_USER="$(prompt "User" "git")"
  require "User" "$SSH_USER"

  IDENTITY_FILE="$(prompt "IdentityFile" "~/.ssh/id_ed25519_${HOST_NAME}")"
  require "IdentityFile" "$IDENTITY_FILE"
  normalize_identity_file "$IDENTITY_FILE"

  IDENTITIES_ONLY="$(normalize_identities_only "$(prompt "IdentitiesOnly" "yes")")"
}

print_host_block() {
  cat <<EOF
Host ${HOST_NAME}
  HostName ${HOST_HOSTNAME}
  User ${SSH_USER}
  IdentityFile ${IDENTITY_FILE}
  IdentitiesOnly ${IDENTITIES_ONLY}
  AddKeysToAgent yes
EOF

  if is_macos; then
    printf '  UseKeychain yes\n'
  fi
}

backup_path() {
  printf '%s\n' "${SSH_DIR}/config.backup.$(date +%s)"
}

create_backup() {
  local backup_file
  backup_file="$(backup_path)"

  if cp -p "$SSH_CONFIG" "$backup_file"; then
    success "Backup created successfully: ${backup_file}"
  else
    fail "Backup file was not created successfully"
  fi
}

generate_ssh_key() {
  if [[ -e "$IDENTITY_FILE_PATH" ]]; then
    note "SSH key already exists at ${IDENTITY_FILE}; leaving it unchanged."
    return 0
  fi

  if ssh-keygen -t ed25519 -f "$IDENTITY_FILE_PATH" -C "$HOST_NAME"; then
    success "SSH key generated successfully: ${IDENTITY_FILE}"
  else
    fail "SSH key was not generated successfully"
  fi
}

add_key_to_agent() {
  if [[ ! -f "$IDENTITY_FILE_PATH" ]]; then
    note "No private key at ${IDENTITY_FILE}; skipped ssh-add"
    return 0
  fi

  # macOS can store the passphrase in Keychain so it survives reboots.
  if is_macos && ssh-add --apple-use-keychain "$IDENTITY_FILE_PATH" 2>/dev/null; then
    success "SSH key added to the agent: ${IDENTITY_FILE}"
    return 0
  fi

  if ssh-add "$IDENTITY_FILE_PATH"; then
    success "SSH key added to the agent: ${IDENTITY_FILE}"
  else
    yellow "Could not add ${IDENTITY_FILE} to the agent. Run: ssh-add ${IDENTITY_FILE}"
  fi
}

add_known_host() {
  if [[ -f "$KNOWN_HOSTS" ]] && ssh-keygen -F "$HOST_HOSTNAME" -f "$KNOWN_HOSTS" >/dev/null 2>&1; then
    note "Host key for ${HOST_HOSTNAME} already present in $(shorten_home "$KNOWN_HOSTS")"
    return 0
  fi

  touch "$KNOWN_HOSTS"
  chmod 644 "$KNOWN_HOSTS"

  if ssh-keyscan -T 5 "$HOST_HOSTNAME" >> "$KNOWN_HOSTS" 2>/dev/null; then
    success "Added ${HOST_HOSTNAME} to $(shorten_home "$KNOWN_HOSTS")"
  else
    yellow "Could not scan ${HOST_HOSTNAME}. Run: ssh-keyscan ${HOST_HOSTNAME} >> ~/.ssh/known_hosts"
  fi
}

# Separate the new Host block from whatever is already in the file.
ensure_blank_line_before_append() {
  local file="$1"
  local last

  [[ -s "$file" ]] || return 0

  [[ "$(tail -c 1 "$file")" == $'\n' ]] || printf '\n' >> "$file"

  last="$(tail -n 1 "$file")"
  [[ "$last" =~ ^[[:space:]]*$ ]] || printf '\n' >> "$file"
}

append_host_entry() {
  local tmp_file
  tmp_file="$(mktemp "${SSH_DIR}/config.tmp.XXXXXX")"

  # Write to a temp file first so a failed append cannot leave a half-written config.
  if ! cp -p "$SSH_CONFIG" "$tmp_file"; then
    rm -f "$tmp_file"
    fail "Host config entry was not created successfully"
  fi

  ensure_blank_line_before_append "$tmp_file"
  print_host_block >> "$tmp_file"

  if mv "$tmp_file" "$SSH_CONFIG"; then
    chmod 600 "$SSH_CONFIG"
    success "Host config entry created successfully: ${HOST_NAME}"
  else
    rm -f "$tmp_file"
    fail "Host config entry was not created successfully"
  fi
}

preview_changes() {
  section "Dry run" "$REPORT_WIDTH"
  note "No changes were made."
  echo

  field "backup" "$(shorten_home "$(backup_path)")"

  if [[ -e "$IDENTITY_FILE_PATH" ]]; then
    field "ssh key" "${IDENTITY_FILE}  (exists, unchanged)"
  else
    field "ssh key" "${IDENTITY_FILE}  (ed25519, comment: ${HOST_NAME})"
  fi

  field "ssh-add" "$IDENTITY_FILE"
  field "known_hosts" "ssh-keyscan ${HOST_HOSTNAME}"
  echo

  note "Would append to $(shorten_home "$SSH_CONFIG"):"
  echo
  print_host_block
  echo
  note "Then add ${IDENTITY_FILE}.pub to the git provider."
  note "Use remotes like: git@${HOST_NAME}:org/repo.git"
  note "Test with: ssh -T git@${HOST_NAME}"
}

print_next_steps() {
  section "Next steps" "$REPORT_WIDTH"
  note "Add the public key to the provider (GitHub, GitLab, Bitbucket, ...)."
  echo

  field "public key" "${IDENTITY_FILE}.pub"
  echo

  if [[ -f "${IDENTITY_FILE_PATH}.pub" ]]; then
    cat "${IDENTITY_FILE_PATH}.pub"
    echo
  fi

  note "Test the connection:"
  note "  ssh -T git@${HOST_NAME}"
  echo
  note "Use remotes in this form (the Host alias, not only HostName):"
  note "  git@${HOST_NAME}:org/repo.git"
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help)
        usage
        exit 0
        ;;
      -n|--dry-run)
        DRY_RUN=true
        shift
        ;;
      *)
        red "Unknown argument: $1" >&2
        echo >&2
        usage >&2
        exit 1
        ;;
    esac
  done
}

main() {
  parse_args "$@"

  [[ "$DRY_RUN" == true ]] || ensure_ssh_dir

  list_existing_hosts
  ask_host_information

  if host_exists "$HOST_NAME"; then
    fail "Host '${HOST_NAME}' already exists in ${SSH_CONFIG}; existing entries are not overwritten"
  fi

  if [[ "$DRY_RUN" == true ]]; then
    preview_changes
    exit 0
  fi

  create_backup
  generate_ssh_key
  add_key_to_agent
  add_known_host
  append_host_entry
  print_next_steps
}

main "$@"
