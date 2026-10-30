#!/usr/bin/env bash
# Static file server for bash 3.2 (macOS) and current bash (Linux).
# One nc listener per address. Each response closes the connection so nc can
# accept the next one. nc's listen queue holds a single extra connection.

set -euo pipefail

PORT="${1:-${PORT:-8080}}"
ROOT="${ROOT:-$(pwd)}"
ADDR="${ADDR:-127.0.0.1}"
HEADER_TIMEOUT="${HEADER_TIMEOUT:-5}"
MAX_HEADER="${MAX_HEADER:-8192}"
MAX_REQUESTS="${MAX_REQUESTS:-100}"

OS="$(uname)"

if [[ ! "$PORT" =~ ^[0-9]+$ ]] || (( PORT < 1 || PORT > 65535 )); then
  printf '%s\n' "Port must be a number from 1 to 65535." >&2
  exit 1
fi
if [[ ! "$HEADER_TIMEOUT" =~ ^[0-9]+$ ]]; then
  printf '%s\n' "HEADER_TIMEOUT must be a number." >&2
  exit 1
fi
if [[ "$ADDR" == *[!0-9A-Za-z.:]* || -z "$ADDR" ]]; then
  printf '%s\n' "ADDR must be an IPv4 or IPv6 address." >&2
  exit 1
fi
if [[ ! -d "$ROOT" ]]; then
  printf '%s\n' "ROOT is not a directory: $ROOT" >&2
  exit 1
fi
ROOT="$(cd "$ROOT" && pwd -P)"

get_mime_type() {
  case "${1##*.}" in
    html|htm) printf '%s' "text/html" ;;
    css) printf '%s' "text/css" ;;
    js|mjs) printf '%s' "application/javascript" ;;
    json) printf '%s' "application/json" ;;
    png) printf '%s' "image/png" ;;
    jpg|jpeg) printf '%s' "image/jpeg" ;;
    gif) printf '%s' "image/gif" ;;
    svg) printf '%s' "image/svg+xml" ;;
    ico) printf '%s' "image/x-icon" ;;
    webp) printf '%s' "image/webp" ;;
    woff) printf '%s' "font/woff" ;;
    woff2) printf '%s' "font/woff2" ;;
    txt|map) printf '%s' "text/plain" ;;
    xml) printf '%s' "application/xml" ;;
    wasm) printf '%s' "application/wasm" ;;
    *) printf '%s' "application/octet-stream" ;;
  esac
}

get_file_size() {
  if [[ "$OS" == "Darwin" ]]; then
    stat -f%z "$1"
  else
    stat -c%s "$1"
  fi
}

http_response() {
  local status="$1"
  local content_type="$2"
  local body="$3"
  local connection="$4"
  local length
  length="$(printf '%s' "$body" | wc -c | tr -d '[:space:]')"

  printf 'HTTP/1.1 %s\r\n' "$status"
  printf 'Content-Type: %s\r\n' "$content_type"
  printf 'Content-Length: %s\r\n' "$length"
  printf 'X-Content-Type-Options: nosniff\r\n'
  printf 'Connection: %s\r\n' "$connection"
  printf '\r\n'
  printf '%s' "$body"
}

send_status() {
  http_response "$1" "text/plain" "$2" "close"
}

send_file() {
  local file="$1"
  local method="$2"
  local connection="$3"
  local mime size

  mime="$(get_mime_type "$file")"
  size="$(get_file_size "$file" | tr -d '[:space:]')"

  printf 'HTTP/1.1 200 OK\r\n'
  printf 'Content-Type: %s\r\n' "$mime"
  printf 'Content-Length: %s\r\n' "$size"
  printf 'X-Content-Type-Options: nosniff\r\n'
  printf 'Connection: %s\r\n' "$connection"
  printf '\r\n'
  if [[ "$method" == "GET" ]]; then
    cat -- "$file"
  fi
}

