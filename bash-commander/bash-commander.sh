#!/usr/bin/env bash

# shellcheck shell=bash

# Bash 3.2+ Commander-inspired parser.
# Source this file, define args/options/commands, then call cli_parse "$@".
#
# Design constraints:
# - macOS default Bash is 3.2, so associative arrays are unavailable.
# - To keep the API portable, this implementation stores map-like data in
#   parallel KEYS/VALUES arrays and wraps access in helper functions.

if [[ -n "${__BASH_COMMANDER_LOADED:-}" ]]; then
  return 0 2>/dev/null || exit 0
fi
__BASH_COMMANDER_LOADED=1

# --------------------------- Public parse output ----------------------------

CLI_SELECTED_COMMAND=""
CLI_GLOBAL_ARGS=()      # positional args before command scope
CLI_COMMAND_ARGS=()     # positional args in selected command scope

# key/value maps represented as parallel arrays for Bash 3.2 compatibility.
# Example:
#   CLI_OPTIONS_KEYS=("debug" "port")
#   CLI_OPTIONS_VALUES=("true" "8080")
# Consumers should use cli_get_option() instead of indexing directly.
CLI_GLOBAL_OPTIONS_KEYS=()
CLI_GLOBAL_OPTIONS_VALUES=()
CLI_COMMAND_OPTIONS_KEYS=()
CLI_COMMAND_OPTIONS_VALUES=()
CLI_OPTIONS_KEYS=()
CLI_OPTIONS_VALUES=()

# ---------------------------- Internal metadata -----------------------------

CLI_NAME=""
CLI_DESCRIPTION=""

__CLI_GLOBAL_ARG_NAMES=()
__CLI_GLOBAL_ARG_REQUIRED=()
__CLI_GLOBAL_ARG_LABELS=()

__CLI_GOPT_KEYS=()
__CLI_GOPT_SHORT=()
__CLI_GOPT_LONG=()
__CLI_GOPT_KIND=()      # flag|value
__CLI_GOPT_METAVAR=()
__CLI_GOPT_DESC=()
__CLI_GOPT_DEFAULT=()

__CLI_COMMANDS=()
__CLI_COMMAND_DESC=()
__CLI_DEFAULT_COMMAND=""

__CLI_CARG_COMMAND=()
__CLI_CARG_NAME=()
__CLI_CARG_REQUIRED=()
__CLI_CARG_LABEL=()

__CLI_COPT_COMMAND=()
__CLI_COPT_KEY=()
__CLI_COPT_SHORT=()
__CLI_COPT_LONG=()
__CLI_COPT_KIND=()      # flag|value
__CLI_COPT_METAVAR=()
__CLI_COPT_DESC=()
__CLI_COPT_DEFAULT=()

# ------------------------------ KV utilities -------------------------------

__cli_kv_set() {
  # Generic "map set" against <prefix>_KEYS / <prefix>_VALUES arrays.
  # If key exists: replace value; otherwise append.
  local map_prefix="$1"
  local key="$2"
  # shellcheck disable=SC2034 # Used through eval assignments.
  local value="$3"
  local keys_var="${map_prefix}_KEYS"
  local vals_var="${map_prefix}_VALUES"

  local i max
  eval "max=\${#${keys_var}[@]}"
  i=0
  while (( i < max )); do
    local k
    eval "k=\${${keys_var}[i]}"
    if [[ "$k" == "$key" ]]; then
      eval "${vals_var}[i]=\$value"
      return 0
    fi
    ((i++))
  done

  eval "${keys_var}[max]=\$key"
  eval "${vals_var}[max]=\$value"
}

__cli_kv_get() {
  # Generic "map get" against <prefix>_KEYS / <prefix>_VALUES arrays.
  # Writes to a caller variable name (third parameter) and returns:
  #   0 when found, 1 when missing.
  local map_prefix="$1"
  local key="$2"
  local __out_var="$3"
  local keys_var="${map_prefix}_KEYS"
  local vals_var="${map_prefix}_VALUES"

  local i max
  eval "max=\${#${keys_var}[@]}"
  i=0
  while (( i < max )); do
    local k
    eval "k=\${${keys_var}[i]}"
    if [[ "$k" == "$key" ]]; then
      # shellcheck disable=SC2034 # Used through eval assignments.
      local v
      eval "v=\${${vals_var}[i]}"
      eval "${__out_var}=\$v"
      return 0
    fi
    ((i++))
  done
  return 1
}

