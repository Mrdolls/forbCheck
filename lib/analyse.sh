#!/bin/bash

#  FORBCHECK ANALYSIS MODULE (v1.16.1)

start_analysis() {

    # On force la détection du projet avant de chercher le preset
    auto_detect_target >/dev/null 2>&1
    auto_detect_libraries >/dev/null 2>&1
    local files_list=""
    local target_bin="$TARGET"

    # 1. Déplacer le chargement du preset ICI, avant le 'find'
    resolve_preset "binary"
    load_preset "$SELECTED_PRESET"
    parse_preset_flags "$(cat "$ACTIVE_PRESET" 2>/dev/null)"
    export AUTH_FUNCS=$(echo "$AUTH_FUNCS" | tr '\n' ' ' | xargs)
    export BLACKLIST_MODE
    export USE_MLX

    # 2. Adapter la recherche de fichiers selon la présence de la MLX
    if [ -n "$SPECIFIC_FILES" ]; then
        for f in $SPECIFIC_FILES; do [ -f "$f" ] && files_list+="$f"$'\n'; done
    else
        if [ "$USE_MLX" = true ]; then
            # On ignore les dossiers contenant "mlx" ou "minilibx"
            files_list=$(find . -maxdepth 5 -type d \( -name "*mlx*" -o -name "*minilibx*" \) -prune -o -type f \( -name "*.c" -o -name "*.cpp" -o -name "*.h" -o -name "*.hpp" \) -print)
        else
            files_list=$(find . -maxdepth 5 -type f \( -name "*.c" -o -name "*.cpp" -o -name "*.h" -o -name "*.hpp" \))
        fi
    fi

    if [ -z "$files_list" ]; then
        log_info "${YELLOW}[Analyse] No source files found for analysis.${NC}"
        safe_exit 0
    fi

    local nb_files=$(echo "$files_list" | grep -c '^')
    log_info "${CYAN}${BOLD}Analyzing project...${NC}"

    # Charger le preset pour identifier les fonctions interdites
    resolve_preset "binary"
    load_preset "$SELECTED_PRESET"
    parse_preset_flags "$(cat "$ACTIVE_PRESET" 2>/dev/null)"
    # Ensure AUTH_FUNCS is on a single line (space separated) for Perl metadata extraction
    export AUTH_FUNCS=$(echo "$AUTH_FUNCS" | tr '\n' ' ' | xargs)
    export BLACKLIST_MODE

    # Appel du moteur d'extraction en Perl
    local data_file=$(mktemp)
    
    export TARGET_BIN="$target_bin"
    
    echo "$files_list" | perl "$INSTALL_DIR/lib/analyse_engine.pl" > "$data_file"
    
    if [ ! -s "$data_file" ]; then
        log_info "${RED}[Analyse] Error: Data extraction failed or no functions found.${NC}"
        rm -f "$data_file"
        safe_exit 1
    fi

    # Lancement du TUI Interactif
    perl "$INSTALL_DIR/lib/analyse_tui.pl" "$data_file"
    
    rm -f "$data_file"
    safe_exit 0
}
