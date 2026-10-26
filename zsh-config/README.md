# zsh-config

`zsh-config.sh` configures zsh and oh-my-zsh from a CachyOS configuration bundle. The CachyOS files are the source of the shell configuration. The tools are installed on the target machine. They are not copied out of the bundle, and the CachyOS tree is not written to `/usr` or `/etc`.

Run it from the repository root, or through `zsh-config/zsh-config.sh`, which calls the same script.

```bash
./zsh-config.sh --help
./zsh-config.sh --export -d ./out
./zsh-config.sh --install -a zsh-config/zsh-config-20261026-124356.tar.gz
./zsh-config.sh --install -n -a zsh-config/zsh-config-20261026-124356.tar.gz
```

`--dry-run` (`-n`) prints the clones, the config files, and the `~/.zshenv` edit. It does not install packages, clone repositories, or write under `$HOME`. `--force` (`-f`) replaces config files that already differ, after copying each one to `<path>.backup.<unix-timestamp>`. An existing tool checkout is left as it is.

`zsh-config-original.sh` is the earlier installer. It restores bundle paths under `/usr` and `/etc`. Do not use it to set up a machine.

## What is copied, and what is installed

The CachyOS base is the file `cachyos-config.zsh` from the `cachyos-zsh-config` package, plus the user dotfiles and the small `/etc/zsh` and `/etc/skel` files that belong to that setup. Export copies only those. Install reads them from the bundle and writes them under the home directory.

These tools are installed on the target. None of them are taken from the CachyOS copies in the bundle:

| Tool | How it is installed | Where it lands |
| --- | --- | --- |
| zsh | Package manager (`apt`, `dnf`, `yum`, `zypper`, `pacman`, or `brew`) | The `zsh` binary on the system |
| git | Same package manager, only when `git` is missing | Used to clone the repositories below |
| oh-my-zsh | `git clone --depth 1 https://github.com/ohmyzsh/ohmyzsh.git` | `~/.local/zsh-config/tools/oh-my-zsh` |
| zsh-syntax-highlighting | `https://github.com/zsh-users/zsh-syntax-highlighting.git` | `~/.local/zsh-config/tools/plugins/zsh-syntax-highlighting` |
| zsh-autosuggestions | `https://github.com/zsh-users/zsh-autosuggestions.git` | `~/.local/zsh-config/tools/plugins/zsh-autosuggestions` |
| zsh-completions | `https://github.com/zsh-users/zsh-completions.git` | `~/.local/zsh-config/tools/plugins/zsh-completions` |
| zsh-history-substring-search | `https://github.com/zsh-users/zsh-history-substring-search.git` | `~/.local/zsh-config/tools/plugins/zsh-history-substring-search` |
| powerlevel10k | `https://github.com/romkatv/powerlevel10k.git` | `~/.local/zsh-config/tools/themes/powerlevel10k` |

powerlevel10k is not a separate request in the tool list. `cachyos-config.zsh` sources it, so the shell cannot start the CachyOS prompt without it. It is cloned from upstream in the same way as the plugins. A Nerd Font is not installed. The prompt needs one in the terminal if you want the icons from the sample `~/.p10k.zsh`.

zsh is the only package that has to live outside the home directory, because it is the shell binary. The package installed is `zsh` alone. `cachyos-zsh-config`, `oh-my-zsh-git`, and the distro plugin packages are not installed, including on Arch.

## Configuration process

Export runs on the CachyOS machine, where `pacman` is available.

1. Read every regular file from `/usr/share/cachyos-zsh-config`.
2. Read `/etc/zsh/zshenv`, `/etc/zsh/zprofile`, `/etc/zsh/zshrc`, `/etc/zsh/zlogin`, `/etc/zsh/zlogout`, and the matching names under `/etc/skel` when those files exist.
3. Read `~/.zshrc`, `~/.zshenv`, `~/.zprofile`, `~/.zlogin`, `~/.zlogout`, and `~/.p10k.zsh` when they exist.
4. Write `manifest.tsv`, `bundle.meta`, and `tool-paths.source.tsv`. The path file records where CachyOS put each tool so install can rewrite those strings. The tools themselves are not archived.
5. Pack `config/`, the manifest, the metadata, and the path file into `zsh-config-<timestamp>.tar.gz`.

