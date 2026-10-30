# box-ui

Technical documentation for `utils/box-ui.sh`.

`box-ui.sh` is a Bash library that draws fixed-width terminal boxes. Callers source it and then print a banner, a series of titled sections, and a final result box. A section can also hold a centered table. `workdays.sh` uses that table for the month calendar. The frame style matches `rebase-push`: a heavy cyan banner, then rounded sections whose border color marks the kind of block (usage, parameters, progress, success, or failure).

The file defines functions and variables in the current shell. It has no command-line interface of its own. `zsh-config/utils/box-ui.sh` is a copy of the box and banner functions used by the zsh-config bundle. The table functions below live in `utils/box-ui.sh`.

Scripts that source it:

| Script | What the boxes show |
| --- | --- |
| `workdays.sh` | Banner, usage, month parameters, calendar, and a green or red result |
| `copy-zsh-config.sh` | Usage, numbered export and install steps, and a result |
| `copy-zsh-config-original.sh` | Same layout as `copy-zsh-config.sh` |
| `create-host-config/create-host-config.sh` | Banner, usage, existing hosts, the planned Host block, and a green or red result |
| `install.sh` | Banner, usage, repository, linked commands, and a green or red result |

`rebase-push/rebase-push.sh` keeps its own copy of the same functions inline.

## Variables

Sourcing the file sets these globals. Later calls read and update `WIDTH`, `SECTION_OPEN`, `BORDER`, and the `TABLE_*` sizes.

| Variable | Initial value | Role |
| --- | --- | --- |
| `WIDTH` | `BOX_UI_WIDTH`, or `68` when that variable is unset | Target width of every box, in characters, including both borders |
| `SECTION_OPEN` | `0` | `1` while a rounded section is open. `section_close` and `finish` read it |
| `BORDER` | empty | ANSI color of the section that is open. Callers pass `"$BORDER"` into row functions so each row uses the same frame color as `section_open` |
| `C_RESET` | `\033[0m` or empty | Turns styling off after a title, a row, or a border |
| `C_BOLD` | `\033[1m` or empty | Bold. `box_top` applies it to the section title. Callers use it for command synopsis lines |
| `C_DIM` | `\033[2m` or empty | Dim. Callers use it for secondary detail and indented notes |
| `C_RED` | `\033[31m` or empty | Red. Callers use it for the failure result border and for error rows |
| `C_GREEN` | `\033[32m` or empty | Green. Callers use it for the success result border and for completed steps |
| `C_YELLOW` | `\033[33m` or empty | Yellow. Callers use it for the usage border and for "would do" / warning rows |
| `C_BLUE` | `\033[34m` or empty | Blue. Callers use it for parameter and summary sections |
| `C_CYAN` | `\033[36m` or empty | Cyan. The banner frame is always cyan. Callers also use it for in-progress sections and `›` rows |
| `TABLE_COLS` | `0` | Column count set by `table_layout` |
| `TABLE_CELL_W` | `0` | Visible width of one cell, in characters. `0` means the last `table_layout` did not fit |
| `TABLE_GRID_W` | `0` | Visible width of one full grid line, including the `┃` separators |

Color variables are set when all three of these are true:

- Standard output is a terminal (`[[ -t 1 ]]`).
- `NO_COLOR` is unset or empty.
- `TERM` is not `dumb`.

Otherwise every `C_*` variable is an empty string and the boxes are plain text. The same strings are safe to pass as function arguments in either mode.

`${#var}` counts characters. A fullwidth character or an emoji is one character and can be wider than one column, so a line can look longer than `WIDTH` on screen.

## Functions

### `repeat_char <char> <count>`

Prints `<char>` repeated `<count>` times and does not add a newline. `box_top`, `box_bottom`, and `box_banner` use it for the horizontal rules. A count of `0` prints nothing.

### `box_top <title> <border>`

Prints the top edge of a rounded section:

```text
╭─ <title> ─────╮
```

`<border>` is an ANSI color (usually one of the `C_*` variables). It colors `╭─`, the dash run, and `╮`. The title is bold, then the color resets so the dashes stay in the border color.

