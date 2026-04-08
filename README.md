# ForbCheck

![Version](https://img.shields.io/badge/version-1.14.2-blue.svg)
![License](https://img.shields.io/badge/license-OSI-green.svg)
![Platform](https://img.shields.io/badge/platform-Linux%20%7C%20macOS-lightgrey.svg)

**ForbCheck** is a powerful utility that inspects your C/C++ binaries and source files to identify any unauthorized function calls.

---

## Key Features

| Precision | Velocity | Reporting |
| :--- | :--- | :--- |
| **Perl-Powered Source Scan** | **nm-Based Binary Check** | **Interactive HTML UI** |
| Strips comments and strings to pinpoint exact line numbers. | Instant symbol extraction for ultra-fast verification. | Export results to a modern, searchable web interface. |

---

## 📥 Installation

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/Mrdolls/forb/refs/heads/main/install.sh)"
```

## How to Use

### Basic Usage
The simplest way to use ForbCheck is to run it without arguments in your project root:
```bash
forb
```

### Advanced Modes

| Mode | Flag | Description |
| :--- | :--- | :--- |
| **Source Scan** | `-s` | Scans `.c` files directly (useful for source-only audits). |
| **Whitelist** | (Default) | Only functions in your preset are allowed. |
| **Blacklist** | `-b` | All functions are allowed EXCEPT those in your preset. |
| **Verbose** | `-v` | Displays code snippets for every violation. |

---

## Preset System
ForbCheck smartly loads `.preset` files from `~/.forb/presets/` by matching your directory name.

- **Edit current list**: `forb -e`
- **Create new preset**: `forb -cp`
- **List all presets**: `forb -lp`

---

## Documentation
Check out our guides for advanced integration and CI/CD setup:
- [English Documentation](doc/doc_en.md)
- [Documentation Française](doc/doc_fr.md)

---
*Created by [Mrdolls](https://github.com/Mrdolls) — 2026*
