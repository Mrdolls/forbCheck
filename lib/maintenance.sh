#!/bin/bash

# ==============================================================================
#  FORBCHECK MAINTENANCE MODULE (Updates, Uninstall, Presets)
# ==============================================================================

get_presets() {
    local mode="$1"
    local choice added preset base_name tmp_dir
    if [[ "$mode" == "manual" ]]; then
        log_info "${YELLOW}${BOLD}Warning: This will download default presets. Overwrite existing? (y/n): ${NC}"
        read -r choice; case "$choice" in [yY][eE][sS]|[yY]) ;; *) log_info "${BLUE}Operation aborted.${NC}"; safe_exit 0 ;; esac
    fi
    log_info "${BLUE}Downloading default presets from GitHub...${NC}"
    mkdir -p "$PRESET_DIR"
    tmp_dir=$(mktemp -d)
    if curl -sfL "https://github.com/Mrdolls/forbCheck/archive/refs/heads/main.tar.gz" | tar -xz -C "$tmp_dir" "forbCheck-main/presets" 2>/dev/null; then
        if [[ "$mode" == "manual" ]]; then
            cp -r "$tmp_dir/forbCheck-main/presets/"* "$PRESET_DIR/" 2>/dev/null
            log_info "${GREEN}[✔] Default presets successfully restored!${NC}"
        else
            added=0; for preset in "$tmp_dir/forbCheck-main/presets/"*; do
                base_name=$(basename "$preset")
                if [ ! -f "$PRESET_DIR/$base_name" ]; then cp "$preset" "$PRESET_DIR/"; added=$((added + 1)); fi
            done
            [ $added -gt 0 ] && log_info "${GREEN}[✔] Added $added new preset(s) during update!${NC}" || log_info "${GREEN}[✔] Presets checked.${NC}"
        fi
        rm -rf "$tmp_dir"
    else log_info "${RED}[✘] Error: Failed to download presets.${NC}"; rm -rf "$tmp_dir"; fi
    [ "$mode" == "manual" ] && safe_exit 0
}

create_preset() {
    local p_name new_f; echo -ne "${BLUE}${BOLD}Enter the name of the new preset: ${NC}"; read -r p_name
    [ -z "$p_name" ] && { log_info "${RED}Error: Name cannot be empty.${NC}"; safe_exit 1; }
    p_name=$(echo "$p_name" | tr ' ' '-'); new_f="$PRESET_DIR/${p_name}.preset"
    mkdir -p "$PRESET_DIR"
    if [ -f "$new_f" ]; then log_info "${YELLOW}Preset already exists. Opening...${NC}"
    else log_info "${GREEN}Creating new preset '${p_name}'...${NC}"
        cat <<EOF > "$new_f"
# ForbCheck Preset: ${p_name}
# BLACKLIST_MODE, ALL_MLX, ALL_MATH
EOF
    fi
    open_editor "$new_f"; log_info "${GREEN}[✔] Preset '${p_name}' saved!${NC}"; safe_exit 0
}

remove_preset() {
    local p_name target confirm; list_presets 0
    echo -ne "\n${BLUE}${BOLD}Enter the name of the preset to remove: ${NC}"; read -r p_name
    [ -z "$p_name" ] || [ "$p_name" = "default" ] && { log_info "${RED}Error: Invalid name.${NC}"; safe_exit 1; }
    target="$PRESET_DIR/${p_name}.preset"; [ ! -f "$target" ] && { log_info "${RED}Error: Preset not found.${NC}"; safe_exit 1; }
    echo -ne "${YELLOW}Are you sure you want to delete '${p_name}'? (y/n): ${NC}"; read -r confirm
    case "$confirm" in [yY][eE][sS]|[yY]) rm -f "$target"; log_info "${GREEN}[✔] Preset removed.${NC}" ;; *) log_info "${BLUE}Deletion aborted.${NC}" ;; esac
    safe_exit 0
}

edit_list() { [ ! -f "$ACTIVE_PRESET" ] && touch "$ACTIVE_PRESET"; open_editor "$ACTIVE_PRESET"; safe_exit 0; }