The title area is at most `WIDTH - 6` characters. A longer title is cut to that limit minus one character and ends with `…`. At `WIDTH` 68 the limit is 62 characters. The dash run fills the rest of the line. The function keeps at least one dash, and at least one character of title room, so a very small `WIDTH` still produces a closed corner.

### `box_bottom <border>`

Prints the bottom edge:

```text
╰──────────────╯
```

The horizontal rule is `WIDTH - 2` dashes, colored with `<border>`.

### `box_row <color> <text> <border>`

Prints one content line inside a rounded box:

```text
│ <text>         │
```

`<color>` colors the text. `<border>` colors both `│` characters. An empty `<text>` prints a blank row padded to `WIDTH`. `box_blank` is that case.

Text longer than the inner width (`WIDTH - 4` on the first line) is wrapped:

- A break falls on the last space that still fits, and the space is dropped.
- A token longer than the remaining room is cut mid-word.
- Each continuation line starts with two spaces, so it holds two fewer characters than the first line.

Embedded newlines are not a line break here. Pass one logical line, or use `box_lines`.

### `box_blank <border>`

Prints one empty `box_row` with `<border>`. Callers use it to separate groups inside a usage box.

### `box_lines <color> <text> <border>`

Splits `<text>` on newlines and prints each line with `box_row`. A non-empty line is indented by two spaces first, then wrapped by `box_row` if it is still too long. A blank line inside `<text>` becomes a blank row. Empty `<text>` prints nothing.

This is the function for command output that already contains newlines, such as a Git status block inside a progress section.

### `section_open <title> <border>`

Opens one rounded section. If `SECTION_OPEN` is already `1`, it calls `section_close` first, so two sections never share a frame. Then it stores `<border>` in `BORDER`, prints `box_top`, and sets `SECTION_OPEN` to `1`.

After this returns, pass `"$BORDER"` as the border argument of `box_row`, `box_blank`, and `box_lines`.

### `section_close`

Closes the open section. When `SECTION_OPEN` is `1`, it prints `box_bottom` with the stored `BORDER`, sets `SECTION_OPEN` to `0`, and prints a blank line so the next box is separated. Calling it with no section open prints nothing.

### `finish <code> <border> <title> [line...]`

Prints a result box and exits the process with `<code>`.

1. `section_close` closes a section that is still open, so the result is its own box.
2. `section_open` draws `<title>` in `<border>`.
3. Each remaining argument is one `box_row`. The text uses `<border>` as its color, so a red result has a red frame and red text, and a green result has a green frame and green text.
4. `section_close` draws the bottom edge.
5. `exit <code>` ends the shell. Code that must run after the result cannot follow `finish`. `workdays.sh` wraps this in `die` for the failure path.

Arguments after the title are separate lines. A newline inside one argument is not split.

### `banner_row <color> <text>`

Prints one row of the heavy banner. The `┃` frame is cyan. `<color>` colors the text. Text longer than `WIDTH - 4` is cut to that limit minus one character and ends with `…`. This row does not wrap.

### `box_banner <title> <subtitle>`

Prints the heavy banner used at the start of a run, then a blank line:

```text
┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃ <title>                                                          ┃
┃ <subtitle>                                                       ┃
┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛
```

The frame is cyan. The title is bold. An empty `<subtitle>` omits the second row. A newline in `<subtitle>` starts another row. Each line goes through `banner_row`, so a long title or subtitle line is truncated with `…`.

`workdays.sh` calls this with the script name and `Contractor workday calculator.` before usage, before a usage error, and before the calendar.

### `choose_box_width [preferred]`

Sets `WIDTH` from the terminal size.

`<preferred>` defaults to `68`. That value is the width used when it fits. When standard output is a terminal, the function reads the column count with `stty size` on stdout (file descriptor 3, so a redirected stdin still works). It subtracts one column so the box does not land on the last column. If that value is smaller than `<preferred>`, `WIDTH` becomes the smaller value. A terminal wider than `<preferred>` leaves `WIDTH` at `<preferred>`.

When stdout is not a terminal, or `stty` does not return a column count, `WIDTH` is `<preferred>`.

`choose_box_width` replaces `WIDTH`. It does not read `BOX_UI_WIDTH`. A caller that wants the environment value passes it explicitly:

```bash
choose_box_width "${BOX_UI_WIDTH:-68}"
```

