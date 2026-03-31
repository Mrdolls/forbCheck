# ForbCheck (forb)

**ForbCheck** is a Bash CLI tool designed to analyze a compiled C executable or library and detect the usage of **forbidden functions**, closely matching how projects are evaluated at 42.

It relies on `nm` to inspect unresolved symbols and reports **exact source locations** where forbidden functions are used.

---

## Key Features

* **Deep Analysis:** Uses `nm` and object file scanning (`.o`) to distinguish between undefined symbols and your own internal functions. No more false positives from your own utils.
* **Smart Context Awareness:** Automatically detects external libraries like **MiniLibX** (`-mlx`) or **Math** (`-lm`) to avoid flagging allowed external calls.
* **Blazing Fast:** Optimized parallel scanning (`xargs -P4`). Runs in under **0.2s** on most projects.
* **Stale Binary Detection:** Smartly compares source code timestamps with your binary. If you forgot to `make re`, ForbCheck warns you that results might be outdated.
* **Precision Locator:** Pinpoints exactly where the forbidden function is called (file and line number).

---

## 🆕 What's New in v1.8.1

### Zero-Config Magic: Auto-Detect Binary & Auto-Preset & Auto-Detect libMath
Say goodbye to lengthy commands! With the new Auto-Detect features, ForbCheck becomes a 100% plug-and-play tool. If you run the script without specifying a target (by simply typing forb), the tool will figure out what to analyze on its own. It first intelligently parses your Makefile to extract the name of the final binary. If no Makefile is found, it automatically falls back to the most recently compiled executable in your directory.

But that's not all: once the target is identified, the new Auto-Preset system kicks in. ForbCheck will automatically search your local library for a matching preset (e.g., minishell.preset) and load it silently. You no longer need to manually pass the -P flag! (And don't worry, power users can always bypass this behavior using the new  `-np` / `--no-preset` flag to force the default list).


Libmath is now detected automatically (can be manually overridden with `--no-auto`).

This powerful combination allows you to launch a complete, accurate, and highly specific analysis of your project with a single keystroke. The ultimate user experience!


### The Ultimate Preset Management System
* **Create & Edit on the Fly:** Added the `-cp` (`--create-preset`) flag. Instantly generate a new preset and open it in your favorite editor (VS Code, Vim, Nano) without leaving the terminal.
* **Interactive Removal:** Clean up your workspace with `-rp` (`--remove-preset`). It safely lists your configurations and asks for confirmation before deleting anything.
* **Quick List & Access:** Use `-lp` (`--list-presets`) to view all your saved presets, or `-op` (`--open-presets`) to pop open the folder directly in your GUI.
* **Cross-OS Folder Opening:** The `-op` command natively supports Linux (`xdg-open`), macOS (`open`), and even Windows Subsystem for Linux (WSL via `explorer.exe`).
* **Restore Defaults:** Messed up your configuration or need the official ones? Use the new `-gp` (`--get-presets`) command to safely fetch the latest default presets directly from GitHub (includes a confirmation prompt before overwriting).

### Smart & Silent Auto-Updates
* **Lightning-Fast Checks:** ForbCheck now checks for new versions automatically before running an analysis. 
* **Zero Lag Guarantee:** Built with a strict 1-second network timeout, the check is silently bypassed so your workflow is never slowed down.

### UX Polish & CLI Experience
* **History-Safe Clear:** The terminal now intelligently clears the screen before displaying the final analysis, keeping the output perfectly readable *without* deleting your scrollback history. 
* **Bulletproof Argument Parsing:** Fixed an edge-case bug where chaining certain short options would confuse the parser. The CLI is now more robust than ever.
* **Under-the-Hood Refactoring:** Cleaned up the core routing logic (`-l` processing) for better maintainability and faster execution.

## Requirements

- `bash`
- `nm` (GNU binutils)
- `grep`, `awk`, `sed`
- `bc` (optional, for execution time display)

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

### Argument (Optionnal)

- `options`: flags (e.g. `-v`, Look at the `Options` section.)
- `target`: Executable or library to analyze

---

## Options

### General
| Option | Description |
|------|-------------|
| `-h`, `--help` | Display help message |
| `-l`, `--list` `[<funcs...>]` | Show default authorized functions list |
| `-e`, `--edit` | Edit default authorized functions list |

### Presets
| Option | Description |
|------|-------------|
| `-P`, `--preset` | Load the preset matching the target name |
| `-np`, `--no-preset` | Disable auto-preset and force default list |
| `-gp`, `--get-preset` | Restore default presets (overwrites matches) |
| `-cp`, `--create-preset` | Create and edit a new preset |
| `-lp`, `--list-presets` | Show all presets |
| `-op`, `--open-presets` | Open presets directory |
| `-rp`, `--remove-presets` | Delete an existing preset |

### Scan Options

| Option | Description |
|------|-------------|
| `-v`, `--verbose` | Show source code context |
| `-f <files...>` | Limit analysis to specific files |
| `-p`, `--full-path` | Show full paths |
| `-a`, `--all` | Show authorized functions during scan |

### Library Filters

| Option | Description |
|------|-------------|
| `-mlx` | Force ignore MiniLibX internal calls |
| `-lm` | Force Ignore Math library internal calls |
| `--no-auto` | Disable automatic library detection |

### Maintenance

| Option | Description |
|------|-------------|
| `-t`, `--time` | Show execution duration |
| `-up`, `--update` | Update ForbCheck |
| `--remove` | Uninstall ForbCheck |

---

## Examples

### Basic analysis:

<img width="593" height="309" alt="image" src="https://github.com/user-attachments/assets/948fb7b5-fe55-4e35-a31e-deca75f98725" />

### Basic analysis with forbidden fonction:

<img width="600" height="353" alt="image" src="https://github.com/user-attachments/assets/52db4fbe-7086-49ca-aa6a-a02d5421f5ed" />

### Basic analysis with verbose (`-v`):

<img width="601" height="354" alt="image" src="https://github.com/user-attachments/assets/1cc0e521-2e63-4a44-ae92-777c926480d7" />

Default Presets list:
<img width="1058" height="19" alt="image" src="https://github.com/user-attachments/assets/c801051f-ad40-44e6-8c5c-fc66197de399" />

---

## Default Authorized Functions

Default authorized functions list are defined in:

```text
$HOME/.forb/authorize.txt
```

Functions may be separated by new lines, spaces, or commas.

Quick edit:

```bash
forb -e
```

Example:

```text
read
write
malloc
free
```

or

```text
read, write, malloc, free
```

---

## Exit Codes

| Code | Meaning |
|----|---------|
| `0` | No forbidden functions detected |
| `1` | Forbidden functions detected or error occurred |

---

## Design Philosophy

ForbCheck is designed to be:

- Simple
- Readable
- Useful before project evaluations
- Explicit rather than permissive

It is an assistance tool, not a substitute for understanding project requirements.

---

## License

Open-source project intended for educational use.

---

## Author

Mrdolls - 2025














