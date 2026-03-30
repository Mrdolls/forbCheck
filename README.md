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

## 🆕 What's New in v1.6.3

### Bug Fixes & Stability
* **Auto-Initialization:** Fixed a bug where running `forb -l` on a fresh install would throw an error. ForbCheck now silently and safely generates its required configuration files (`authorize.txt`) if they are missing.

### Smarter False-Positive Filtering
* **Comment Ignoring:** ForbCheck is now smart enough to ignore forbidden keywords found in comments (e.g., `// TODO: remove printf`). It only flags code that actually compiles!

### Smart Sync & Cache
* **Desync Warning:** Modified your `.c` files but forgot to recompile? The tool now alerts you immediately to prevent testing against an old binary.
* **Undo-Friendly:** The intelligent cache tracks line counts and file sizes. If you undo changes (Ctrl+Z), the warning resolves itself automatically.

### Enhanced CLI Experience
* **Hybrid List Command:** Use `-l` to view all authorized functions, or `forb -l <func>` to quickly check the status of a specific one.
* **Global Awareness:** Seamlessly switch between projects (e.g., `minishell` -> `cub3d`). The tool updates its internal reference context instantly.
* **Cleaner Help:** A reorganized `--help` menu for better readability during those late-night coding sessions.
* **Optimized Performance:** Even on standard school lab machines, the overhead remains negligible, ensuring your workflow is never interrupted.

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

---

## Authorized Functions

Authorized functions are defined in:

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

Mrdolls














