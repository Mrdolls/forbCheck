#!/bin/bash

# ==============================================================================
#  ForbCheck - New Modular Installer (Dynamic Version)
# ==============================================================================

# Colors Configuration
GREEN='\033[0;32m'; BLUE='\033[0;34m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; CYAN='\033[0;36m'; NC='\033[0m'
BOLD='\033[1m'

# Constants
INSTALL_DIR="$HOME/.forb"
BIN_DIR="$INSTALL_DIR/bin"
LIB_DIR="$INSTALL_DIR/lib"
DOC_DIR="$INSTALL_DIR/doc"
PRESET_DIR="$INSTALL_DIR/presets"
LOG_DIR="$INSTALL_DIR/logs"
REPO_URL="https://github.com/Mrdolls/forb"
ARCHIVE_URL="$REPO_URL/archive/refs/heads/main.tar.gz"

# Detect if running from local source (development mode)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/forb.sh" ] && [ -f "$SCRIPT_DIR/lib/analyse.sh" ]; then
    USE_LOCAL=true
    LOCAL_SOURCE="$SCRIPT_DIR"
else
    USE_LOCAL=false
fi

log_action() {
    [ -f "$LOG_FILE" ] && echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

# 1. Initialization
echo -e "${BLUE}${BOLD}Starting ForbCheck installation...${NC}"
mkdir -p "$LIB_DIR" "$DOC_DIR" "$PRESET_DIR" "$BIN_DIR" "$LOG_DIR"
LOG_FILE="$LOG_DIR/install.log"
echo "=== ForbCheck Installation Log - $(date) ===" > "$LOG_FILE"
log_action "USE_LOCAL=$USE_LOCAL"

# 2. Dependency Check (skip if using local source)
if [ "$USE_LOCAL" = false ]; then
    echo -ne "  Checking dependencies... "
    for cmd in curl tar perl nm; do
        if ! command -v "$cmd" &>/dev/null; then
            echo -e "${RED}\nError: '$cmd' is required but not installed.${NC}"
            exit 1
        fi
    done
    echo -e "${GREEN}OK!${NC}"
fi

# 3. Get source files (local or remote)
tmp_dir=""
if [ "$USE_LOCAL" = true ]; then
    echo -e "${CYAN}Installing from local source (development mode)${NC}"
    src_root="$LOCAL_SOURCE"
    log_action "Using local source: $src_root"
else
    log_action "Fetching project archive from $ARCHIVE_URL"
    echo -ne "  Downloading and extracting components... "
    tmp_dir=$(mktemp -d)
    if curl -sL "$ARCHIVE_URL" | tar -xz -C "$tmp_dir" >> "$LOG_FILE" 2>&1; then
        src_root="$tmp_dir/forb-main" # GitHub adds -main suffix
        [ ! -d "$src_root" ] && src_root="$tmp_dir/$(ls -1 "$tmp_dir" | head -n 1)" # Fallback to first dir
        
        if [ ! -d "$src_root" ]; then
            echo -e "${RED}\nError: Failed to find source directory in archive.${NC}"
            rm -rf "$tmp_dir"
            exit 1
        fi
        echo -e "${GREEN}OK!${NC}"
    else
        echo -e "${RED}\nFatal Error: Failed to download or extract archive.${NC}"
        rm -rf "$tmp_dir"
        exit 1
    fi
fi

# 4. Sync Components
log_action "Syncing files from: $src_root"

# Main Script
cp "$src_root/forb.sh" "$INSTALL_DIR/forb.sh"
chmod +x "$INSTALL_DIR/forb.sh"

# Extract Version from forb.sh
VERSION=$(grep -E "^(readonly )?VERSION=" "$INSTALL_DIR/forb.sh" | cut -d'"' -f2)

# Library Modules
echo -ne "  Installing modules... "
for f in "$src_root/lib/"*; do
    if [ -f "$f" ]; then
        cp "$f" "$LIB_DIR/$(basename "$f")"
        [[ "$f" == *.sh || "$f" == *.pl ]] && chmod +x "$LIB_DIR/$(basename "$f")"
    fi
done
echo -e "${GREEN}OK!${NC}"

# Documentation
echo -ne "  Installing documentation... "
for f in "$src_root/doc/"*; do
    [ -f "$f" ] && cp "$f" "$DOC_DIR/$(basename "$f")"
done
echo -e "${GREEN}OK!${NC}"

# 5. Setup Binary & Path
ln -sf "$INSTALL_DIR/forb.sh" "$BIN_DIR/forb"
log_action "Symlink created at $BIN_DIR/forb."

# Clean old aliases
if [[ "$OSTYPE" == "darwin"* ]]; then
    sed -i '' '/alias forb=/d' "$HOME/.zshrc" "$HOME/.bashrc" 2>/dev/null
else
    sed -i '/alias forb=/d' "$HOME/.zshrc" "$HOME/.bashrc" 2>/dev/null
fi

configure_shell() {
    local rc_file="$1"; local is_zsh="$2"
    [ ! -f "$rc_file" ] && return

    log_action "Configuring shell: $rc_file"
    # Path
    if ! grep -q "$BIN_DIR" "$rc_file"; then
        echo -e "\n# Add ForbCheck bin to PATH\nexport PATH=\"$BIN_DIR:\$PATH\"" >> "$rc_file"
    fi
    # Autocompletion
    if [ -s "$LIB_DIR/forb_completion.sh" ]; then
        if ! grep -q "forb_completion.sh" "$rc_file"; then
            echo -e "\n# ForbCheck Autocompletion" >> "$rc_file"
            if [ "$is_zsh" = true ]; then
                echo "autoload -U +X compinit && compinit" >> "$rc_file"
                echo "autoload -U +X bashcompinit && bashcompinit" >> "$rc_file"
            fi
            echo "source $LIB_DIR/forb_completion.sh" >> "$rc_file"
        fi
    fi
}

configure_shell "$HOME/.zshrc" true >> "$LOG_FILE" 2>&1
configure_shell "$HOME/.bashrc" false >> "$LOG_FILE" 2>&1

# 6. Finalize Presets
if [ "$USE_LOCAL" = true ]; then
    echo -e "  ${CYAN}Skipping preset sync (local install)${NC}"
    log_action "Skipped preset sync - local install"
else
    log_action "Fetching default presets..."
    echo -ne "  Synchronizing presets... "
    bash "$INSTALL_DIR/forb.sh" -gp <<EOF >> "$LOG_FILE" 2>&1
y
EOF
    echo -e "${GREEN}OK!${NC}"
fi

# Cleanup
rm -rf "$tmp_dir"

echo -e "\n${GREEN}${BOLD}Installation complete successfully! (v$VERSION)${NC}"
echo -e "Documentation: ${CYAN}$DOC_DIR/doc_fr.md${NC}"
echo -e "Logs: ${YELLOW}$LOG_FILE${NC}"
if [ "$USE_LOCAL" = true ]; then
    echo -e "${YELLOW}Installed from local source (development mode)${NC}"
fi
echo -e "Please run: ${BLUE}source ~/.zshrc${NC} (or exec zsh/bash)"

log_action "Installation finished successfully."
