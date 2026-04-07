#!/bin/bash

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

INSTALL_DIR="$HOME/.forb"
BIN_DIR="$INSTALL_DIR/bin"
REPO_RAW_URL="https://raw.githubusercontent.com/Mrdolls/forb/main"
LOG_FILE="$INSTALL_DIR/install.log"

mkdir -p "$INSTALL_DIR"

log_action() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

echo "=== ForbCheck Installation Log ===" > "$LOG_FILE"
echo -e "${BLUE}Starting installation...${NC}"

mkdir -p "$INSTALL_DIR/presets" >> "$LOG_FILE" 2>&1
mkdir -p "$BIN_DIR" >> "$LOG_FILE" 2>&1
log_action "Directories created."

log_action "Fetching core files from GitHub..."
curl -sfL "$REPO_RAW_URL/forb.sh" -o "$INSTALL_DIR/forb.sh" >> "$LOG_FILE" 2>&1
curl -sfL "$REPO_RAW_URL/forb_completion.sh" -o "$INSTALL_DIR/forb_completion.sh" >> "$LOG_FILE" 2>&1
curl -sfL "$REPO_RAW_URL/html_generator.sh" -o "$INSTALL_DIR/html_generator.sh" >> "$LOG_FILE" 2>&1
curl -sfL "$REPO_RAW_URL/doc_fr.md" -o "$INSTALL_DIR/doc_fr.md" >> "$LOG_FILE" 2>&1

if [ ! -s "$INSTALL_DIR/forb.sh" ]; then
    echo -e "${RED}Error: Could not download forb.sh. Check your internet connection.${NC}"
    log_action "ERROR: Failed to download forb.sh."
    exit 1
fi

chmod +x "$INSTALL_DIR/forb.sh" >> "$LOG_FILE" 2>&1
log_action "Core files downloaded and made executable."

ln -sf "$INSTALL_DIR/forb.sh" "$BIN_DIR/forb" >> "$LOG_FILE" 2>&1
log_action "Symlink created at $BIN_DIR/forb."

if [[ "$OSTYPE" == "darwin"* ]]; then
    sed -i '' '/alias forb=/d' "$HOME/.zshrc" "$HOME/.bashrc" 2>/dev/null
else
    sed -i '/alias forb=/d' "$HOME/.zshrc" "$HOME/.bashrc" 2>/dev/null
fi
log_action "Old aliases cleaned up."

configure_shell() {
    local rc_file="$1"
    local is_zsh="$2"

    if [ -f "$rc_file" ]; then
        log_action "Configuring shell for $rc_file..."
        if ! grep -q "$BIN_DIR" "$rc_file"; then
            echo -e "\n# Add ForbCheck bin to PATH" >> "$rc_file"
            echo "export PATH=\"$BIN_DIR:\$PATH\"" >> "$rc_file"
        fi
        
        if [ -s "$INSTALL_DIR/forb_completion.sh" ]; then
            if ! grep -q "forb_completion.sh" "$rc_file"; then
                echo -e "\n# ForbCheck Autocompletion" >> "$rc_file"
                if [ "$is_zsh" = true ]; then
                    echo "autoload -U +X compinit && compinit" >> "$rc_file"
                    echo "autoload -U +X bashcompinit && bashcompinit" >> "$rc_file"
                fi
                echo "source $INSTALL_DIR/forb_completion.sh" >> "$rc_file"
            fi
        fi
        log_action "Shell configuration finished for $rc_file."
    fi
}

configure_shell "$HOME/.zshrc" true >> "$LOG_FILE" 2>&1
configure_shell "$HOME/.bashrc" false >> "$LOG_FILE" 2>&1

log_action "Starting 'forb.sh -gp' to fetch presets..."
if yes | bash "$INSTALL_DIR/forb.sh" -gp >> "$LOG_FILE" 2>&1; then
    log_action "Presets fetched successfully."
else
    echo -e "${RED}[✖] Error while fetching presets!${NC}"
    echo -e "Check $LOG_FILE for details."
    log_action "ERROR: 'forb.sh -gp' failed."
    exit 1
fi

echo -e "\n${GREEN}Installation complete!${NC}"
echo -e "For more info, see installation log here: ${YELLOW}$LOG_FILE${NC}"
echo -e "Please restart your terminal or run: ${BLUE}exec zsh${NC} (or exec bash)"

log_action "Installation completed successfully."
