#!/bin/bash

# Minify TypeScript Scripts
# Usage: ./minify-code.sh --file <file.ts> | ./minify-code.sh --dir <directory>
# Removes both block comments (/* */) and line comments (//) from TypeScript files
# Author: Álvaro José Agamez Licha (alvaroagamez@outlook.com)
# Date: 2025-11-18

set -e

minify_file() {
  local filename="$1"

  awk '
  BEGIN {
    in_block = 0
    in_string = 0
    string_char = ""
  }

  {
      line = $0
      result = ""
      i = 1

      while (i <= length(line)) {
          char = substr(line, i, 1)
          next_char = substr(line, i + 1, 1)

          if (in_block) {
              # Look for end of block comment
              if (char == "*" && next_char == "/") {
                  in_block = 0
                  i += 2
              } else {
                  i++
              }
          } else if (in_string) {
              # Inside string literal
              result = result char
              if (char == string_char && substr(line, i - 1, 1) != "\\") {
                  in_string = 0
              }
              i++
          } else {
              # Check for string start
              if (char == "\"" || char == "\"" || char == "`") {
                  in_string = 1
                  string_char = char
                  result = result char
                  i++
              # Check for block comment start
              } else if (char == "/" && next_char == "*") {
                  in_block = 1
                  i += 2
              # Check for line comment
              } else if (char == "/" && next_char == "/") {
                  break  # Skip rest of line
              } else {
                  result = result char
                  i++
              }
          }
      }

      if (length(result) > 0) {
          print result
      }
  }' "$filename" |
  # Now minimize the code
  sed -E '
  # Remove all newlines and replace with spaces
  N; s/\n/ /g

  # Remove leading/trailing whitespace
  s/^[[:space:]]*//
  s/[[:space:]]*$//

  # Replace multiple spaces with single space
  s/[[:space:]]+/ /g

  # Remove spaces around semicolons, braces, brackets, parentheses
  s/ *; */;/g
  s/ *{ */{/g
  s/ *} */}/g
  s/ *\[/[/g
  s/ *\]/]/g
  s/ *\(/(/g
  s/ *\)/)/g

  # Remove spaces around operators (but preserve export * from)
  s/ *= */=/g
  s/ *\+ */\+/g
  s/ *- */-/g
  s/ *\/ *\//\//g
  s/ *> */>/g
  s/ *< */</g

  # Final cleanup of any remaining multiple spaces
  s/  */ /g
  s/^ //
  s/ $//
  ' | tr -d '\n'
}

minify_dir() {
  local dir="$1"

  for file in "$dir"/**/*.ts; do
    minify_file "$file"
    echo ""  # empty line for better readability
  done
}

usage() {
  echo "Usage: $0 --file <file.ts|tsx> | --dir <directory>"
  exit 1
}

# INPUT_FILE="$1"

# Parse arguments
MODE=""; TARGET=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --file)
      MODE="file"; TARGET="${2:-}"; shift 2 ;;
    --dir)
      MODE="dir"; TARGET="${2:-}"; shift 2 ;;
    -h|--help)
      usage ;;
    *)
      echo "Unknown argument: $1" >&2; usage ;;
  esac
done

# Check if parameters are provided
if [[ -z "$MODE" || -z "$TARGET" ]]; then
  usage
fi

if [[ "$MODE" == "file" ]]; then
  # Check if file is a TypeScript file
  if [[ ! "$TARGET" =~ \.(ts|js)$ ]]; then
    echo "Warning: File doesn't appear to be a TypeScript file (.ts/.tsx expected)"
  fi

  minify_file "$TARGET"
elif [[ "$MODE" == "dir" ]]; then
  minify_dir "$TARGET"
else
  usage
fi