Install runs on the machine you are configuring. Linux package managers and Homebrew are supported. zsh and git must already be installed when none of those managers is present.

1. Read the bundle from a `.tar.gz` archive. A directory is rejected.
2. Install `zsh` and, if it is missing, `git`.
3. Clone each tool into `~/.local/zsh-config/tools` when its files are not already there. A checkout that is already complete is left untouched. A directory that exists but is missing the tool's main file stops the install so a half-written tree is not overwritten.
4. Choose the configuration files. User dotfiles win over `/etc/zsh`, which wins over `/etc/skel`, when two bundle entries would write the same name. Files from oh-my-zsh, the plugins, completions, powerlevel10k, `/usr/share/doc`, and `/usr/share/licenses` are counted and skipped.
5. Rewrite CachyOS paths to `$HOME/.local/zsh-config/...`, rewrite the source account's home directory to this account's home, and quote `$HOME` paths. A `source` of a file this install does not provide is wrapped so a missing file does not abort the shell.
6. Write the files under `~/.local/zsh-config/config` and add the `ZDOTDIR` block to `~/.zshenv`.
7. Leave the login shell alone. When you want new terminals to start zsh, run `chsh -s "$(command -v zsh)"` and open a new terminal.

## Portable layout

Everything the installer writes is under `$HOME`.

The directory name is `ZSH_CONFIG_NAME` in `utils/zsh-tool-paths.sh`. It defaults to `zsh-config`. Configuration and tools are both under `~/.local/$ZSH_CONFIG_NAME`, so changing that one variable and reinstalling moves the whole tree.

```text
~/.zshenv
~/.local/zsh-config/
  config/                            ZDOTDIR
    .zshenv
    .zshrc
    .zprofile
    .p10k.zsh
    cachyos-config.zsh
    paths.generated.zsh
  tools/
    oh-my-zsh/
    plugins/zsh-syntax-highlighting/
    plugins/zsh-autosuggestions/
    plugins/zsh-completions/
    plugins/zsh-history-substring-search/
    themes/powerlevel10k/
```

