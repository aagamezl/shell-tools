# Discover zsh tool locations and rewrite config paths for the target distro.
# Sourced by copy-zsh-config.sh (requires bash 4+ for namerefs).

# Logical keys written to tool-paths.source.tsv / resolved on install.
readonly -a ZSH_TOOL_KEYS=(
  OMZ_ROOT
  AUTOSUGGESTIONS
  SYNTAX_HIGHLIGHTING
  HISTORY_SUBSTRING
  COMPLETIONS_DIR
  POWERLEVEL10K
  CACHYOS_ZSH_CONFIG
)

tool_pkg_for_manager() {
  local key="$1"
  local mgr="$2"
  case "$mgr" in
    pacman)
      case "$key" in
        OMZ_ROOT) printf '%s' oh-my-zsh-git ;;
        AUTOSUGGESTIONS) printf '%s' zsh-autosuggestions ;;
        SYNTAX_HIGHLIGHTING) printf '%s' zsh-syntax-highlighting ;;
        HISTORY_SUBSTRING) printf '%s' zsh-history-substring-search ;;
        COMPLETIONS_DIR) printf '%s' zsh-completions ;;
        POWERLEVEL10K) printf '%s' zsh-theme-powerlevel10k ;;
        CACHYOS_ZSH_CONFIG) printf '%s' cachyos-zsh-config ;;
      esac
      ;;
    apt)
      case "$key" in
        AUTOSUGGESTIONS) printf '%s' zsh-autosuggestions ;;
        SYNTAX_HIGHLIGHTING) printf '%s' zsh-syntax-highlighting ;;
        *) printf '%s' "" ;;
      esac
      ;;
    dnf | yum)
      case "$key" in
        AUTOSUGGESTIONS) printf '%s' zsh-autosuggestions ;;
        SYNTAX_HIGHLIGHTING) printf '%s' zsh-syntax-highlighting ;;
        *) printf '%s' "" ;;
      esac
      ;;
    zypper)
      case "$key" in
        AUTOSUGGESTIONS) printf '%s' zsh-autosuggestions ;;
        SYNTAX_HIGHLIGHTING) printf '%s' zsh-syntax-highlighting ;;
        *) printf '%s' "" ;;
      esac
      ;;
    *)
      printf '%s' ""
      ;;
  esac
}

_pacman_pkg_match() {
  local pkg="$1"
  local pattern="$2"
  local line

  [[ -n "$pkg" ]] || return 1
  command -v pacman > /dev/null 2>&1 || return 1
  pacman -Qq "$pkg" > /dev/null 2>&1 || return 1
  line="$(pacman -Qlq "$pkg" 2>/dev/null | grep -E "$pattern" | head -n1 || true)"
  [[ -n "$line" ]] && printf '%s\n' "$line"
}

_dpkg_pkg_match() {
  local pkg="$1"
  local pattern="$2"
  local line

  [[ -n "$pkg" ]] || return 1
  command -v dpkg-query > /dev/null 2>&1 || return 1
  dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "install ok installed" || return 1
  line="$(dpkg-query -L "$pkg" 2>/dev/null | grep -E "$pattern" | head -n1 || true)"
  [[ -n "$line" ]] && printf '%s\n' "$line"
}

_rpm_pkg_match() {
  local pkg="$1"
  local pattern="$2"
  local line

  [[ -n "$pkg" ]] || return 1
  rpm -q "$pkg" > /dev/null 2>&1 || return 1
  line="$(rpm -ql "$pkg" 2>/dev/null | grep -E "$pattern" | head -n1 || true)"
  [[ -n "$line" ]] && printf '%s\n' "$line"
}

_pkg_match() {
  local mgr="$1"
  local pkg="$2"
  local pattern="$3"

  case "$mgr" in
    pacman) _pacman_pkg_match "$pkg" "$pattern" ;;
    apt) _dpkg_pkg_match "$pkg" "$pattern" ;;
    dnf | yum | zypper) _rpm_pkg_match "$pkg" "$pattern" ;;
    *) return 1 ;;
  esac
}

_first_existing() {
  local candidate
  for candidate in "$@"; do
    if [[ -e "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  return 1
}

discover_tool_path() {
  local key="$1"
  local mgr="$2"
  local pkg path dir

  pkg="$(tool_pkg_for_manager "$key" "$mgr")"

  case "$key" in
    OMZ_ROOT)
      path="$(_pkg_match "$mgr" "$pkg" '/oh-my-zsh\.sh$' || true)"
      if [[ -n "$path" ]]; then
        dirname "$path"
        return 0
      fi
      _first_existing \
        /usr/share/oh-my-zsh \
        /usr/local/share/oh-my-zsh \
        "${HOME}/.oh-my-zsh"
      ;;
    AUTOSUGGESTIONS)
      path="$(_pkg_match "$mgr" "$pkg" 'zsh-autosuggestions\.zsh$' || true)"
      [[ -n "$path" ]] && printf '%s\n' "$path" && return 0
      _first_existing \
        /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh \
        /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh \
        /usr/share/zsh/vendor-completions/zsh-autosuggestions.zsh
      ;;
    SYNTAX_HIGHLIGHTING)
      path="$(_pkg_match "$mgr" "$pkg" 'zsh-syntax-highlighting\.zsh$' || true)"
      [[ -n "$path" ]] && printf '%s\n' "$path" && return 0
      _first_existing \
        /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh \
        /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
      ;;
    HISTORY_SUBSTRING)
      path="$(_pkg_match "$mgr" "$pkg" 'zsh-history-substring-search\.zsh$' || true)"
      [[ -n "$path" ]] && printf '%s\n' "$path" && return 0
      _first_existing \
        /usr/share/zsh/plugins/zsh-history-substring-search/zsh-history-substring-search.zsh \
        /usr/share/zsh-history-substring-search/zsh-history-substring-search.zsh
      ;;
    COMPLETIONS_DIR)
      path="$(_pkg_match "$mgr" "$pkg" '/Completion/.*\.zsh$' || true)"
      if [[ -n "$path" ]]; then
        dirname "$(dirname "$path")"
        return 0
      fi
      _first_existing /usr/share/zsh/plugins/zsh-completions /usr/share/zsh-completions
      ;;
    POWERLEVEL10K)
      path="$(_pkg_match "$mgr" "$pkg" 'powerlevel10k\.zsh-theme$' || true)"
      [[ -n "$path" ]] && dirname "$path" && return 0
      _first_existing \
        /usr/share/zsh-theme-powerlevel10k \
        /usr/share/zsh/themes/powerlevel10k
      ;;
    CACHYOS_ZSH_CONFIG)
      path="$(_pkg_match "$mgr" "$pkg" '(cachyos|/etc/zsh/)' || true)"
      if [[ -n "$path" ]]; then
        if [[ -d "$path" ]]; then
          printf '%s\n' "$path"
        else
          dirname "$path"
        fi
        return 0
      fi
      _first_existing /usr/share/cachyos-zsh-config /etc/cachyos-zsh
      ;;
    *)
      return 1
      ;;
  esac
}

