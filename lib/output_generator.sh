#!/bin/bash

# ==============================================================================
#  FORBCHECK OUTPUT GENERATOR MODULE (JSON & Helpers)
# ==============================================================================

generate_json_output() {
    local count_val="$1" f_name safe_name first_func=true
    if [ -z "$count_val" ]; then
        if [ "$IS_SOURCE_SCAN" = true ]; then [ -n "$JSON_RAW_DATA" ] && count_val=$(echo "$JSON_RAW_DATA" | grep -c "MATCH")
        else [ -n "$forbidden_list" ] && count_val=$(echo "$forbidden_list" | wc -w); fi
    fi
    echo -n "{\"target\":\"$TARGET\",\"version\":\"$VERSION\",\"forbidden_count\":$count_val,\"mode\":\"$( [ "$BLACKLIST_MODE" = true ] && echo "blacklist" || echo "whitelist" )\",\"results\":["
    if [ "$IS_SOURCE_SCAN" = true ]; then
        local first_loc=true match_data=$(echo "$JSON_RAW_DATA" | grep "MATCH")
        while IFS= read -r line; do
            [ -z "$line" ] && continue; [ "$first_loc" = false ] && echo -n ","
            local fname=$(echo "$line" | perl -nle 'print $1 if /-> ([^|]+)/')
            local fpath=$(echo "$line" | perl -nle 'print $1 if /in (\S+?):/')
            local lnum=$(echo "$line"  | perl -nle 'print $1 if /:([0-9]+)$/')
            echo -n "{\"function\":\"$fname\",\"file\":\"$fpath\",\"line\":${lnum:-0}}"; first_loc=false
        done <<< "$match_data"
    else
        for f_name in $forbidden_list; do
            [ "$first_func" = false ] && echo -n ","
            echo -n "{\"function\":\"$f_name\",\"locations\":["
            safe_name=$(printf '%s\n' "$f_name" | sed 's/[.[\*^$]/\\&/g')
            local locations=$(grep -E ":.*\b${safe_name}\b" <<< "$grep_res")
            local first_loc=true
            while read -r line; do
                [ -z "$line" ] && continue; [ "$first_loc" = false ] && echo -n ","
                local f_path=$(echo "$line" | cut -d: -f1 | sed 's|^\./||'); local l_num=$(echo "$line" | cut -d: -f2)
                echo -n "{\"file\":\"$f_path\",\"line\":${l_num:-0}}"; first_loc=false
            done <<< "$locations"
            echo -n "]}"; first_func=false
        done
    fi
    echo -n "],\"status\":$( [ "$count_val" -eq 0 ] && echo "\"PERFECT\"" || echo "\"FAILURE\"" )}"
}

show_list() {
    local exit="${1:-1}" f; if [ ! -f "$ACTIVE_PRESET" ] || [ ! -s "$ACTIVE_PRESET" ]; then log_info "${YELLOW}No authorized functions list found.${NC}"; safe_exit 0; fi
    if [ $# -gt 1 ]; then
        shift; log_info "${BLUE}${BOLD}Checking functions:${NC}"
        for f in "$@"; do
            local found=false; grep -qFx "$f" <<< "$AUTH_FUNCS" && found=true
            if [ "$BLACKLIST_MODE" = true ]; then [ "$found" = true ] && log_info "   [${RED}KO${NC}] -> $f (Blacklisted)" || log_info "   [${GREEN}OK${NC}] -> $f"
            else [ "$found" = true ] && log_info "   [${GREEN}OK${NC}] -> $f" || log_info "   [${RED}KO${NC}] -> $f"; fi
        done
    else
        local m="Whitelist"; [ "$BLACKLIST_MODE" = true ] && m="Blacklist"
        log_info "${BLUE}${BOLD}Listed functions ($m):${NC} ${CYAN}(Use -e to edit)${NC}\n---------------------------------------"
        [ -n "$AUTH_FUNCS" ] && echo "$AUTH_FUNCS" | column || log_info "${YELLOW}(List is empty)${NC}"
    fi
    [ "$exit" -eq 1 ] && safe_exit 0
}

process_list() {
    local args=""; while [[ $# -gt 0 && ! $1 =~ ^- ]]; do args+="$1 "; shift; done
    resolve_preset "list"; load_preset "$SELECTED_PRESET"
    [ -L "$ACTIVE_PRESET" ] && { echo "Error: ACTIVE_PRESET is symlink"; safe_exit 1; }
    [ -f "$ACTIVE_PRESET" ] && parse_preset_flags "$(cat "$ACTIVE_PRESET" 2>/dev/null)"
    show_list 1 $args
}
