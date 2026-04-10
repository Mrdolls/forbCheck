# ForbCheck

[![Version](https://img.shields.io/badge/version-1.16.1-00bcd4.svg)](https://github.com/Mrdolls/forbCheck)
[![Platform](https://img.shields.io/badge/platform-Linux%20%7C%20macOS-lightgrey.svg)](https://github.com/Mrdolls/forbCheck)

**ForbCheck** is a powerful security and audit utility for C/C++ projects. It ensures codebase integrity by detecting unauthorized function calls through three specialized analysis modes.

---

## Installation

To install or update ForbCheck, run the following command in your terminal:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/Mrdolls/forb/refs/heads/main/install.sh)"
```

---

## The Three Core Pillars

### 1. Binary Scan (NM-Based)
The default mode. It analyzes symbols extracted directly from your compiled binaries. This is the most reliable way to verify what is actually included in the final executable.

*   Instant execution speed.
*   Ideal for quick checks after compilation.
*   Detects dynamically linked libraries.

<!-- GIF: Binary Scan Demo -->
![binary-ezgif com-crop](https://github.com/user-attachments/assets/576733a9-3e36-48dd-a49c-5136877027c7)

### 2. Source Scan (`-s`)
This mode scans your source code (`.c`, `.cpp`, `.h`) directly. Essential for surgical audits during the development phase or when binaries are not yet available.

*   Pinpoint accuracy (filename and line number).
*   Smart stripping of comments and strings to eliminate false positives.
*   Recursive scanning across all project directories.

<!-- GIF: Source Scan Demo -->
![source-ezgif com-crop](https://github.com/user-attachments/assets/d9c59257-a7bb-44fd-9e46-af7d48ab7bb9)

### 3. Interactive Analysis Dashboard (`-A`)
New in v1.16.0. A high-performance Interactive TUI that maps your entire project structure.

*   **Classification**: Automatically separates internal project functions from external system calls.
*   **Deep Macro Scan**: Recursive analysis of `#define` to find hidden calls and Header Guards.
*   **Navigation**: Fluid Cyan/Green interface to explore symbols and their call contexts.

<!-- GIF: Analysis Dashboard Demo -->
![analyse](https://github.com/user-attachments/assets/5e3c49c7-d87c-487a-b651-737c4262649d)

---

## Quick Start

### Step 1: Standard Binary Scan
Analyze your compiled binary against the authorized function list.
```bash
forb
```

### Step 2: Deep Source Audit
Scan your `.c` files directly to find forbidden functions with exact line numbers.
```bash
forb -s
```

### Step 3: Architecture Exploration
Open the interactive dashboard to visualize your project's function and macro mapping.
```bash
forb -A
```

---

## Documentation & Configuration

For advanced settings, custom presets, and CI/CD integration, check our detailed guides:

*   [English Documentation](doc/doc_en.md)
*   [French Documentation](doc/doc_fr.md)

---
*Created by [Mrdolls](https://github.com/Mrdolls) — 2026*
