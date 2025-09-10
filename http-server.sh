#!/bin/bash

#################################
# Constants
#################################
HOST="127.0.0.1"
PORT=3000
DOC_ROOT="./www"
DEFAULT_CONTENT_TYPE="text/plain"
# Content type mappings
declare -A CONTENT_TYPES=(
  [".html"]="text/html"
  [".txt"]="text/plain"
  [".css"]="text/css"
  [".js"]="application/javascript"
  [".jpg"]="image/jpeg"
  [".png"]="image/png"
)

#################################
# Functions
#################################

# Function to log messages
log() {
  echo "[$1] $2" >&2
}

# Function to get content type
get_content_type() {
  local file_extension="${1##*.}"

  log "info" "File extension: [$file_extension]"
  echo "${CONTENT_TYPES[."$file_extension"]:-application/octet-stream}"
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
  # # Read the request line
  # read -r request_line
  # # Extract method and path from the request line
  # read -r method path http_version <<< "$request_line"

  # # Read and log all headers until we get an empty line
  # log "info" "Request: $method $path $http_version"

  # while :; do
  #   read -t 0.01 -r header || break
  #   [ -z "$header" ] && break
  #   log "debug" "Header: $header"
  # done

  # log "info" "Header: [$header]"

  # # Default to index.html if path is /
  # if [[ "$path" == "/" ]]; then
  #   path="/index.html"
  # fi

  # path="${path#/}"  # Remove leading slash

  # # Get the file path
  # file_path="$DOC_ROOT/$path"

  # log "info" "File Path: [$file_path]"

  #   # Security check
  # if [[ "$file_path" != "$DOC_ROOT"/* ]]; then
  #   log "warn" "Security violation: $path"
  #   send_response 403 "Forbidden" "text/plain" "403 Forbidden: Access denied"

  #   return
  # fi

  # # Check if file exists and is readable
  # if [ ! -f "$file_path" ] || [ ! -r "$file_path" ]; then
  #   log "warn" "File not found or not readable: $file_path"
  #   send_response 404 "Not Found" "text/plain" "404 Not Found: $path"

  #   return
  # fi

  # # Get the file size
  # local file_size=$(stat -c%s "$file_path" 2>/dev/null || stat -f%z "$file_path" 2>/dev/null)

  # local content_type
  # content_type=$(get_content_type "$file_path")

  # # Send the file
  # send_file "$file_path" "$content_type"

    # Read the request line
  read -r request_line
  [ -z "$request_line" ] && return  # Empty request
  
  # Log the request
  log "info" "Request: $request_line"
  
  # Parse method and path
  read -r method path http_version <<< "$request_line"
  
  # Read headers until empty line
  # while :; do
  #   read -t 0.01 -r header || break
  #   [ -z "$header" ] && break
  #   log "debug" "Header: $header"
  # done
  
  # Default to index.html if path is /
  [ "$path" = "/" ] && path="/index.html"
  
  # Clean and secure the path
  localpath="${path#/}"  # Remove leading slash
  local file_path="${DOC_ROOT}/${path}"
  file_path=$(realpath -m "$file_path" 2>/dev/null || echo "$file_path")
  
  # Security check
  # if [[ "$file_path" != "$DOC_ROOT"/* ]]; then
  #     log "warn" "Security violation: $path"
  #     send_response 403 "Forbidden" "text/plain" "403 Forbidden: Access denied"
  #     return
  # fi
  
  # Check if file exists and is readable
  if [ ! -f "$file_path" ] || [ ! -r "$file_path" ]; then
      log "warn" "File not found or not readable: $file_path"
      send_response 404 "Not Found" "text/plain" "404 Not Found: $path"
      return
  fi
  
  # Get content type
  local content_type
  content_type=$(get_content_type "$file_path")
  
  # Send the file
  send_file "$file_path" "$content_type"
}

#################################
# Main server loop
#################################
log "info" "Server started at http://$HOST:$PORT"

while true; do 
  # method=$(nc -l -p $PORT -s $HOST -q 1 | awk '{print $1}')
  # path=$(nc -l -p $PORT -s $HOST -q 1 | awk '{print $2}')
  # path="${path#/}"  # strip leading /

  # echo "[INFO] Request: $method $path"

  # echo -e "HTTP/1.1 200 OK\n\n Date: $(date)" | nc -l -p $PORT -s $HOST -q 1

  # Use a FIFO to handle the request
  tmpfifo=$(mktemp -u)
  mkfifo "$tmpfifo"
  
  # Use netcat to listen for connections
  cat "$tmpfifo" | nc -l -p $PORT -s $HOST -q 1 > >(
    # Process the request
    handle_request > "$tmpfifo"
    # Clean up
    rm -f "$tmpfifo"
  )
  # Clean up in case of errors
  rm -f "$tmpfifo"

  sleep 0.1
done