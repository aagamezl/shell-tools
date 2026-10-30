#!/usr/bin/env bash
# ASCII banner for shell-tools. Sourcing this file prints it.
# Sourcing this file prints the banner.

# macOS /bin/sh is bash in POSIX mode. Re-exec a normal bash.
# SHELL_TOOLS_BASH_EXEC stops a second hop.
if [ -z "${SHELL_TOOLS_BASH_EXEC:-}" ]; then
  need_bash=0
  if [ -z "${BASH_VERSION:-}" ]; then
    need_bash=1
  fi
  case ":${SHELLOPTS:-}:" in
    *:posix:*) need_bash=1 ;;
  esac
  if [ "$need_bash" -eq 1 ]; then
    if [ -f "$0" ] && command -v bash >/dev/null 2>&1 && command -v env >/dev/null 2>&1; then
      SHELL_TOOLS_BASH_EXEC=1
      export SHELL_TOOLS_BASH_EXEC
      exec env -u POSIXLY_CORRECT bash "$0" "$@"
    fi
    printf '%s\n' "ascii.sh requires bash." >&2
    exit 1
  fi
fi

print_shell_tools_ascii() {
  local art line i
  local -a lines colors
  art=$(cat <<'ART'
         __         ____      __              __
   _____/ /_  ___  / / /     / /_____  ____  / /____
  / ___/ __ \/ _ \/ / /     / __/ __ \/ __ \/ / ___/
 (__  ) / / /  __/ / /     / /_/ /_/ / /_/ / (__  )
/____/_/ /_/\___/_/_/      \__/\____/\____/_/____/
ART
)
  colors=(
    $'\033[38;5;81m'  # cyan
    $'\033[38;5;75m'  # light blue
    $'\033[38;5;69m'  # sky blue
    $'\033[38;5;63m'  # dodger blue
    $'\033[38;5;57m'  # deep sky blue
    $'\033[38;5;51m'  # cornflower blue
    $'\033[38;5;45m'  # royal blue
  )
  printf '\n'
  if [[ -t 1 && -z "${NO_COLOR:-}" && "${TERM:-}" != "dumb" ]]; then
    i=0
    while IFS= read -r line; do
      printf '%b%s\033[0m\n' "${colors[$((i % ${#colors[@]}))]}" "$line"
      i=$((i + 1))
    done <<< "$art"
  else
    printf '%s\n' "$art"
  fi
  printf '\n'
}

print_shell_tools_ascii
