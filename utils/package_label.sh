package_label() {
  local base
  base=$(basename "$1")
  base="${base#sct2_Description_}"
  printf '%s' "${base%.txt}"
}