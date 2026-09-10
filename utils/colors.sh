#!/usr/bin/env bash
#
# Sourced, not executed. Every colour is defined whether or not a given caller
# uses it, so shellcheck's unused-variable warning does not apply here.
# shellcheck disable=SC2034

RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[0;33m'
BLUE=$'\033[0;34m'
MAGENTA=$'\033[0;35m'
CYAN=$'\033[0;36m'
ORANGE=$'\033[38;5;208m'
WHITE=$'\033[0;37m'
BOLD=$'\033[1m'
DIM=$'\033[2m'
NC=$'\033[0m' # No Color

# Escape codes corrupt anything that is not a terminal: they break column
# alignment when piped through less or a pager that does not decode them, and
# they end up as literal bytes in redirected output. NO_COLOR is the de facto
# opt-out convention (https://no-color.org).
if [[ -n "${NO_COLOR:-}" ]] || [[ ! -t 1 ]]; then
  RED=''
  GREEN=''
  YELLOW=''
  BLUE=''
  MAGENTA=''
  CYAN=''
  ORANGE=''
  WHITE=''
  BOLD=''
  DIM=''
  NC=''
fi

function red() {
  echo -e "${RED}$1${NC}"
}

function green() {
  echo -e "${GREEN}$1${NC}"
}

function yellow() {
  echo -e "${YELLOW}$1${NC}"
}

function blue() {
  echo -e "${BLUE}$1${NC}"
}

function magenta() {
  echo -e "${MAGENTA}$1${NC}"
}

function cyan() {
  echo -e "${CYAN}$1${NC}"
}

function white() {
  echo -e "${WHITE}$1${NC}"
}

function bold() {
  echo -e "${BOLD}$1${NC}"
}

function dim() {
  echo -e "${DIM}$1${NC}"
}

function no_color() {
  echo -e "$1${NC}"
}