`workdays.sh` calls `choose_box_width 100` once, at the start of `main`, before the banner. The calendar needs that wider box so seven weekday columns still have room for a full name.

### `box_vis_row <visible> <colored>`

Prints one row of the open section when the visible width is not `${#colored}`.

`colored` may contain ANSI codes. `visible` is the column count of that string with the codes left out. Padding goes on the right, so the closing `│` stays on the `WIDTH` column. The frame color is `BORDER`.

`box_row` measures its text with `${#text}` and applies one color to the whole line. A table cell carries its own color inside the text, so the row has to be told how wide the text looks.

### `box_center_row <colored> <visible>`

Centers `colored` in the open section. The left side is padded with spaces, and the padded width is passed to `box_vis_row`. A run wider than the inner width is left as-is and the right pad is `0`, so the closing border can sit past `WIDTH`.

`workdays.sh` uses this for every calendar line and for the legend under the grid. The legend string contains color codes around the swatches, and `visible` is the length of the same legend with those codes removed.

### `table_cell <width> <open> <text>`

Prints one cell, with no newline. The visible width is `width`.

`text` is centered. A longer value is cut to `width` characters. `open` is an ANSI sequence applied to the padding and the text, then closed with `C_RESET`. An empty `open` prints plain text.

Command substitution keeps the padding spaces, so a caller can store the cell and pass it to `table_row`:

```bash
cell="$(table_cell "$TABLE_CELL_W" "$C_BOLD" "Mon")"
```

### `table_layout <cols> [min_cell]`

Fits `<cols>` equal columns into the open box. `<min_cell>` defaults to `3` and is the narrowest cell that still counts as a fit.

The grid spends one column on each `┃`, including both ends, so the separator count is `<cols> + 1`. The cell width is what remains, split evenly:

```text
TABLE_CELL_W = (WIDTH - 4 - cols - 1) / cols
TABLE_GRID_W = TABLE_CELL_W * cols + cols + 1
```

`WIDTH - 4` is the inner width `box_row` uses (the two spaces inside the `│` borders). Leftover columns stay as space around the centered grid.

On success the function sets `TABLE_COLS`, `TABLE_CELL_W`, and `TABLE_GRID_W` and returns `0`. When the cell would be narrower than `<min_cell>`, or `<cols>` is less than `1`, it sets the two widths to `0` and returns `1`. `workdays.sh` treats that as "this terminal is too narrow to draw the calendar" and prints the day lists as ordinary rows instead.

Seven columns at the default width of 68 produce a cell of 8. At the width of 100 used by `workdays.sh`, the cell is 12, which is enough for `Monday`.

### `table_rule <left> <mid> <right>`

Prints one horizontal line of the open table, centered with `box_center_row`.

`<left>`, `<mid>`, and `<right>` are the junction characters. A calendar uses three calls:

| Call | Line |
| --- | --- |
| `table_rule "┏" "┳" "┓"` | Top edge |
| `table_rule "┣" "╋" "┫"` | Line under the header |
| `table_rule "┗" "┻" "┛"` | Bottom edge |

Each cell is a run of `━` of length `TABLE_CELL_W`. The middle junction is written between cells. The whole line is dim when `C_DIM` is set. Call `table_layout` first.

### `table_row [cell...]`

Prints one row of cells. Each argument is a cell already built by `table_cell`, so its visible width is `TABLE_CELL_W`. A missing argument becomes a blank cell of that width. The `┃` separators, including both ends, are dim when color is on. The row is centered.

Passing cells in other widths moves the right border, because `TABLE_GRID_W` is what `box_center_row` trusts as the visible length.

### `table_texts <color> [text...]`

Prints one row in which every cell uses `<color>`. Each text is centered by `table_cell`, then the cells go to `table_row`. Extra arguments are ignored. A missing argument is a blank cell.

Use this when the row is one color. `workdays.sh` does not: a weekday, a day off, and an extra day each carry a different color, so it builds the cells with `table_cell` and passes them to `table_row`.

## Options and arguments

There are no flags. Configuration is environment variables read at source time, plus the arguments of each function.

### Environment

