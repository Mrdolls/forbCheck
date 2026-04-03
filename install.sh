#!/bin/bash

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

INSTALL_DIR="$HOME/.forb"
BIN_DIR="$HOME/.local/bin"
REPO_RAW_URL="https://raw.githubusercontent.com/Mrdolls/forb/main"
LOG_FILE="$INSTALL_DIR/install.log"
log_action() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

echo -e "${BLUE}Downloading and Installing ForbCheck V1.9.93...${NC}"
mkdir -p "$INSTALL_DIR/presets"
mkdir -p "$BIN_DIR"
echo "=== ForbCheck Installation Log ===" > "$LOG_FILE"
log_action "Directories created."
echo -e "${YELLOW}Fetching core files from GitHub...${NC}"
log_action "Fetching forb.sh from GitHub..."
curl -sfL "$REPO_RAW_URL/forb.sh" -o "$INSTALL_DIR/forb.sh"

log_action "Fetching forb_completion.sh from GitHub..."
curl -sfL "$REPO_RAW_URL/forb_completion.sh" -o "$INSTALL_DIR/forb_completion.sh"

if [ ! -s "$INSTALL_DIR/forb.sh" ]; then
    echo -e "${RED}Error: Could not download forb.sh. Check your internet connection or GitHub repo name.${NC}"
    log_action "ERROR: Failed to download forb.sh. File is empty or missing."
    exit 1
fi
chmod +x "$INSTALL_DIR/forb.sh"
log_action "Core files downloaded and made executable."
ln -sf "$INSTALL_DIR/forb.sh" "$BIN_DIR/forb"
echo -e "${GREEN}[✔] Symlink created in $BIN_DIR/forb${NC}"
log_action "Symlink created at $BIN_DIR/forb."
sed -i '/alias forb=/d' "$HOME/.zshrc" "$HOME/.bashrc" 2>/dev/null
log_action "Old aliases cleaned up."
configure_shell() {
    local rc_file="$1"
    local is_zsh="$2"

    if [ -f "$rc_file" ]; then
        log_action "Configuring shell for $rc_file..."

        if ! grep -q "\.local/bin" "$rc_file"; then
            echo -e "\n# Add local bin to PATH" >> "$rc_file"
            echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$rc_file"
            log_action "Added $BIN_DIR to PATH in $rc_file."
        fi
        if [ -s "$INSTALL_DIR/forb_completion.sh" ]; then
            if ! grep -q "forb_completion.sh" "$rc_file"; then
                echo -e "\n# ForbCheck Autocompletion" >> "$rc_file"
                if [ "$is_zsh" = true ]; then
                    echo "autoload -U +X compinit && compinit" >> "$rc_file"
                    echo "autoload -U +X bashcompinit && bashcompinit" >> "$rc_file"
                fi
                echo "source $INSTALL_DIR/forb_completion.sh" >> "$rc_file"
                echo -e "${GREEN}[✔] Autocompletion added to $rc_file${NC}"
                log_action "Autocompletion configured in $rc_file."
            else
                echo -e "${BLUE}[ℹ] Autocompletion already configured in $rc_file${NC}"
                log_action "Autocompletion was already present in $rc_file."
            fi
        fi
    fi
}

configure_shell "$HOME/.zshrc" true
configure_shell "$HOME/.bashrc" false
echo -e "${YELLOW}Fetching default presets... (Logs in $LOG_FILE)${NC}"
log_action "Starting 'forb.sh -gp' to fetch presets..."
if yes | bash "$INSTALL_DIR/forb.sh" -gp >> "$LOG_FILE" 2>&1; then
    echo -e "${GREEN}[✔] Default presets fetched successfully!${NC}"
    log_action "Presets fetched successfully."
else
    echo -e "${RED}[✖] Error while fetching presets! Check $LOG_FILE for details.${NC}"
    log_action "ERROR: 'forb.sh -gp' failed. Check the output above."
    exit 1
fi

echo -e "\n${GREEN}Installation complete!${NC}"
echo -e "Please restart your terminal or run: ${YELLOW}exec zsh${NC} (or exec bash)"
log_action "Installation completed successfully."
