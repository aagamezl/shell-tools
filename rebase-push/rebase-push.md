# rebase-push

Technical documentation for the `rebase-push` command.

The script lives at `~/.local/bin/rebase-push`. That directory is on `PATH`, so the command can be run from any repository as `rebase-push`.

It updates a local base branch from `origin`, rebases another local branch onto that base, and, when the rebase applies cleanly, publishes the rewritten branch with the same push used by the `gpsupf` alias.

## What the command replaces

These are the shell shortcuts the script reproduces:

| Alias | Definition used by this workflow |
| --- | --- |
| `gco` | `git checkout` |
| `ggl` | `git pull origin <current-branch>` when called with no arguments |
| `gpsupf` | `git push --set-upstream origin <current-branch> --force-with-lease --force-if-includes` |

Run by hand, the workflow is:

```bash
gco <base> && ggl
gco <branch>
git rebase <base>
gpsupf
```

The script does not invoke those aliases. It runs the equivalent Git commands in Bash, so it works in a non-interactive shell where Zsh aliases and `git_current_branch` are not defined. After the rebase, the current branch is `<branch>`, which is what `gpsupf` would push.

`ggl` pulls the branch that is checked out. The script checks out `<base>` first, then runs `git pull origin <base>`. That is the same pull `ggl` would perform at that moment.

## Command line

```bash
rebase-push --branch <name> [--base <name>]
rebase-push --help
```

| Flag | Required | Default | Meaning |
| --- | --- | --- | --- |
| `--branch <name>` | yes | none | Local branch to rebase and push |
| `--base <name>` | no | `main` | Local branch to update, then rebase onto |
| `-h`, `--help` | no | | Print usage and exit `0` |

Both flags accept a separate argument or an equals form:

```bash
rebase-push --branch feature
rebase-push --branch=feature --base=develop
rebase-push --base develop --branch feature
```

Flag order does not matter. Repeating a flag keeps the last value.

A value must not be empty and must not start with `-`. `--branch --base develop` is rejected because `--base` is not a branch name.

`--help` is recognized anywhere in a valid argument list. Parsing still checks every argument. An unknown token or a missing value exits immediately, even if `--help` appears later. A valid command that also includes `--help` prints usage and does not touch the repository.

Calling the command with no arguments prints usage and exits `1`. That path does not print a Result box. Every other usage error prints usage and a red Result box.

Unknown tokens, including the old positional form `rebase-push feature`, are rejected.

## Execution flow

```text
parse arguments
        │
        ├─ no arguments ──────────────► usage, exit 1
        ├─ invalid arguments ─────────► usage + Result, exit 1
        └─ --help ────────────────────► usage, exit 0
        │
choose box width
        │
print banner and parameters
        │
preflight
        ├─ fail ──────────────────────► Result, exit 1 (repository unchanged)
        │
checkout <base>
        ├─ fail ──────────────────────► Result, exit 2
        │
pull origin <base>
        ├─ fail ──────────────────────► Result, exit 2 (HEAD is <base>)
        │
checkout <branch>
        ├─ fail ──────────────────────► Result, exit 3 (HEAD is the updated <base>)
        │
rebase <branch> onto <base>
        ├─ conflict ──────────────────► Result, exit 4 (rebase left in progress, no push)
        ├─ other rebase failure ──────► Result, exit 5 (no push)
        │
push <branch> to origin (gpsupf)
        ├─ fail ──────────────────────► Result, exit 6 (local rebase kept)
        └─ success ───────────────────► Result, exit 0
```

The script uses `set -uo pipefail` and does not use `set -e`. Each Git step is checked on its own, and the first failure stops the rest of the workflow.

## 1. Parameters

Before any Git command, the script records:

| Field | Source |
| --- | --- |
| Branch | `--branch` |
| Base | `--base`, or `main` |
| Repository | Basename of `git rev-parse --show-toplevel` |
| Starting at | `git rev-parse --abbrev-ref HEAD` |

Outside a repository those last two fields are `(unknown)` and `(not a repository)`. Preflight then fails. Nothing has been checked out yet.

A detached `HEAD` is shown as `HEAD`. Preflight can still pass from a detached `HEAD` when the other checks succeed, because checkout of the base branch is valid in that state.

## 2. Preflight

Preflight runs in this order and stops at the first failure. A preflight failure does not change the current branch.