write_tool_paths_file() {
  local outfile="$1"
  local mgr="$2"
  local key path

  : > "$outfile"
  for key in "${ZSH_TOOL_KEYS[@]}"; do
    path="$(discover_tool_path "$key" "$mgr" 2>/dev/null || true)"
    if [[ -n "$path" ]]; then
      printf '%s\t%s\n' "$key" "$path" >> "$outfile"
    fi
  done
}

load_tool_paths_tsv() {
  local file="$1"
  local -n _out="$2"
  local key path

  [[ -f "$file" ]] || return 1
  while IFS=$'\t' read -r key path || [[ -n "${key:-}" ]]; do
    [[ -z "${key:-}" || "$key" == key ]] && continue
    _out["$key"]="$path"
  done < "$file"
}

# Fallback Arch/CachyOS paths when tool-paths.source.tsv is missing (old bundles).
seed_source_paths() {
  local -n _src="$1"
  local key path

  for key in "${ZSH_TOOL_KEYS[@]}"; do
    [[ -n "${_src[$key]:-}" ]] && continue
    path="$(discover_tool_path "$key" pacman 2>/dev/null || true)"
    [[ -n "$path" ]] && _src["$key"]="$path"
  done
}

build_path_replacement_pairs() {
  local -n _src="$1"
  local -n _tgt="$2"
  local -n _pairs="$3"
  local key from to

  _pairs=()
  for key in "${ZSH_TOOL_KEYS[@]}"; do
    from="${_src[$key]:-}"
    to="${_tgt[$key]:-}"
    [[ -z "$from" || -z "$to" || "$from" == "$to" ]] && continue
    _pairs+=("$from|$to")
  done

  # Longest source paths first to avoid partial replacements.
  if ((${#_pairs[@]} > 1)); then
    local IFS=$'\n'
    _pairs=($(printf '%s\n' "${_pairs[@]}" | awk -F'|' '{ print length($1), $0 }' | sort -rn | cut -d' ' -f2-))
  fi
}

_paths_generated_content() {
  local -n _tgt="$1"
  local key

  cat <<'EOF'
# Generated by copy-zsh-config — do not edit manually.
# >>> copy-zsh-config paths >>>
EOF
  for key in "${ZSH_TOOL_KEYS[@]}"; do
    [[ -n "${_tgt[$key]:-}" ]] || continue
    case "$key" in
      OMZ_ROOT)
        printf 'export ZSH=%q\n' "${_tgt[$key]}"
        ;;
      POWERLEVEL10K)
        printf 'export POWERLEVEL10K_DIR=%q\n' "${_tgt[$key]}"
        ;;
      COMPLETIONS_DIR)
        printf 'fpath=(%q $fpath)\n' "${_tgt[$key]}/src"
        ;;
      AUTOSUGGESTIONS | SYNTAX_HIGHLIGHTING | HISTORY_SUBSTRING)
        printf '# %s: %q\n' "$key" "${_tgt[$key]}"
        ;;
      CACHYOS_ZSH_CONFIG)
        printf '# %s: %q\n' "$key" "${_tgt[$key]}"
        ;;
    esac
  done
  printf '%s\n' '# <<< copy-zsh-config paths <<<'
}

_rewrite_file_paths() {
  local file="$1"
  local -n _pairs="$2"
  local pair from to content

  [[ -f "$file" ]] || return 0
  if ! grep -Iq . "$file" 2>/dev/null; then
    return 0
  fi

  content="$(<"$file")"
  for pair in "${_pairs[@]}"; do
    from="${pair%%|*}"
    to="${pair#*|}"
    [[ -z "$from" || -z "$to" || "$from" == "$to" ]] && continue
    content="${content//${from}/${to}}"
  done
  printf '%s' "$content" > "$file"
}

rewrite_config_tree_paths() {
  local config_dir="$1"
  local -n _pairs_ref="$2"
  local file

  [[ -d "$config_dir" ]] || return 0
  while IFS= read -r -d '' file; do
    _rewrite_file_paths "$file" _pairs_ref
  done < <(find "$config_dir" -type f ! -name 'paths.generated.zsh' -print0 2>/dev/null)
}
