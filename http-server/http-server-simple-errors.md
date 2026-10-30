# `http-server-simple.sh` failure on macOS

The script was not changed. This note records the run in the terminal, why each message appears, and the code changes that fix it.

## Command that failed

```sh
PORT=3000 ADDR=localhost ROOT=http-server/public ./http-server/http-server-simple.sh
```

Environment at the time of the run:

| Tool | What is installed |
| --- | --- |
| `/bin/bash` | GNU bash 3.2.57, the version macOS ships. The script's `#!/bin/bash` selects this interpreter. |
| `/usr/bin/nc` | BSD `nc`. It has no `-q`. `-l` cannot be combined with `-p` or `-s`. The listen address and port are positional arguments. |

Two failures are independent. The script has no `set -e`, so the first one is printed and execution continues into the listen loop.

## 1. Line 11: `.html: syntax error: operand expected`

```
./http-server/http-server-simple.sh: line 11: .html: syntax error: operand expected (error token is ".html")
```

`CONTENT_TYPES` is declared as an associative array:

```bash
declare -A CONTENT_TYPES=(
  [".html"]="text/html"
  [".txt"]="text/plain"
  ...
)
```

`declare -A` was added in bash 4. Bash 3.2 accepts the assignment as an ordinary indexed array. In that form the text inside `[...]` is an arithmetic expression, not a string key. `.html` is not a valid arithmetic operand, so the assignment fails.

In a script file this error does not stop the shell. `CONTENT_TYPES` is left unset. `get_content_type` would later hit the same error if a request ever reached it, because `"${CONTENT_TYPES[."$file_extension"]}"` is also an arithmetic subscript on bash 3.2.

The message is reported on line 11 because that is the line where `declare` starts. The token `.html` comes from the next line.

### Fix

Replace the map with a `case` statement. That is what `http-server.sh` already does, and it runs on bash 3.2.

```bash
get_content_type() {
  case "${1##*.}" in
    html|htm) printf '%s' "text/html" ;;
    txt) printf '%s' "text/plain" ;;
    css) printf '%s' "text/css" ;;
    js|mjs) printf '%s' "application/javascript" ;;
    jpg|jpeg) printf '%s' "image/jpeg" ;;
    png) printf '%s' "image/png" ;;
    *) printf '%s' "application/octet-stream" ;;
  esac
}
```

Delete the `declare -A CONTENT_TYPES=(...)` block. `get_content_type` already receives the file path and strips the extension with `${1##*.}`, so the keys do not need a leading dot.

## 2. `nc: invalid option -- q`

```
nc: invalid option -- q
usage: nc [-46AacCDdEFhklMnOortUuvz] ...
```

The listen command is:

```bash
cat "$tmpfifo" | nc -l -p $PORT -s $HOST -q 1 > >(
  handle_request > "$tmpfifo"
  rm -f "$tmpfifo"
)
```

`-q seconds` belongs to traditional netcat (and some OpenBSD builds). After stdin reaches EOF, that `nc` waits that many seconds and then exits. macOS `nc` rejects the flag before it binds a port.

Removing only `-q` is not enough. On this `nc`, the man page states that `-l` must not be used with `-p` or `-s`:

- `-p` is the source port of an outbound connection.
- `-s` is the source address of an outbound connection.
- The listen form is `nc -l address port`.
- `-k` keeps the process listening after a connection closes. Without it, `nc` handles one connection and exits, which matches the current one-connection loop.

### Why the usage text repeats

`nc` exits immediately. The `while true` loop sleeps 0.1 seconds and starts another `nc` with the same flags. Each failed listen prints the full usage block. Nothing is bound to port 3000, so a browser refresh produces no HTTP response from this script. The `[info] Server started` line is only a log; it is printed before the loop and does not mean the socket is open.

### Fix

Detect the `nc` flavor and pass flags that binary accepts. BSD is the macOS case:

```bash
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
```

Open the FIFO read-write on an unused descriptor before `nc` starts. Otherwise `nc` blocks forever on an empty FIFO, and `handle_request` blocks waiting for `nc` to deliver the request.

```bash
while true; do
  tmpfifo=$(mktemp -u)
  mkfifo "$tmpfifo"
  # 3<> opens both directions so the FIFO has a writer before nc reads it.
  nc_listen "$tmpfifo" 3<>"$tmpfifo" 3>&- | handle_request >"$tmpfifo"
  rm -f "$tmpfifo"
done
```