1. The current directory is inside a Git working tree (`git rev-parse --is-inside-work-tree`).
2. No rebase is already in progress. The script treats either `.git/rebase-merge` or `.git/rebase-apply` as an active rebase. Finish that rebase with `git rebase --continue` or leave it with `git rebase --abort` before running the command again.
3. The working tree has no staged or unstaged changes to tracked files. The check is `git status --porcelain --untracked-files=no`. Untracked files do not block the run. A later checkout can still fail if an untracked file would be overwritten.
4. `--branch` and `--base` are different names.
5. `--base` exists as a local branch, `refs/heads/<base>`.
6. `--branch` exists as a local branch, `refs/heads/<branch>`.

Remote-only branches are not accepted. `origin/feature` without a local `feature` fails preflight even when `git checkout feature` could create it from the remote. Create the local branch first.

The remote is always `origin`. There is no flag for another remote name.

## 3. Update the base

```bash
git checkout <base>
git pull origin <base>
```

Checkout and pull are separate steps. If checkout fails, the current branch is unchanged and the command exits `2`.

If checkout succeeds and pull fails, `HEAD` is `<base>` and the command exits `2`. A pull that stops with conflicts is reported as “Could not pull origin/<base>”. The script does not list those conflicted files and does not abort the merge. The pull uses whatever `pull.rebase` and related settings are already configured. The script does not add `--rebase` or `--no-rebase`.

`GIT_TERMINAL_PROMPT=0` is exported before the first Git command. A missing credential fails the pull or the later push instead of waiting for an interactive prompt.

## 4. Rebase

```bash
git checkout <branch>
git rebase <base>
```

If checkout of `<branch>` fails, `<base>` stays checked out and is already updated. The command exits `3`.

`git rebase <base>` replays the commits that are on `<branch>` and not on `<base>`.

- Exit `0` from Git means the rebase finished. “Current branch is up to date” is a success. The script continues to the push.
- A non-zero exit while `rebase-merge` or `rebase-apply` exists is a conflict, or another stop that left the rebase in progress. The command exits `4` and does not push.
- A non-zero exit with no rebase directory is reported as “Rebase failed before it could apply commits” and exits `5`. The branch is checked out. Nothing is pushed.

On a conflict the Result box lists files from `git diff --name-only --diff-filter=U` and prints:

```bash
git rebase --continue
git rebase --abort
```

The script does not edit files, stage resolutions, or run either of those commands. The rebase stays in progress so it can be finished by hand. Running `rebase-push` again while that rebase is open fails preflight.

## 5. Push

The push runs only after a rebase that exited `0`. It is the `gpsupf` command, with the branch name passed explicitly:

```bash
git push --set-upstream origin <branch> --force-with-lease --force-if-includes
```

A rebase rewrites commit hashes, so a normal fast-forward push is rejected once `<branch>` has already been published. This push updates the remote branch to the rewritten history and sets the local upstream to `origin/<branch>`.

The two force options are the safety checks from `gpsupf`:

- `--force-with-lease` refuses the update when the remote branch is not at the commit recorded in the local remote-tracking ref. Someone else’s push is not overwritten just because the local `origin/<branch>` ref is stale in a way the lease can detect during the push negotiation.
- `--force-if-includes` refuses the update unless that remote-tracking tip is already present in the local branch reflog. A fetched remote update that was never merged or rebased into the local branch cannot be force-pushed away.

The script does not fetch `<branch>` before this push. It only pulled `<base>`. The lease is evaluated against the `origin/<branch>` ref already present in the local repository, and against what the server reports at push time.

If the push fails, the local rebase is kept. The Result box says the rebase succeeded and the push failed, and the command exits `6`. The remote branch is unchanged. Typical causes are a rejected lease, missing permission, a missing `origin`, or authentication failure.

If the push succeeds, the command exits `0`. Local `<branch>` and `origin/<branch>` point at the same commit, and `<branch>` tracks `origin/<branch>`.

## Exit codes and repository state

| Exit | Meaning | Where `HEAD` is left |
| --- | --- | --- |
| `0` | Rebase and push succeeded | `<branch>`, published to `origin` |
| `1` | Usage error or preflight failure | Unchanged |
| `2` | Checkout or pull of `<base>` failed | Unchanged if checkout failed; `<base>` if pull failed |
| `3` | Checkout of `<branch>` failed after `<base>` was updated | `<base>` |
| `4` | Rebase stopped with conflicts | `<branch>`, rebase in progress, not pushed |
| `5` | Rebase failed without leaving a rebase in progress | `<branch>`, not pushed |
| `6` | Rebase succeeded and the push failed | `<branch>`, rewritten locally, remote unchanged |

