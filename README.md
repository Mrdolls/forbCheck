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

## 🆕 What's New in v1.7.4

### Auto Detect Binary !
Say goodbye to lengthy commands! With the new Auto Detect Binary feature, ForbCheck becomes a 100% plug-and-play tool. If you run the script without specifying a target (by simply typing forb), the tool can now figure out what it needs to analyze on its own. It will first intelligently parse your Makefile to extract the name of the final binary. If no Makefile is found, it will automatically fall back to the most recently compiled executable in your current directory. Coupled with the dynamic presets system, this addition allows you to launch a complete, accurate, and secure analysis of your project with a single keystroke. The ultimate user experience!


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
forb [options] <target> [-f <files...>]
```

### Argument

- `<target>`: Executable or library to analyze

---

## Options

### General
| Option | Description |
|------|-------------|
| `-h`, `--help` | Display help message |
| `-l`, `--list` `[<funcs...>]` | Show list or check specific functions |
| `-e`, `--edit` | Edit authorized functions list |

### Presets
| Option | Description |
|------|-------------|
| `-P`, `--preset` | Load the preset matching the target name |
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
| `--no-auto` | Disable automatic library detection |

### Library Filters

| Option | Description |
|------|-------------|
| `-mlx` | Force ignore MiniLibX internal calls |
| `-lm` | Force Ignore Math library internal calls |

### Maintenance

| Option | Description |
|------|-------------|
| `-t`, `--time` | Show execution duration |
| `-up`, `--update` | Update ForbCheck |
| `--remove` | Uninstall ForbCheck |

---

## Examples

### Basic analysis:

```bash
forb minishell (no forbidden fonctions)
```

<img width="405" height="173" alt="image" src="https://github.com/user-attachments/assets/0ee6b142-d969-4ca9-8f46-d16e9d606420" />


### Show execution time:

```bash
forb -t minishell (with forbidden fonctions)
```

<img width="532" height="320" alt="image" src="https://github.com/user-attachments/assets/383a258a-ce57-4c07-98f8-2e5d0cc2eac3" />


### Limit analysis to specific files:

```bash
forb minishell -f heredoc_utils.c
```

<img width="538" height="202" alt="image" src="https://github.com/user-attachments/assets/7ae6c24a-7452-45ee-aaaf-00f5ffdfcda4" />


### Verbose mode:

```bash
forb -v minishell
```
<img width="545" height="196" alt="image" src="https://github.com/user-attachments/assets/81af8b99-552e-47d7-92e0-83916e4a9bec" />

### Use Presets:
```bash
forb -P minishell
```
<img width="423" height="258" alt="image" src="https://github.com/user-attachments/assets/ee70ca08-524d-4d2e-9d7f-ef6a1964219a" />

Default Presets list:
<img width="1058" height="19" alt="image" src="https://github.com/user-attachments/assets/c801051f-ad40-44e6-8c5c-fc66197de399" />

---

## Default Authorized Functions

Default authorized functions are defined in:

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