# Decode one pass. Reject NUL, controls, and backslash so the path cannot
# smuggle a separator or a ".." through percent-encoding.
url_decode() {
  local s="$1" i=0 len out="" ch hex byte
  len=${#s}
  while (( i < len )); do
    ch=${s:i:1}
    if [[ "$ch" == "%" ]]; then
      (( i + 2 < len )) || return 1
      hex=${s:i+1:2}
      [[ "$hex" =~ ^[0-9A-Fa-f][0-9A-Fa-f]$ ]] || return 1
      byte=$((16#$hex))
      (( byte >= 32 && byte != 92 && byte != 127 )) || return 1
      out="${out}$(printf "\\$(printf '%03o' "$byte")")"
      i=$((i + 3))
    else
      case "$ch" in
        [[:cntrl:]]|\\) return 1 ;;
      esac
      out="${out}${ch}"
      i=$((i + 1))
    fi
  done
  printf '%s' "$out"
}

# Collapse extra slashes. Any ".." segment is a hard failure, including one
# produced by decoding %2e%2e.
normalize_path() {
  local raw="$1" part out=""
  local parts=()
  raw="${raw%%\?*}"
  raw="${raw%%#*}"
  [[ "$raw" == /* ]] || return 1
  IFS=/ read -r -a parts <<< "${raw#/}"
  if (( ${#parts[@]} > 0 )); then
    for part in "${parts[@]}"; do
      [[ -z "$part" || "$part" == "." ]] && continue
      [[ "$part" == ".." || "$part" == *\\* ]] && return 1
      out="${out}/${part}"
    done
  fi
  [[ -z "$out" ]] && out="/index.html"
  printf '%s' "$out"
}

under_root() {
  case "$1/" in
    "$ROOT"/*) return 0 ;;
    *) return 1 ;;
  esac
}

fallback_realpath() {
  local path="$1" i=0 link dir base
  while [[ -L "$path" && i -lt 16 ]]; do
    link="$(readlink "$path")" || return 1
    if [[ "$link" != /* ]]; then
      link="$(dirname "$path")/$link"
    fi
    path="$link"
    i=$((i + 1))
  done
  [[ -L "$path" ]] && return 1
  dir="$(dirname "$path")"
  dir="$(cd "$dir" && pwd -P)" || return 1
  base="$(basename "$path")"
  printf '%s/%s' "$dir" "$base"
}

# 0 when any component below ROOT is a symlink.
has_symlink() {
  local full="$1" rest part acc="$ROOT" parts=()
  rest="${full#"$ROOT"/}"
  IFS=/ read -r -a parts <<< "$rest"
  for part in "${parts[@]}"; do
    [[ -z "$part" ]] && continue
    acc="${acc}/${part}"
    if [[ -L "$acc" ]]; then
      return 0
    fi
  done
  return 1
}

canonical_file() {
  local path="$1" resolved
  if command -v realpath >/dev/null 2>&1; then
    resolved="$(realpath "$path" 2>/dev/null)" || return 2
  else
    resolved="$(fallback_realpath "$path")" || return 2
  fi
  under_root "$resolved" || return 1
  printf '%s' "$resolved"
}

# Print the regular file to serve. Status 1 is forbidden, 2 is not found.
resolve_file() {
  local rel="$1" path parent resolved
  path="${ROOT}${rel}"

  if [[ -d "$path" && ! -L "$path" ]]; then
    path="${path}/index.html"
  fi

  if [[ ! -e "$path" && ! -L "$path" ]]; then
    parent="$(dirname "$path")"
    [[ -d "$parent" ]] || return 2
    parent="$(cd "$parent" && pwd -P)" || return 2
    under_root "$parent" || return 1
    return 2
  fi

  # Most files are not links. Skip realpath unless a component can escape ROOT.
  if has_symlink "$path"; then
    resolved="$(canonical_file "$path")" || return $?
  else
    resolved="$path"
  fi
  [[ -f "$resolved" ]] || return 2
  printf '%s' "$resolved"
}

handle_connection() {
  local count=0 request_line line method path protocol decoded normalized
  local file connection close_after unread_body total headers_done lower status

  while (( count < MAX_REQUESTS )); do
    request_line=""
    # Block until nc delivers a request. A timeout here restarts nc and
    # drops a connection that is waiting in its queue.
    if ! IFS= read -r request_line; then
      return 0
    fi
    request_line="${request_line%$'\r'}"
    if (( ${#request_line} == 0 || ${#request_line} > 2048 )); then
      send_status "400 Bad Request" "Bad Request"
      return 0
    fi

    total=${#request_line}
    headers_done=0
    close_after=0
    unread_body=0
    while IFS= read -r -t "$HEADER_TIMEOUT" line; do
      line="${line%$'\r'}"
      if [[ -z "$line" ]]; then
        headers_done=1
        break
      fi
      total=$((total + ${#line}))
      if (( total > MAX_HEADER )); then
        send_status "431 Request Header Fields Too Large" "Header too large"
        return 0
      fi
      case "$line" in
        [Cc]onnection:*[Cc]lose*) close_after=1 ;;
        [Cc]ontent-[Ll]ength:*|[Tt]ransfer-[Ee]ncoding:*) unread_body=1 ;;
      esac
    done
    if (( headers_done == 0 )); then
      send_status "408 Request Timeout" "Request Timeout"
      sleep 0.05
      return 0
    fi

    method=""
    path=""
    protocol=""
    read -r method path protocol <<< "$request_line"
    case "$protocol" in
      HTTP/1.1) ;;
      *) close_after=1 ;;
    esac
    case "$method" in
      GET|HEAD) ;;
      "")
        send_status "400 Bad Request" "Bad Request"
        continue
        ;;
      *)
        send_status "405 Method Not Allowed" "Method Not Allowed"
        if (( unread_body )); then
          sleep 0.05
          return 0
        fi
        continue
        ;;
    esac

    decoded="$(url_decode "$path")" || {
      send_status "400 Bad Request" "Bad Request"
      continue
    }
    normalized="$(normalize_path "$decoded")" || {
      send_status "403 Forbidden" "Forbidden"
      continue
    }

    status=0
    file="$(resolve_file "$normalized")" || status=$?
    if (( status != 0 )); then
      if (( status == 1 )); then
        send_status "403 Forbidden" "Forbidden"
      else
        send_status "404 Not Found" "Not Found"
      fi
      continue
    fi

    count=$((count + 1))
    # One nc can read the next connection only after this one closes.
    connection="close"
    send_file "$file" "$method" "$connection"
    # Leave the write end open long enough for nc to copy the fifo. Closing
    # it in the same instant lets nc drop the socket before the client reads.
    if (( unread_body || count >= MAX_REQUESTS )); then
      sleep 0.05
      return 0
    fi
    file=""
  done
}

# nc -h exits non-zero. Capturing it avoids pipefail treating a match as failure.
# Prefer the system nc when the nc on PATH cannot keep listening (-k).
NC_BIN="nc"
if [[ -x /usr/bin/nc ]]; then
  usr_help="$(/usr/bin/nc -h 2>&1 || true)"
  if printf '%s\n' "$usr_help" | grep -Eq -- '\[-[0-9A-Za-z]*k'; then
    path_help="$(nc -h 2>&1 || true)"
    if ! printf '%s\n' "$path_help" | grep -Eq -- '\[-[0-9A-Za-z]*k'; then
      NC_BIN="/usr/bin/nc"
    fi
  fi
fi
NC_HELP="$("$NC_BIN" -h 2>&1 || true)"
# bsd: nc -k -l ADDR PORT. gnu: GNU netcat 0.7, which rejects -q. traditional: nc -l -p PORT -q 0.
NC_MODE="bsd"
if printf '%s\n' "$NC_HELP" | grep -q 'GNU netcat'; then
  NC_MODE="gnu"
elif printf '%s\n' "$NC_HELP" | grep -Eq -- '--local-port|-l -p port'; then
  NC_MODE="traditional"
fi

nc_serve() {
  local addr="$1"
  local fifo="$2"
  if [[ "$NC_MODE" == "bsd" ]]; then
    "$NC_BIN" -k -l "$addr" "$PORT" <"$fifo" 3<>"$fifo" 3>&- | handle_connection 3<>"$fifo" >&3 3>&-
  elif [[ "$NC_MODE" == "gnu" ]]; then
    "$NC_BIN" -l -s "$addr" -p "$PORT" -c <"$fifo" 3<>"$fifo" 3>&- | handle_connection 3<>"$fifo" >&3 3>&-
  else
    "$NC_BIN" -l -s "$addr" -p "$PORT" -q 0 <"$fifo" 3<>"$fifo" 3>&- | handle_connection 3<>"$fifo" >&3 3>&-
  fi
}

listen_on() {
  local addr="$1"
  local slot="$2"
  local fifo="$RUNTIME/fifo.${slot}.${addr//[^0-9A-Za-z]/_}"
  mkfifo "$fifo"
  while true; do
    # A failed bind must not spin. A finished connection returns success
    # and accepts again immediately.
    nc_serve "$addr" "$fifo" || sleep 0.2
  done
}

can_bind() {
  local addr="$1" probe
  if [[ "$NC_MODE" == "bsd" ]]; then
    "$NC_BIN" -k -l "$addr" "$PORT" </dev/null >/dev/null 2>&1 &
  elif [[ "$NC_MODE" == "gnu" ]]; then
    "$NC_BIN" -l -s "$addr" -p "$PORT" -c </dev/null >/dev/null 2>&1 &
  else
    "$NC_BIN" -l -s "$addr" -p "$PORT" -q 0 </dev/null >/dev/null 2>&1 &
  fi
  probe=$!
  sleep 0.2
  if kill -0 "$probe" 2>/dev/null; then
    kill "$probe" 2>/dev/null || true
    wait "$probe" 2>/dev/null || true
    return 0
  fi
  wait "$probe" 2>/dev/null || true
  return 1
}

RUNTIME=""
PIDS=()

cleanup() {
  local pid
  trap - EXIT INT TERM
  for pid in ${PIDS[@]+"${PIDS[@]}"}; do
    # set -m makes each listener its own process group, so this reaches nc.
    kill -TERM -- "-$pid" 2>/dev/null || kill -TERM "$pid" 2>/dev/null || true
  done
  if [[ -n "$RUNTIME" ]]; then
    rm -rf "$RUNTIME"
  fi
}

start_server() {
  local extra
  if command -v lsof >/dev/null 2>&1 && lsof -nP -iTCP:"$PORT" -sTCP:LISTEN >/dev/null 2>&1; then
    printf '%s\n' "Port $PORT is already in use." >&2
    exit 1
  fi

  set -m
  RUNTIME="$(mktemp -d "${TMPDIR:-/tmp}/http-server.XXXXXX")"
  chmod 700 "$RUNTIME"
  trap cleanup EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM

  if ! can_bind "$ADDR"; then
    printf '%s\n' "Cannot bind $ADDR:$PORT." >&2
    exit 1
  fi

  listen_on "$ADDR" "v4" &
  PIDS+=($!)

  extra=0
  if [[ "$ADDR" == "127.0.0.1" ]] && can_bind "::1"; then
    listen_on "::1" "v6" &
    PIDS+=($!)
    extra=1
  fi

  printf 'Serving %s\n' "$ROOT"
  printf 'http://%s:%s/\n' "$ADDR" "$PORT"
  if (( extra )); then
    printf 'http://[::1]:%s/\n' "$PORT"
  fi

  wait || true
}

start_server
