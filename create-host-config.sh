#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -f "$SCRIPT_DIR/utils/colors.sh" ]]; then
  # shellcheck source=utils/colors.sh
  source "$SCRIPT_DIR/utils/colors.sh"
fi

SSH_DIR="${HOME}/.ssh"
SSH_CONFIG="${SSH_DIR}/config"
DRY_RUN=false
SCRIPT_NAME="$(basename "$0")"

success() {
  if command -v green >/dev/null 2>&1; then
    green "$1"
  else
    echo "$1"
  fi
}

fail() {
  if command -v red >/dev/null 2>&1; then
    red "Error: $1" >&2
  else
    echo "Error: $1" >&2
  fi
  exit 1
}

info() {
  if command -v cyan >/dev/null 2>&1; then
    cyan "$1"
  else
    echo "$1"
  fi
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

expand_path() {
  local path="$1"

  # Match a literal '~' prefix. An unquoted ~/* is tilde-expanded to $HOME/*
  # and never matches an IdentityFile typed as ~/.ssh/..., so ssh-keygen
  # would create a "~" directory in the current working directory.
  if [[ "$path" == '~' ]]; then
    printf '%s\n' "$HOME"
  elif [[ "$path" == '~/'* ]]; then
    printf '%s\n' "${HOME}/${path:2}"
  else
    printf '%s\n' "$path"
  fi
}

unix_timestamp() {
  date +%s
}

# Always place keys in ~/.ssh. A user-supplied path contributes only its
# basename so ssh-keygen cannot write outside that directory.
normalize_identity_file() {
  local input="$1"
  local expanded name

  expanded="$(expand_path "$input")"
  name="$(basename "$expanded")"

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

list_existing_hosts() {
  info "Existing SSH host entries in ${SSH_CONFIG}:"
  echo

  if [[ ! -f "$SSH_CONFIG" ]]; then
    echo "  (none)"
    echo
    return
  fi

  local found=0
  local line

  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" =~ ^[[:space:]]*Host[[:space:]]+(.+)$ ]]; then
      printf '  %s\n' "- ${BASH_REMATCH[1]}"
      found=1
    fi
  done < "$SSH_CONFIG"

  if [[ "$found" -eq 0 ]]; then
    echo "  (none)"
  fi

  echo
}

host_exists() {
  local name="$1"
  local line aliases alias

  [[ -f "$SSH_CONFIG" ]] || return 1

  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" =~ ^[[:space:]]*Host[[:space:]]+(.+)$ ]]; then
      aliases="${BASH_REMATCH[1]}"
      # shellcheck disable=SC2086
      for alias in $aliases; do
        if [[ "$alias" == "$name" ]]; then
          return 0
        fi
      done
    fi
  done < "$SSH_CONFIG"

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
    github|github.com)
      echo "github.com"
      ;;
    gitlab|gitlab.com)
      echo "gitlab.com"
      ;;
    bitbucket|bitbucket.org)
      echo "bitbucket.org"
      ;;
    *)
      echo "$1"
      ;;
  esac
}

normalize_identities_only() {
  local value
  value="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"

  case "$value" in
    yes|y|true|1)
      echo "yes"
      ;;
    no|n|false|0)
      echo "no"
      ;;
    *)
      fail "IdentitiesOnly must be yes or no (got: $1)"
      ;;
  esac
}

ask_host_information() {
  HOST_NAME="$(prompt "Host name")"

  [[ -n "$HOST_NAME" ]] || fail "Host name is required"
  [[ "$HOST_NAME" != *" "* ]] || fail "Host name must be a single alias (no spaces)"

  HOST_HOSTNAME="$(prompt "HostName" "$(default_hostname_for "$HOST_NAME")")"

  [[ -n "$HOST_HOSTNAME" ]] || fail "HostName is required"

  SSH_USER="$(prompt "User" "git")"
  [[ -n "$SSH_USER" ]] || fail "User is required"

  IDENTITY_FILE="$(prompt "IdentityFile" "~/.ssh/id_ed25519_${HOST_NAME}")"
  [[ -n "$IDENTITY_FILE" ]] || fail "IdentityFile is required"

  normalize_identity_file "$IDENTITY_FILE"

  IDENTITIES_ONLY="$(normalize_identities_only "$(prompt "IdentitiesOnly" "yes")")"
}

create_backup() {
  local timestamp backup_file

  timestamp="$(unix_timestamp)"
  backup_file="${SSH_DIR}/config.backup.${timestamp}"

  if cp -p "$SSH_CONFIG" "$backup_file"; then
    success "Backup created successfully: ${backup_file}"
  else
    fail "Backup file was not created successfully"
  fi
}

generate_ssh_key() {
  mkdir -p "$SSH_DIR"
  chmod 700 "$SSH_DIR"

  if [[ -e "$IDENTITY_FILE_PATH" ]]; then
    info "SSH key already exists at ${IDENTITY_FILE}; leaving it unchanged."
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
    info "No private key at ${IDENTITY_FILE}; skipped ssh-add"
    return 0
  fi

  # macOS can store the passphrase in Keychain so it survives reboots.
  if [[ "$(uname)" == Darwin ]] && ssh-add --apple-use-keychain "$IDENTITY_FILE_PATH" 2>/dev/null; then
    success "SSH key added to the agent: ${IDENTITY_FILE}"
    return 0
  fi

  if ssh-add "$IDENTITY_FILE_PATH"; then
    success "SSH key added to the agent: ${IDENTITY_FILE}"
  else
    info "Could not add ${IDENTITY_FILE} to the agent. Run: ssh-add ${IDENTITY_FILE}"
  fi
}