Section numbers in the output follow the same path. Conflict stops at `5 · Result` because the push block is skipped. A completed rebase uses `5 · Push` and then `6 · Result`. Preflight and argument errors use an unnumbered Result box.

## Interface

Every run starts with a banner, then one boxed section per phase. Git commands are printed with a `›` prefix. Their combined stdout and stderr are indented inside the same box. A blank row separates commands inside a section.

| Color | Used for |
| --- | --- |
| Cyan | Banner, update, rebase, and push sections; the `›` command lines |
| Blue | Parameters and preflight |
| Yellow | Usage box; the “Conflicted files” heading |
| Green | Passed checks and the success Result |
| Red | Failed checks and error Results |
| Dim | Git output and secondary notes |
| Bold | Banner title, usage command, and the main failure line |

Colors are enabled only when standard output is a terminal, `NO_COLOR` is unset, and `TERM` is not `dumb`. Otherwise the same boxes are printed with no ANSI codes. Set `NO_COLOR=1` to force plain text.

The box width starts at 68 columns. On a terminal it grows so these lines fit on one row:

- `3 · Update <base>`
- `4 · Rebase onto <base>`
- `5 · Push <branch>`
- `Branch       <branch>`
- `Base         <base>`

The width is capped at one less than the terminal width, measured with `stty size` on the real standard output. If that measurement fails, the cap is 80. When standard output is not a terminal, the width stays 68 even for long branch names.

A section title that still does not fit is cut at the end and closed with `…`. The right border stays on the same column as the other rows. Body text wraps on spaces. Wrapped continuations are indented two spaces. A line with no space is split at the column limit. Carriage returns in Git output, such as rebase progress, are turned into newlines so they cannot overwrite the left border.

## Requirements

- Bash. The script is written for Bash 3.2, which is the Bash shipped with macOS.
- A local clone with a remote named `origin`.
- Local branches for both `--branch` and `--base`.
- A clean index and worktree for tracked files.
- Permission to pull `<base>` and to force-push `<branch>` with lease.
- No rebase already in progress.

The script does not stash, does not create missing branches, does not fetch `<branch>`, does not resolve conflicts, and does not run `git rebase --abort` or `git rebase --continue`.

## Examples

Update `main`, rebase `feature` onto it, and push `feature`:

```bash
rebase-push --branch feature
```

Use `develop` as the base:

```bash
rebase-push --branch feature --base develop
```

After a conflict, the command has already stopped. From the same repository:

```bash
git status
# edit the conflicted files
git add <files>
git rebase --continue
```

Or return to the pre-rebase branch tip:

```bash
git rebase --abort
```

A conflict does not push. After the rebase is continued by hand, publish with `gpsupf` or run `rebase-push` again. The second run pulls the base again and rebases once more; if the branch is already on the updated base, the rebase is a no-op and the push still runs.

## Failure catalog

| Result text | What happened |
| --- | --- |
| `--branch is required.` | `--base` was passed without `--branch`, or the branch value was never set |
| `--branch needs a branch name.` | The flag was present without a usable value |
| `--base needs a branch name.` | The flag was present without a usable value |
| `Unknown argument '…'.` | A positional argument or an unrecognized flag |
| `Run this from a git working tree.` | The current directory is not inside a repository |
| `Finish or abort the current rebase first.` | `rebase-merge` or `rebase-apply` already exists |
| `Commit or stash changes before rebasing.` | A tracked file is staged or modified |
| `Choose a branch to rebase onto <base>.` | `--branch` and `--base` are the same name |
| `No local branch named '…'.` | That name is not in `refs/heads` |
| `Could not check out <base>.` | Git refused to switch to the base |
| `Could not pull origin/<base>.` | The pull failed. If it was a merge conflict, `HEAD` is `<base>` and the merge may still be open |
| `Could not check out <branch>.` | The base checkout and pull succeeded; `<branch>` did not |
| `Rebase conflict` | The rebase is in progress. Resolve it or abort it. Nothing was pushed |
| `Rebase failed before it could apply commits.` | `git rebase` failed without leaving a rebase directory |
| `Push to origin failed.` | The local rebase is complete. Read the Git error in the Push box |

The Git error for a failed checkout, pull, rebase, or push is printed in that step’s box, above the Result summary.
