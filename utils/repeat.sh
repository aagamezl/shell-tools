repeat() {
  local index output=""
  for ((index = 0; index < $2; index++)); do
    output+="$1"
  done
  printf '%s' "$output"
}