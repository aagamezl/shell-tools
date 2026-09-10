# Bash Commander

## Why this parser exists

`bash-commander.sh` provides a Commander-like definition style in Bash:

- define options, arguments, and commands declaratively
- auto-generate usage/help text
- parse runtime arguments into Bash-native fields
- support default command behavior

It is designed to be sourced from scripts:

```bash
source "./bash-commander.sh"
```

Then used through a simple lifecycle:

1. `cli_create`
2. register definitions (`cli_option`, `cli_argument`, `cli_command`, etc.)
3. `cli_parse "$@"`
4. read parsed result (`cli_get_option`, `CLI_GLOBAL_ARGS`, `CLI_SELECTED_COMMAND`, ...)

## Core design decisions

### Bash 3.2 compatibility first

macOS ships Bash 3.2 by default. Bash 3.2 has no associative arrays, so this
project cannot rely on `declare -A` if it wants broad out-of-the-box support.

Because of that, map-like structures are represented as **parallel arrays**:

- `<PREFIX>_KEYS`
- `<PREFIX>_VALUES`

Example:

```bash
CLI_OPTIONS_KEYS=("debug" "port")
CLI_OPTIONS_VALUES=("true" "8080")
```

Access is abstracted with:

- `__cli_kv_set <prefix> <key> <value>`
- `__cli_kv_get <prefix> <key> <out_var>`
- `__cli_kv_reset <prefix>`

You should treat these helpers as the map API and avoid direct manipulation
unless you are changing internals.

### Stateful parser instance in global variables

The parser is intentionally global-state based (as is common in Bash). A single
script typically has one parser instance and calls `cli_create` once.

`cli_create` performs a full reset so the same shell session can define/parse
again without stale state.

### Internal naming conventions

- Public API/state: `cli_*`, `CLI_*`
- Internal helpers/state: `__cli_*`, `__CLI_*`

Use this convention for new code. It keeps public and internal responsibilities
clear.

## High-level architecture

The implementation has three layers:

1. **Definition storage layer**
   Stores command/argument/option metadata (`__CLI_*` arrays).
2. **Parsing/runtime layer**
   Walks argv, resolves command scope, assigns option values, validates args.
3. **Presentation layer**
   Generates usage/help and debug output (`cli_help`, `cli_dump_result`).

## Data model in detail

### Public runtime result fields

- `CLI_SELECTED_COMMAND`
  Selected command name, or empty if no command mode.
- `CLI_GLOBAL_ARGS`
  Positional tokens in global scope.
- `CLI_COMMAND_ARGS`
  Positional tokens in selected command scope.
- `CLI_GLOBAL_OPTIONS_KEYS` / `CLI_GLOBAL_OPTIONS_VALUES`
  Runtime resolved global options.
- `CLI_COMMAND_OPTIONS_KEYS` / `CLI_COMMAND_OPTIONS_VALUES`
  Runtime resolved command options.
- `CLI_OPTIONS_KEYS` / `CLI_OPTIONS_VALUES`
  Merged view where command options override global options on key collision.

### Internal definition fields

#### Global arguments

- `__CLI_GLOBAL_ARG_NAMES`
- `__CLI_GLOBAL_ARG_REQUIRED` (`1` required, `0` optional)
- `__CLI_GLOBAL_ARG_LABELS` (`<name>` or `[name]`)

#### Global options

Aligned arrays by index:

- `__CLI_GOPT_KEYS` (canonical key)
- `__CLI_GOPT_SHORT` (e.g. `p`)
- `__CLI_GOPT_LONG` (e.g. `port`)
- `__CLI_GOPT_KIND` (`flag` or `value`)
- `__CLI_GOPT_METAVAR` (e.g. `port_number`)
- `__CLI_GOPT_DESC`
- `__CLI_GOPT_DEFAULT`

#### Commands

- `__CLI_COMMANDS`
- `__CLI_COMMAND_DESC`
- `__CLI_DEFAULT_COMMAND`

#### Command arguments/options

Command-scoped definitions use parallel arrays with `command` as discriminator:

- arguments: `__CLI_CARG_COMMAND`, `__CLI_CARG_NAME`, `__CLI_CARG_REQUIRED`, `__CLI_CARG_LABEL`
- options: `__CLI_COPT_COMMAND`, `__CLI_COPT_KEY`, `__CLI_COPT_SHORT`, `__CLI_COPT_LONG`, `__CLI_COPT_KIND`, `__CLI_COPT_METAVAR`, `__CLI_COPT_DESC`, `__CLI_COPT_DEFAULT`

## Parsing algorithm (`cli_parse`) step by step

`cli_parse` is a single-pass state machine over input tokens.

### 1) Reset runtime state

- clears selected command and positional outputs
- applies global option defaults
- clears command option runtime map

### 2) Iterate tokens

Loop variable: `i` over `args=("$@")`.

State variables:

- `expecting_scope`
- `expecting_key`

