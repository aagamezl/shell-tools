# shellcheck shell=bash
# Path map for zsh-config.sh.
# Bash 3.2 compatible: no associative arrays and no namerefs.
# Sourced by zsh-config.sh. Do not execute directly.

# One directory under ~/.local holds this setup. Change the name to move
# both the configuration and the cloned tools together.
ZSH_CONFIG_NAME="zsh-config"
ZSH_ROOT_REL=".local/${ZSH_CONFIG_NAME}"
ZSH_CONFIG_REL="${ZSH_ROOT_REL}/config"
ZSH_TOOLS_REL="${ZSH_ROOT_REL}/tools"
ZSH_CONFIG_MARKER="zsh-config"

# Literal $HOME/.local/<name> written into files that zsh will source.
zsh_root_ref() {
  printf '%s\n' "\$HOME/${ZSH_ROOT_REL}"
}

# Longest CachyOS paths first so a directory prefix cannot eat a longer path.
zsh_tool_keys() {
  printf '%s\n' \
    POWERLEVEL10K \
    SYNTAX_HIGHLIGHTING \
    AUTOSUGGESTIONS \
    HISTORY_SUBSTRING \
    COMPLETIONS_DIR \
    OMZ_ROOT \
    CACHYOS_ZSH_CONFIG
}

# Keys cloned from upstream. CachyOS config is copied from the bundle, not cloned.
clone_tool_keys() {
  printf '%s\n' \
    OMZ_ROOT \
    SYNTAX_HIGHLIGHTING \
    AUTOSUGGESTIONS \
    COMPLETIONS_DIR \
    HISTORY_SUBSTRING \
    POWERLEVEL10K
}

# Strings as they appear in CachyOS cachyos-config.zsh and the sample bundle.
default_source_path() {
  case "$1" in
    OMZ_ROOT)
      printf '%s\n' /usr/share/oh-my-zsh
      ;;
    AUTOSUGGESTIONS)
      printf '%s\n' /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh
      ;;
    SYNTAX_HIGHLIGHTING)
      printf '%s\n' /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
      ;;
    HISTORY_SUBSTRING)
      printf '%s\n' /usr/share/zsh/plugins/zsh-history-substring-search/zsh-history-substring-search.zsh
      ;;
    COMPLETIONS_DIR)
      printf '%s\n' /usr/share/zsh/site-functions
      ;;
    POWERLEVEL10K)
      printf '%s\n' /usr/share/zsh-theme-powerlevel10k
      ;;
    CACHYOS_ZSH_CONFIG)
      printf '%s\n' /usr/share/cachyos-zsh-config
      ;;
    *)
      return 1
      ;;
  esac
}

# Text written into zsh files. $HOME is literal so the tree works for whoever owns it.
zsh_file_path() {
  local root
  root="$(zsh_root_ref)"

  case "$1" in
    OMZ_ROOT)
      printf '%s\n' "${root}/tools/oh-my-zsh"
      ;;
    AUTOSUGGESTIONS)
      printf '%s\n' "${root}/tools/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh"
      ;;
    SYNTAX_HIGHLIGHTING)
      printf '%s\n' "${root}/tools/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"
      ;;
    HISTORY_SUBSTRING)
      printf '%s\n' "${root}/tools/plugins/zsh-history-substring-search/zsh-history-substring-search.zsh"
      ;;
    COMPLETIONS_DIR)
      printf '%s\n' "${root}/tools/plugins/zsh-completions/src"
      ;;
    POWERLEVEL10K)
      printf '%s\n' "${root}/tools/themes/powerlevel10k"
      ;;
    CACHYOS_ZSH_CONFIG)
      printf '%s\n' "${root}/config"
      ;;
    *)
      return 1
      ;;
  esac
}

