#!/bin/bash

source "utils/colors.sh"

# Minimal, reliable Hello World HTTP server using a single nc per request.
# Reads request-line (method + path), responds "Hello, World!".
# Requires: bash >= 4 (for coproc), netcat.

HOST="127.0.0.1"
PORT=3000

# Document root for serving static files.
# Every request path is resolved relative to this folder.
DOC_ROOT="./www"

# trap cleanup SIGINT SIGTERM

# Function to log messages
log() {
  local type="$1"
  local message="$2"
  local COLOR

  case "$type" in
    "info") COLOR="${LIGHT_CYAN}" ;;
    "warning") COLOR="${YELLOW}" ;;
    "error") COLOR="${RED}" ;;
    "debug") COLOR="${GREEN}" ;;
  esac

  # echo "[$1] $2" >&2
  echo -e "${COLOR}[$type] $message${NC}" >&2
  # echo -e "${COLOR}[$type]: $1${NC}"
}

cleanup() {
  exec {NC[1]}>&- 2>/dev/null
  exec {NC[0]}<&- 2>/dev/null
  wait "$NC_PID" 2>/dev/null
}

#################################
# Content type detection
#################################

# Returns MIME type for a given file based on its extension.
# Used to tell browsers how to render the file.
get_content_type() {
  local file="$1"
  case "$file" in
    *.html) echo "text/html" ;;
    *.css)  echo "text/css" ;;
    *.js)   echo "application/javascript" ;;
    *.json) echo "application/json" ;;
    *.png)  echo "image/png" ;;
    *.jpg|*.jpeg) echo "image/jpeg" ;;
    *.gif)  echo "image/gif" ;;
    *)      echo "$DEFAULT_CONTENT_TYPE" ;;
  esac
}

#################################
# Response helpers
#################################

# Sends a generic HTTP response with custom status, type, and body.
# Always includes Content-Length and closes the connection.
send_response() {
  local status="$1"
  local content_type="$2"
  local body="$3"

  echo -e "HTTP/1.1 $status\r"
  echo -e "Content-Type: $content_type\r"
  echo -e "Content-Length: ${#body}\r"
  echo -e "Connection: close\r"
  echo -e "\r"
  echo -n "$body"
}

# Serves a file from disk with headers and content.
# Includes Content-Length so browsers know when body ends.
# If cat fails (e.g. permissions issue), return 500 error.
send_file() {
  local filepath="$1"
  local content_type
  local filesize

  content_type=$(get_content_type "$filepath")

  log "debug" "Content Type: $content_type"
  
  if ! filesize=$(stat -c%s "$filepath" 2>/dev/null); then
    send_response "500 Internal Server Error" "text/plain" "Failed to read file"
    return
  fi

  echo -e "HTTP/1.1 200 OK\r"
  echo -e "Content-Type: $content_type\r"
  echo -e "Content-Length: $filesize\r"
  echo -e "Connection: close\r"
  echo -e "\r"

  if ! cat "$filepath"; then
    send_response "500 Internal Server Error" "text/plain" "Error reading file"
  fi
}

handle_request() {
  coproc NC { nc -l -p "$PORT" -s "$HOST" -q 1; }

  read -r request_line  <&"${NC[0]}"

    # If nothing was read, return a 400 Bad Request.
  if [[ -z "$request_line" ]]; then
    cleanup

    return
  fi

  # Strip a trailing CR (browsers send \r\n).
  request_line=${request_line%$'\r'}

  log "debug" "Request: $request_line"

  # Extract method and path without spawning extra processes.
  # request_line looks like: "GET /foo HTTP/1.1"
  method=${request_line%% *}             # first token
  rest=${request_line#* }                # drop first token + space
  path=${rest%% *}                       # second token

  log "debug" "Method: $method Path: $path"

  [ "$path" = "/" ] && path="/index.html"

  path="${path#/}"
  file="$DOC_ROOT/$path"

  log "debug" "File Path: $file"

  # Serve the file if it exists, else return 404.
  if [[ -f "$file" ]]; then
    # Prepare response body.
    # body="$(cat "$file")"

    # Write the HTTP response back to the same socket via NC[1].
    {
      send_file "$file"
      # printf 'HTTP/1.1 200 OK\r\n'
      # printf 'Content-Type: text/html\r\n'
      # printf 'Content-Length: %d\r\n' "${#body}"
      # printf 'Connection: close\r\n'
      # printf '\r\n'
      # printf '%s' "$body"
    } >&"${NC[1]}"
  else
    {
      log "error" "File Not Found: '$file'"

      send_response "404 Not Found" "text/plain" "Not Found"
    } >&"${NC[1]}"
  fi

  # Close both ends and wait for nc to exit before accepting the next connection.
  cleanup
}

log "info" "Listening on http://$HOST:$PORT"

while true; do
  handle_request &

  sleep 1
done