How a new zsh process finds this tree is in [Activation](#activation).

## Activation

Install writes the files and stops. It does not reload the shell you are in, and it does not change the login shell. The config is used the next time a zsh process starts.

1. Run the installer. It appends the `ZDOTDIR` block to `~/.zshenv` and writes the rest under `~/.local/zsh-config/config`.
2. Leave the current terminal as it is. That process already finished its startup and will not read the new files.
3. Start zsh. If zsh is already your login shell, open a new terminal. Otherwise run `zsh`, or switch the login shell and then open a new terminal:

   ```bash
   chsh -s "$(command -v zsh)"
   ```

4. In the new shell, `ZDOTDIR` is `$HOME/.local/zsh-config/config` and `ZSH` is `$HOME/.local/zsh-config/tools/oh-my-zsh`. `echo $ZDOTDIR` and `echo $ZSH` show those paths when the chain below ran.

The first zsh process does not yet have `ZDOTDIR` in its environment, so it reads `~/.zshenv`. That file sets `ZDOTDIR`. zsh then reads the interactive and login files from the new directory. It does not go back and read `~/.local/zsh-config/config/.zshenv` in that same process.

```text
zsh starts                         ZDOTDIR is unset
        |
        v
/etc/zshenv                        always, from the system
        |
        v
~/.zshenv                          export ZDOTDIR=$HOME/.local/zsh-config/config
        |
        +-- login shell only ----> /etc/zprofile
        |                                   |
        |                                   v
        |                          $ZDOTDIR/.zprofile
        |
        +-- interactive shell ---> /etc/zshrc
                                            |
                                            v
                                   $ZDOTDIR/.zshrc
                                            |
                                            v
                                   cachyos-config.zsh
                                            |
                    +-----------------------+------------------------+
                    |                       |                        |
                    v                       v                        v
         paths.generated.zsh        $ZSH/oh-my-zsh.sh         powerlevel10k
         sets ZSH and fpath         plugins:                  then syntax highlighting
                                    git, fzf, extract         autosuggestions
                                                              history-substring-search
                                                              then .p10k.zsh
```

`$ZDOTDIR` in that diagram is `$HOME/.local/zsh-config/config`. `~/.zshrc` is not in the chain. The file stays where it was, and zsh does not read it while `ZDOTDIR` is set.

A later zsh inherits `ZDOTDIR` from the environment. Startup then skips `~/.zshenv` and reads the copy inside the config directory, which loads `paths.generated.zsh` before `.zshrc` runs the same chain again.

```text
later zsh                          ZDOTDIR already exported
        |
        v
/etc/zshenv
        |
        v
$ZDOTDIR/.zshenv                   ~/.zshenv is not read
        |                          source paths.generated.zsh
        v
$ZDOTDIR/.zshrc
        |
        v
cachyos-config.zsh                 same sources as the first shell
```

`paths.generated.zsh` sets `ZSH` to the oh-my-zsh checkout and puts `zsh-completions/src` on `fpath` before oh-my-zsh runs `compinit`. The CachyOS `plugins=(git fzf extract)` line is unchanged. Syntax highlighting, autosuggestions, and history substring search are sourced after oh-my-zsh, which is the order in the CachyOS file. Those four plugins live in `~/.local/zsh-config/tools/plugins`, next to oh-my-zsh rather than inside it. `git`, `fzf`, and `extract` are the copies inside `~/.local/zsh-config/tools/oh-my-zsh/plugins`.

## Files the installer creates

| File | Role |
| --- | --- |
| `~/.zshenv` | Exports `ZDOTDIR="${HOME}/.local/zsh-config/config"`. Appended if the file already exists. A copy is saved beside it first. |
| `~/.local/zsh-config/config/.zshenv` | Sources `paths.generated.zsh` for shells that already have `ZDOTDIR` set. |
| `~/.local/zsh-config/config/.zshrc` | The source user's `.zshrc`, with CachyOS paths rewritten. `/etc/skel/.zshrc` is used only when the bundle has no user `.zshrc`. |
| `~/.local/zsh-config/config/.zprofile` | The source `/etc/zsh/zprofile` when the user has no `.zprofile`. The sample file sources `/etc/profile`. |
| `~/.local/zsh-config/config/.p10k.zsh` | The source user's Powerlevel10k wizard output. |
| `~/.local/zsh-config/config/cachyos-config.zsh` | The CachyOS base configuration, with tool paths pointed at `~/.local/zsh-config/tools`. |
| `~/.local/zsh-config/config/paths.generated.zsh` | Generated on every install. Sets `ZSH` and `fpath`. Replaced when it differs; the previous file is backed up. |

Marked blocks look like this:

```zsh
# >>> zsh-config >>>
export ZDOTDIR="${HOME}/.local/zsh-config/config"
# <<< zsh-config <<<
```

A second install sees the marker and leaves the block in place.

## Path rewrite

The sample `cachyos-config.zsh` refers to the CachyOS locations. Install replaces them with the home-directory checkouts:

| CachyOS path | Written into the config |
| --- | --- |
| `/usr/share/oh-my-zsh` | `$HOME/.local/zsh-config/tools/oh-my-zsh` |
| `/usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh` | `$HOME/.local/zsh-config/tools/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh` |
| `/usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh` | `$HOME/.local/zsh-config/tools/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh` |
| `/usr/share/zsh/plugins/zsh-history-substring-search/zsh-history-substring-search.zsh` | `$HOME/.local/zsh-config/tools/plugins/zsh-history-substring-search/zsh-history-substring-search.zsh` |
| `/usr/share/zsh/site-functions` | `$HOME/.local/zsh-config/tools/plugins/zsh-completions/src` |
| `/usr/share/zsh-theme-powerlevel10k` | `$HOME/.local/zsh-config/tools/themes/powerlevel10k` |
| `/usr/share/cachyos-zsh-config` | `$HOME/.local/zsh-config/config` |
| `~/.p10k.zsh` | `$HOME/.local/zsh-config/config/.p10k.zsh` |

`/home/<source user>` and `/Users/<source user>` in the user files become this machine's `$HOME`. `bundle.meta` supplies `source_user` and, on a new export, `source_home`.

`source /usr/share/doc/pkgfile/command-not-found.zsh` is kept and guarded, because pkgfile is not one of the installed tools. The same guard is applied to other bare `source` lines whose target is not part of this install, such as a source user's nvm or alias file. `FZF_BASE=/usr/share/fzf` is left as the CachyOS file wrote it. Install fzf yourself if you want the `fzf` plugin to find it.

Three CachyOS aliases run a command while the file is read: `make` and `ninja` call `` `nproc` ``, and `cleanup` calls `$(pacman -Qtdq)`. Install stores them in single quotes so they run when you use the alias. The other Arch aliases (`pacman`, `expac`, `journalctl`) stay as written.

## Export bundle

A new archive looks like this:

```text
zsh-config-YYYYMMDD-HHMMSS.tar.gz
  manifest.tsv
  bundle.meta
  tool-paths.source.tsv
  config/
    cachyos/cachyos-config.zsh
    user/.zshrc
    user/.p10k.zsh
    host-etc/zsh/zprofile
    host-etc/skel/.zshrc
```

`manifest.tsv` rows are `config`, the path under `~/.local/zsh-config/config`, and the path inside the archive, separated by tabs. `bundle.meta` records the time, the source host, the source user, and `source_home`.

## Sample bundle

`zsh-config/zsh-config-20261026-124356.tar.gz` is a full copy taken from a CachyOS machine on 2026-10-26. Install reads that archive, not the extracted directory beside it. Most of its 1,330 manifest rows are oh-my-zsh, plugins, completions, powerlevel10k, docs, and licenses. Install does not copy those. From that sample it keeps:

| Bundle path | Installed as |
| --- | --- |
| `root/usr/share/cachyos-zsh-config/cachyos-config.zsh` | `~/.local/zsh-config/config/cachyos-config.zsh` |
| `user/.zshrc` | `~/.local/zsh-config/config/.zshrc` |
| `user/.p10k.zsh` | `~/.local/zsh-config/config/.p10k.zsh` |
| `root/etc/zsh/zprofile` | `~/.local/zsh-config/config/.zprofile` |
| `root/etc/skel/.zshrc` | Not installed, because `user/.zshrc` is present |

`bundle.meta` in the sample names the source user `aagamezl` on host `aagamezl-laptop`. The user `.zshrc` also sources nvm, a private alias file, bun, and pnpm. Those lines are rewritten to this home directory and skipped when the files are absent. The sample has no `tool-paths.source.tsv`. Install uses the CachyOS paths listed above, which match that `cachyos-config.zsh`.

```bash
./zsh-config.sh --install -a zsh-config/zsh-config-20261026-124356.tar.gz
```

## Uninstall

```bash
./zsh-config.sh --uninstall
./zsh-config.sh --uninstall -n
```

Uninstall reverses the files this tool wrote.

1. `~/.zshenv` is put back. When install saved `~/.zshenv.backup.<unix-timestamp>` before adding the block, that backup is restored and then deleted. When `~/.zshenv` was created by the install and contains only the block, the file is deleted. Otherwise only the marked block is removed.
2. `~/.local/zsh-config` is removed, including `config/` and `tools/`. A symlink at that path is left in place.
3. `~/.zshrc` is not read or written. The login shell is not changed. The `zsh` and `git` packages are not removed, because the installer does not record whether they were already present.

A second uninstall finds nothing to remove and exits `0`. Open a new terminal afterward. A shell that already exported `ZDOTDIR` keeps using it until it exits.

## Flags and exit status

| Flag | Meaning |
| --- | --- |
| `--export` | Collect configuration on Arch or CachyOS. Implied when `--destination` is set and no mode is given. |
| `--install` | Install tools and write configuration on this machine. |
| `--uninstall` | Remove `~/.local/zsh-config` and the `ZDOTDIR` block. Restore `~/.zshenv` from the pre-install backup when that backup exists. |
| `-d`, `--destination` | Directory for the export staging tree and the default archive name. |
| `-a`, `--archive` | `.tar.gz` to write on export, or `.tar.gz` to install. A directory is rejected. |
| `-n`, `--dry-run` | Print the plan. |
| `-f`, `--force` | Replace an existing config file that differs. The previous file is saved as `<path>.backup.<unix-timestamp>`. |
| `-h`, `--help` | Print usage. |

Exit `0` means the run finished. Exit `1` is a usage error. Exit `2` means zsh, git, or a package manager is missing. Exit `3` means the bundle or a clone failed.