# Directory created by git clone.
tool_clone_dir() {
  local home="$1"
  local key="$2"
  local root="${home}/${ZSH_TOOLS_REL}"

  case "$key" in
    OMZ_ROOT) printf '%s\n' "${root}/oh-my-zsh" ;;
    AUTOSUGGESTIONS) printf '%s\n' "${root}/plugins/zsh-autosuggestions" ;;
    SYNTAX_HIGHLIGHTING) printf '%s\n' "${root}/plugins/zsh-syntax-highlighting" ;;
    HISTORY_SUBSTRING) printf '%s\n' "${root}/plugins/zsh-history-substring-search" ;;
    COMPLETIONS_DIR) printf '%s\n' "${root}/plugins/zsh-completions" ;;
    POWERLEVEL10K) printf '%s\n' "${root}/themes/powerlevel10k" ;;
    *)
      return 1
      ;;
  esac
}

tool_git_url() {
  case "$1" in
    OMZ_ROOT) printf '%s\n' https://github.com/ohmyzsh/ohmyzsh.git ;;
    AUTOSUGGESTIONS) printf '%s\n' https://github.com/zsh-users/zsh-autosuggestions.git ;;
    SYNTAX_HIGHLIGHTING) printf '%s\n' https://github.com/zsh-users/zsh-syntax-highlighting.git ;;
    HISTORY_SUBSTRING) printf '%s\n' https://github.com/zsh-users/zsh-history-substring-search.git ;;
    COMPLETIONS_DIR) printf '%s\n' https://github.com/zsh-users/zsh-completions.git ;;
    POWERLEVEL10K) printf '%s\n' https://github.com/romkatv/powerlevel10k.git ;;
    *)
      return 1
      ;;
  esac
}

tool_marker() {
  local home="$1"
  local key="$2"
  local dir
  dir="$(tool_clone_dir "$home" "$key")" || return 1

  case "$key" in
    OMZ_ROOT) printf '%s\n' "${dir}/oh-my-zsh.sh" ;;
    AUTOSUGGESTIONS) printf '%s\n' "${dir}/zsh-autosuggestions.zsh" ;;
    SYNTAX_HIGHLIGHTING) printf '%s\n' "${dir}/zsh-syntax-highlighting.zsh" ;;
    HISTORY_SUBSTRING) printf '%s\n' "${dir}/zsh-history-substring-search.zsh" ;;
    COMPLETIONS_DIR) printf '%s\n' "${dir}/src" ;;
    POWERLEVEL10K) printf '%s\n' "${dir}/powerlevel10k.zsh-theme" ;;
    *)
      return 1
      ;;
  esac
}

tool_label() {
  case "$1" in
    OMZ_ROOT) printf '%s\n' oh-my-zsh ;;
    AUTOSUGGESTIONS) printf '%s\n' zsh-autosuggestions ;;
    SYNTAX_HIGHLIGHTING) printf '%s\n' zsh-syntax-highlighting ;;
    HISTORY_SUBSTRING) printf '%s\n' zsh-history-substring-search ;;
    COMPLETIONS_DIR) printf '%s\n' zsh-completions ;;
    POWERLEVEL10K) printf '%s\n' powerlevel10k ;;
    CACHYOS_ZSH_CONFIG) printf '%s\n' cachyos-zsh-config ;;
    *)
      printf '%s\n' "$1"
      ;;
  esac
}

source_path_for() {
  local key="$1"
  local paths_file="${2:-}"
  local found=""

  if [[ -n "$paths_file" && -f "$paths_file" ]]; then
    found="$(awk -F '\t' -v k="$key" '$1 == k { print $2; exit }' "$paths_file")"
  fi
  if [[ -n "$found" ]]; then
    printf '%s\n' "$found"
    return 0
  fi
  default_source_path "$key"
}

