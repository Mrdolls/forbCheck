# ForbCheck

**ForbCheck** is a Bash CLI tool that analyzes compiled C executables and libraries to detect forbidden function usage — designed to match how projects are evaluated at 42.

It combines `nm`-based binary inspection with an optional deep source scan, giving you precise file and line-level reporting before your evaluation.

---

## How It Works

ForbCheck uses two complementary approaches:

**Binary analysis (default):** Inspects unresolved symbols in your compiled binary using `nm`, then cross-references them against your authorized functions list. Fast and reliable — typically runs in under 0.2s.

**Source scan (`-s`):** Parses your `.c` files directly using a Perl-based engine that strips comments and string literals before analysis. Whitelists functions you defined yourself, so your `ft_printf` is never confused with a forbidden `printf`.

---

## Features

- Detects forbidden functions at the binary level via `nm` and `.o`/`.a` object scanning
- Deep source scan with comment/string stripping for zero false positives
- Pinpoints exact file and line number for every forbidden call
- Auto-detects your project binary via `Makefile` or recent executables
- Auto-loads the correct preset from your folder name (case-insensitive, substring match)
- Detects external libraries (MiniLibX, Math) and excludes their internal symbols automatically
- Warns you if your source code is newer than your binary (stale binary detection)
- **Blacklist Mode** — inverts the scan logic: all functions allowed except the ones you explicitly list
- **Preset flags** — embed behavior directly inside `.preset` files (`BLACKLIST_MODE`, `ALL_MLX`, `ALL_MATH`)
- JSON output mode for CI/CD integration
- Preset system to manage authorized function lists per project

---

## Requirements

- `bash`
- `nm` (GNU binutils)
- `perl`
- `curl`, `tar`
- `grep`, `awk`, `sed`
- `bc` (optional — only needed for `-t` execution time display)

---

## Installation

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/Mrdolls/forb/refs/heads/main/install.sh)"
```

---

## Usage

```bash
forb [options] [target] [-f <files...>]
```

`target` is optional — ForbCheck will auto-detect your binary if omitted.

---

## Options

| Category | Option | Description |
| :--- | :--- | :--- |
| **General** | `<target>` | Executable or library (`.a`, `.o`) to analyze |
| | `-h, --help` | Show help message |
| | `--json` | JSON output for CI/CD automations |
| | `-l, --list [<funcs...>]` | Show default authorized list or check specific functions |
| | `-e` | Open the default authorized functions list for editing |
| **Presets** | `-P, --preset` | Load the preset matching the target name |
| | `-np, --no-preset` | Disable auto-preset, force default list |
| | `-gp, --get-presets` | Restore default presets from GitHub |
| | `-cp, --create-preset` | Create and edit a new custom preset |
| | `-lp, --list-presets` | Show all available presets |
| | `-op, --open-presets` | Open the presets directory |
| | `-rp, --remove-preset` | Delete an existing preset |
| **Scan** | `-s, --source` | Deep scan source files for unauthorized C functions |
| | `-b, --blacklist` | Force Blacklist Mode (hunt specific functions instead of using whitelist) |
| | `-v` | Verbose: show source code context with highlighting |
| | `-f <files...>` | Limit scan to specific files |
| | `-p, --full-path` | Show full file paths |
| | `-a` | Show authorized functions during the scan |
| | `--no-auto` | Disable auto-detection (must be placed before `-s`) |
| **Library Filters** | `-mlx` | Ignore MiniLibX internal calls |
| | `-lm` | Ignore Math library internal calls |
| **Maintenance** | `-t, --time` | Show execution duration |
| | `--version` | Show version's forbCheck |
| | `-up, --update` | Check and install the latest version |
| | `--remove` | Uninstall ForbCheck |

---

## Examples

```bash
# Auto-detect binary and run analysis
forb

# Analyze a specific binary with default preset (-e for edit)
forb minishell

