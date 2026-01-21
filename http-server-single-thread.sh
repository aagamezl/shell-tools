#!/usr/bin/env bash

#################################
# Constants
#################################

# Host and port define where the server will bind.
# 127.0.0.1 restricts access to local machine only.
# If you want LAN access, change HOST to 0.0.0.0.
HOST="127.0.0.1"
PORT=8080

# Document root for serving static files.
# Every request path is resolved relative to this folder.
DOC_ROOT="./www"

# Default content type to use when no known extension is found.
DEFAULT_CONTENT_TYPE="text/plain"


#################################
# Signal handling
#################################

# The cleanup function ensures that when the process
# is terminated with SIGINT (Ctrl+C) or SIGTERM, 
# we exit gracefully and kill any background children.
cleanup() {
  echo -e "\n[INFO] Stopping server..."
  kill 0 2>/dev/null
  exit 0
}

# Register the cleanup handler for SIGINT and SIGTERM.
trap cleanup SIGINT SIGTERM


#################################
# Content type detection
#################################

# HTTP requires the correct Content-Type header to
# inform the browser how to interpret the body.
# This function uses a case statement to detect
# the MIME type based on file extension.
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

# send_response:
#   - Writes an HTTP response with a given status, type, and body.
#   - Always includes Content-Length (important because browsers
#     need to know when the body ends, unless the connection is closed).
#   - Uses CRLF (\r\n) as required by HTTP/1.1.
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

# send_file:
#   - Serves an existing file from disk.
#   - Determines its Content-Type and size.
#   - Outputs headers + file content.
send_file() {
  local filepath="$1"
  local content_type
  content_type=$(get_content_type "$filepath")
  local filesize
  filesize=$(stat -c%s "$filepath")

  echo -e "HTTP/1.1 200 OK\r"
  echo -e "Content-Type: $content_type\r"
  echo -e "Content-Length: $filesize\r"
  echo -e "Connection: close\r"
  echo -e "\r"
  cat "$filepath"
}


#################################
# Main server loop
#################################

echo "[INFO] Server started at http://$HOST:$PORT"

# Infinite loop: each iteration handles exactly one connection.
# Netcat (`nc`) accepts a connection, passes request data to our block,
# and we send back a response through the same connection.
while true; do
  {
    # Read the HTTP request line, e.g. "GET /index.html HTTP/1.1"
    # We only need the first line to know method and path.
    IFS=$'\r' read -r request_line || exit 0

    # Extract method (e.g. GET) and path (e.g. /index.html).
    method=$(awk '{print $1}' <<<"$request_line")
    path=$(awk '{print $2}' <<<"$request_line")

    # Normalize path:
    #  - Strip leading "/" because we serve relative to DOC_ROOT.
    #  - If path is empty or "/", default to index.html.
    path="${path#/}"
    if [[ -z "$path" || "$path" == "/" ]]; then
      path="index.html"
    fi

    file="$DOC_ROOT/$path"

    echo "[INFO] Request: $method $path"

    # Handle only GET requests. Other methods -> 500 error.
    if [[ "$method" != "GET" ]]; then
      send_response "500 Internal Server Error" "text/plain" "Internal Server Error"
    else
      # Serve file if it exists, else return 404.
      if [[ -f "$file" ]]; then
        send_file "$file"
      else
        send_response "404 Not Found" "text/plain" "Not Found"
      fi
    fi
  } | nc -l -p "$PORT" -s "$HOST" -q 1
done