These represent “previous token was a value option without inline value”, for
example `--port 8080`.

### 3) Handle pending option value

If `expecting_scope` is set, current token is assigned as option value and loop
continues.

### 4) Handle control tokens

- `-h` / `--help`: print help and return `2`
- `--`: stop option parsing; all remaining tokens become positional arguments

### 5) Resolve command selection

If command list exists and no command selected yet:

- first non-option token can select an explicit command
- if not explicit and default command exists, parser may enter default command
  scope

There are two default-command entry paths:

1. user starts with option token and default exists
2. parse ends with no explicit command and default exists

### 6) Resolve option tokens

Option resolution uses `__cli_resolve_option`:

- supports `--name`
- supports `--name=value`
- supports `-n`

Lookup order is:

1. global scope
2. command scope (only when command is selected)

If an option is kind `flag`, value becomes `"true"`.
If kind `value`, either consume inline value (`--name=value`) or arm
`expecting_*` to consume next token.

Unknown option triggers `__cli_die`.

### 7) Collect positional tokens

Non-option tokens become:

- `CLI_COMMAND_ARGS` when command selected
- `CLI_GLOBAL_ARGS` otherwise

### 8) Post-parse validation

Validation order is:

1. missing value for option (`expecting_scope` still set)
2. required global argument count
3. required command argument count
4. maximum command argument count (too many args error)

Current too-many-args format:

```text
error: too many arguments for '<command>'. Expected <N> arguments but got <M>.
```

### 9) Merge option maps

`__cli_merge_options` builds `CLI_OPTIONS_*` from both scopes, applying
command-scope overwrite when keys collide.

## Help generation behavior (`cli_help`)

`cli_help` builds output from metadata and (optionally) selected command
context.

Sections:

1. description (if any)
2. `Usage: ...` line from `__cli_usage_line`
3. global options + built-in `-h, --help`
4. command-specific options section when a command is selected
5. commands list (with `(default)` marker when applicable)

This means help can vary slightly depending on whether a command has already
been selected before help is rendered.

## Public API reference

### Initialization

- `cli_create <name> [description]`

### Definitions

- `cli_argument "<arg>"` where arg syntax is `<required>` or `[optional]`
- `cli_option "<spec>" [description] [default]`
- `cli_command "<name>" [description] [is_default_true_or_false]`
- `cli_command_argument "<command>" "<arg>"`
- `cli_command_option "<command>" "<spec>" [description] [default]`

### Parsing and output

- `cli_parse "$@"`
- `cli_help`
- `cli_dump_result`
- `cli_get_option "<key>" <output_var_name>`

## Option spec grammar and canonical keys

### Supported declaration forms

- `--debug`
- `-d, --debug`
- `-p, --port <port_number>`
- `--port <port_number>`

### Canonical key rules

- If long name exists, key is long name (`port`)
- If no long name, key is short name (`p`)

You should use canonical key names with `cli_get_option`.

## Error model and return codes

- `0`: parse success
- `1`: parse/validation error
- `2`: help was shown (`-h`/`--help`)

Definition-time errors (`cli_option`, `cli_argument`, etc.) print explicit
messages to stderr and return `1`.

## Internal helpers worth understanding before extending

- `__cli_parse_option_spec`
  Converts declaration strings into normalized metadata.
- `__cli_resolve_option`
  Maps runtime option tokens to metadata entries and determines kind/value flow.
- `__cli_set_default_option_values`
  Preloads runtime option state with defaults.
- `__cli_required_count_for_*` / `__cli_total_count_for_command_args`
  Validation helpers for minimum/maximum positional argument checks.

## Extension guide

If you want to extend behavior, these are the safest patterns.

### Add a new option type

1. Extend `__cli_parse_option_spec` to classify the new type.
2. Extend runtime assignment branch in `cli_parse`.
3. Extend `cli_help` rendering for type-specific formatting.

### Add command aliases

1. Introduce alias metadata arrays (e.g. `__CLI_COMMAND_ALIAS_*`).
2. Update `__cli_command_exists` and command selection branch in `cli_parse`.
3. Keep `CLI_SELECTED_COMMAND` canonical (primary command name).

### Add global “too many args” validation

Add a helper mirroring `__cli_total_count_for_command_args` for global args and
insert validation after required-global validation.

### Add subcommand nesting

Current model supports one command layer. Nested subcommands require:

- hierarchical metadata
- recursive or staged parse logic
- contextual help rendering

This is a non-trivial change and should be done in isolated incremental steps.

## Known limitations (current implementation)

- no short-option bundling (`-abc`)
- no automatic type coercion (all values are strings)
- no repeated-option list accumulation
- no variadic args (`<arg...>`) semantics yet
- single command depth

## Practical usage examples

Ready-to-run examples are in:

- `example-thank.sh`
- `example-default-command.sh`
- `example-split.sh`

They intentionally mirror common Commander usage patterns and are good starting
templates for new tools.