__cli_kv_reset() {
  # Clears both key/value arrays for a map prefix.
  local map_prefix="$1"
  eval "${map_prefix}_KEYS=()"
  eval "${map_prefix}_VALUES=()"
}

__cli_trim() {
  # Trim leading/trailing whitespace (used while parsing option specs).
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

__cli_die() {
  # Standard error path for parse-time validation failures.
  # Prints user-friendly message + full help.
  printf 'Error: %s\n\n' "$1" >&2
  cli_help >&2
  return 1
}

__cli_command_exists() {
  # Linear lookup over command list.
  local wanted="$1" i
  for ((i = 0; i < ${#__CLI_COMMANDS[@]}; i++)); do
    [[ "${__CLI_COMMANDS[$i]}" == "$wanted" ]] && return 0
  done
  return 1
}

__cli_usage_line() {
  # Build usage dynamically from current metadata and (if selected) command args.
  local usage="${CLI_NAME:-program}"
  if (( ${#__CLI_GOPT_KEYS[@]} > 0 )); then
    usage+=" [options]"
  fi
  if (( ${#__CLI_COMMANDS[@]} > 0 )); then
    usage+=" [command]"
  fi
  local i
  for ((i = 0; i < ${#__CLI_GLOBAL_ARG_LABELS[@]}; i++)); do
    usage+=" ${__CLI_GLOBAL_ARG_LABELS[$i]}"
  done
  if [[ -n "$CLI_SELECTED_COMMAND" ]]; then
    for ((i = 0; i < ${#__CLI_CARG_COMMAND[@]}; i++)); do
      if [[ "${__CLI_CARG_COMMAND[$i]}" == "$CLI_SELECTED_COMMAND" ]]; then
        usage+=" ${__CLI_CARG_LABEL[$i]}"
      fi
    done
  fi
  printf '%s\n' "$usage"
}

__cli_format_opt_label() {
  # Render option left-hand side like:
  #   -p, --port <port_number>
  local short="$1"
  local long="$2"
  local metavar="$3"
  local out=""
  [[ -n "$short" ]] && out="-$short"
  if [[ -n "$long" ]]; then
    [[ -n "$out" ]] && out+=", "
    out+="--$long"
  fi
  [[ -n "$metavar" ]] && out+=" <$metavar>"
  printf '%s' "$out"
}

__cli_parse_option_spec() {
  # Parse declaration syntax:
  #   "-p, --port <value>" -> short=p, long=port, kind=value, metavar=value
  #   "--debug"            -> long=debug, kind=flag
  #
  # The canonical option key is:
  #   --long when present, otherwise -short.
  local spec="$1"
  local default_value="$2"
  local scope="$3"      # global|command
  local command="$4"    # when scope=command
  local desc="$5"

  local syntax="$spec"
  local has_value=0
  local metavar=""
  local re='[[:space:]]<([^>]+)>'
  if [[ $spec =~ $re ]]; then
    has_value=1
    metavar="${BASH_REMATCH[1]}"
    syntax="${spec%%<*}"
    syntax="$(__cli_trim "$syntax")"
  fi

  local short="" long=""
  local parts=() IFS=','
  read -r -a parts <<<"$syntax"
  local p
  for p in "${parts[@]}"; do
    p="$(__cli_trim "$p")"
    if [[ "$p" == --* ]]; then
      long="${p#--}"
    elif [[ "$p" == -* ]]; then
      short="${p#-}"
    fi
  done

  if [[ -z "$short" && -z "$long" ]]; then
    printf 'invalid option spec "%s"' "$spec"
    return 1
  fi

  local key="$long"
  [[ -z "$key" ]] && key="$short"
  local kind="flag"
  (( has_value == 1 )) && kind="value"

  if [[ "$scope" == "global" ]]; then
    __CLI_GOPT_KEYS+=("$key")
    __CLI_GOPT_SHORT+=("$short")
    __CLI_GOPT_LONG+=("$long")
    __CLI_GOPT_KIND+=("$kind")
    __CLI_GOPT_METAVAR+=("$metavar")
    __CLI_GOPT_DESC+=("$desc")
    __CLI_GOPT_DEFAULT+=("$default_value")
  else
    __CLI_COPT_COMMAND+=("$command")
    __CLI_COPT_KEY+=("$key")
    __CLI_COPT_SHORT+=("$short")
    __CLI_COPT_LONG+=("$long")
    __CLI_COPT_KIND+=("$kind")
    __CLI_COPT_METAVAR+=("$metavar")
    __CLI_COPT_DESC+=("$desc")
    __CLI_COPT_DEFAULT+=("$default_value")
  fi
}

__cli_add_arg_spec() {
  # Parse argument declaration syntax:
  #   <arg> -> required
  #   [arg] -> optional
  local token="$1"
  local scope="$2"      # global|command
  local command="$3"
  local required=0 label="" name=""

  if [[ "$token" == \<*\> ]]; then
    required=1
    name="${token#<}"
    name="${name%>}"
    label="<$name>"
  elif [[ "$token" == \[*\] ]]; then
    required=0
    name="${token#[}"
    name="${name%]}"
    label="[$name]"
  else
    printf 'invalid argument syntax "%s" (expected <arg> or [arg])' "$token"
    return 1
  fi

  if [[ "$scope" == "global" ]]; then
    __CLI_GLOBAL_ARG_NAMES+=("$name")
    __CLI_GLOBAL_ARG_REQUIRED+=("$required")
    __CLI_GLOBAL_ARG_LABELS+=("$label")
  else
    __CLI_CARG_COMMAND+=("$command")
    __CLI_CARG_NAME+=("$name")
    __CLI_CARG_REQUIRED+=("$required")
    __CLI_CARG_LABEL+=("$label")
  fi
}

__cli_set_default_option_values() {
  # Hydrate runtime option maps from declaration defaults.
  # Flag options default to "false" when no explicit default is provided.
  local scope="$1"    # global|command
  local command="$2"
  local i key kind def

  if [[ "$scope" == "global" ]]; then
    __cli_kv_reset "CLI_GLOBAL_OPTIONS"
    for ((i = 0; i < ${#__CLI_GOPT_KEYS[@]}; i++)); do
      key="${__CLI_GOPT_KEYS[$i]}"
      kind="${__CLI_GOPT_KIND[$i]}"
      def="${__CLI_GOPT_DEFAULT[$i]}"
      if [[ "$kind" == "flag" && -z "$def" ]]; then
        def="false"
      fi
      __cli_kv_set "CLI_GLOBAL_OPTIONS" "$key" "$def"
    done
  else
    __cli_kv_reset "CLI_COMMAND_OPTIONS"
    for ((i = 0; i < ${#__CLI_COPT_KEY[@]}; i++)); do
      [[ "${__CLI_COPT_COMMAND[$i]}" == "$command" ]] || continue
      key="${__CLI_COPT_KEY[$i]}"
      kind="${__CLI_COPT_KIND[$i]}"
      def="${__CLI_COPT_DEFAULT[$i]}"
      if [[ "$kind" == "flag" && -z "$def" ]]; then
        def="false"
      fi
      __cli_kv_set "CLI_COMMAND_OPTIONS" "$key" "$def"
    done
  fi
}

__cli_resolve_option() {
  # Resolve a runtime token to a declared option in the target scope.
  # Supports:
  #   --name
  #   --name=value
  #   -n
  #
  # Output is returned via variable names passed by the caller:
  #   key, kind(flag|value), inline value (for --name=value)
  local token="$1"
  local scope="$2"         # global|command
  local command="$3"
  local __out_key="$4"
  local __out_kind="$5"
  local __out_inline="$6"

  local raw="$token" inline=""
  if [[ "$raw" == --*=* ]]; then
    inline="${raw#*=}"
    raw="${raw%%=*}"
  fi

  local want_long="" want_short=""
  if [[ "$raw" == --* ]]; then
    want_long="${raw#--}"
  elif [[ "$raw" == -* ]]; then
    want_short="${raw#-}"
  else
    return 1
  fi

  local i found_key
  if [[ "$scope" == "global" ]]; then
    for ((i = 0; i < ${#__CLI_GOPT_KEYS[@]}; i++)); do
      if [[ -n "$want_long" && "${__CLI_GOPT_LONG[$i]}" == "$want_long" ]]; then
        found_key="${__CLI_GOPT_KEYS[$i]}"
      elif [[ -n "$want_short" && "${__CLI_GOPT_SHORT[$i]}" == "$want_short" ]]; then
        found_key="${__CLI_GOPT_KEYS[$i]}"
      else
        continue
      fi
      printf -v "$__out_key" '%s' "$found_key"
      printf -v "$__out_kind" '%s' "${__CLI_GOPT_KIND[$i]}"
      printf -v "$__out_inline" '%s' "$inline"
      return 0
    done
  else
    for ((i = 0; i < ${#__CLI_COPT_KEY[@]}; i++)); do
      [[ "${__CLI_COPT_COMMAND[$i]}" == "$command" ]] || continue
      if [[ -n "$want_long" && "${__CLI_COPT_LONG[$i]}" == "$want_long" ]]; then
        found_key="${__CLI_COPT_KEY[$i]}"
      elif [[ -n "$want_short" && "${__CLI_COPT_SHORT[$i]}" == "$want_short" ]]; then
        found_key="${__CLI_COPT_KEY[$i]}"
      else
        continue
      fi
      printf -v "$__out_key" '%s' "$found_key"
      printf -v "$__out_kind" '%s' "${__CLI_COPT_KIND[$i]}"
      printf -v "$__out_inline" '%s' "$inline"
      return 0
    done
  fi

  return 1
}

__cli_required_count_for_global_args() {
  # Count required global positional declarations.
  local c=0 i
  for ((i = 0; i < ${#__CLI_GLOBAL_ARG_REQUIRED[@]}; i++)); do
    [[ "${__CLI_GLOBAL_ARG_REQUIRED[$i]}" == "1" ]] && ((c++))
  done
  printf '%s' "$c"
}

__cli_required_count_for_command_args() {
  # Count required positional declarations for a given command.
  local command="$1" c=0 i
  for ((i = 0; i < ${#__CLI_CARG_COMMAND[@]}; i++)); do
    [[ "${__CLI_CARG_COMMAND[$i]}" == "$command" ]] || continue
    [[ "${__CLI_CARG_REQUIRED[$i]}" == "1" ]] && ((c++))
  done
  printf '%s' "$c"
}

__cli_total_count_for_command_args() {
  # Count total positional declarations (required + optional) for a command.
  # Used to detect "too many arguments" errors.
  local command="$1" c=0 i
  for ((i = 0; i < ${#__CLI_CARG_COMMAND[@]}; i++)); do
    [[ "${__CLI_CARG_COMMAND[$i]}" == "$command" ]] || continue
    ((c++))
  done
  printf '%s' "$c"
}

__cli_merge_options() {
  # Build combined CLI_OPTIONS map where command options override global keys
  # when names collide, mirroring "most specific scope wins".
  __cli_kv_reset "CLI_OPTIONS"
  local i key val
  for ((i = 0; i < ${#CLI_GLOBAL_OPTIONS_KEYS[@]}; i++)); do
    key="${CLI_GLOBAL_OPTIONS_KEYS[$i]}"
    val="${CLI_GLOBAL_OPTIONS_VALUES[$i]}"
    __cli_kv_set "CLI_OPTIONS" "$key" "$val"
  done
  for ((i = 0; i < ${#CLI_COMMAND_OPTIONS_KEYS[@]}; i++)); do
    key="${CLI_COMMAND_OPTIONS_KEYS[$i]}"
    val="${CLI_COMMAND_OPTIONS_VALUES[$i]}"
    __cli_kv_set "CLI_OPTIONS" "$key" "$val"
  done
}

# ------------------------------- Public API --------------------------------

cli_create() {
  # Full reset so one shell session can define/parse multiple CLIs safely.
  CLI_NAME="$1"
  CLI_DESCRIPTION="${2:-}"

  __CLI_GLOBAL_ARG_NAMES=()
  __CLI_GLOBAL_ARG_REQUIRED=()
  __CLI_GLOBAL_ARG_LABELS=()

  __CLI_GOPT_KEYS=()
  __CLI_GOPT_SHORT=()
  __CLI_GOPT_LONG=()
  __CLI_GOPT_KIND=()
  __CLI_GOPT_METAVAR=()
  __CLI_GOPT_DESC=()
  __CLI_GOPT_DEFAULT=()

  __CLI_COMMANDS=()
  __CLI_COMMAND_DESC=()
  __CLI_DEFAULT_COMMAND=""

  __CLI_CARG_COMMAND=()
  __CLI_CARG_NAME=()
  __CLI_CARG_REQUIRED=()
  __CLI_CARG_LABEL=()

  __CLI_COPT_COMMAND=()
  __CLI_COPT_KEY=()
  __CLI_COPT_SHORT=()
  __CLI_COPT_LONG=()
  __CLI_COPT_KIND=()
  __CLI_COPT_METAVAR=()
  __CLI_COPT_DESC=()
  __CLI_COPT_DEFAULT=()

  CLI_SELECTED_COMMAND=""
  CLI_GLOBAL_ARGS=()
  CLI_COMMAND_ARGS=()
  __cli_kv_reset "CLI_GLOBAL_OPTIONS"
  __cli_kv_reset "CLI_COMMAND_OPTIONS"
  __cli_kv_reset "CLI_OPTIONS"
}

cli_argument() {
  # Declare a global positional argument.
  if ! __cli_add_arg_spec "$1" "global" ""; then
    printf 'Error: invalid argument definition: %s\n' "$1" >&2
    return 1
  fi
}

cli_option() {
  # Declare a global option.
  if ! __cli_parse_option_spec "$1" "${3:-}" "global" "" "${2:-}"; then
    printf 'Error: invalid option definition: %s\n' "$1" >&2
    return 1
  fi
}

cli_command() {
  # Register a command and optional default flag ("true").
  local name="$1"
  local description="${2:-}"
  local is_default="${3:-false}"
  if __cli_command_exists "$name"; then
    printf 'Error: command "%s" already defined\n' "$name" >&2
    return 1
  fi
  __CLI_COMMANDS+=("$name")
  __CLI_COMMAND_DESC+=("$description")
  [[ "$is_default" == "true" ]] && __CLI_DEFAULT_COMMAND="$name"
  return 0
}

cli_command_argument() {
  # Declare command-scoped positional argument.
  local command="$1"
  if ! __cli_command_exists "$command"; then
    printf 'Error: unknown command "%s"\n' "$command" >&2
    return 1
  fi
  if ! __cli_add_arg_spec "$2" "command" "$command"; then
    printf 'Error: invalid command argument definition: %s\n' "$2" >&2
    return 1
  fi
}

cli_command_option() {
  # Declare command-scoped option.
  local command="$1"
  if ! __cli_command_exists "$command"; then
    printf 'Error: unknown command "%s"\n' "$command" >&2
    return 1
  fi
  if ! __cli_parse_option_spec "$2" "${4:-}" "command" "$command" "${3:-}"; then
    printf 'Error: invalid command option definition: %s\n' "$2" >&2
    return 1
  fi
}

cli_get_option() {
  # Public option accessor for callers. This abstracts internal storage.
  local key="$1"
  local out_var="$2"
  if __cli_kv_get "CLI_OPTIONS" "$key" "$out_var"; then
    return 0
  fi
  return 1
}

cli_help() {
  # Dynamic help renderer. Uses selected command context (if any) to show
  # command-specific options in addition to global options.
  [[ -n "$CLI_DESCRIPTION" ]] && printf '%s\n\n' "$CLI_DESCRIPTION"
  printf 'Usage: '
  __cli_usage_line
  printf '\n'

  printf 'Options:\n'
  local i label desc
  for ((i = 0; i < ${#__CLI_GOPT_KEYS[@]}; i++)); do
    label="$(__cli_format_opt_label "${__CLI_GOPT_SHORT[$i]}" "${__CLI_GOPT_LONG[$i]}" "${__CLI_GOPT_METAVAR[$i]}")"
    desc="${__CLI_GOPT_DESC[$i]}"
    if [[ "${__CLI_GOPT_KIND[$i]}" == "flag" && -n "${__CLI_GOPT_DEFAULT[$i]}" ]]; then
      desc="$desc (default: ${__CLI_GOPT_DEFAULT[$i]})"
    fi
    printf '  %-26s %s\n' "$label" "$desc"
  done
  printf '  %-26s %s\n' '-h, --help' 'display help for command'

  if [[ -n "$CLI_SELECTED_COMMAND" ]]; then
    local has_any=0
    for ((i = 0; i < ${#__CLI_COPT_KEY[@]}; i++)); do
      if [[ "${__CLI_COPT_COMMAND[$i]}" == "$CLI_SELECTED_COMMAND" ]]; then
        has_any=1
        break
      fi
    done
    if (( has_any == 1 )); then
      printf '\nCommand Options (%s):\n' "$CLI_SELECTED_COMMAND"
      for ((i = 0; i < ${#__CLI_COPT_KEY[@]}; i++)); do
        [[ "${__CLI_COPT_COMMAND[$i]}" == "$CLI_SELECTED_COMMAND" ]] || continue
        label="$(__cli_format_opt_label "${__CLI_COPT_SHORT[$i]}" "${__CLI_COPT_LONG[$i]}" "${__CLI_COPT_METAVAR[$i]}")"
        desc="${__CLI_COPT_DESC[$i]}"
        if [[ "${__CLI_COPT_KIND[$i]}" == "flag" && -n "${__CLI_COPT_DEFAULT[$i]}" ]]; then
          desc="$desc (default: ${__CLI_COPT_DEFAULT[$i]})"
        fi
        printf '  %-26s %s\n' "$label" "$desc"
      done
    fi
  fi

  if (( ${#__CLI_COMMANDS[@]} > 0 )); then
    printf '\nCommands:\n'
    local c j label2 suffix
    for ((i = 0; i < ${#__CLI_COMMANDS[@]}; i++)); do
      c="${__CLI_COMMANDS[$i]}"
      suffix=""

      local has_opts=0
      for ((j = 0; j < ${#__CLI_COPT_COMMAND[@]}; j++)); do
        [[ "${__CLI_COPT_COMMAND[$j]}" == "$c" ]] && has_opts=1
      done
      (( has_opts == 1 )) && suffix+=" [options]"

      for ((j = 0; j < ${#__CLI_CARG_COMMAND[@]}; j++)); do
        [[ "${__CLI_CARG_COMMAND[$j]}" == "$c" ]] || continue
        suffix+=" ${__CLI_CARG_LABEL[$j]}"
      done

      label2="$c$suffix"
      [[ "$c" == "$__CLI_DEFAULT_COMMAND" ]] && label2="$label2 (default)"
      printf '  %-26s %s\n' "$label2" "${__CLI_COMMAND_DESC[$i]}"
    done
    printf '  %-26s %s\n' 'help [command]' 'display help for command'
  fi
}

cli_dump_result() {
  # Debug helper to inspect parser output state.
  local i
  printf 'CLI_SELECTED_COMMAND=%q\n' "$CLI_SELECTED_COMMAND"

  printf 'CLI_GLOBAL_OPTIONS:\n'
  for ((i = 0; i < ${#CLI_GLOBAL_OPTIONS_KEYS[@]}; i++)); do
    printf '  %s=%q\n' "${CLI_GLOBAL_OPTIONS_KEYS[$i]}" "${CLI_GLOBAL_OPTIONS_VALUES[$i]}"
  done

  printf 'CLI_COMMAND_OPTIONS:\n'
  for ((i = 0; i < ${#CLI_COMMAND_OPTIONS_KEYS[@]}; i++)); do
    printf '  %s=%q\n' "${CLI_COMMAND_OPTIONS_KEYS[$i]}" "${CLI_COMMAND_OPTIONS_VALUES[$i]}"
  done

  printf 'CLI_OPTIONS (merged):\n'
  for ((i = 0; i < ${#CLI_OPTIONS_KEYS[@]}; i++)); do
    printf '  %s=%q\n' "${CLI_OPTIONS_KEYS[$i]}" "${CLI_OPTIONS_VALUES[$i]}"
  done

  printf 'CLI_GLOBAL_ARGS=('
  for ((i = 0; i < ${#CLI_GLOBAL_ARGS[@]}; i++)); do
    printf ' %q' "${CLI_GLOBAL_ARGS[$i]}"
  done
  printf ' )\n'

  printf 'CLI_COMMAND_ARGS=('
  for ((i = 0; i < ${#CLI_COMMAND_ARGS[@]}; i++)); do
    printf ' %q' "${CLI_COMMAND_ARGS[$i]}"
  done
  printf ' )\n'
}

cli_parse() {
  # Main parse state machine.
  #
  # Strategy:
  # 1) Initialize runtime state + option defaults.
  # 2) Single pass over argv with "expecting value" sub-state.
  # 3) Resolve command boundary and option scope (global vs command).
  # 4) Validate missing/extra positional args.
  # 5) Merge scoped options for convenient retrieval.
  CLI_SELECTED_COMMAND=""
  CLI_GLOBAL_ARGS=()
  CLI_COMMAND_ARGS=()
  __cli_set_default_option_values "global" ""
  __cli_kv_reset "CLI_COMMAND_OPTIONS"

  local args=("$@")
  local i=0
  # expecting_* tracks cases like "--port 8080" where value arrives in
  # next token.
  local expecting_scope="" expecting_key=""
  local explicit_command_seen=0

  while (( i < ${#args[@]} )); do
    local token="${args[$i]}"

    if [[ -n "$expecting_scope" ]]; then
      if [[ "$expecting_scope" == "global" ]]; then
        __cli_kv_set "CLI_GLOBAL_OPTIONS" "$expecting_key" "$token"
      else
        __cli_kv_set "CLI_COMMAND_OPTIONS" "$expecting_key" "$token"
      fi
      expecting_scope=""
      expecting_key=""
      ((i++))
      continue
    fi

    # Global control tokens are processed before command/option matching.
    case "$token" in
      -h|--help)
        cli_help
        return 2
        ;;
      --)
        ((i++))
        while (( i < ${#args[@]} )); do
          if [[ -n "$CLI_SELECTED_COMMAND" ]]; then
            CLI_COMMAND_ARGS+=("${args[$i]}")
          else
            CLI_GLOBAL_ARGS+=("${args[$i]}")
          fi
          ((i++))
        done
        break
        ;;
    esac

    # If commands exist, first non-option token can select command.
    if [[ -z "$CLI_SELECTED_COMMAND" && ${#__CLI_COMMANDS[@]} -gt 0 && "$token" != -* ]]; then
      if __cli_command_exists "$token"; then
        CLI_SELECTED_COMMAND="$token"
        explicit_command_seen=1
        __cli_set_default_option_values "command" "$CLI_SELECTED_COMMAND"
        ((i++))
        continue
      elif [[ -n "$__CLI_DEFAULT_COMMAND" ]]; then
        CLI_SELECTED_COMMAND="$__CLI_DEFAULT_COMMAND"
        __cli_set_default_option_values "command" "$CLI_SELECTED_COMMAND"
      fi
    fi

    # Commander-like behavior: if a default command exists and user starts with
    # options, bind those options to default command scope when applicable.
    if [[ -z "$CLI_SELECTED_COMMAND" && ${#__CLI_COMMANDS[@]} -gt 0 && -n "$__CLI_DEFAULT_COMMAND" && "$token" == -* ]]; then
      CLI_SELECTED_COMMAND="$__CLI_DEFAULT_COMMAND"
      __cli_set_default_option_values "command" "$CLI_SELECTED_COMMAND"
    fi

    # Option token path.
    if [[ "$token" == -* ]]; then
      local key="" kind="" inline="" matched=0

      # Global options take precedence while resolving to keep behavior
      # predictable when duplicate names exist across scopes.
      if __cli_resolve_option "$token" "global" "" key kind inline; then
        matched=1
        if [[ "$kind" == "flag" ]]; then
          __cli_kv_set "CLI_GLOBAL_OPTIONS" "$key" "true"
        else
          if [[ -n "$inline" ]]; then
            __cli_kv_set "CLI_GLOBAL_OPTIONS" "$key" "$inline"
          else
            expecting_scope="global"
            expecting_key="$key"
          fi
        fi
      elif [[ -n "$CLI_SELECTED_COMMAND" ]] && __cli_resolve_option "$token" "command" "$CLI_SELECTED_COMMAND" key kind inline; then
        matched=1
        if [[ "$kind" == "flag" ]]; then
          __cli_kv_set "CLI_COMMAND_OPTIONS" "$key" "true"
        else
          if [[ -n "$inline" ]]; then
            __cli_kv_set "CLI_COMMAND_OPTIONS" "$key" "$inline"
          else
            expecting_scope="command"
            expecting_key="$key"
          fi
        fi
      fi

      if (( matched == 0 )); then
        __cli_die "unknown option: $token" || return 1
        return 1
      fi

      ((i++))
      continue
    fi

    # Positional token path.
    if [[ -n "$CLI_SELECTED_COMMAND" ]]; then
      CLI_COMMAND_ARGS+=("$token")
    else
      CLI_GLOBAL_ARGS+=("$token")
    fi
    ((i++))
  done

  # Value option was declared but missing its value token.
  if [[ -n "$expecting_scope" ]]; then
    __cli_die "missing value for option: $expecting_key" || return 1
    return 1
  fi

  # Final fallback to default command when command list exists and user did not
  # explicitly name one.
  if [[ -z "$CLI_SELECTED_COMMAND" && ${#__CLI_COMMANDS[@]} -gt 0 && -n "$__CLI_DEFAULT_COMMAND" && $explicit_command_seen -eq 0 ]]; then
    CLI_SELECTED_COMMAND="$__CLI_DEFAULT_COMMAND"
    __cli_set_default_option_values "command" "$CLI_SELECTED_COMMAND"
  fi

  local req_global req_cmd
  # Validation order:
  # 1) required global args
  # 2) required command args
  # 3) max command args
  req_global="$(__cli_required_count_for_global_args)"
  if (( ${#CLI_GLOBAL_ARGS[@]} < req_global )); then
    __cli_die "missing required argument(s)" || return 1
    return 1
  fi

  if [[ -n "$CLI_SELECTED_COMMAND" ]]; then
    req_cmd="$(__cli_required_count_for_command_args "$CLI_SELECTED_COMMAND")"
    if (( ${#CLI_COMMAND_ARGS[@]} < req_cmd )); then
      __cli_die "missing required argument(s) for command '$CLI_SELECTED_COMMAND'" || return 1
      return 1
    fi

    local total_cmd
    total_cmd="$(__cli_total_count_for_command_args "$CLI_SELECTED_COMMAND")"
    if (( ${#CLI_COMMAND_ARGS[@]} > total_cmd )); then
      printf "error: too many arguments for '%s'. Expected %s arguments but got %s.\n" \
        "$CLI_SELECTED_COMMAND" "$total_cmd" "${#CLI_COMMAND_ARGS[@]}" >&2
      return 1
    fi
  fi

  __cli_merge_options
  return 0
}
