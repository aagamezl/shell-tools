shorten_home() {
  local tilde='~'
  printf '%s' "${1/#$HOME/$tilde}"
}