`-q 1` stays only in the traditional branch, which is the `nc` the current command was written for. GNU netcat 0.7 uses `-c` and also rejects `-q`.

## 3. Problems the same command hits after those two fixes

These do not print in the terminal yet. The `nc` loop never accepts a connection, so request handling never runs.

### `PORT`, `ADDR`, and `ROOT` are ignored

The script assigns its own constants and never reads the variables from the command line:

```bash
HOST="127.0.0.1"
PORT=3000
DOC_ROOT="./www"
```

`PORT=3000` in the environment is overwritten by that assignment. `ADDR=localhost` is never read. `ROOT=http-server/public` is never read, so files would be looked up under `./www`, which is not the directory passed in.

```bash
HOST="${ADDR:-127.0.0.1}"
PORT="${PORT:-3000}"
DOC_ROOT="${ROOT:-./www}"

if [[ "$HOST" == "localhost" ]]; then
  HOST="127.0.0.1"
fi
if [[ ! -d "$DOC_ROOT" ]]; then
  log "error" "ROOT is not a directory: $DOC_ROOT"
  exit 1
fi
DOC_ROOT="$(cd "$DOC_ROOT" && pwd -P)"
```

`localhost` must be turned into `127.0.0.1` because BSD `nc -l` takes an address. A hostname fails the bind.

### The file path keeps the leading slash

```bash
[ "$path" = "/" ] && path="/index.html"
localpath="${path#/}"
local file_path="${DOC_ROOT}/${path}"
```

`localpath` is the stripped path, and it is never used. `file_path` is built from `$path`, so `/index.html` becomes `<DOC_ROOT>//index.html`. Use the stripped value:

```bash
[ "$path" = "/" ] && path="/index.html"
local relpath="${path#/}"
relpath="${relpath%%\?*}"
local file_path="${DOC_ROOT}/${relpath}"
```

### `realpath -m` is GNU-only

```bash
file_path=$(realpath -m "$file_path" 2>/dev/null || echo "$file_path")
```

macOS `realpath` has no `-m` (canonicalize even when the last component is missing). The command fails, the `||` branch keeps the raw path, and the security check below is commented out. A path such as `/../install.sh` would escape `DOC_ROOT`.

On macOS, require the file to exist and then compare the canonical path with the document root:

```bash
if [[ ! -f "$file_path" || ! -r "$file_path" ]]; then
  log "warn" "File not found or not readable: $file_path"
  send_response 404 "Not Found" "text/plain" "404 Not Found: $path"
  return
fi

local resolved
resolved="$(cd "$(dirname "$file_path")" && pwd -P)/$(basename "$file_path")"
case "$resolved" in
  "$DOC_ROOT"/*) file_path="$resolved" ;;
  *)
    log "warn" "Security violation: $path"
    send_response 403 "Forbidden" "text/plain" "403 Forbidden: Access denied"
    return
    ;;
esac
```

`stat` in `send_file` already falls back from `stat -c` (GNU) to `stat -f` (macOS). That part can stay.

### Response headers are still unread

`handle_request` reads only the request line. The browser then sends `Host`, `User-Agent`, and a blank line on the same connection. With one `nc` process per connection that is discarded when `nc` exits. If the listen call is later changed to `nc -k` so one process serves many connections, those leftover header lines will be parsed as the next request. Drain them before sending the file:

```bash
while IFS= read -r header; do
  header="${header%$'\r'}"
  [[ -z "$header" ]] && break
done
```

## Order to apply the changes

1. Remove `declare -A` and resolve the content type with `case`.
2. Read `PORT`, `ADDR`, and `ROOT`, and reject a missing document root before listening.
3. Replace `nc -l -p "$PORT" -s "$HOST" -q 1` with the BSD form `nc -l "$HOST" "$PORT"`, keeping `-q` only for traditional `nc`.
4. Build `file_path` from the path with the leading slash removed, and confine the resolved path to `DOC_ROOT`.

After that, this command serves `http-server/public` at `http://127.0.0.1:3000`:

```sh
PORT=3000 ADDR=localhost ROOT=http-server/public ./http-server/http-server-simple.sh
```
