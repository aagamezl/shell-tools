# shell-tools

A collection of lightweight shell-based tools for everyday development and system tasks. Built entirely with Bash to stay portable, minimal, and dependency-free.

## Install

`install.sh` copies the tools you name into `~/.local/shell-tools` and puts each command on `PATH`. `utils/` is installed with every selection. The tools source those files from next to their own scripts, so the installer keeps the repository layout under the install directory. The catalog of tool names is `tools_list` in `install.sh`.

```bash
sh -c "$(curl -fsSL https://raw.githubusercontent.com/aagamezl/shell-tools/master/install.sh)" -- --help
sh -c "$(curl -fsSL https://raw.githubusercontent.com/aagamezl/shell-tools/master/install.sh)" -- --all
sh -c "$(curl -fsSL https://raw.githubusercontent.com/aagamezl/shell-tools/master/install.sh)" -- workdays
sh -c "$(curl -fsSL https://raw.githubusercontent.com/aagamezl/shell-tools/master/install.sh)" -- --prefix ~/.local/shell-tools create-host-config
```

The `--` after `sh -c` is required. The shell uses it as the command name, and everything after it is passed to `install.sh`.

From a checkout of this repository:

```bash
./install.sh --help
./install.sh --list
./install.sh --all
./install.sh workdays
./install.sh --prefix ~/.local/shell-tools bpm http-server
```

`--prefix` (`-p`) changes the install directory. `SHELL_TOOLS_PREFIX` does the same when the flag is omitted. `--all` (`-a`) installs every tool in the catalog. Naming one or more tools installs only those, plus `utils/`. `--list` (`-l`) prints the catalog. `--ref` chooses the git branch downloaded by the GitHub command. A checkout installs the files next to `install.sh` and does not download them.

Installed tree:

```text
~/.local/shell-tools/
  bin/                 workdays, create-host-config, and the other command names
  utils/               shared libraries sourced by the tools
  workdays.sh
  zsh-config.sh
  create-host-config/create-host-config.sh
  ...
```

`bin/<name>` runs the real script, except `bash-commander`, which is a symlink so it can be sourced. When `/usr/local/bin` is writable, each command is linked there too. The installer also prepends the `bin` directory to `PATH` in `~/.zshenv`, `~/.zprofile`, `~/.zshrc`, `~/.bashrc`, and `~/.profile` (or `~/.bash_profile` when that file already exists):

```sh
# >>> shell-tools >>>
export PATH="$HOME/.local/shell-tools/bin:$PATH"
# <<< shell-tools <<<
```

Open a new terminal after installing. The command name is the catalog name, for example `workdays --help`. The `shell-tools` block uses its own markers, so it can sit in `~/.zshenv` next to the `zsh-config` block. If `zsh-config --uninstall` restores `~/.zshenv` from a backup taken before this block existed, run the installer again to put the block back.

`--system-bin` chooses a different directory for those links. `SHELL_TOOLS_SYSTEM_BIN` does the same when the flag is omitted.

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

`zsh-config/zsh-config-20261026-124356.tar.gz` is a full CachyOS copy you can install from. Install reads that archive. It does not read the extracted directory next to it. The installer uses its configuration files and ignores the bundled oh-my-zsh, plugins, and theme. The whole setup lives in `~/.local/zsh-config`: configuration in `config/`, cloned tools in `tools/`. `~/.zshenv` only sets `ZDOTDIR` to `~/.local/zsh-config/config`. That directory name is `ZSH_CONFIG_NAME` in `utils/zsh-tool-paths.sh`. The next zsh process follows that `ZDOTDIR`; the shell you are already in does not. `--uninstall` removes `~/.local/zsh-config` and puts `~/.zshenv` back. The startup sequence is in [Activation](zsh-config/README.md#activation). The layout, the path rewrite, and every file the installer creates are in [zsh-config/README.md](zsh-config/README.md). Installing this tool also copies the `zsh-config/` directory, including that sample archive when it is in the source tree, into the install directory.

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

Serve the current directory, or the directory in `ROOT`, over HTTP. The optional argument is the port. The default port is `8080`. The sample page shipped with the tool is `http-server/public/index.html` under the install directory.

```bash
http-server
http-server 3000
```

## bash-commander

Bash 3.2 parser for options, arguments, and subcommands. Source it, define the command, then call `cli_parse`. The description of the API is `bash-commander/BASH_COMMANDER.md` under the install directory. Examples are installed beside the library.

```bash
. ~/.local/shell-tools/bash-commander/bash-commander.sh
```

## utils

Shared helpers sourced by the other tools: terminal boxes, color, layout, and the zsh-config path map. `install.sh` always copies `utils/` into the install directory. The helpers are not commands on `PATH`.
