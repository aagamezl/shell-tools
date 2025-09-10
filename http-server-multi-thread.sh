#!/usr/bin/env bash

#################################
# Constants
#################################

# Server host: restrict to loopback for safety by default.
# Change to 0.0.0.0 if you want LAN access.
HOST="127.0.0.1"

# TCP port the server listens on.
PORT=8080

# Directory that holds static files to be served.
# All paths are resolved relative to this folder.
DOC_ROOT="./www"

# Default Content-Type if the file extension is unknown.
DEFAULT_CONTENT_TYPE="text/plain"


#################################
# Signal handling
#################################

# Cleanup function ensures that when the server
# is stopped (SIGINT or SIGTERM), we:
#  - Print a log message
#  - Kill any background child processes
#  - Exit cleanly
cleanup() {
  echo -e "\n[INFO] Stopping server..."
  kill 0 2>/dev/null
  exit 0
}

trap cleanup SIGINT SIGTERM


#################################
# Error checks before starting
#################################

# Check if netcat (nc) is available.
if ! command -v nc >/dev/null 2>&1; then
  echo "[ERROR] netcat (nc) is not installed. Please install it to run this server."
  exit 1
fi

# Check if stat command is available.
if ! command -v stat >/dev/null 2>&1; then
  echo "[ERROR] stat command is missing. Cannot determine file sizes."
  exit 1
fi

# Ensure document root exists.
if [[ ! -d "$DOC_ROOT" ]]; then
  echo "[ERROR] Document root '$DOC_ROOT' does not exist."
  exit 1
fi


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
  content_type=$(get_content_type "$filepath")
  local filesize
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


#################################
# Request handler
#################################

# This function handles a single client connection.
# It reads the request, parses method and path, and
# dispatches a response accordingly.
handle_request() {
  # Read the first line of the request, e.g. "GET /index.html HTTP/1.1".
  # Use IFS=$'\r' to correctly split by carriage return.
  IFS=$'\r' read -r request_line

  # If nothing was read, return a 400 Bad Request.
  if [[ -z "$request_line" ]]; then
    send_response "400 Bad Request" "text/plain" "Bad Request"
    return
  fi

  # Parse method and path.
  method=$(awk '{print $1}' <<<"$request_line")
  path=$(awk '{print $2}' <<<"$request_line")

  # Validate method and path.
  if [[ -z "$method" || -z "$path" ]]; then
    send_response "400 Bad Request" "text/plain" "Malformed Request"
    return
  fi

  # Normalize path:
  #  - Remove leading slash
  #  - Default to index.html
  path="${path#/}"
  if [[ -z "$path" || "$path" == "/" ]]; then
    path="index.html"
  fi

  file="$DOC_ROOT/$path"

  echo "[INFO] Request: $method $path"

  # Only support GET for now.
  if [[ "$method" != "GET" ]]; then
    send_response "405 Method Not Allowed" "text/plain" "Method Not Allowed"
    return
  fi

  # Serve the file if it exists, else return 404.
  if [[ -f "$file" ]]; then
    send_file "$file"
  else
    send_response "404 Not Found" "text/plain" "Not Found"
  fi
}


#################################
# Main server loop
#################################

echo "[INFO] Server started at http://$HOST:$PORT"

# Loop forever, accepting new connections.
while true; do
  # Each connection runs in its own background process (&),
  # so multiple clients can be served in parallel.
  {
    handle_request
  } | nc -l -p "$PORT" -s "$HOST" -q 1 &
done
