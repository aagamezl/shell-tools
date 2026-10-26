# shell-tools

A collection of lightweight shell-based tools for everyday development and system tasks. Built entirely with Bash to stay portable, minimal, and dependency-free.

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

`zsh-config/zsh-config-20261026-124356.tar.gz` is a full CachyOS copy you can install from. Install reads that archive. It does not read the extracted directory next to it. The installer uses its configuration files and ignores the bundled oh-my-zsh, plugins, and theme. The whole setup lives in `~/.local/zsh-config`: configuration in `config/`, cloned tools in `tools/`. `~/.zshenv` only sets `ZDOTDIR` to `~/.local/zsh-config/config`. That directory name is `ZSH_CONFIG_NAME` in `utils/zsh-tool-paths.sh`. The next zsh process follows that `ZDOTDIR`; the shell you are already in does not. `--uninstall` removes `~/.local/zsh-config` and puts `~/.zshenv` back. The startup sequence is in [Activation](zsh-config/README.md#activation). The layout, the path rewrite, and every file the installer creates are in [zsh-config/README.md](zsh-config/README.md).
