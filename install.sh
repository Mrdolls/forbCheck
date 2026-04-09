#!/bin/bash

# ==============================================================================
#  ForbCheck - New Modular Installer
# ==============================================================================

GREEN='\033[0;32m'; BLUE='\033[0;34m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'

INSTALL_DIR="$HOME/.forb"
BIN_DIR="$INSTALL_DIR/bin"
LIB_DIR="$INSTALL_DIR/lib"
DOC_DIR="$INSTALL_DIR/doc"
PRESET_DIR="$INSTALL_DIR/presets"
REPO_RAW_URL="https://raw.githubusercontent.com/Mrdolls/forb/main"
LOG_FILE="$INSTALL_DIR/logs/install.log"

# 1. Initialization
mkdir -p "$LIB_DIR" "$DOC_DIR" "$PRESET_DIR" "$BIN_DIR"
echo "=== ForbCheck Installation Log - $(date) ===" > "$LOG_FILE"

log_action() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

echo -e "${BLUE}Starting modular installation...${NC}"

# 2. Download Core
log_action "Fetching main script..."
curl -sfL "$REPO_RAW_URL/forb.sh" -o "$INSTALL_DIR/forb.sh" >> "$LOG_FILE" 2>&1

if [ ! -s "$INSTALL_DIR/forb.sh" ]; then
    echo -e "${RED}Error: Could not download forb.sh. Check your internet connection.${NC}"
    log_action "ERROR: Failed to download forb.sh."
    exit 1
fi
chmod +x "$INSTALL_DIR/forb.sh"

# 3. Download Modules
log_action "Fetching modules..."
# Shell modules
SH_MODULES=("ui.sh" "utils.sh" "presets.sh" "scan.sh" "output_generator.sh" "maintenance.sh" "html_generator.sh" "forb_completion.sh" "test_suite.sh")
# Perl modules
PL_MODULES=("macro_engine.pl" "source_scan.pl" "symbol_filter"))

for mod in "${SH_MODULES[@]}" "${PL_MODULES[@]}"; do
    echo -ne "  Downloading $mod...\r"
    curl -sfL "$REPO_RAW_URL/lib/$mod" -o "$LIB_DIR/$mod" >> "$LOG_FILE" 2>&1
    if [ ! -s "$LIB_DIR/$mod" ]; then
        echo -e "${RED}\nError: Failed to download $mod.${NC}"
        log_action "ERROR: Failed to download $mod."
        exit 1
    fi
done
echo -e "${GREEN}  All modules downloaded successfully!      ${NC}"

# 4. Download Documentation
log_action "Fetching documentation..."
curl -sfL "$REPO_RAW_URL/doc/doc_fr.md" -o "$DOC_DIR/doc_fr.md" >> "$LOG_FILE" 2>&1
curl -sfL "$REPO_RAW_URL/doc/doc_en.md" -o "$DOC_DIR/doc_en.md" >> "$LOG_FILE" 2>&1

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
log_action "Fetching default presets..."
bash "$INSTALL_DIR/forb.sh" -gp <<EOF >> "$LOG_FILE" 2>&1
y
EOF

echo -e "\n${GREEN}Installation complete! (v1.14.0)${NC}"
echo -e "Documentation: ${CYAN}$DOC_DIR/doc_fr.md${NC}"
echo -e "Logs: ${YELLOW}$LOG_FILE${NC}"
echo -e "Please run: ${BLUE}source ~/.zshrc${NC} (or exec zsh/bash)"

log_action "Installation finished successfully."
