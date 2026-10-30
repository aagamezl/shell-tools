# shell-tools

A collection of lightweight shell-based tools for everyday development and system tasks. Built entirely with Bash to stay portable, minimal, and dependency-free.

## Install

`git` is required. The tools are the GitHub `master` branch, checked out at `~/.local/share/shell-tools`, in the same layout as this repository. Each command is a symlink in `~/.local/bin`. Nothing is written to `/usr/local/bin`, and shell startup files are left unchanged. `~/.local/bin` needs to be on `PATH`.

`boot.sh` is the entry point from GitHub. It clones `master` into `~/.local/share/shell-tools` when `install.sh` is not there yet. If that path already exists and does not contain `install.sh`, `boot.sh` stops instead of replacing it. It then runs `install.sh` from the checkout and passes its arguments through.

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/aagamezl/shell-tools/master/boot.sh)"
bash -c "$(curl -fsSL https://raw.githubusercontent.com/aagamezl/shell-tools/master/boot.sh)" -- --all
bash -c "$(curl -fsSL https://raw.githubusercontent.com/aagamezl/shell-tools/master/boot.sh)" -- workdays
bash -c "$(curl -fsSL https://raw.githubusercontent.com/aagamezl/shell-tools/master/boot.sh)" -- --help
bash -c "$(curl -fsSL https://raw.githubusercontent.com/aagamezl/shell-tools/master/boot.sh)" -- --list
```

The `--` after `bash -c` is required when you pass arguments. The shell uses it as the command name, and everything after it is passed to `boot.sh`, which passes it to `install.sh`.

From a checkout of this repository:

```bash
./install.sh --help
./install.sh --list
./install.sh
./install.sh --all
./install.sh workdays
./install.sh workdays http-server
./install.sh --update
./install.sh --uninstall
```

`--help` (`-h`) prints usage. `--list` (`-l`) prints every tool and whether `~/.local/bin` already points into `~/.local/share/shell-tools`. Neither command clones or updates the checkout.

With no arguments, or with `--all` (`-a`), `install.sh` links every tool. Naming one or more tools links only those commands and leaves the other links as they are. `--update` does the same after refreshing the checkout; with no names it links every tool.

Install and update make `~/.local/share/shell-tools` match GitHub `master`: the directory is cloned when it is missing, and otherwise fetched and reset to `origin/master`. Files changed inside that directory are replaced by the GitHub tree. The checkout is the whole repository even when only one command is linked. If you run `install.sh` from any other directory, it updates that checkout first and continues with `~/.local/share/shell-tools/install.sh`.

`--uninstall` removes each symlink in `~/.local/bin` that points into `~/.local/share/shell-tools`, then removes that directory. A command in `~/.local/bin` that is not one of those links is left in place.

```text
~/.local/bin/workdays -> ~/.local/share/shell-tools/workdays.sh
~/.local/bin/create-host-config -> ~/.local/share/shell-tools/create-host-config/create-host-config.sh
~/.local/bin/zsh-config -> ~/.local/share/shell-tools/zsh-config/zsh-config.sh
~/.local/bin/list-recent-collaborators -> ~/.local/share/shell-tools/list-recent-collaborators.sh
~/.local/bin/minify-code -> ~/.local/share/shell-tools/minify-code.sh
~/.local/bin/profile-backup -> ~/.local/share/shell-tools/profile-backup.sh
~/.local/bin/http-server -> ~/.local/share/shell-tools/http-server/http-server.sh
~/.local/bin/bash-commander -> ~/.local/share/shell-tools/bash-commander/bash-commander.sh
~/.local/bin/port-view -> ~/.local/share/shell-tools/port-view.sh
```

Open a new terminal after installing. The command name is the tool name, for example `workdays --help`.

## Tools

| Command | What it does |
| --- | --- |
| `workdays` | Count billable days in a month and draw them on a calendar. |
| `create-host-config` | Add one Host entry to `~/.ssh/config`. |
| `zsh-config` | Set up zsh from a CachyOS configuration bundle. |
| `list-recent-collaborators` | List recent git authors for a directory. |
| `minify-code` | Remove comments from TypeScript files. |
| `profile-backup` | Back up shell and SSH profile files. |
| `run-and-report` | Log whether the editor is active or idle. |
| `bpm` | Keep a local `package.bpm` manifest and dependency list. |
| `http-server` | Serve a directory over HTTP. |
| `bash-commander` | Bash 3.2 command-line parser library. Source it. |
| `port-view` | List ports in use and stop the process holding one. |

## create-host-config

Add one Host entry to `~/.ssh/config` without overwriting an existing alias. The script lists the aliases already in the file, asks for the new host, and shows the block it would append. After you confirm, it writes `~/.ssh/config.backup.<unix-timestamp>`, generates an ed25519 key in `~/.ssh` when that key is missing, adds the key to the agent, scans the server into `~/.ssh/known_hosts`, and appends the Host block.

```bash
./create-host-config/create-host-config.sh
./create-host-config/create-host-config.sh --dry-run
./create-host-config/create-host-config.sh --help
```

`--dry-run` (`-n`) prints the Host block that would be appended. It leaves the backup, the key, `known_hosts`, and `~/.ssh/config` untouched.

Prompts, in order. Press Enter to accept the default.

| Prompt | Default | Notes |
| --- | --- | --- |
| Host name |  | Alias used as `ssh <alias>`. Starts with a letter or digit, then letters, digits, and `. _ @ + -`. |
| HostName | `github.com`, `gitlab.com`, or `bitbucket.org` when the alias is that name or that host; otherwise the alias | Server name or IP. |
| User | `git` | |
| Port | `22` | Omitted from the block when it is 22. |
| IdentityFile | `~/.ssh/id_ed25519_<Host name>` | Only the file name is kept. The key is always created in `~/.ssh`. The name is the private key: not a `.pub` file, and not `config`, `known_hosts`, `authorized_keys`, or `environment` in any case. |
| IdentitiesOnly | `yes` | `yes` or `no`. |

The new block also sets `AddKeysToAgent yes`. On macOS it sets `IgnoreUnknown UseKeychain` and `UseKeychain yes`, and `ssh-add` tries the Apple keychain first. An existing private key and its `.pub` file are left unchanged and still added to the agent. A partial pair (only one of the two files) stops the script before anything is written. `Include` files are not scanned. A `Host` pattern that contains `*`, `?`, `!`, or `[` is listed and reported as a pattern that may also match. The script says so when it sees either case.

A real run needs a terminal, because `ssh-keygen` asks for a passphrase. After the plan it asks you to confirm. If the agent is not running, or the server scan fails, the Host block is still written and the result names the step to finish by hand. The public key is printed at the end.

## zsh-config

Set up zsh and oh-my-zsh from a CachyOS configuration bundle. The CachyOS files (`cachyos-config.zsh`, the user dotfiles, and `/etc/zsh`) are the configuration. zsh is installed with the system package manager. oh-my-zsh, zsh-syntax-highlighting, zsh-autosuggestions, zsh-completions, and zsh-history-substring-search are cloned from upstream into `~/.local/zsh-config/tools`. powerlevel10k is cloned the same way because the CachyOS config sources it. Nothing from those CachyOS packages is copied onto the target, and nothing is written outside the home directory.

```bash
./zsh-config.sh --install -a zsh-config/zsh-config-20261026-124356.tar.gz
./zsh-config.sh --install -n -a zsh-config/zsh-config-20261026-124356.tar.gz
./zsh-config.sh --export -d ./out
./zsh-config.sh --uninstall
./zsh-config.sh --help
```

`zsh-config/zsh-config-20261026-124356.tar.gz` is a full CachyOS copy you can install from. Install reads that archive. It does not read the extracted directory next to it. The installer uses its configuration files and ignores the bundled oh-my-zsh, plugins, and theme. The whole setup lives in `~/.local/zsh-config`: configuration in `config/`, cloned tools in `tools/`. `~/.zshenv` only sets `ZDOTDIR` to `~/.local/zsh-config/config`. That directory name is `ZSH_CONFIG_NAME` in `utils/zsh-tool-paths.sh`. The next zsh process follows that `ZDOTDIR`; the shell you are already in does not. `--uninstall` removes `~/.local/zsh-config` and puts `~/.zshenv` back. The startup sequence is in [Activation](zsh-config/README.md#activation). The layout, the path rewrite, and every file the installer creates are in [zsh-config/README.md](zsh-config/README.md). That archive ships in the checkout at `~/.local/share/shell-tools/zsh-config/`.

## workdays

Count Monday-Friday in a month, subtract days passed to `--off`, and add days passed to `--extra`. The result includes a calendar. The year defaults to the current year.

```bash
workdays 10
workdays 10 2026 --off 13,14 --extra 18
workdays --help
```

## list-recent-collaborators

Print the most recent distinct git authors for a directory, newest commit first. `--path` is the directory and `--limit` is how many authors to print.

```bash
list-recent-collaborators --path src/api --limit 5
```

## minify-code

Remove `/* */` and `//` comments from TypeScript files. `--file` takes one `.ts` or `.tsx` file. `--dir` walks a directory.

```bash
minify-code --file src/app.ts
minify-code --dir src
```

## profile-backup

Back up shell and SSH files from the home directory. `--create` writes an archive, `--dry` only lists the files, `--list` shows the latest archive, and `--view` prints one file from that archive.

```bash
profile-backup --dry
profile-backup --create
profile-backup --list
```

## run-and-report

Append `timestamp,status` rows to `~/.coding-time.csv` while a process named `fresh` is running. Idle time comes from the macOS HID idle counter or `xprintidle` on Linux. The loop runs until the process is stopped.

## bpm

Keep a `package.bpm` manifest in the current directory and a `bpm_modules/` tree. `init` creates the manifest. `install` records a dependency and writes a placeholder file for it. `search` prints a fixed sample list.

```bash
bpm init
bpm install bash-utils
bpm search log
```

## http-server

Serve the current directory, or the directory in `ROOT`, over HTTP. The optional argument is the port. The default port is `8080`. The server listens on `127.0.0.1` and `::1`. Set `ADDR` to bind somewhere else, for example `ADDR=0.0.0.0`. The sample page shipped with the tool is `http-server/public/index.html` under the install directory.

```bash
http-server
http-server 3000
ROOT=http-server/public http-server
ADDR=0.0.0.0 http-server
```

## port-view

List TCP listeners and bound UDP ports, then stop the process that holds one of them. The list fills the terminal. Arrow keys move the highlight, and Enter asks before sending `SIGTERM`. If the process stays up, the next screen offers `SIGKILL`. `r` refreshes, `/` filters, and `q` quits. `--all` includes established and connected sockets. `lsof` is required.

```bash
port-view
port-view --all
port-view --list --proto tcp --user "$USER"
port-view --help
```

## bash-commander

Bash 3.2 parser for options, arguments, and subcommands. Source it, define the command, then call `cli_parse`. The description of the API is `bash-commander/BASH_COMMANDER.md` under the install directory. Examples are installed beside the library.

```bash
. ~/.local/share/shell-tools/bash-commander/bash-commander.sh
```

## utils

Shared helpers sourced by the other tools: terminal boxes, prompts, color, layout, and the zsh-config path map. They live in `~/.local/share/shell-tools/utils` with the rest of the repository. The helpers are not commands on `PATH`.