update_script() {
    local tmp=$(mktemp) remote_v
    log_info "${BLUE}[Update] Checking latest version at ${CYAN}$UPDATE_URL${NC}..."
    if curl -sL "$UPDATE_URL" -o "$tmp"; then
        remote_v=$(grep -E "^(readonly )?VERSION=" "$tmp" | cut -d'"' -f2)
        if [ -z "$remote_v" ]; then log_info "${RED}[Update] Error: Parse failure.${NC}"; rm -f "$tmp"; return 1; fi
        log_info "${BLUE}[Update] Current: $VERSION | Remote: $remote_v"
        if [ "$(version_to_int "$remote_v")" -gt "$(version_to_int "$VERSION")" ]; then
            log_info "${YELLOW}[Update] New version detected!${NC}"
            local t_script=$(realpath "$0" 2>/dev/null || echo "$0")
            [ ! -w "$t_script" ] && { log_info "${RED}Error: No write permission.${NC}"; rm -f "$tmp"; return 1; }
            if mv "$tmp" "$t_script" && chmod +x "$t_script"; then
                log_info "${GREEN}[Update] Success!${NC}"; get_presets "auto"
                log_info "${GREEN}${BOLD}[Update] Updated to $remote_v!${NC}"; safe_exit 0
            else log_info "${RED}Fatal error during move.${NC}"; rm -f "$tmp"; return 1; fi
        else log_info "${GREEN}[Update] Already at latest version.${NC}"; rm -f "$tmp"; fi
    else log_info "${RED}[Update] Connection failure.${NC}"; rm -f "$tmp"; return 1; fi
    safe_exit 0
}

auto_check_update() {
    [ "$USE_JSON" = true ] || [ "$USE_HTML" = true ] && return
    local remote_v=$(curl -s --max-time 1 "$UPDATE_URL" | grep -E "^(readonly )?VERSION=" | head -n 1 | cut -d'"' -f2)
    if [ -n "$remote_v" ] && [ "$(version_to_int "$remote_v")" -gt "$(version_to_int "$VERSION")" ]; then
        echo -ne "${YELLOW}New version (v${remote_v}) available! Update now? (y/n): ${NC}"; read -r choice
        case "$choice" in [yY][eE][sS]|[yY]) update_script ;; *) log_info "${BLUE}Update skipped.${NC}\n" ;; esac
    fi
}

uninstall_script() {
    local choice; echo -ne "${RED}${BOLD}Warning: Uninstall ForbCheck? (y/n): ${NC}"; read -r choice
    case "$choice" in [yY][eE][sS]|[yY])
        log_info "${YELLOW}Uninstalling...${NC}"
        rm -f "$HOME/.local/bin/forb"
        local sed_cmd="sed -i"; [[ "$IS_MAC" == true ]] && sed_cmd="sed -i ''"
        $sed_cmd '/alias forb=/d; /# Autocompletion & ForbCheck/,/source ~\/.forb\/lib\/forb_completion\.sh/d; /# ForbCheck Autocompletion/d; /forb_completion\.sh/d' ~/.zshrc ~/.bashrc 2>/dev/null
        rm -rf "$HOME/.forb"; log_info "${GREEN}[✔] Uninstalled.${NC}"; safe_exit 0 ;;
    *) log_info "${BLUE}Aborted.${NC}"; safe_exit 0 ;; esac
}

check_dependencies() {
    local missing=0 deps=("nm" "perl" "curl" "tar")
    for cmd in "${deps[@]}"; do command -v "$cmd" &>/dev/null || { echo -e "${RED}[✘] Error: '${BOLD}$cmd${NC}${RED}' missing.${NC}"; missing=$((missing + 1)); } done
    command -v bc &>/dev/null || echo -e "${YELLOW}[!] Warning: 'bc' missing. Timer unavailable.${NC}"
    [ "$missing" -gt 0 ] && { echo -e "${YELLOW}Please install missing packages.${NC}"; safe_exit 1; }
}
