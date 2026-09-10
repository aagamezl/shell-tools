#!/usr/bin/env bash

set -euo pipefail

PORT="${1:-8080}"
ROOT="${ROOT:-$(pwd)}"

# Detect OS
OS="$(uname)"

# --- MIME TYPES ---
get_mime_type() {
  case "${1##*.}" in
    html) echo "text/html" ;;
    css) echo "text/css" ;;
    js) echo "application/javascript" ;;
    json) echo "application/json" ;;
    png) echo "image/png" ;;
    jpg|jpeg) echo "image/jpeg" ;;
    gif) echo "image/gif" ;;
    svg) echo "image/svg+xml" ;;
    txt) echo "text/plain" ;;
    *) echo "application/octet-stream" ;;
  esac
}

# --- FILE SIZE (portable) ---
get_file_size() {
  if [[ "$OS" == "Darwin" ]]; then
    stat -f%z "$1"
  else
    stat -c%s "$1"
  fi
}

# --- RESPONSE HELPERS ---
http_response() {
  local status="$1"
  local content_type="$2"
  local body="$3"

  printf "HTTP/1.1 %s\r\n" "$status"
  printf "Content-Type: %s\r\n" "$content_type"
  printf "Content-Length: %s\r\n" "$(printf "%s" "$body" | wc -c)"
  printf "Connection: close\r\n"
  printf "\r\n"
  printf "%s" "$body"
}

serve_file() {
  local file="$1"

  if [[ ! -f "$file" ]]; then
    http_response "404 Not Found" "text/plain" "Not Found"
    return
  fi

  local mime
  mime=$(get_mime_type "$file")

  printf "HTTP/1.1 200 OK\r\n"
  printf "Content-Type: %s\r\n" "$mime"
  printf "Content-Length: %s\r\n" "$(get_file_size "$file")"
  printf "Connection: close\r\n"
  printf "\r\n"

  cat "$file"
}

# --- REQUEST HANDLER ---
handle_request() {
  local request_line
  read -r request_line || return

  local method path protocol
  read -r method path protocol <<< "$request_line"

  path="${path%%\?*}"
  path="${path%/}"
  [[ -z "$path" ]] && path="/index.html"

  local file="$ROOT$path"

  if [[ "$file" != "$ROOT"* ]]; then
    http_response "403 Forbidden" "text/plain" "Forbidden"
    return
  fi

  case "$method" in
    GET)
      serve_file "$file"
      ;;
    *)
      http_response "405 Method Not Allowed" "text/plain" "Method Not Allowed"
      ;;
  esac
}

# --- NETCAT WRAPPER (portable) ---
nc_listen() {
  if [[ "$OS" == "Darwin" ]]; then
    # BSD netcat (macOS)
    nc -l "$PORT"
  else
    # GNU netcat
    nc -l -p "$PORT"
  fi
}

MAX_JOBS=50

wait_for_slot() {
  while (( $(jobs -rp | wc -l) >= MAX_JOBS )); do
    sleep 0.01
  done
}

start_server() {
  echo "Serving $ROOT on port $PORT"

  while true; do
    wait_for_slot

    {
      nc_listen | handle_request
    } &

    wait -n 2>/dev/null || true
  done
}

start_server