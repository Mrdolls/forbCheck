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

## 🆕 What's New in v1.9.0

### The "Deep Scan" Engine (`-s` / `--scan-source`)
This is the major update of this version. ForbCheck now goes beyond binary analysis by auditing your **source code** directly.
- **Zero False Positives:** Built with a powerful Perl parser that cleans comments (`/* ... */`, `//`) and strings (`"..."`) before analysis. No more warnings for words inside a `printf` or a comment!
- **Function Shield:** Automatically extracts and whitelists all functions **you** defined in your project. It perfectly distinguishes between your `ft_printf` and a forbidden `printf`.
- **Line Mapping:** Provides the exact file name and line number for every forbidden call found.

### Smart Auto-Detection
ForbCheck is now smarter and faster at identifying your project:
- **Intelligent Matching:** Automatically loads the correct preset based on your folder name (e.g., `minishell-r` or `Minishell_v2` will both correctly load `minishell.preset`).
- **Case-Insensitive:** No more manual typing or case issues.
- **The "Red Button" (`--no-auto`):** A new flag to disable auto-detection and force the interactive selection menu. *Note: Must be placed before `-s`.*

### Unified Preset Architecture
- **Goodbye `authorize.txt`:** All configurations are now centralized in the `presets/` directory for a cleaner workspace.
- **`default.preset`:** Your personalized authorized list has been renamed to `default.preset` for better consistency.
- **Library Awareness:** Improved handling for **MiniLibX** and **Math Library** (including new math functions like `abs` and `labs`).

---

### Examples
```bash
# Auto-detect project and run source scan
forb -s

# Force manual selection and run source scan
forb --no-auto -s

# Check the help for all new options
forb -h
```

---

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

If the automatic detection doesn't work, here's the manual method:

<img width="592" height="324" alt="image" src="https://github.com/user-attachments/assets/1b27e860-130c-4a6a-82f6-f5d841f89cef" />

`-P` to use the preset to name cub3D, then `cub3D` to specify the executable name.

And if the lib detection doesn't work :

<img width="507" height="294" alt="image" src="https://github.com/user-attachments/assets/93459b4d-ae39-4784-ad50-33a3d8bb9b78" />

`-mlx` Force ignore MiniLibX internal calls
`-lm` Force ignore Math library internal calls

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














