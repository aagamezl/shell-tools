#!/bin/bash

#################################
# Configuration
#################################
HOST="${ADDR:-127.0.0.1}"
PORT="${PORT:-3000}"
DOC_ROOT="${ROOT:-./www}"

# BSD nc listens on an address. A hostname fails the bind.
if [[ "$HOST" == "localhost" ]]; then
  HOST="127.0.0.1"
fi

#################################
# Functions
#################################

# Function to log messages
log() {
  echo "[$1] $2" >&2
}

# Function to get content type. Bash 3.2 has no associative arrays.
get_content_type() {
  local file_extension="${1##*.}"

  log "info" "File extension: [$file_extension]"
  case "$file_extension" in
    html|htm) printf '%s' "text/html" ;;
    txt) printf '%s' "text/plain" ;;
    css) printf '%s' "text/css" ;;
    js|mjs) printf '%s' "application/javascript" ;;
    jpg|jpeg) printf '%s' "image/jpeg" ;;
    png) printf '%s' "image/png" ;;
    *) printf '%s' "application/octet-stream" ;;
  esac
}

# Helper function to send response
send_response() {
  local status_code="$1"
  local status_text="$2"
  local content_type="$3"
  local message="$4"
  local length=${#message}

  printf "HTTP/1.1 %s %s\r\n" "$status_code" "$status_text"
  printf "Content-Type: %s\r\n" "$content_type"
  printf "Content-Length: %s\r\n" "$length"
  printf "Connection: close\r\n\r\n"
  printf "%s" "$message"
}

# Helper function to send file
send_file() {
  local file_path="$1"
  local content_type="$2"
  local file_size
  file_size=$(stat -c%s "$file_path" 2>/dev/null || stat -f%z "$file_path" 2>/dev/null)

  printf "HTTP/1.1 200 OK\r\n"
  printf "Content-Type: %s\r\n" "$content_type"
  printf "Content-Length: %s\r\n" "$file_size"
  printf "Connection: close\r\n\r\n"
  cat "$file_path"
}

# Function to handle requests
handle_request() {
  # Read the request line
  read -r request_line
  [ -z "$request_line" ] && return  # Empty request
  request_line="${request_line%$'\r'}"

  # Log the request
  log "info" "Request: $request_line"

  # Parse method and path
  read -r method path http_version <<< "$request_line"

  # Default to index.html if path is /
  [ "$path" = "/" ] && path="/index.html"

  # Drop the leading slash and any query string before joining DOC_ROOT.
  local relpath="${path#/}"
  relpath="${relpath%%\?*}"
  local file_path="${DOC_ROOT}/${relpath}"

  # Check if file exists and is readable
  if [ ! -f "$file_path" ] || [ ! -r "$file_path" ]; then
      log "warn" "File not found or not readable: $file_path"
      send_response 404 "Not Found" "text/plain" "404 Not Found: $path"
      return
  fi

  # macOS realpath has no -m. Resolve the existing file and keep it inside DOC_ROOT.
  local resolved
  resolved="$(cd "$(dirname "$file_path")" && pwd -P)/$(basename "$file_path")"
  case "$resolved" in
    "$DOC_ROOT"/*)
      file_path="$resolved"
      ;;
    *)
      log "warn" "Security violation: $path"
      send_response 403 "Forbidden" "text/plain" "403 Forbidden: Access denied"
      return
      ;;
  esac

  # Get content type
  local content_type
  content_type=$(get_content_type "$file_path")

  # Send the file
  send_file "$file_path" "$content_type"
}

# Listen flags depend on the nc binary. -q exists only on traditional nc.
NC_BIN="/usr/bin/nc"
NC_HELP="$("$NC_BIN" -h 2>&1 || true)"
NC_MODE="bsd"
if printf '%s\n' "$NC_HELP" | grep -q 'GNU netcat'; then
  NC_MODE="gnu"
elif printf '%s\n' "$NC_HELP" | grep -Eq -- '--local-port|-l -p port'; then
  NC_MODE="traditional"
fi

nc_listen() {
  local fifo="$1"
  if [[ "$NC_MODE" == "bsd" ]]; then
    "$NC_BIN" -l "$HOST" "$PORT" <"$fifo"
  elif [[ "$NC_MODE" == "gnu" ]]; then
    "$NC_BIN" -l -s "$HOST" -p "$PORT" -c <"$fifo"
  else
    "$NC_BIN" -l -s "$HOST" -p "$PORT" -q 1 <"$fifo"
  fi
}

#################################
# Main server loop
#################################
if [[ ! -d "$DOC_ROOT" ]]; then
  log "error" "ROOT is not a directory: $DOC_ROOT"
  exit 1
fi
DOC_ROOT="$(cd "$DOC_ROOT" && pwd -P)"

log "info" "Server started at http://$HOST:$PORT"

while true; do
  # Use a FIFO to handle the request
  tmpfifo=$(mktemp -u)
  mkfifo "$tmpfifo"

  # 3<> opens both directions so the FIFO has a writer before nc reads it.
  nc_listen "$tmpfifo" 3<>"$tmpfifo" 3>&- | handle_request >"$tmpfifo"
  rm -f "$tmpfifo"
done
