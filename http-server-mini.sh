#!/bin/bash

HOST="127.0.0.1"
PORT=8080
DOC_ROOT="./www"
DEFAULT_CONTENT_TYPE="text/plain"

# while : ; do ( echo -ne "HTTP/1.1 200 OK\r\n" ; cat www/index.html; ) | nc -l -p 8080 ; done

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

log() {
  echo "[$1] $2" >&2
}

while true; do 
  # echo -e "HTTP/1.1 200 OK\n\n Date: $(date)" | nc -l -p $PORT -s $HOST -q 1

  # send_response "200 Internal Server Error" "text/plain" "Error reading file" | nc -l -p "$PORT" -s "$HOST" -q 1

  {
    # # Read the HTTP request line, e.g. "GET /index.html HTTP/1.1"
    # # We only need the first line to know method and path.
    # IFS=$'\r' read -r request_line
    # read -r request_line
    # request_line=$(nc -l -p "$PORT" -s "$HOST" -q 1 | head -n 1)
    # method=$(awk '{print $1}' <<<"$request_line")
    # path=$(awk '{print $2}' <<<"$request_line")

    # # Extract method (e.g. GET) and path (e.g. /index.html).
    # method=$(awk '{print $1}' <<<"$request_line")
    # path=$(awk '{print $2}' <<<"$request_line")

    # # Normalize path:
    # #  - Strip leading "/" because we serve relative to DOC_ROOT.
    # #  - If path is empty or "/", default to index.html.
    # path="${path#/}"
    # if [[ -z "$path" || "$path" == "/" ]]; then
    #   path="index.html"
    # fi

    # file="$DOC_ROOT/$path"

    log "info" "Request: $request_line"
    log "info" "Method, Path: $method $path"

    # echo -e "HTTP/1.1 200 OK\n\n Date: $(date)"

    body="Hello World!"
    echo -e "HTTP/1.1 200 OK\r"
    echo -e "Content-Type: text/plain\r"
    echo -e "Content-Length: ${#body}\r"
    echo -e "Connection: close\r"
    echo -e "\r"
    echo -n "$body"
  } | nc -l -p "$PORT" -s "$HOST" -q 1
  # } | nc -lvp 8080
done
