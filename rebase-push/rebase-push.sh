#!/usr/bin/env bash
# Update a base branch, rebase onto it, then push with gpsupf.
# gpsupf = git push --set-upstream origin <branch> --force-with-lease --force-if-includes

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOX_UI="${SCRIPT_DIR}/../utils/box-ui.sh"
if [[ ! -f "$BOX_UI" ]]; then
  printf 'Missing %s\n' "$BOX_UI" >&2
  exit 1
fi
# Resolved from the repository root, which is where shellcheck is run.
# shellcheck source=utils/box-ui.sh
source "$BOX_UI"

banner() {
  box_banner "rebase-push" "Update a base branch, rebase onto it, then push."
}

usage() {
  section_open "Usage" "$C_YELLOW"
  box_row "$C_BOLD" "rebase-push --branch <name> [--base <name>]" "$BORDER"
  box_row "$C_BOLD" "rebase-push --file <path> [--base <name>]" "$BORDER"
  box_row "$C_DIM" "--base defaults to main" "$BORDER"
  box_blank "$BORDER"
  box_row "" "1. git checkout <base>" "$BORDER"
  box_row "" "2. git pull origin <base>" "$BORDER"
  box_row "" "3. git checkout <branch>" "$BORDER"
  box_row "" "4. git rebase <base>" "$BORDER"
  box_row "" "5. gpsupf (push --force-with-lease --force-if-includes)" "$BORDER"
  box_blank "$BORDER"
  box_row "$C_DIM" "Push runs only when the rebase has no conflicts." "$BORDER"
  box_row "$C_DIM" "A conflict leaves the rebase in progress." "$BORDER"
  box_blank "$BORDER"
  box_row "$C_DIM" "--file reads a checklist. Pending lines look like:" "$BORDER"
  box_row "" "  [] feature/my-branch" "$BORDER"
  box_row "$C_DIM" "A finished rebase and push rewrites that line to:" "$BORDER"
  box_row "" "  [X] feature/my-branch" "$BORDER"
  box_row "$C_DIM" "Lines already marked [X] are skipped." "$BORDER"
  box_row "$C_DIM" "The list stops at the first failure." "$BORDER"
  section_close
}

require_git_repo() {
  git rev-parse --is-inside-work-tree >/dev/null 2>&1
}

rebase_in_progress() {
  local path
  path="$(git rev-parse --git-path rebase-merge 2>/dev/null || true)"
  if [[ -n "$path" && -d "$path" ]]; then
    return 0
  fi
  path="$(git rev-parse --git-path rebase-apply 2>/dev/null || true)"
  if [[ -n "$path" && -d "$path" ]]; then
    return 0
  fi
  return 1
}

working_tree_dirty() {
  local status
  status="$(git status --porcelain --untracked-files=no)"
  [[ -n "$status" ]]
}

mark_checklist_line() {
  local file="$1"
  local line_no="$2"
  local tmp

  tmp="$(mktemp "${TMPDIR:-/tmp}/rebase-push.XXXXXX")"
  awk -v n="$line_no" '
    NR == n { sub(/\[\]/, "[X]") }
    { print }
  ' "$file" > "$tmp"
  mv "$tmp" "$file"
}