# Deep source scan (auto-detects project preset)
forb -s

# Force manual preset selection, then source scan
forb --no-auto -s

# Verbose output with source context
forb -v minishell

# Use a named preset with a specific binary
forb -P cub3D

# Force-ignore MiniLibX and Math internal calls
forb -mlx -lm cub3D

# Check which functions are in your authorized list
forb -l read write malloc free

# JSON output for automation
forb --json minishell

# Show execution time
forb -t minishell

# Blacklist mode: detect usage of specific forbidden functions
forb -b -s

# Blacklist mode via preset flag (see Preset Flags section)
forb -s
```

---

## Preset System

Presets are per-project authorized function lists stored in `~/.forb/presets/`.

ForbCheck automatically selects the right preset by matching your current folder name against preset filenames (case-insensitive, substring match). For example, being inside `minishell-r` or `Minishell_v2` will both load `minishell.preset`.

**Managing presets:**

```bash
forb -cp        # Create a new preset
forb -lp        # List available presets
forb -op        # Open the presets directory
forb -rp        # Remove a preset
forb -gp        # Download/restore default presets from GitHub
```

**Default preset** (`default.preset`) is used when no project-specific preset is found.

Functions can be separated by commas, spaces, or newlines:

```text
read, write, malloc, free, open, close
```

Quick edit:

```bash
forb -e
```

---

## Preset Flags

Presets now support embedded flags that configure ForbCheck's behavior without needing CLI options. Add them anywhere in the `.preset` file (outside of comments).

| Flag | Description |
| :--- | :--- |
| `BLACKLIST_MODE` | Inverts the scan logic. **All functions are allowed** except the ones listed in the preset. Useful when you want to hunt specific forbidden calls rather than maintain a full whitelist. |
| `ALL_MLX` | Automatically ignores MiniLibX internal functions (equivalent to `-mlx`). |
| `ALL_MATH` | Automatically authorizes all standard `<math.h>` functions (`cos`, `sin`, `sqrt`, `pow`, etc.) and adds them to the authorized list (equivalent to `-lm`). |

**Example preset using flags:**

```text
# my_project.preset

BLACKLIST_MODE
ALL_MLX
ALL_MATH

# Functions that are FORBIDDEN in this project (blacklist):
system
execve
fork
```

When `BLACKLIST_MODE` is active, the list below the flags becomes a **blacklist** — ForbCheck will report any call to those functions, and allow everything else.

When no flag is set (default), the list is a **whitelist** — ForbCheck reports anything *not* in the list.

---

## Blacklist Mode

Blacklist Mode inverts ForbCheck's core logic:

- **Default (Whitelist):** All functions are **forbidden** unless listed in your preset.
- **Blacklist Mode:** All functions are **allowed** unless listed in your preset.

This is useful for projects where the restriction is narrow — e.g., "no `system()` or `execve()`" — rather than maintaining an exhaustive authorized list.

**Activate via CLI:**

```bash
forb -b -s
```

**Activate via preset flag** (persistent, no CLI flag needed):

```text
BLACKLIST_MODE

system
execve
```

Both methods work identically. The preset flag takes effect automatically when the preset is loaded.

---

## Exit Codes

| Code | Meaning |
| :--- | :--- |
| `0` | No forbidden functions detected |
| `1` | Forbidden functions detected or error occurred |

---

## Notes

- ForbCheck is an assistance tool, not a substitute for reading your project's subject carefully.
- Results depend on the state of your compiled binary. If your source is newer than your binary, ForbCheck will warn you to recompile.
- The `-s` deep scan operates on source files and is complementary to the binary analysis — both can catch different things.
- In Blacklist Mode, the source scan (`-s`) uses a dedicated engine that reports only functions matching your blacklist, with exact file and line locations.

---

## License

Open-source — intended for educational use.

## Author

[Mrdolls](https://github.com/Mrdolls) — 2025