# True when the manifest path is a tool, license, or doc shipped by CachyOS.
# Those files are never installed. The target gets a fresh upstream copy.
is_bundled_tool_path() {
  case "$1" in
    *.zwc) return 0 ;;
    /usr/share/oh-my-zsh | /usr/share/oh-my-zsh/*) return 0 ;;
    /usr/share/zsh/plugins | /usr/share/zsh/plugins/*) return 0 ;;
    /usr/share/zsh/site-functions | /usr/share/zsh/site-functions/*) return 0 ;;
    /usr/share/zsh-theme-powerlevel10k | /usr/share/zsh-theme-powerlevel10k/*) return 0 ;;
    /usr/share/doc | /usr/share/doc/*) return 0 ;;
    /usr/share/licenses | /usr/share/licenses/*) return 0 ;;
  esac
  return 1
}

# CachyOS aliases such as make="make -j`nproc`" run the substitution while the
# file is read. Single quotes run it when the alias is used, so a machine
# without nproc or pacman can still start zsh.
defer_startup_aliases() {
  local line="$1"
  local name value

  if [[ "$line" =~ ^alias[[:space:]]+([A-Za-z0-9_]+)=\"(.*)\"[[:space:]]*$ ]]; then
    name="${BASH_REMATCH[1]}"
    value="${BASH_REMATCH[2]}"
    if [[ "$value" != *"'"* && ( "$value" == *'$('* || "$value" == *'`'* ) ]]; then
      printf "alias %s='%s'" "$name" "$value"
      return 0
    fi
  fi
  printf '%s' "$line"
}

# Quote a bare $HOME/... word so a home directory that contains spaces still sources.
# Leave a path that is already inside double quotes alone.
quote_bare_home_paths() {
  local line="$1"
  local out="" pre rest token

  rest="$line"
  while [[ "$rest" == *'$HOME/'* ]]; do
    pre="${rest%%\$HOME/*}"
    rest="${rest#"$pre"}"
    if [[ "$rest" == *[[:space:]]* ]]; then
      token="${rest%%[[:space:]]*}"
    else
      token="$rest"
    fi
    rest="${rest#"$token"}"
    # A sentence period after a path is not part of the path.
    local last
    while true; do
      last="${token#${token%?}}"
      case "$last" in
        '.' | ',' | ';' | ':')
          rest="${last}${rest}"
          token="${token%?}"
          ;;
        *) break ;;
      esac
    done
    if [[ "$pre" == *'"' || "$token" == *'"'* ]]; then
      out+="${pre}${token}"
    else
      out+="${pre}\"${token}\""
    fi
  done
  printf '%s%s' "$out" "$rest"
}

rewrite_config_file() {
  local file="$1"
  local paths_file="$2"
  local source_user="$3"
  local source_home="$4"
  local content key from to

  [[ -f "$file" ]] || return 0
  content="$(cat "$file")"

  while IFS= read -r key; do
    [[ -n "$key" ]] || continue
    from="$(source_path_for "$key" "$paths_file")"
    to="$(zsh_file_path "$key")"
    [[ -z "$from" || -z "$to" || "$from" == "$to" ]] && continue
    content="${content//${from}/${to}}"
  done < <(zsh_tool_keys)

  if [[ -n "$source_home" && "$source_home" != "$HOME" ]]; then
    content="${content//${source_home}/${HOME}}"
  elif [[ -n "$source_user" ]]; then
    content="${content//\/home\/${source_user}/${HOME}}"
    content="${content//\/Users\/${source_user}/${HOME}}"
  fi

  local needle='$HOME/.p10k.zsh'
  local p10k_ref
  p10k_ref="$(zsh_file_path CACHYOS_ZSH_CONFIG)/.p10k.zsh"
  content="${content//${needle}/${p10k_ref}}"
  needle='~/.p10k.zsh'
  content="${content//${needle}/${p10k_ref}}"

  local quoted="" line
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="$(quote_bare_home_paths "$line")"
    line="$(defer_startup_aliases "$line")"
    quoted+="${line}"$'\n'
  done <<< "$content"
  printf '%s' "$quoted" > "$file"
}