run_file_batch() {
  local line
  local line_no=0
  local branch
  local code
  local i
  local total
  local done_count=0
  local skipped=0
  local -a pending_lines=()
  local -a pending_names=()

  if [[ ! -f "$FILE" ]]; then
    banner
    usage
    finish 1 "$C_RED" "Result" "✗ File not found: $FILE"
  fi
  if [[ ! -r "$FILE" || ! -w "$FILE" ]]; then
    banner
    usage
    finish 1 "$C_RED" "Result" "✗ File must be readable and writable: $FILE"
  fi

  while IFS= read -r line || [[ -n "$line" ]]; do
    line_no=$((line_no + 1))
    line="${line%$'\r'}"
    if [[ "$line" =~ ^[[:space:]]*$ || "$line" =~ ^[[:space:]]*# ]]; then
      continue
    fi
    if [[ "$line" =~ ^[[:space:]]*\[[Xx]\] ]]; then
      skipped=$((skipped + 1))
      continue
    fi
    if [[ "$line" =~ ^[[:space:]]*\[\][[:space:]]+([^[:space:]]+)[[:space:]]*$ ]]; then
      pending_lines+=("$line_no")
      pending_names+=("${BASH_REMATCH[1]}")
      continue
    fi
    banner
    usage
    finish 1 "$C_RED" "Result" "✗ Unrecognized checklist line ${line_no}: ${line}"
  done < "$FILE"

  total=${#pending_names[@]}
  if (( total == 0 )); then
    banner
    section_open "Checklist" "$C_GREEN"
    box_row "$C_GREEN" "✓ No pending branches." "$BORDER"
    box_row "" "File         $FILE" "$BORDER"
    if (( skipped > 0 )); then
      box_row "$C_DIM" "Already marked  $skipped" "$BORDER"
    fi
    section_close
    exit 0
  fi

  for (( i = 0; i < total; i++ )); do
    branch="${pending_names[$i]}"
    line_no="${pending_lines[$i]}"
    printf '\n%s── %s/%s  %s ──%s\n\n' \
      "$C_BOLD" "$((i + 1))" "$total" "$branch" "$C_RESET"
    "$0" --branch "$branch" --base "$BASE"
    code=$?
    if (( code == 0 )); then
      mark_checklist_line "$FILE" "$line_no"
      done_count=$((done_count + 1))
      continue
    fi
    section_open "Checklist" "$C_RED"
    box_row "$C_RED$C_BOLD" "✗ Stopped on $branch." "$BORDER"
    box_row "" "Exit         $code" "$BORDER"
    box_row "" "Marked       $done_count" "$BORDER"
    box_row "" "File         $FILE" "$BORDER"
    box_row "$C_DIM" "Pending boxes were left empty." "$BORDER"
    section_close
    exit "$code"
  done

  section_open "Checklist" "$C_GREEN"
  box_row "$C_GREEN$C_BOLD" "✓ Rebased and pushed $done_count branch(es)." "$BORDER"
  box_row "" "File         $FILE" "$BORDER"
  if (( skipped > 0 )); then
    box_row "$C_DIM" "Already marked  $skipped" "$BORDER"
  fi
  section_close
  exit 0
}

if [[ $# -eq 0 ]]; then
  banner
  usage
  exit 1
fi

BRANCH=""
BASE="main"
FILE=""
SHOW_HELP=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      SHOW_HELP=1
      shift
      ;;
    --file)
      if [[ $# -lt 2 || "$2" == -* ]]; then
        banner
        usage
        finish 1 "$C_RED" "Result" "✗ --file needs a file path."
      fi
      FILE="$2"
      shift 2
      ;;
    --file=*)
      FILE="${1#--file=}"
      if [[ -z "$FILE" || "$FILE" == -* ]]; then
        banner
        usage
        finish 1 "$C_RED" "Result" "✗ --file needs a file path."
      fi
      shift
      ;;
    --branch)
      if [[ $# -lt 2 || "$2" == -* ]]; then
        banner
        usage
        finish 1 "$C_RED" "Result" "✗ --branch needs a branch name."
      fi
      BRANCH="$2"
      shift 2
      ;;
    --branch=*)
      BRANCH="${1#--branch=}"
      if [[ -z "$BRANCH" || "$BRANCH" == -* ]]; then
        banner
        usage
        finish 1 "$C_RED" "Result" "✗ --branch needs a branch name."
      fi
      shift
      ;;
    --base)
      if [[ $# -lt 2 || "$2" == -* ]]; then
        banner
        usage
        finish 1 "$C_RED" "Result" "✗ --base needs a branch name."
      fi
      BASE="$2"
      shift 2
      ;;
    --base=*)
      BASE="${1#--base=}"
      if [[ -z "$BASE" || "$BASE" == -* ]]; then
        banner
        usage
        finish 1 "$C_RED" "Result" "✗ --base needs a branch name."
      fi
      shift
      ;;
    *)
      banner
      usage
      finish 1 "$C_RED" "Result" "✗ Unknown argument '$1'."
      ;;
  esac
done

if (( SHOW_HELP )); then
  banner
  usage
  exit 0
fi

if [[ -n "$FILE" && -n "$BRANCH" ]]; then
  banner
  usage
  finish 1 "$C_RED" "Result" "✗ Use either --branch or --file."
fi

if [[ -n "$FILE" ]]; then
  run_file_batch
fi

if [[ -z "$BRANCH" ]]; then
  banner
  usage
  finish 1 "$C_RED" "Result" "✗ --branch or --file is required."
fi

choose_box_width_for 68 \
  "3 · Update ${BASE}" \
  "4 · Rebase onto ${BASE}" \
  "5 · Push ${BRANCH}" \
  "Branch       ${BRANCH}" \
  "Base         ${BASE}"
banner

REPO_NAME="(unknown)"
START_BRANCH="(not a repository)"
if require_git_repo; then
  REPO_NAME="$(basename "$(git rev-parse --show-toplevel)")"
  START_BRANCH="$(git rev-parse --abbrev-ref HEAD)"
fi

section_open "1 · Parameters" "$C_BLUE"
box_row "" "Branch       $BRANCH" "$BORDER"
box_row "" "Base         $BASE" "$BORDER"
box_row "" "Repository   $REPO_NAME" "$BORDER"
box_row "" "Starting at  $START_BRANCH" "$BORDER"
section_close

section_open "2 · Preflight" "$C_BLUE"

if ! require_git_repo; then
  box_row "$C_RED" "✗ Not inside a git repository." "$BORDER"
  finish 1 "$C_RED" "Result" "✗ Run this from a git working tree."
fi
box_row "$C_GREEN" "✓ Git repository" "$BORDER"

if rebase_in_progress; then
  box_row "$C_RED" "✗ A rebase is already in progress." "$BORDER"
  finish 1 "$C_RED" "Result" \
    "✗ Finish or abort the current rebase first." \
    "  git rebase --continue" \
    "  git rebase --abort"
fi
box_row "$C_GREEN" "✓ No rebase in progress" "$BORDER"

if working_tree_dirty; then
  box_row "$C_RED" "✗ Working tree has uncommitted changes." "$BORDER"
  finish 1 "$C_RED" "Result" "✗ Commit or stash changes before rebasing."
fi
box_row "$C_GREEN" "✓ Working tree clean" "$BORDER"

if [[ "$BRANCH" == "$BASE" ]]; then
  box_row "$C_RED" "✗ Target branch is the base branch." "$BORDER"
  finish 1 "$C_RED" "Result" "✗ Choose a branch to rebase onto $BASE."
fi
box_row "$C_GREEN" "✓ Target is not $BASE" "$BORDER"

if ! git show-ref --verify --quiet "refs/heads/$BASE"; then
  box_row "$C_RED" "✗ Local base branch not found." "$BORDER"
  finish 1 "$C_RED" "Result" "✗ No local branch named '$BASE'."
fi
box_row "$C_GREEN" "✓ Local base branch exists" "$BORDER"

if ! git show-ref --verify --quiet "refs/heads/$BRANCH"; then
  box_row "$C_RED" "✗ Local branch not found." "$BORDER"
  finish 1 "$C_RED" "Result" "✗ No local branch named '$BRANCH'."
fi
box_row "$C_GREEN" "✓ Local branch exists" "$BORDER"
section_close

export GIT_TERMINAL_PROMPT=0

section_open "3 · Update $BASE" "$C_CYAN"
if ! box_run "git checkout $BASE" git checkout "$BASE"; then
  finish 2 "$C_RED" "Result" "✗ Could not check out $BASE."
fi
box_blank "$BORDER"
if ! box_run "git pull origin $BASE" git pull origin "$BASE"; then
  finish 2 "$C_RED" "Result" "✗ Could not pull origin/$BASE."
fi
section_close

section_open "4 · Rebase onto $BASE" "$C_CYAN"
if ! box_run "git checkout $BRANCH" git checkout "$BRANCH"; then
  finish 3 "$C_RED" "Result" \
    "✗ Could not check out $BRANCH." \
    "  $BASE is checked out and updated."
fi
box_blank "$BORDER"
if ! box_run "git rebase $BASE" git rebase "$BASE"; then
  if rebase_in_progress; then
    section_close
    section_open "5 · Result" "$C_RED"
    box_row "$C_RED$C_BOLD" "✗ Rebase conflict" "$BORDER"
    box_blank "$BORDER"
    box_row "$C_RED" "The rebase is still in progress." "$BORDER"
    box_blank "$BORDER"
    conflict_found=0
    while IFS= read -r file; do
      if [[ -z "$file" ]]; then
        continue
      fi
      if (( conflict_found == 0 )); then
        box_row "$C_YELLOW" "Conflicted files" "$BORDER"
        conflict_found=1
      fi
      box_row "$C_RED" "  $file" "$BORDER"
    done < <(git diff --name-only --diff-filter=U)
    box_blank "$BORDER"
    box_row "$C_DIM" "Resolve the files, then continue or abort:" "$BORDER"
    box_row "" "  git rebase --continue" "$BORDER"
    box_row "" "  git rebase --abort" "$BORDER"
    section_close
    exit 4
  fi
  finish 5 "$C_RED" "Result" "✗ Rebase failed before it could apply commits."
fi
section_close

section_open "5 · Push $BRANCH" "$C_CYAN"
if ! box_run "git push --set-upstream origin $BRANCH --force-with-lease --force-if-includes" \
  git push --set-upstream origin "$BRANCH" --force-with-lease --force-if-includes; then
  section_close
  section_open "6 · Result" "$C_RED"
  box_row "$C_GREEN" "✓ Rebased $BRANCH onto $BASE." "$BORDER"
  box_row "$C_RED$C_BOLD" "✗ Push to origin failed." "$BORDER"
  section_close
  exit 6
fi
section_close

finish 0 "$C_GREEN" "6 · Result" \
  "✓ Rebased $BRANCH onto $BASE." \
  "✓ Pushed $BRANCH to origin."
