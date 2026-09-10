# shell-tools

A collection of lightweight shell-based tools for everyday development and system tasks. Built entirely with Bash to stay portable, minimal, and dependency-free.

## create-host-config.sh

Add a new Host entry to `~/.ssh/config` without overwriting existing entries. A timestamped backup is created first, then a new SSH key is generated for the host.

### Usage

```
create-host-config.sh

Add a new Host entry to ~/.ssh/config without overwriting existing entries.
A timestamped backup is created first, then a new SSH key is generated
for the host.

Usage:
  ./create-host-config.sh
  ./create-host-config.sh -n
  ./create-host-config.sh --dry-run
  ./create-host-config.sh -h
  ./create-host-config.sh --help

Options:
  -n, --dry-run    Show the changes that would be made and exit
                   without writing to ~/.ssh/config, creating a
                   backup, or generating an SSH key
  -h, --help       Show this usage guide and exit

What the script does:
  1. Lists existing Host entries in ~/.ssh/config
  2. Prompts for the new host information
  3. Refuses to continue if that Host alias already exists
  4. Copies ~/.ssh/config to ~/.ssh/config.backup.<timestamp>
     where <timestamp> is a Unix timestamp (seconds since epoch)
  5. Generates an ed25519 SSH key in ~/.ssh
     (existing keys are left unchanged)
  6. Adds the private key to the SSH agent (ssh-add)
  7. Adds the provider host key to ~/.ssh/known_hosts
     if it is not already present (ssh-keyscan)
  8. Appends the new Host block to ~/.ssh/config

Prompts:
  Host name        SSH alias used as: ssh <Host name>
  HostName         Real hostname (github.com, gitlab.com,
                   bitbucket.org, ...)
  User             SSH user (default: git)
  IdentityFile     Key file name or path; the key is always
                   created in ~/.ssh (default:
                   ~/.ssh/id_ed25519_<Host name>)
  IdentitiesOnly   yes or no (default: yes)

Messages:
  Success and error messages are printed for the backup and for
  the new host config entry.

Examples:
  ./create-host-config.sh
  ./create-host-config.sh --dry-run
  ./create-host-config.sh --help
```