| Variable | When it is read | Effect |
| --- | --- | --- |
| `BOX_UI_WIDTH` | Once, while the file is sourced | Initial `WIDTH`. Unset means `68`. Ignored after `choose_box_width`, which assigns `WIDTH` itself |
| `NO_COLOR` | Once, while the file is sourced | Any non-empty value clears every `C_*` variable. This is the [no-color.org](https://no-color.org) opt-out. Set it before `source` |
| `TERM` | Once, while the file is sourced | A value of `dumb` clears every `C_*` variable |

Color is also cleared when stdout is not a terminal at source time. Piping or redirecting the caller in a context where the library is sourced with stdout already redirected produces plain boxes. Sourcing on a terminal and redirecting later leaves the escape codes in the stream.

### Function arguments

| Function | Arguments |
| --- | --- |
| `repeat_char` | `char`, `count` |
| `box_top` | `title`, `border` color |
| `box_bottom` | `border` color |
| `box_row` | `text` color, `text`, `border` color |
| `box_blank` | `border` color |
| `box_lines` | `text` color, `text` (may contain newlines), `border` color |
| `section_open` | `title`, `border` color |
| `section_close` | none |
| `finish` | exit `code`, `border` color, `title`, then zero or more text lines |
| `banner_row` | `text` color, `text` |
| `box_banner` | `title`, `subtitle` (pass `""` to omit the subtitle) |
| `choose_box_width` | optional preferred width (default `68`) |
| `box_vis_row` | visible column count, colored text |
| `box_center_row` | colored text, visible column count |
| `table_cell` | cell width, opening ANSI color (or `""`), text |
| `table_layout` | column count, optional minimum cell width (default `3`) |
| `table_rule` | left junction, middle junction, right junction |
| `table_row` | one prebuilt cell per column |
| `table_texts` | text color, then one string per column |

Border and text colors are the `C_*` strings, or `""` for uncolored text. The rounded frame characters stay inside the box functions. `table_rule` takes the junction characters for a horizontal line, and `table_row` draws the `┃` separators.

Conventions used by the scripts in this repo:

| Piece | Color | Text |
| --- | --- | --- |
| Banner | cyan frame, bold title | Script name, then a one-line description |
| Usage section | `C_YELLOW` | Bold synopsis lines, a blank row, then dim explanation and flag rows |
| Parameters | `C_BLUE` | Label and value on one row, padded in the text so the values line up |
| Step in progress | `C_CYAN` | `›` plus the action |
| Warning or dry-run | `C_YELLOW` | `› would …`, or a note that something was skipped |
| Completed step | `C_GREEN` | `✓` plus the outcome |
| Detail under a step | `C_DIM` | Two leading spaces, often a path or a command transcript |
| Success result | `finish 0` with `C_GREEN` | `✓` and a short summary |
| Failure result | `finish <code>` with `C_RED` | `✗` and the reason |

## Output

Two frames are used.

A banner is a heavy box, cyan when color is on. `box_banner` prints it and then a blank line. Rows are single-line and truncate.

A section is a rounded box. `section_open` prints the titled top. Rows printed while it is open add the sides. `section_close` prints the bottom and a blank line. The border color is the color passed to `section_open` (usage yellow, parameters blue, progress cyan, result green or red).

A table is drawn inside that section and centered in it. The outer `│` borders stay the section color. The grid uses a heavy rule: `┏ ┳ ┓` on top, `┣ ╋ ┫` under the header, `┗ ┻ ┛` on the bottom, and `┃` between cells. Those rules and separators are dim when color is on. Cell text is centered. Color inside a cell is the caller's ANSI sequence, closed with `C_RESET`, and the row functions are given the visible width so the codes do not push the border.

At the default width of 68, a usage section looks like this when color is off:

```text
╭─ Usage ──────────────────────────────────────────────────────────╮
│ workdays <month> [year] [--off <list>] [--extra <list>]          │
│ workdays --month <1-12> [--year <yyyy>] [--off <list>]           │
│                                                                  │
│ Counts Monday-Friday, then adjusts that total.                   │
│   --off subtracts weekdays you did not work.                     │
╰──────────────────────────────────────────────────────────────────╯
```

Each line is `WIDTH` characters. The inner text sits between a leading space and a trailing space inside the `│` borders. Short rows are padded with spaces. `section_close` adds one empty line after `╰─╯`.

When color is on, the bytes around that first row are the border color, `│`, reset, space, text color, the text, reset, padding, space, border color, `│`, reset. Those bytes are not part of the `WIDTH` count. A pipe, a pager, `NO_COLOR`, or `TERM=dumb` leaves the same characters with no escape codes, which keeps column alignment.

Wrapping keeps the side borders. A sentence that does not fit at width 68 breaks on a space, and the next row is indented two spaces:

```text
╭─ Notes ──────────────────────────────────────────────────────────╮
│ Dry-run lists every file, dependency, backup, and archive        │
│   action without changing the system or writing the bundle.      │
╰──────────────────────────────────────────────────────────────────╯
```

A title that does not fit ends with `…` and still closes the corner:

```text
╭─ This title is far too long to fit inside a sixty-eight column… ─╮
```

`finish` writes the same rounded box, then terminates the process. The exit status is the code passed in. A failure from `copy-zsh-config.sh` looks like this and exits `1`:

```text
╭─ Result ─────────────────────────────────────────────────────────╮
│ ✗ --destination requires a path.                                 │
╰──────────────────────────────────────────────────────────────────╯
```

A success result can carry more than one line. Each argument is one row:

```text
╭─ Result ─────────────────────────────────────────────────────────╮
│ ✓ Export complete.                                               │
│   Archive: /tmp/zsh-bundle.tar.gz                                │
╰──────────────────────────────────────────────────────────────────╯
```

## Examples

Source the library from the directory that contains it, the same way the callers do:

```bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=utils/box-ui.sh
source "${SCRIPT_DIR}/utils/box-ui.sh"
```

The examples below assume that source has already run. Output is shown with color off so the box characters are visible. On a terminal the frames and the text use the `C_*` colors passed in.

### Banner at the start of a run

`workdays.sh` prints this banner before help, before a missing-month error, and before the calendar. The subtitle is the one-line description above every later section. The sample is the default width of 68. `workdays.sh` calls `choose_box_width 100` first, so its banner is 100 columns on a wide terminal and one column short of the screen on a narrow one.

```bash
box_banner "workdays" "Contractor workday calculator."
```

```text
┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃ workdays                                                         ┃
┃ Contractor workday calculator.                                   ┃
┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛
```

Pass `""` as the subtitle when the script name is enough. That second row is omitted. `rebase-push` uses that form for the same banner shape.

### Usage and help

Help is a yellow section: a bold synopsis, a blank row, then the rules and the flags. `workdays.sh` and both copy-zsh-config scripts use this when `--help` is passed, and `workdays.sh` prints it again when the month is missing, just before a red result.

```bash
section_open "Usage" "$C_YELLOW"
box_row "$C_BOLD" "workdays <month> [year] [--off <list>] [--extra <list>]" "$BORDER"
box_row "$C_BOLD" "workdays --month <1-12> [--year <yyyy>] [--off <list>]" "$BORDER"
box_blank "$BORDER"
box_row "" "Counts Monday-Friday, then adjusts that total." "$BORDER"
box_row "$C_DIM" "  --off subtracts weekdays you did not work." "$BORDER"
section_close
```

```text
╭─ Usage ──────────────────────────────────────────────────────────╮
│ workdays <month> [year] [--off <list>] [--extra <list>]          │
│ workdays --month <1-12> [--year <yyyy>] [--off <list>]           │
│                                                                  │
│ Counts Monday-Friday, then adjusts that total.                   │
│   --off subtracts weekdays you did not work.                     │
╰──────────────────────────────────────────────────────────────────╯
```

`copy-zsh-config.sh` fills the same frame with the export and install synopses, a dim paragraph for each mode, another blank row, and one row per flag (`-d`, `-a`, `-n`, `-f`, `-h`). The blank rows are `box_blank "$BORDER"`. The dim rows are the explanation, indented inside the text so they sit under the synopsis.

### Parameters and numbered steps

Export and install print one blue section for the resolved arguments, then a cyan section per step. The label column is spaces inside the text, so the values share a column. `copy-zsh-config.sh` does this for "1 · Parameters" through "7 · Compress". `workdays.sh` does it for "1 · Month", "2 · Summary", and "3 · <Month> <Year>".

```bash
section_open "1 · Parameters" "$C_BLUE"
box_row "" "Mode         export" "$BORDER"
box_row "" "Destination  /tmp/zsh-bundle" "$BORDER"
box_row "" "Dry run      false" "$BORDER"
section_close

section_open "3 · Package files" "$C_CYAN"
box_row "$C_CYAN" "› zsh" "$BORDER"
box_row "$C_GREEN" "✓ zsh already installed" "$BORDER"
box_row "$C_YELLOW" "› would install zsh-syntax-highlighting via pacman" "$BORDER"
box_row "$C_DIM" "  /etc/zsh/zshenv → ~/.local/etc/zsh/host-etc/zsh/zshenv" "$BORDER"
section_close
```

```text
╭─ 1 · Parameters ─────────────────────────────────────────────────╮
│ Mode         export                                              │
│ Destination  /tmp/zsh-bundle                                     │
│ Dry run      false                                               │
╰──────────────────────────────────────────────────────────────────╯

╭─ 3 · Package files ──────────────────────────────────────────────╮
│ › zsh                                                            │
│ ✓ zsh already installed                                          │
│ › would install zsh-syntax-highlighting via pacman               │
│   /etc/zsh/zshenv → ~/.local/etc/zsh/host-etc/zsh/zshenv         │
╰──────────────────────────────────────────────────────────────────╯
```

Cyan `›` is the step that is running. Green `✓` is a step that already holds. Yellow `› would` is a dry-run: the script is describing the write it skipped. Dim indented rows are the paths under that step. Opening the next section closes the previous one, which is why the blank line appears between the boxes even when the caller never calls `section_close` itself.

### Command output inside a section

`box_lines` is for a string that already has newlines, such as stdout captured from Git. Each line is indented, then drawn as its own row. `rebase-push` uses this pattern under a `›` label.

```bash
section_open "Command" "$C_CYAN"
box_lines "$C_DIM" $'Already up to date.\nCurrent branch is main.' "$BORDER"
section_close
```

```text
╭─ Command ────────────────────────────────────────────────────────╮
│   Already up to date.                                            │
│   Current branch is main.                                        │
╰──────────────────────────────────────────────────────────────────╯
```

### Success and failure results

`finish` is the last thing a script prints. It closes whatever section is still open, draws a Result box, and exits. `copy-zsh-config.sh` uses exit `0` after a completed export, and a non-zero code for usage errors, a missing archive, or a missing package manager. `workdays.sh` sends failures through `die`, which is `finish` with a red Result border.

Success, two lines, exit `0`:

```bash
finish 0 "$C_GREEN" "Result" \
  "✓ Export complete." \
  "  Archive: /tmp/zsh-bundle.tar.gz"
```

```text
╭─ Result ─────────────────────────────────────────────────────────╮
│ ✓ Export complete.                                               │
│   Archive: /tmp/zsh-bundle.tar.gz                                │
╰──────────────────────────────────────────────────────────────────╯
```

Failure while a section is still open. The open section is closed first, then the process exits `1`:

```bash
section_open "2 · Preflight" "$C_BLUE"
box_row "" "checking destination" "$BORDER"
finish 1 "$C_RED" "Result" "✗ --destination requires a path."
```

```text
╭─ 2 · Preflight ──────────────────────────────────────────────────╮
│ checking destination                                             │
╰──────────────────────────────────────────────────────────────────╯

╭─ Result ─────────────────────────────────────────────────────────╮
│ ✗ --destination requires a path.                                 │
╰──────────────────────────────────────────────────────────────────╯
```

### Calendar table

`workdays.sh` draws the month inside the cyan section `3 · <Month> <Year>`. It calls `choose_box_width 100` first, then `table_layout 7 3`. Seven columns and a minimum cell of 3 are the calendar: Monday through Sunday, and a cell smaller than three characters is rejected. On that failure the section stays a normal box and lists the off days and extra days as text.

The header row is one `table_cell` per weekday. Monday through Friday are bold. Saturday and Sunday are dim. The cells go to `table_row`. Each week is then three rows, again one cell per day:

1. A blank cell. With color on, the blank is a background wash: green for a weekday, red for a day off, cyan for an extra day.
2. The day number, centered. Plain output marks a day off with a leading `-` and an extra day with brackets. Today is prefixed with `●` when it fits.
3. A bar of `▓`, `x`, or `█`, two characters narrower than the cell so it does not touch the `┃` borders. With color on, this row is another wash and the glyphs are omitted.

`box_blank` leaves a gap above the grid and below it. The legend is one `box_center_row`. Its colored form and its plain length are passed separately, because the swatches are ANSI backgrounds and `${#colored}` would count those bytes.

This is that sequence at the default width of 68, where each cell is 8 characters and the header uses the short names. `workdays.sh` at width 100 uses the same calls with a cell of 12, so the headers read `Monday` through `Sunday`.

```bash
section_open "3 · October 2026" "$C_CYAN"
box_blank "$BORDER"
table_layout 7 3

names=(Mon Tue Wed Thu Fri Sat Sun)
cells=()
for ((i = 0; i < 7; i++)); do
  if (( i >= 5 )); then
    open="$C_DIM"
  else
    open="$C_BOLD"
  fi
  cells+=("$(table_cell "$TABLE_CELL_W" "$open" "${names[$i]}")")
done
table_rule "┏" "┳" "┓"
table_row "${cells[@]}"
table_rule "┣" "╋" "┫"
table_texts ""
table_texts "" "" "" "" 1 2 -3 "[4]"
bar="$(repeat_char "▓" $((TABLE_CELL_W - 2)))"
off="$(repeat_char "x" $((TABLE_CELL_W - 2)))"
extra="$(repeat_char "█" $((TABLE_CELL_W - 2)))"
table_texts "" "" "" "" "$bar" "$bar" "$off" "$extra"
table_rule "┗" "┻" "┛"
box_blank "$BORDER"
legend="▓▓ Weekday    xx Day off    ██ Extra    ● Today"
box_center_row "$legend" "${#legend}"
section_close
```

```text
╭─ 3 · October 2026 ───────────────────────────────────────────────╮
│                                                                  │
│ ┏━━━━━━━━┳━━━━━━━━┳━━━━━━━━┳━━━━━━━━┳━━━━━━━━┳━━━━━━━━┳━━━━━━━━┓ │
│ ┃  Mon   ┃  Tue   ┃  Wed   ┃  Thu   ┃  Fri   ┃  Sat   ┃  Sun   ┃ │
│ ┣━━━━━━━━╋━━━━━━━━╋━━━━━━━━╋━━━━━━━━╋━━━━━━━━╋━━━━━━━━╋━━━━━━━━┫ │
│ ┃        ┃        ┃        ┃        ┃        ┃        ┃        ┃ │
│ ┃        ┃        ┃        ┃   1    ┃   2    ┃   -3   ┃  [4]   ┃ │
│ ┃        ┃        ┃        ┃ ▓▓▓▓▓▓ ┃ ▓▓▓▓▓▓ ┃ xxxxxx ┃ ██████ ┃ │
│ ┗━━━━━━━━┻━━━━━━━━┻━━━━━━━━┻━━━━━━━━┻━━━━━━━━┻━━━━━━━━┻━━━━━━━━┛ │
│                                                                  │
│         ▓▓ Weekday    xx Day off    ██ Extra    ● Today          │
╰──────────────────────────────────────────────────────────────────╯
```

The body rows above use `table_texts` because every cell in the sample is plain. The real calendar uses `table_cell` for those rows so each day can carry its own color. A uniform row, such as a header in one weight, can stay on `table_texts`.

### Width and plain output

Set the width before sourcing when the default of 68 is wrong and the script will not call `choose_box_width`:

```bash
export BOX_UI_WIDTH=80
source "${SCRIPT_DIR}/utils/box-ui.sh"
```

Call `choose_box_width` when the box should shrink on a small terminal and stay capped on a large one. `workdays.sh` uses `100` because the calendar is wider than the default 68.

```bash
choose_box_width 100
```

Force plain text before sourcing. Do this when the script's stdout will be logged, or when the terminal has no reliable color:

```bash
export NO_COLOR=1
source "${SCRIPT_DIR}/utils/box-ui.sh"
```

`TERM=dumb` has the same effect. Redirecting stdout before `source` also leaves the `C_*` variables empty, because color is decided only at source time.
