#!/bin/bash

# Configuration
RAW_URL="https://raw.githubusercontent.com/Mrdolls/forb/main/forb.sh"
INSTALL_DIR="$HOME/.forb"
BIN_PATH="$INSTALL_DIR/forb.sh"
COMPLETION_FILE="$INSTALL_DIR/forb_completion.sh"

C_BLUE='\033[0;34m'
C_GREEN='\033[0;32m'
C_RESET='\033[0m'

main() {
    clear
    echo -e "${C_BLUE}Starting ForbCheck Installation...${C_RESET}"
    
    mkdir -p "$INSTALL_DIR"
    echo -e "Downloading ForbCheck..."
    curl -sL "$RAW_URL" -o "$BIN_PATH"
    chmod +x "$BIN_PATH"
    
    cat << 'EOF' > "$COMPLETION_FILE"
_forb_completion() {
    local cur opts
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    opts="-v -f -p -a -t -up -e -l -mlx -lm --remove --no-auto -P -np -gp -cp -lp -op -rp"

    if [[ ${cur} == -* ]] ; then
        COMPREPLY=( $(compgen -W "${opts}" -- ${cur}) )
        return 0
    fi
}
complete -F _forb_completion forb
EOF

    CONFIG_FILES=("$HOME/.zshrc" "$HOME/.bashrc")
    CONFIG_UPDATED=0

    for config in "${CONFIG_FILES[@]}"; do
        if [ -f "$config" ]; then
            sed -i.bak '/# ForbCheck/d' "$config" 2>/dev/null
            sed -i.bak "/alias forb=/d" "$config" 2>/dev/null
            sed -i.bak "/forb_completion.sh/d" "$config" 2>/dev/null
            sed -i.bak "/bashcompinit/d" "$config" 2>/dev/null

            echo -e "\n# ForbCheck" >> "$config"
            echo "alias forb='bash $BIN_PATH'" >> "$config"

            if [[ "$config" == *".zshrc" ]]; then
                echo "autoload -U +X compinit && compinit" >> "$config"
                echo "autoload -U +X bashcompinit && bashcompinit" >> "$config"
            fi

            echo "source $COMPLETION_FILE" >> "$config"
            echo -e "${C_GREEN}✔ Added configuration to $config${C_RESET}"
            CONFIG_UPDATED=1
        fi
    done

    if [ "$CONFIG_UPDATED" -eq 0 ]; then
        echo -e "\n# ForbCheck" >> "$HOME/.profile"
        echo "alias forb='bash $BIN_PATH'" >> "$HOME/.profile"
        echo "source $COMPLETION_FILE" >> "$HOME/.profile"
        echo -e "${C_GREEN}✔ Added configuration to $HOME/.profile${C_RESET}"
    fi
    echo -e "\n${C_BLUE}Fetching default presets...${C_RESET}"
    yes | bash "$BIN_PATH" -gp > /dev/null 2>&1
    echo -e "\n${C_GREEN}✔ ForbCheck installed successfully!${C_RESET}"
    echo -e "${C_BLUE}Please restart your terminal or run:${C_RESET}"
    echo -e "  source ~/.zshrc  (if using Zsh)"
    echo -e "  source ~/.bashrc (if using Bash)"
}

main