host_in_known_hosts() {
  local known_hosts="${SSH_DIR}/known_hosts"

  [[ -f "$known_hosts" ]] || return 1
  ssh-keygen -F "$HOST_HOSTNAME" -f "$known_hosts" >/dev/null 2>&1
}

add_known_host() {
  local known_hosts="${SSH_DIR}/known_hosts"

  if host_in_known_hosts; then
    info "Host key for ${HOST_HOSTNAME} already present in ${known_hosts}"
    return 0
  fi

  touch "$known_hosts"
  chmod 644 "$known_hosts"

  if ssh-keyscan -T 5 "$HOST_HOSTNAME" >> "$known_hosts" 2>/dev/null; then
    success "Added ${HOST_HOSTNAME} to ${known_hosts}"
  else
    info "Could not scan ${HOST_HOSTNAME}. Run: ssh-keyscan ${HOST_HOSTNAME} >> ~/.ssh/known_hosts"
  fi
}

print_host_block() {
  printf 'Host %s\n' "$HOST_NAME"
  printf '  HostName %s\n' "$HOST_HOSTNAME"
  printf '  User %s\n' "$SSH_USER"
  printf '  IdentityFile %s\n' "$IDENTITY_FILE"
  printf '  IdentitiesOnly %s\n' "$IDENTITIES_ONLY"
  printf '  AddKeysToAgent yes\n'

  if [[ "$(uname)" == Darwin ]]; then
    printf '  UseKeychain yes\n'
  fi
}

print_next_steps() {
  echo
  echo "The host entry is ready for git once the public key is added"
  echo "to the provider (GitHub, GitLab, Bitbucket, ...)."
  echo
  echo "Public key (${IDENTITY_FILE}.pub):"

  if [[ -f "${IDENTITY_FILE_PATH}.pub" ]]; then
    echo
    cat "${IDENTITY_FILE_PATH}.pub"
    echo
  else
    echo "  ${IDENTITY_FILE}.pub"
    echo
  fi

  echo "Test the connection:"
  echo "  ssh -T git@${HOST_NAME}"
  echo
  echo "Use remotes in this form (the Host alias, not only HostName):"
  echo "  git@${HOST_NAME}:org/repo.git"
}

file_has_trailing_newline() {
  local file="$1"

  [[ -s "$file" ]] && [[ "$(tail -c 1 "$file")" == $'\n' ]]
}

# True when the last line is empty or whitespace-only (a blank line already
# sits at the insertion point).
file_ends_with_blank_line() {
  local file="$1"
  local last

  [[ -s "$file" ]] || return 1

  last="$(tail -n 1 "$file")"
  [[ "$last" =~ ^[[:space:]]*$ ]]
}

preview_changes() {
  local timestamp backup_file

  timestamp="$(unix_timestamp)"
  backup_file="${SSH_DIR}/config.backup.${timestamp}"

  info "Dry run: no changes were made."
  echo
  echo "Would create backup:"
  echo "  ${backup_file}"
  echo
  echo "Would generate SSH key in ~/.ssh:"

  if [[ -e "$IDENTITY_FILE_PATH" ]]; then
    echo "  ${IDENTITY_FILE} (already exists; would be left unchanged)"
  else
    echo "  ${IDENTITY_FILE} (ed25519, comment: ${HOST_NAME})"
  fi

  echo
  echo "Would append to ${SSH_CONFIG}:"
  echo

  print_host_block
  echo
  echo "Would add the key to the SSH agent:"
  echo "  ssh-add ${IDENTITY_FILE}"
  echo
  echo "Would add the provider host key if missing:"
  echo "  ssh-keyscan ${HOST_HOSTNAME} >> ~/.ssh/known_hosts"
  echo
  echo "After applying, add ${IDENTITY_FILE}.pub to the git provider"
  echo "and use remotes like: git@${HOST_NAME}:org/repo.git"
  echo "Test with: ssh -T git@${HOST_NAME}"
}

append_host_entry() {
  local tmp_file
  tmp_file="$(mktemp "${SSH_DIR}/config.tmp.XXXXXX")"

  # Copy existing config, then append the new Host block. Using a temp file
  # keeps the original untouched if the write fails mid-way.
  if ! cp -p "$SSH_CONFIG" "$tmp_file"; then
    rm -f "$tmp_file"

    fail "Host config entry was not created successfully"
  fi

  {
    if [[ -s "$tmp_file" ]]; then
      if ! file_has_trailing_newline "$tmp_file"; then
        printf '\n'
      fi

      if ! file_ends_with_blank_line "$tmp_file"; then
        printf '\n'
      fi
    fi

    print_host_block
  } >> "$tmp_file"

  if mv "$tmp_file" "$SSH_CONFIG"; then
    chmod 600 "$SSH_CONFIG"
    success "Host config entry created successfully: ${HOST_NAME}"
  else
    rm -f "$tmp_file"
    fail "Host config entry was not created successfully"
  fi
}

main() {
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
        echo "Unknown argument: $1" >&2
        echo >&2
        usage >&2
        exit 1
        ;;
    esac
  done

  if [[ "$DRY_RUN" != true ]]; then
    ensure_ssh_dir
  fi

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
