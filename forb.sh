#!/bin/bash

# ==============================================================================
#  SECTION 1: GLOBAL CONFIGURATION & COLORS
# ==============================================================================

if [[ -t 1 ]]; then
    BOLD="\033[1m"; GREEN="\033[0;32m"; RED="\033[0;31m"; YELLOW="\033[0;33m"; BLUE="\033[0;34m"; CYAN="\033[0;36m"; NC="\033[0m"
else
    BOLD=""; GREEN=""; RED=""; YELLOW=""; BLUE=""; CYAN=""; NC=""
fi

# Constants
readonly VERSION="1.12.0"
readonly INSTALL_DIR="$HOME/.forb"
readonly LOG_DIR="$HOME/.forb/logs"
readonly PRESET_DIR="$INSTALL_DIR/presets"
readonly UPDATE_URL="https://raw.githubusercontent.com/Mrdolls/forb/refs/heads/main/install.sh"

# Global State Variables (Mutable)
ACTIVE_PRESET="$PRESET_DIR/default.preset"
LOG_FILE=""
USE_JSON=false
USE_HTML=false
USE_PRESET=0
SHOW_ALL=false
USE_MLX=false
USE_MATH=false
BLACKLIST_MODE=false
FULL_PATH=false
VERBOSE=false
TARGET=""
SPECIFIC_FILES=""
SHOW_TIME=false
DISABLE_AUTO=false
DISABLE_PRESET=false
SET_WARNING=false
PUT_LOG=false

SHOW_HELP=false
SHOW_VERSION=false
DO_UPDATE=false
DO_REMOVE=false
DO_GET_PRESETS=false
DO_LIST_PRESETS=false
DO_OPEN_PRESETS=false
DO_OPEN_HTML=false
DO_CREATE_PRESET=false
DO_REMOVE_PRESET=false
DO_EDIT_LIST=false
RUN_LIST=false
LIST_FUNCS=""

# Détection OS
if [[ "$OSTYPE" == "darwin"* ]]; then
    readonly IS_MAC=true
else
    readonly IS_MAC=false
fi

# Load external modules
[ -f "$INSTALL_DIR/html_generator.sh" ] && source "$INSTALL_DIR/html_generator.sh"

# ==============================================================================
#  SECTION 2: UTILITY FUNCTIONS (Low-level helpers)
# ==============================================================================

safe_exit() {
    local exit_code=${1:-0}
    if [ "$PUT_LOG" = true ] && [ -n "$LOG_FILE" ] && [ "$USE_JSON" = false ]; then
        echo -e "\n${BLUE}ℹ Scan log saved to: ${YELLOW}$LOG_FILE${NC}"
    fi

    exit "$exit_code"
}

log_info() {
    if [ "$USE_JSON" != true ] && [ "$USE_HTML" != true ]; then
        if [ "$PUT_LOG" = true ] && [ -n "$LOG_FILE" ]; then
            echo -e "$@" | sed 's/\x1b\[[0-9;]*m//g' >> "$LOG_FILE"
        else
            echo -e "$@"
        fi
    fi
}

version_to_int() {
    echo "$1" | sed 's/v//' | awk -F. '{ printf("%d%03d%03d\n", $1,$2,$3); }'
}

crop_line() {
    local func="$1"
    local code="$2"
    local display_code="$code"

    if [ ${#code} -gt 65 ]; then
        local prefix="${code%%$func*}"
        local pos=${#prefix}
        local start=$((pos > 20 ? pos - 20 : 0))
        display_code="...${code:$start:100}..."
    fi

    local final_code="${display_code//$func/$RED$BOLD$func$NC$CYAN}"

    echo -e "$final_code"
}

clean_code_snippet() {
    local snippet="$1"
    local f_name="$2"
    local safe_name=$(printf '%s\n' "$f_name" | sed 's/[.[\*^$]/\\&/g')

    snippet=$(echo "$snippet" | sed 's|//.*||')
    snippet=$(echo "$snippet" | sed 's|/\*.*\*/||g')

    if echo "$snippet" | grep -qE "\b${safe_name}\b"; then
        echo "$snippet"
        return 0
    else
        return 1
    fi
}

generate_json_output() {
    local f_name safe_name first_func=true
    local count_val=0

    if [ "$IS_SOURCE_SCAN" = true ]; then
        [ -n "$JSON_RAW_DATA" ] && count_val=$(echo "$JSON_RAW_DATA" | grep -c "MATCH")
    else
        [ -n "$forbidden_list" ] && count_val=$(echo "$forbidden_list" | wc -w)
    fi

    echo -n "{"
    echo -n "\"target\":\"$TARGET\","
    echo -n "\"version\":\"$VERSION\","
    echo -n "\"forbidden_count\":$count_val,"
    echo -n "\"mode\":\"$( [ "$BLACKLIST_MODE" = true ] && echo "blacklist" || echo "whitelist" )\","
    echo -n "\"results\":["

    if [ "$IS_SOURCE_SCAN" = true ]; then
        local first_loc=true
        local match_data=$(echo "$JSON_RAW_DATA" | grep "MATCH")
        while IFS= read -r line; do
            [ -z "$line" ] && continue
            [ "$first_loc" = false ] && echo -n ","

            local fname=$(echo "$line" | perl -nle 'print $1 if /-> ([^|]+)/')
            local fpath=$(echo "$line" | perl -nle 'print $1 if /in (\S+?):/')
            local lnum=$(echo "$line"  | perl -nle 'print $1 if /:([0-9]+)$/')
            lnum=${lnum:-0}

            echo -n "{\"function\":\"$fname\",\"file\":\"$fpath\",\"line\":$lnum}"
            first_loc=false
        done <<< "$match_data"
    else
        for f_name in $forbidden_list; do
            [ "$first_func" = false ] && echo -n ","
            echo -n "{\"function\":\"$f_name\",\"locations\":["

            safe_name=$(printf '%s\n' "$f_name" | sed 's/[.[\*^$]/\\&/g')
            local locations=$(grep -E ":.*\b${safe_name}\b" <<< "$grep_res")
            local first_loc=true

            while read -r line; do
                [ -z "$line" ] && continue
                [ "$first_loc" = false ] && echo -n ","

                local f_path=$(echo "$line" | cut -d: -f1 | sed 's|^\./||')
                local l_num=$(echo "$line" | cut -d: -f2)
                l_num=${l_num:-0}

                echo -n "{\"file\":\"$f_path\",\"line\":$l_num}"
                first_loc=false
            done <<< "$locations"
            echo -n "]}"
            first_func=false
        done
    fi

    echo -n "],"
    echo -n "\"status\":$( [ "$count_val" -eq 0 ] && echo "\"PERFECT\"" || echo "\"FAILURE\"" )"
    echo "}"
}



open_editor() {
    local target_file="$1"

    if command -v code &>/dev/null; then
        code -r "$target_file"
    else
        vim "$target_file" || nano "$target_file"
    fi
}

# ==============================================================================
#  SECTION 3: PRESET MANAGEMENT
# ==============================================================================

prompt_preset_menu() {
    [ "$DISABLE_AUTO" == "true" ] && log_info "\n${YELLOW}${BOLD}Auto-detection disabled by --no-auto flag.${NC}"
    log_info "${CYAN}${BOLD}Select a project preset:${NC}"

    if [ ! -f "$PRESET_DIR/default.preset" ]; then
        mkdir -p "$PRESET_DIR"
        touch "$PRESET_DIR/default.preset"
    fi

    local presets=($(ls "$PRESET_DIR" 2>/dev/null | grep '\.preset$' | sed 's/\.preset//'))
    if [ -t 0 ] || [ -c /dev/tty ]; then
        exec 3<&0
        exec 0</dev/tty

        PS3=$'\n\033[1;36mEnter the number of your preset: \033[0m'
        select choice in "${presets[@]}"; do
            if [ -n "$choice" ]; then
                export SELECTED_PRESET="$choice"
                log_info "${GREEN}Loaded preset: ${BOLD}$SELECTED_PRESET${NC}"
                break
            else
                log_info "${RED}Invalid selection. Please enter a valid number.${NC}"
            fi
        done
        exec 0<&3
        exec 3<&-
    else
        log_info "${RED}Error: Non-interactive environment detected. Please explicitly provide a preset (e.g., using -P or matching folder name).${NC}"
        safe_exit 1
    fi

    if [ -z "$SELECTED_PRESET" ]; then
         log_info "${RED}Error: Preset selection aborted.${NC}"
         safe_exit 1
    fi
}

auto_find_preset() {
    local target_name_lower="$1"
    local preset_file base_name base_name_lower

    for preset_file in "$PRESET_DIR"/*.preset; do
        [ -e "$preset_file" ] || continue
        base_name=$(basename "$preset_file" .preset)
        base_name_lower=$(echo "$base_name" | tr '[:upper:]' '[:lower:]')

        if [[ "$target_name_lower" == *"$base_name_lower"* ]]; then
            export SELECTED_PRESET="$base_name"
            log_info "${CYAN}[Auto-Detect] Preset : ${BOLD}${base_name}${NC}"
            return 0
        fi
    done
    if find . -maxdepth 3 -type f \( -name "*.cpp" -o -name "*.hpp" -o -name "*.cc" \) -print -quit | grep -q "."; then
        if [ -f "$PRESET_DIR/cpp.preset" ]; then
            log_info "${CYAN}[Auto-Detect] Preset : ${BOLD}cpp${NC} (C++ detected)"
            export SELECTED_PRESET="cpp"
            return 0
        fi
    fi
    return 1
}

resolve_preset() {
    local mode="$1"
    local project_name project_name_lower

    if [ "$DISABLE_PRESET" = true ]; then
        export SELECTED_PRESET="default"
        return 0
    fi

    project_name=$([ -n "$TARGET" ] && basename "$TARGET" || basename "$PWD")

    if [ "$USE_PRESET" -eq 1 ]; then
     prompt_preset_menu
        return 0
    fi
    if [ "$DISABLE_AUTO" = "true" ] && { [ "$USE_JSON" = true ] || [ "$USE_HTML" = true ]; }; then
        export SELECTED_PRESET="default"
        return 0
    fi

    if [ -z "$SELECTED_PRESET" ] && [ -n "$project_name" ]; then
        if [ -f "$PRESET_DIR/${project_name}.preset" ]; then
            export SELECTED_PRESET="$project_name"
            [ "$DISABLE_AUTO" != "true" ] && log_info "${CYAN}[Auto-Detect] Preset : ${BOLD}${project_name}${NC} (Exact match)"
            return 0
        fi
    fi

    if [ "$DISABLE_AUTO" != "true" ] && [ -z "$SELECTED_PRESET" ]; then
        project_name_lower=$(echo "$project_name" | tr '[:upper:]' '[:lower:]')
        auto_find_preset "$project_name_lower"
    fi
    [ -n "$SELECTED_PRESET" ] && return 0

    if [ "$DO_EDIT_LIST" = true ]; then
        prompt_preset_menu
        return 0
    fi
    if [ "$RUN_LIST" = true ]; then
        export SELECTED_PRESET="default"
        return 0
    fi

    if [ "$USE_JSON" = true ] || [ "$USE_HTML" = true ] || [ "$mode" == "binary" ]; then
        export SELECTED_PRESET="default"
        return 0
    fi
    prompt_preset_menu
}

load_preset() {
    local target_name="$1"
    local available_presets

    ACTIVE_PRESET="$PRESET_DIR/${target_name}.preset"

    if [ "$target_name" = "default" ] && [ ! -f "$ACTIVE_PRESET" ]; then
        touch "$ACTIVE_PRESET"
    fi

    if [ ! -f "$ACTIVE_PRESET" ]; then
        available_presets=$(find "$PRESET_DIR" -maxdepth 1 -name "*.preset" -exec basename {} .preset \; | tr '\n' ',' | sed 's/,/, /g' | sed 's/, $//')

        if [ "$USE_JSON" = true ]; then
            log_info "{\"target\":\"$TARGET\",\"version\":\"$VERSION\",\"error\":\"No preset found for '${target_name}'\",\"status\":\"FAILURE\"}"
        else
            log_info "\033[31mError: No preset found for '${target_name}'.\033[0m"
            if [ -z "$available_presets" ]; then
                log_info "\033[33mNo presets available.\033[0m"
            else
                log_info "Available presets: \033[36m$available_presets\033[0m"
            fi
        fi
        safe_exit 1
    fi
}

list_presets() {
    local should_exit="${1:-1}"
    local available_presets

    available_presets=$(find "$PRESET_DIR" -maxdepth 1 -name "*.preset" -exec basename {} .preset \; | tr '\n' ',' | sed 's/,/, /g' | sed 's/, $//')

    if [ -z "$available_presets" ]; then
        log_info "\033[33mNo presets available in $PRESET_DIR\033[0m"
    else
        log_info "Available presets: \033[36m$available_presets\033[0m"
    fi

    [ "$should_exit" -eq 1 ] && safe_exit 0
}

get_presets() {
    local mode="$1"
    local choice added preset base_name tmp_dir

    if [[ "$mode" == "manual" ]]; then
        log_info "${YELLOW}${BOLD}Warning: This will download default presets. Any existing preset with the same name will be overwritten. Continue? (y/n): ${NC}"
        read -r choice
        case "$choice" in
            [yY][eE][sS]|[yY]) ;;
            *) log_info "${BLUE}Operation aborted.${NC}"; safe_exit 0 ;;
        esac
    fi
    log_info "${BLUE}Downloading default presets from GitHub...${NC}"
    tmp_dir=$(mktemp -d)

    if curl -sfL "https://github.com/Mrdolls/forbCheck/archive/refs/heads/main.tar.gz" | tar -xz -C "$tmp_dir" "forbCheck-main/presets" 2>/dev/null; then
        if [[ "$mode" == "manual" ]]; then
            cp -r "$tmp_dir/forbCheck-main/presets/"* "$PRESET_DIR/" 2>/dev/null
            log_info "${GREEN}[✔] Default presets successfully restored!${NC}"
        else
            added=0
            for preset in "$tmp_dir/forbCheck-main/presets/"*; do
                base_name=$(basename "$preset")
                if [ ! -f "$PRESET_DIR/$base_name" ]; then
                    cp "$preset" "$PRESET_DIR/"
                    added=$((added + 1))
                fi
            done

            if [ $added -gt 0 ]; then
                log_info "${GREEN}[✔] Added $added new preset(s) during update!${NC}"
            else
                log_info "${GREEN}[✔] Presets checked (no user modifications overwritten).${NC}"
            fi
        fi
        rm -rf "$tmp_dir"
    else
        log_info "${RED}[✘] Error: Failed to download presets. Check your connection or GitHub URL.${NC}"
        rm -rf "$tmp_dir"
    fi

    [ "$mode" == "manual" ] && safe_exit 0
}

open_presets() {
    log_info "\033[32mOpening presets directory: $PRESET_DIR\033[0m"

    if command -v explorer.exe > /dev/null; then
        (cd "$PRESET_DIR" && explorer.exe .)
    elif command -v xdg-open > /dev/null; then
        xdg-open "$PRESET_DIR"
    elif command -v open > /dev/null; then
        open "$PRESET_DIR"
    else
        log_info "\033[31mError: Could not open the folder automatically. You can find it at: $PRESET_DIR\033[0m"
    fi
    safe_exit 0
}

open_html() {
    local html_dir="$INSTALL_DIR/reports_html"
    mkdir -p "$html_dir"

    log_info "\033[32mOpening HTML reports directory: $html_dir\033[0m"

    if command -v explorer.exe > /dev/null; then
        (cd "$html_dir" && explorer.exe .)
    elif command -v xdg-open > /dev/null; then
        xdg-open "$html_dir"
    elif command -v open > /dev/null; then
        open "$html_dir"
    else
        log_info "\033[31mError: Could not open the folder automatically. You can find it at: $html_dir\033[0m"
    fi
    safe_exit 0
}

get_preset_template() {
    local preset_name="$1"

    cat <<EOF
# ==============================================================================
# ForbCheck Preset: ${preset_name}
# ==============================================================================
#
# AVAILABLE FLAGS (Add them anywhere in this file to activate):
# -------------------------------------------------------------
# BLACKLIST_MODE : Inverts the logic. ALL functions are allowed EXCEPT the ones listed below.
# ALL_MLX     : Automatically ignores MiniLibX internal functions.
# ALL_MATH    : Automatically authorizes standard <math.h> functions (cos, sin, etc.).
#
# ==============================================================================
# Add your functions below (one per line or space/comma separated):

EOF
}

create_preset() {
    local preset_name new_file

    echo -ne "${BLUE}${BOLD}Enter the name of the new preset (e.g., minishell): ${NC}"
    read -r preset_name

    if [ -z "$preset_name" ]; then
        log_info "${RED}Error: Preset name cannot be empty.${NC}"
        safe_exit 1
    fi

    preset_name=$(echo "$preset_name" | tr ' ' '-')
    new_file="$PRESET_DIR/${preset_name}.preset"

    if [ -f "$new_file" ]; then
        log_info "${YELLOW}Preset '${preset_name}' already exists. Opening it for edition...${NC}"
    else
        log_info "${GREEN}Creating new preset '${preset_name}'...${NC}"
        get_preset_template "$preset_name" > "$new_file"
        touch "$new_file"
    fi

    open_editor "$new_file"
    log_info "${GREEN}[✔] Preset '${preset_name}' saved!${NC}"
    safe_exit 0
}

remove_preset() {
    local preset_name target_file confirm
    list_presets 0

    echo -ne "\n${BLUE}${BOLD}Enter the name of the preset to remove: ${NC}"
    read -r preset_name

    if [ -z "$preset_name" ]; then
        log_info "${RED}Error: Preset name cannot be empty.${NC}"
        safe_exit 1
    fi

    if [ "$preset_name" = "default" ]; then
        log_info "${RED}Error: The 'default' preset is a core file and cannot be removed.${NC}"
        safe_exit 1
    fi

    target_file="$PRESET_DIR/${preset_name}.preset"
    if [ ! -f "$target_file" ]; then
        log_info "${RED}Error: Preset '${preset_name}' does not exist.${NC}"
        safe_exit 1
    fi

    echo -ne "${YELLOW}Are you sure you want to delete '${preset_name}'? (y/n): ${NC}"
    read -r confirm
    case "$confirm" in
        [yY][eE][sS]|[yY])
            rm -f "$target_file"
            log_info "${GREEN}[✔] Preset '${preset_name}' has been removed.${NC}"
            ;;
        *)
            log_info "${BLUE}Deletion aborted.${NC}"
            ;;
    esac
    safe_exit 0
}

edit_list() {
    [ ! -f "$ACTIVE_PRESET" ] && touch "$ACTIVE_PRESET"
    open_editor "$ACTIVE_PRESET"

    safe_exit 0
}

show_list() {
    local should_exit="${1:-1}"
    local f

    if [ ! -f "$ACTIVE_PRESET" ] || [ ! -s "$ACTIVE_PRESET" ]; then
        log_info "${YELLOW}No authorized functions list found. (Use -e to create one)${NC}"
        safe_exit 0
    fi

    if [ $# -gt 1 ]; then
        shift
        log_info "${BLUE}${BOLD}Checking functions:${NC}"
        for f in "$@"; do
            local is_listed=false
            grep -qFx "$f" <<< "$AUTH_FUNCS" && is_listed=true
            if [ "$BLACKLIST_MODE" = true ]; then
                if [ "$is_listed" = true ]; then
                    log_info "   [${RED}KO${NC}] -> $f (Blacklisted)"
                else
                    log_info "   [${GREEN}OK${NC}] -> $f"
                fi
            else
                if [ "$is_listed" = true ]; then
                    log_info "   [${GREEN}OK${NC}] -> $f"
                else
                    log_info "   [${RED}KO${NC}] -> $f"
                fi
            fi
        done
    else
        local mode_text="Whitelist"
        [ "$BLACKLIST_MODE" = true ] && mode_text="Blacklist"

        log_info "${BLUE}${BOLD}Listed functions ($mode_text):${NC} ${CYAN}(Use -e to edit)${NC}"
        log_info "---------------------------------------"
        if [ -n "$AUTH_FUNCS" ]; then
            echo "$AUTH_FUNCS" | column
        else
            log_info "${YELLOW}(List is empty)${NC}"
        fi
    fi

    [ "$should_exit" -eq 1 ] && safe_exit 0
}

process_list() {
    local check_args=""

    while [[ $# -gt 0 && ! $1 =~ ^- ]]; do
        check_args+="$1 "
        shift
    done
    resolve_preset "list"
    load_preset "$SELECTED_PRESET"

    if [ -L "$ACTIVE_PRESET" ]; then
        echo "Error: ACTIVE_PRESET must be a regular file, not a symlink"
        safe_exit 1
    fi

    if [ -f "$ACTIVE_PRESET" ]; then
        local raw_preset=$(cat "$ACTIVE_PRESET" 2>/dev/null)
        parse_preset_flags "$raw_preset"
    fi

    show_list 1 $check_args
}

# ==============================================================================
#  SECTION 4: CORE ENGINE - SCAN & DETECT
# ==============================================================================

auto_detect_libraries() {
    [ "$DISABLE_AUTO" = true ] && return
    [ "$USE_MLX" = true ] && return

    if find . -maxdepth 5 -type d \( -name "*mlx*" -o -name "*minilibx*" \) -print -quit | grep -q . || [ -f "libmlx.a" ] || \
        nm "$TARGET" 2>/dev/null | grep -qiE "mlx_"; then
        USE_MLX=true
        log_info "${CYAN}[Auto-Detect] MiniLibX detected (Use --no-auto to scan everything)${NC}"
    fi

    if [ "$USE_MATH" = false ] && [ -n "$TARGET" ]; then
        if grep -qE "\-lm\b" Makefile 2>/dev/null || \
           nm -u "$TARGET" 2>/dev/null | grep -qE "\b(sin|cos|sqrt|pow|exp|atan2)f?\b"; then
            USE_MATH=true
            log_info "${CYAN}[Auto-Detect] Math library detected (Use --no-auto to scan everything)${NC}"
        fi
    fi
}

auto_detect_target() {
    local make_target fallback_targets fallback_target

    # 1. Try to detect via Makefile
    if [ -f "Makefile" ]; then
        make_target=$(grep -m 1 -E "^NAME[[:space:]]*=" Makefile | cut -d '=' -f2 | tr -d ' ' | tr -d '"' | tr -d "'")
        if [ -n "$make_target" ] && [ -f "$make_target" ] && nm "$make_target" &>/dev/null; then
            export AUTO_BIN_DETECTED=true
            TARGET="$make_target"
            log_info "${CYAN}[Auto-Detect] Binary : ${BOLD}$TARGET${NC} (via Makefile)"
            return 0
        fi
    fi

    # 2. Try to detect via recent executable files
    if [ "$IS_MAC" = true ]; then
        fallback_targets=$(find . -maxdepth 1 -type f -perm +111 ! -name "*.sh" ! -name ".*" -exec stat -f "%m %N" {} + | sort -rn | cut -d' ' -f2- | sed 's|^\./||')
    else
        fallback_targets=$(find . -maxdepth 1 -type f -executable ! -name "*.sh" ! -name ".*" -printf '%T@ %p\n' 2>/dev/null | sort -nr | cut -d' ' -f2 | sed 's|^\./||')
    fi

    for fallback_target in $fallback_targets; do
        if [ -n "$fallback_target" ] && [ -f "$fallback_target" ] && nm "$fallback_target" &>/dev/null; then
            export AUTO_BIN_DETECTED=true
            TARGET="$fallback_target"
            log_info "${CYAN}[Auto-Detect] Binary : ${BOLD}$TARGET${NC} (via file search)"
            return 0
        fi
    done

    return 1
}

get_user_defined_funcs() {
    local files=$(find . -maxdepth 5 -type f \( -name "*.c" -o -name "*.cpp" -o -name "*.h" \))
    [ -z "$files" ] && return

    echo "$files" | tr '\n' '\0' | xargs -0 perl -e '
        my %shield;
        local $/ = undef;
        my $types = qr/(?:int|char|float|double|long|short|unsigned|signed|void|size_t|ssize_t|pid_t|sig_atomic_t|bool|t_\w+|struct\s+\w+|enum\s+\w+|FILE|DIR)/;

        foreach my $file (@ARGV) {
            open(my $fh, "<", $file) or next;
            my $content = <$fh>; close($fh);

            $content =~ s/\/\*.*?\*\//\n/gs;
            $content =~ s/\/\/.*//g;
            $content =~ s/"(?:\\.|[^"\\])*"|\x27(?:\\.|[^\x27\\])*\x27/ /gs;

            my $skeleton = $content;
            while ($skeleton =~ s/\{[^{}]*\}/;\n/g) {}

            foreach my $line (split /\n/, $skeleton) {
                next if $line =~ /^\s*$/;
                if ($line =~ /^(.*?)(\b[a-zA-Z_]\w*\b)(\s*\(.*)$/) {
                    my $avant = $1;
                    my $mot = $2;

                    if ($avant =~ /^[\s\w\*]+$/ && $avant =~ /\b(?:$types|static|extern)\b|\*/) {
                        $shield{$mot} = 1;
                    }
                }
            }
        }

        my $kw = qr/^(if|while|for|return|else|switch|case|default|do|sizeof)$/;
        foreach my $k (sort keys %shield) { print "$k " unless $k =~ $kw; }
    ' 2>/dev/null
}

parse_preset_flags() {
    local raw_content="$1"

    if [ -z "$raw_content" ]; then
        log_info "${YELLOW}[Warning] Preset is empty.${NC}"
        AUTH_FUNCS=""
        return
    fi

    raw_content=$(echo "$raw_content" | sed 's/#.*//g')

    if echo "$raw_content" | grep -q "BLACKLIST_MODE"; then
        export BLACKLIST_MODE=true
        raw_content=$(echo "$raw_content" | sed 's/BLACKLIST_MODE//g')
    fi

    if echo "$raw_content" | grep -q "ALL_MLX"; then
        USE_MLX=true
        raw_content=$(echo "$raw_content" | sed 's/ALL_MLX//g')
    fi

    if echo "$raw_content" | grep -q "ALL_MATH"; then
        USE_MATH=true
        local math_funcs="cos sin tan acos asin atan atan2 cosh sinh tanh exp frexp ldexp log log10 modf pow sqrt ceil fabs floor fmod round trunc abs labs"
        raw_content=$(echo "$raw_content" | sed 's/ALL_MATH//g')
        raw_content="$raw_content $math_funcs"
    fi

    AUTH_FUNCS=$(echo "$raw_content" | tr ',' ' ' | tr -s ' ' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | grep -v '^$')

    if [ -z "$AUTH_FUNCS" ] && [ "$BLACKLIST_MODE" = false ]; then
        log_info "${YELLOW}[Warning] Preset loaded but function list is empty.${NC}"
    fi
}

scan_source_engine() {
    local files="$1"
    local user_funcs="$2"

    export USE_JSON
    export USE_HTML
    export BLACKLIST_MODE
    export VERBOSE
    export SHOW_ALL
    export USER_FUNCS="$user_funcs"

    if [ "$BLACKLIST_MODE" = true ]; then
        export BLACKLIST_FUNCS=$(echo "$AUTH_FUNCS" | tr '\n' ' ')
    else
        local keywords="if while for return sizeof switch else case default do static const volatile struct union enum typedef extern inline unsigned signed short long int char float double void bool va_arg va_start va_end va_list NULL del f"
        local macros="WIFEXITED WEXITSTATUS WIFSIGNALED WTERMSIG S_ISDIR S_ISREG"
        export KEYWORDS_MACROS="$keywords $macros"
        export ALLOW_MLX=0
        [ "$USE_MLX" = true ] && export ALLOW_MLX=1
        export WHITELIST="$(echo "$AUTH_FUNCS" | tr '\n' ' ')"
    fi

    echo "$files" | tr '\n' '\0' | xargs -0 perl -0777 -e '
        my $is_blacklist = ($ENV{BLACKLIST_MODE} eq "true");
        my %forbidden = map { $_ => 1 } split(" ", $ENV{BLACKLIST_FUNCS} || "");
        my %safe = map { $_ => 1 } split(" ", $ENV{WHITELIST} || "");
        my %user_defined = map { $_ => 1 } split(" ", $ENV{USER_FUNCS} || "");
        my $allow_mlx = $ENV{ALLOW_MLX} || 0;
        my $count = 0;
        my $json_mode = ($ENV{USE_JSON} eq "true" || $ENV{USE_HTML} eq "true") ? "true" : "false";
        my $show_all = ($ENV{SHOW_ALL} eq "true");
        my %kw_macros = map { $_ => 1 } split(" ", $ENV{KEYWORDS_MACROS} || "");
        my %authorized_found = ();

        foreach my $file (@ARGV) {
            # En whitelist, on passe les fichiers MLX si autorisé
            if (!$is_blacklist && $allow_mlx == 1 && ($file =~ m{/mlx_} || $file =~ m{/mlx/} || $file =~ m{/minilibx/})) {
                next;
            }

            open(my $fh, "<", $file) or next;
            my $content = do { local $/; <$fh> };
            close($fh);
            my @orig_lines = split(/\n/, $content);

            # --- LE BOUCLIER ANTI-QUOTES ET COMMENTAIRES (Factorisé !) ---
            $content =~ s{(/\*.*?\*/)}{ my $c = $1; my $n = () = $c =~ /\n/g; "\n" x $n }egs;
            $content =~ s{//.*}{}g;
            $content =~ s{("(?:\\.|[^"\\])*"|\x27(?:\\.|[^\x27\\])*\x27)}{ my $c = $1; my $n = () = $c =~ /\n/g; "\n" x $n }egs;

            my $verbose = ($ENV{VERBOSE} // "") eq "true";
            my @lines = split(/\n/, $content);
            for (my $i = 0; $i < @lines; $i++) {
                my $line = $lines[$i];

                while ($line =~ /\b([a-zA-Z_]\w*)\s*\(/g) {
                    my $fname = $1;
                    my $is_illegal = 0;

                    # Logique de détection unifiée
                    if (length($fname) <= 2 || $kw_macros{$fname} || $user_defined{$fname}) {
                        next;
                    }

                    if ($is_blacklist) {
                        if ($forbidden{$fname}) {
                            $is_illegal = 1;
                        } else {
                            $authorized_found{$fname} = 1;
                            next;
                        }
                    } else {
                        if ($safe{$fname} || ($allow_mlx == 1 && $fname =~ /^mlx_/)) {
                            $authorized_found{$fname} = 1;
                            next;
                        } else {
                            $is_illegal = 1;
                        }
                    }

                    # Formatage de la sortie
                    if ($is_illegal) {
                        my $clean_file = $file;
                        $clean_file =~ s|^\./||;
                        if ($json_mode ne "true") {
                            printf "   \033[31m[FORBIDDEN]\033[0m -> \033[1m%s\033[0m\n", $fname;
                            printf "          \033[33m\xe2\x86\xb3 Location: \033[34m%s:%d\033[0m\n", $clean_file, $i + 1;
                            if ($verbose) {
                                my $snippet = $orig_lines[$i] // "";
                                $snippet =~ s/^\s+//;
                                printf "          \033[33m\xe2\x86\xb3 Code:     \033[36m%s\033[0m\n", $snippet;
                            }
                        } else {
                            my $lnum = $i + 1;
                            print "MATCH|-> $fname|in $clean_file:$lnum\n";
                        }
                        $count++;
                    }
                }
            }
        }

        # Message de fin
        if ($json_mode ne "true") {
            if ($show_all) {
                foreach my $func (sort keys %authorized_found) {
                    printf "   [\033[32mOK\033[0m]         -> %s\n", $func;
                }
            }
            print "\n-------------------------------------------------\n";
            if ($count == 0) {
                print "\t\t\033[32mRESULT: PERFECT\033[0m\n";
            } else {
                printf "\033[31mTotal forbidden functions found: %d\033[0m\n\n", $count;
                print "\t\t\033[31mRESULT: FAILURE\033[0m\n";
            }
        }
    '
}

source_scan() {
    local _src_start
    if [ "$IS_MAC" = true ]; then
        _src_start=$(perl -MTime::HiRes=time -e 'print time')
    else
        _src_start=$(date +%s.%N)
    fi
    resolve_preset "source"
    load_preset "$SELECTED_PRESET" || { log_info "${RED}Error: Preset not found.${NC}"; exit 1; }

    local files_list=""
    if [ -n "$SPECIFIC_FILES" ]; then
        for f in $SPECIFIC_FILES; do
            [ -f "$f" ] && files_list+="$f"$'\n'
        done
        files_list=$(echo "$files_list" | sed '/^$/d')
    else
        files_list=$(find . -maxdepth 5 -type f \( -name "*.c" -o -name "*.cpp" \))
    fi
    [ -z "$files_list" ] && safe_exit 1
    local nb_files=$(echo "$files_list" | grep -c '^')
    [ "$nb_files" -eq 0 ] && safe_exit 1

    local raw_preset=$(cat "$ACTIVE_PRESET" 2>/dev/null)
    parse_preset_flags "$raw_preset"

    local preset_mode="Whitelist"
    [ "$BLACKLIST_MODE" = true ] && preset_mode="Blacklist"

    log_info "${BLUE}Scan Mode  :${NC} ${YELLOW}Source${NC} (*.c / *.cpp)"
    log_info "${BLUE}Preset     :${NC} ${BOLD}${SELECTED_PRESET}${NC} ${CYAN}(${preset_mode})${NC}"
    [ -n "$SPECIFIC_FILES" ] && log_info "${BLUE}Scope      :${NC} $SPECIFIC_FILES"
    log_info ""
    log_info "${BLUE}${BOLD}Execution:${NC}"
    log_info "-------------------------------------------------"
    log_info "${BLUE}Scanning $nb_files source file(s)...${NC}\n"

    local my_funcs=$(get_user_defined_funcs)
    local scan_output
    scan_output=$(scan_source_engine "$files_list" "$my_funcs")

    if [ "$USE_JSON" = true ] || [ "$USE_HTML" = true ]; then
        export JSON_RAW_DATA="$scan_output"
        export IS_SOURCE_SCAN=true
        if [ "$USE_JSON" = true ]; then
            generate_json_output
        else
            generate_html_report
        fi
    else
        while IFS= read -r line; do
            log_info "$line"
        done <<< "$scan_output"
        if [ "$SHOW_TIME" = true ]; then
            local _end_t
            if [ "$IS_MAC" = true ]; then
                _end_t=$(perl -MTime::HiRes=time -e 'print time')
            else
                _end_t=$(date +%s.%N)
            fi
            local _dur=$(echo "$_end_t - $_src_start" | bc 2>/dev/null || echo "0")
            [[ "$_dur" == .* ]] && _dur="0${_dur}"
            log_info "$_dur"
        fi
        log_info "\n${GREEN}Source audit complete.${NC}"
    fi
    safe_exit 0
}

extract_undefined_symbols() {
    if [ "$IS_MAC" = true ]; then
        raw_funcs=$(nm -u "$TARGET" 2>/dev/null | awk '{print $NF}' | sed -E 's/^_//' | sed -E 's/@.*//' | sort -u)
        NM_RAW_DATA=$(find . -not -path '*/.*' -type f \( -name "*.o" -o -name "*.a" \) ! -name "$TARGET" ! -path "*mlx*" ! -path "*MLX*" -print0 2>/dev/null | xargs -0 -P4 nm -o 2>/dev/null)
        MY_DEFINED=$(grep -E ' [TRD] ' <<< "$NM_RAW_DATA" | awk '{print $NF}' | sed -E 's/^_//' | sort -u)
        ALL_UNDEFINED=$(grep " U " <<< "$NM_RAW_DATA" | sed -E 's/ U _/ U /')
    else
        raw_funcs=$(nm -u "$TARGET" 2>/dev/null | awk '{print $NF}' | sed -E 's/@.*//' | sort -u)
        NM_RAW_DATA=$(find . -not -path '*/.*' -type f \( -name "*.o" -o -name "*.a" \) ! -name "$TARGET" ! -path "*mlx*" ! -path "*MLX*" -print0 2>/dev/null | xargs -0 -P4 nm -A 2>/dev/null)
        MY_DEFINED=$(grep -E ' [TRD] ' <<< "$NM_RAW_DATA" | awk '{print $NF}' | sort -u)
        ALL_UNDEFINED=$(grep " U " <<< "$NM_RAW_DATA")
    fi
}

filter_forbidden_functions() {
    local func
    forbidden_list=""

    while read -r func; do
        [ -z "$func" ] && continue
        [[ "$func" =~ ^(_|ITM|edata|end|bss_start) ]] && continue

        [ "$USE_MLX" = true ] && [[ "$func" =~ ^(X|shm|gethostname|puts|exit|strerror) ]] && continue
        [ "$USE_MATH" = true ] && [[ "$func" =~ ^(abs|cos|sin|sqrt|pow|exp|log|fabs|floor)f?$ ]] && continue
        grep -qx "$func" <<< "$MY_DEFINED" && continue
        local is_authorized=false

        if [ "$BLACKLIST_MODE" = true ]; then
            grep -qx "$func" <<< "$AUTH_FUNCS" || is_authorized=true
        else
            grep -qx "$func" <<< "$AUTH_FUNCS" && is_authorized=true
        fi

        if [ "$is_authorized" = true ]; then
            [ "$SHOW_ALL" = true ] && printf "   [${GREEN}OK${NC}]         -> %s\n" "$func"
        else
            if grep -qE " U ${func}$" <<< "$ALL_UNDEFINED"; then
                forbidden_list+="${func} "
            fi
        fi
    done <<< "$raw_funcs"
}

print_analysis_report() {
    local f_name specific_locs errors=0

    for f_name in $forbidden_list; do
        specific_locs=$(grep -E ":.*\b${f_name}\b" <<< "$grep_res")

        if [ -n "$specific_locs" ]; then
            log_info "   [${RED}FORBIDDEN${NC}] -> $f_name"
            [ -z "$SPECIFIC_FILES" ] && errors=$((errors + 1))

            while read -r line; do
                [ -z "$line" ] && continue
                local f_path=$(echo "$line" | cut -d: -f1)
                local l_num=$(echo "$line" | cut -d: -f2)
                local snippet=$(echo "$line" | cut -d: -f3- | sed 's/^[[:space:]]*//')

                if clean_code_snippet "$snippet" "$f_name" > /dev/null; then
                    local display_name=$( [ "$FULL_PATH" = true ] && echo "$f_path" | sed 's|^\./||' || basename "$f_path" )
                    local loc_prefix=$( [ -n "$SPECIFIC_FILES" ] && [ "$VERBOSE" = false ] && echo "line ${l_num}" || echo "${display_name}:${l_num}" )

                    if [ "$VERBOSE" = true ]; then
                        local s_crop=$(crop_line "$f_name" "$snippet")
                        log_info "          ${YELLOW}↳ Location: ${BLUE}${loc_prefix}${NC}: ${CYAN}${s_crop}${NC}"
                    else
                        log_info "          ${YELLOW}↳ Location: ${BLUE}${loc_prefix}${NC}"
                    fi
                fi
            done <<< "$specific_locs"
        elif [ -z "$SPECIFIC_FILES" ]; then
            # Warning block (Found in binary but not in .c)
            log_info "   [${YELLOW}WARNING${NC}]   -> %s\n" "$f_name"
            local objects=$(grep -E " U ${f_name}$" <<< "$ALL_UNDEFINED" | awk -F: '{split($1, path, "/"); print path[length(path)]}' | sort -u | tr '\n' ' ')
            log_info "          ${YELLOW}↳ Found in objects: ${BLUE}${objects}${NC}"
            [[ "$f_name" =~ ^(strlen|memset|memcpy|printf|puts|putchar)$ ]] && log_info " ${CYAN}(Builtin?)${NC}" || log_info " ${CYAN}(Sync?)${NC}"
        fi
    done
    return $errors
}

build_grep_results() {
    local f_name safe_name
    grep_res=""
    local grep_args=("-rHE")

    for f_name in $forbidden_list; do
        safe_name=$(printf '%s\n' "$f_name" | sed 's/[.[\*^$]/\\&/g')

        local current_grep_args=("${grep_args[@]}" "\b${safe_name}\b" ".")

        if [ -n "$SPECIFIC_FILES" ]; then
            read -ra FILES_ARRAY <<< "$SPECIFIC_FILES"
            for f in "${FILES_ARRAY[@]}"; do
                current_grep_args+=("--include=$f")
            done
        else
            current_grep_args+=("--include=*.c")
        fi
        grep_res+="$(grep "${current_grep_args[@]}" -n 2>/dev/null | grep -vE "mlx|MLX")"$'\n'
    done
}

run_analysis() {
    export IS_SOURCE_SCAN=false
    extract_undefined_symbols
    filter_forbidden_functions
    build_grep_results

    local count=0
    if [ -n "$forbidden_list" ]; then
        count=$(echo "$forbidden_list" | wc -w)
    fi

    if [ "$USE_JSON" = true ] || [ "$USE_HTML" = true ]; then
        if [ "$USE_JSON" = true ]; then
            generate_json_output "$count"
        else
            generate_html_report "$count"
        fi
        [ $count -eq 0 ] && return 0 || return 1
    else
        print_analysis_report
        local total_errors=$?

        if [ $total_errors -eq 0 ] && [ $count -eq 0 ]; then
            log_info "\t${GREEN}No forbidden functions detected.${NC}"
        else
            log_info "\n${RED}Total forbidden functions found: $count${NC}"
        fi
        return $total_errors
    fi
}

check_binary_cache() {
    local cache_file current_src_data current_src_lines bin_mtime target_name
    local ref_data ref_lines ref_size ref_bin_date diff_size abs_diff tmp_file target_name_escaped

    cache_file="$INSTALL_DIR/.forb_cache"
    mkdir -p "$INSTALL_DIR"
    [ ! -f "$cache_file" ] && touch "$cache_file"

    current_src_lines=$(find . -name "*.c" -not -path '*/.*' -type f -exec wc -l {} + 2>/dev/null | awk '{s+=$1} END {print s+0}')
    if [ "$IS_MAC" = true ]; then
        bin_mtime=$(stat -f %m "$TARGET" 2>/dev/null || echo 0)
        current_src_data=$(find . -name "*.c" -not -path '*/.*' -type f -exec stat -f "%z" {} + 2>/dev/null | awk '{s+=$1} END {print s+0}')
    else
        bin_mtime=$(stat -c %Y "$TARGET" 2>/dev/null || echo 0)
        current_src_data=$(find . -name "*.c" -not -path '*/.*' -type f -exec stat -c "%s" {} + 2>/dev/null | awk '{s+=$1} END {print s+0}')
    fi
    target_name=$(basename "$TARGET")

    ref_data=$(grep "^$(printf '%s\n' "$target_name" | sed 's/[.[\*^$/]/\\&/g'):" "$cache_file" 2>/dev/null)
    ref_lines=$(echo "$ref_data" | cut -d: -f2)
    ref_size=$(echo "$ref_data" | cut -d: -f3)
    ref_bin_date=$(echo "$ref_data" | cut -d: -f4)

    if [[ "$bin_mtime" != "$ref_bin_date" ]]; then
        tmp_file=$(mktemp)
        grep -v "^${target_name}:" "$cache_file" > "$tmp_file"
        mv "$tmp_file" "$cache_file"
        target_name_escaped=$(printf '%s\n' "$target_name" | sed 's/:/\\:/g')
        echo "${target_name_escaped}:$current_src_lines:$current_src_data:$bin_mtime" >> "$cache_file"
        SET_WARNING=false
    else
        diff_size=$((current_src_data - ref_size))
        abs_diff=${diff_size#-}

        if [[ "$current_src_lines" != "$ref_lines" ]] || [[ "$abs_diff" -gt 2 ]]; then
            SET_WARNING=true
        else
            SET_WARNING=false
        fi
    fi
}


# ==============================================================================
#  SECTION 5: MAINTENANCE & HELPERS
# ==============================================================================

show_help() {
    echo -e "${BOLD}ForbCheck v$VERSION${NC}"
    echo -e "Usage: forb [options] <target> [-f <files...>]\n"

    echo -e "${BOLD}Arguments:${NC}"
    printf "  %-24s %s\n" "<target>" "Executable or library to analyze"

    echo -e "\n${BOLD}General:${NC}"
    printf "  %-24s %s\n" "-h, --help" "Show help message"
    printf "  %-24s %s\n" "--json" "Generate a JSON output for automations"
    printf "  %-24s %s\n" "--html" "Generate a beautiful interactive HTML report"
    printf "  %-24s %s\n" "-oh, --open-html" "Open the folder containing HTML reports"
    printf "  %-24s %s\n" "--log" "Generate a .log of the output"
    printf "  %-24s %s\n" "-l, --list [<funcs...>]" "Show list or check specific functions"
    printf "  %-24s %s\n" "-e, --edit" "Edit authorized list"

    echo -e "\n${BOLD}Presets:${NC}"
    printf "  %-24s %s\n" "-P, --preset" "Load the preset matching the target name"
    printf "  %-24s %s\n" "-np, --no-preset" "Disable auto-preset and force default list"
    printf "  %-24s %s\n" "-gp, --get-presets" "Restore default presets (overwrites matches)"
    printf "  %-24s %s\n" "-cp, --create-preset" "Create and edit a new preset"
    printf "  %-24s %s\n" "-lp, --list-presets" "Show all presets"
    printf "  %-24s %s\n" "-op, --open-presets" "Open presets directory"
    printf "  %-24s %s\n" "-rp, --remove-preset" "Delete an existing preset"

    echo -e "\n${BOLD}Scan Options:${NC}"
    printf "  %-24s %s\n" "-b, --blacklist" "Force Blacklist Mode (Hunt specific functions instead of whitelist)"
    printf "  %-24s %s\n" "-v, --verbose" "Show source code context"
    printf "  %-24s %s\n" "-f <files...>" "Limit scan to specific files"
    printf "  %-24s %s\n" "-p, --full-path" "Show full paths"
    printf "  %-24s %s\n" "-a, --all" "Show authorized functions during scan"
    printf "  %-24s %s\n" "--no-auto" "Disable auto-detection (must be used BEFORE -s)"

    echo -e "\n${BOLD}Deep Scan:${NC}"
    printf "  %-24s %s\n" "-s, --source" "Scan source files for unauthorized C functions"

    echo -e "\n${BOLD}Library Filters:${NC}"
    printf "  %-24s %s\n" "-mlx" "Ignore MiniLibX internal calls"
    printf "  %-24s %s\n" "-lm" "Ignore Math library internal calls"

    echo -e "\n${BOLD}Maintenance:${NC}"
    printf "  %-24s %s\n" "-t, --time" "Show execution duration"
    printf "  %-24s %s\n" "--version" "Show version's forbCheck"
    printf "  %-24s %s\n" "-up, --update" "Check and install latest version"
    printf "  %-24s %s\n" "--remove" "Remove ForbCheck"
    safe_exit 0
}

update_script() {
    local tmp_file=$(mktemp)
    local remote_version

    log_info "${BLUE}[Update] Checking for latest version at ${CYAN}$UPDATE_URL${NC}..."

    if curl -sL "$UPDATE_URL" -o "$tmp_file"; then
        log_info "${GREEN}[Update] Download successful.${NC}"

        remote_version=$(grep "^readonly VERSION=" "$tmp_file" | cut -d'"' -f2)

        if [ -z "$remote_version" ]; then
            log_info "${RED}[Update] Error: Could not parse version from downloaded file.${NC}"
            rm -f "$tmp_file"
            return 1
        fi

        log_info "${BLUE}[Update] Current: ${BOLD}$VERSION${NC}${BLUE} | Remote: ${BOLD}$remote_version${NC}"

        if [ "$(version_to_int "$remote_version")" -gt "$(version_to_int "$VERSION")" ]; then
            log_info "${YELLOW}[Update] New version detected! Preparing to overwrite...${NC}"

            if [ ! -w "$0" ]; then
                log_info "${RED}[Update] Error: No write permission on $0. Try running with sudo or check file owner.${NC}"
                rm -f "$tmp_file"
                return 1
            fi
            if mv "$tmp_file" "$0" && chmod +x "$0"; then
                log_info "${GREEN}[Update] Script replaced successfully.${NC}"
                log_info "${BLUE}[Update] Updating presets...${NC}"
                get_presets "auto"

                log_info "${GREEN}${BOLD}[Update] ForbCheck has been updated to $remote_version!${NC}"
                log_info "${CYAN}[Update] Please restart your terminal or run 'forb' again.${NC}"
                safe_exit 0
            else
                log_info "${RED}[Update] Fatal error: Failed to replace $0.${NC}"
                rm -f "$tmp_file"
                return 1
            fi
        else
            log_info "${GREEN}[Update] ForbCheck is already at the latest version.${NC}"
            rm -f "$tmp_file"
        fi
    else
        log_info "${RED}[Update] Error: Network failure. Could not reach GitHub.${NC}"
        rm -f "$tmp_file"
        return 1
    fi
    safe_exit 0
}

auto_check_update() {
    # Skip interactive update check if running in JSON mode (prevents CI hangs)
    [ "$USE_JSON" = true ] || [ "$USE_HTML" = true ] && return

    local remote_version choice

    # Silent curl with 1-second timeout to prevent lag
    remote_version=$(curl -s --max-time 1 "$UPDATE_URL" | grep "^readonly VERSION=" | head -n 1 | cut -d'"' -f2)

    if [ -n "$remote_version" ]; then
        if [ "$(version_to_int "$remote_version")" -gt "$(version_to_int "$VERSION")" ]; then
            echo -ne "${YELLOW}New version of ForbCheck (v${remote_version}) is available! Update now? (y/n): ${NC}"
            read -r choice
            case "$choice" in
                [yY][eE][sS]|[yY])
                    update_script
                    ;;
                *)
                    log_info "${BLUE}Update skipped. Starting analysis...${NC}\n"
                    ;;
            esac
        fi
    fi
}

uninstall_script() {
    local choice
    echo -ne "${RED}${BOLD}Warning: You are about to uninstall ForbCheck. All configurations will be lost. Continue? (y/n): ${NC}"
    read -r choice
    case "$choice" in
        [yY][eE][sS]|[yY])
            log_info "${YELLOW}Uninstalling ForbCheck...${NC}"

            rm -f "$HOME/.local/bin/forb"

            if [ "$IS_MAC" = true ]; then
                sed -i '' '/alias forb=/d' ~/.zshrc ~/.bashrc 2>/dev/null
                sed -i '' '/# Autocompletion & ForbCheck/,/source ~\/.forb\/forb_completion\.sh/d' ~/.zshrc ~/.bashrc 2>/dev/null
                sed -i '' '/# ForbCheck Autocompletion/d' ~/.zshrc ~/.bashrc 2>/dev/null
                sed -i '' '/forb_completion\.sh/d' ~/.zshrc ~/.bashrc 2>/dev/null
                sed -i '' '/autoload -U +X compinit && compinit/d' ~/.zshrc ~/.bashrc 2>/dev/null
                sed -i '' '/autoload -U +X bashcompinit && bashcompinit/d' ~/.zshrc ~/.bashrc 2>/dev/null
            else
                sed -i '/alias forb=/d' ~/.zshrc ~/.bashrc 2>/dev/null
                sed -i '/# Autocompletion & ForbCheck/,/source ~\/.forb\/forb_completion\.sh/d' ~/.zshrc ~/.bashrc 2>/dev/null
                sed -i '/# ForbCheck Autocompletion/d' ~/.zshrc ~/.bashrc 2>/dev/null
                sed -i '/forb_completion\.sh/d' ~/.zshrc ~/.bashrc 2>/dev/null
                sed -i '/autoload -U +X compinit && compinit/d' ~/.zshrc ~/.bashrc 2>/dev/null
                sed -i '/autoload -U +X bashcompinit && bashcompinit/d' ~/.zshrc ~/.bashrc 2>/dev/null
            fi
            rm -rf "$HOME/.forb"

            log_info "${GREEN}[✔] ForbCheck has been successfully removed.${NC}"
            echo -e "${YELLOW}Note: Run 'exec zsh' to refresh your shell.${NC}"
            safe_exit 0
            ;;
        *)
            log_info "${BLUE}Uninstallation aborted.${NC}"
            safe_exit 0
            ;;
    esac
}

check_dependencies() {
    local missing_deps=0
    local deps=("nm" "perl" "curl" "tar")

    for cmd in "${deps[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            echo -e "${RED}[✘] Error: Required command '${BOLD}$cmd${NC}${RED}' is not installed.${NC}"
            missing_deps=$((missing_deps + 1))
        fi
    done

    if ! command -v bc &> /dev/null; then
        echo -e "${YELLOW}[!] Warning: 'bc' is not installed. Execution time (-t) will be unavailable.${NC}"
    fi

    if [ "$missing_deps" -gt 0 ]; then
        echo -e "${YELLOW}Please install the missing packages to use ForbCheck.${NC}"
        safe_exit 1
    fi
}


# ==============================================================================
#  SECTION 6: MAIN DISPATCHER & EXECUTION
# ==============================================================================

# 1. Pre-process arguments (handle split/combined flags)
args=()
for arg in "$@"; do
    if [[ "$arg" =~ ^-(mlx|lm|up|op|lp|cp|rp|gp|np|oh)$ ]]; then
        args+=("$arg")
    elif [[ "$arg" == "--"* ]]; then
        args+=("$arg")
    elif [[ "$arg" =~ ^-[a-zA-Z]{2,}$ ]]; then
        _i=1
        while (( _i < ${#arg} )); do
            _two="${arg:$_i:2}"
            if [[ "$_two" =~ ^(np|lm|up|op|lp|cp|rp|gp|mlx|oh)$ ]]; then
                args+=("-$_two")
                _i=$(( _i + 2 ))
            else
                args+=("-${arg:$_i:1}")
                _i=$(( _i + 1 ))
            fi
        done
    else
        args+=("$arg")
    fi
done
set -- "${args[@]}"

# 2. Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help) SHOW_HELP=true; shift ;;
        --version) SHOW_VERSION=true; shift ;;
        --json) USE_JSON=true; shift ;;
        --html) USE_HTML=true; shift ;;
        --log) PUT_LOG=true; shift ;;
        -up|--update) DO_UPDATE=true; shift ;;
        --remove) DO_REMOVE=true; shift ;;
        --no-auto) DISABLE_AUTO=true; shift ;;
        -b|--blacklist) export BLACKLIST_MODE=true; shift ;;
        -s|--source) FORCE_SOURCE_SCAN=true; shift ;;
        -v|--verbose) VERBOSE=true; shift ;;
        -p|--full-path) FULL_PATH=true; shift ;;
        -a|--all) SHOW_ALL=true; shift ;;
        -mlx) USE_MLX=true; shift ;;
        -lm) USE_MATH=true; shift ;;
        --preset|-P) USE_PRESET=1; shift ;;
        -np|--no-preset) DISABLE_PRESET=true; shift ;;
        -gp|--get-presets) DO_GET_PRESETS=true; shift ;;
        -lp|--list-presets) DO_LIST_PRESETS=true; shift ;;
        -op|--open-presets) DO_OPEN_PRESETS=true; shift ;;
        -oh|--open-html) DO_OPEN_HTML=true; shift ;;
        -cp|--create-preset) DO_CREATE_PRESET=true; shift ;;
        -rp|--remove-preset) DO_REMOVE_PRESET=true; shift ;;
        -e|--edit) DO_EDIT_LIST=true; shift ;;
        -l|--list)
            RUN_LIST=true; shift
            while [[ $# -gt 0 && ! "$1" =~ ^- && ! -f "$1" && "$1" != "$TARGET" ]]; do
                LIST_FUNCS+="$1 "
                shift
            done
            continue
            ;;
        -t|--time) SHOW_TIME=true; shift ;;
        -f)
            shift
            while [[ $# -gt 0 && ! "$1" =~ ^- ]]; do
                SPECIFIC_FILES+="$1 "
                shift
            done
            continue
            ;;
        -*) echo -e "${RED}Unknown option: $1${NC}"; safe_exit 1 ;;
        *) TARGET=$1; shift ;;
    esac
done

if [ "$SHOW_HELP" = true ]; then show_help; fi
if [ "$SHOW_VERSION" = true ]; then log_info "V$VERSION"; safe_exit 0; fi
if [ "$DO_UPDATE" = true ]; then update_script; fi
if [ "$DO_REMOVE" = true ]; then uninstall_script; fi
if [ "$DO_GET_PRESETS" = true ]; then get_presets "manual"; fi
if [ "$DO_LIST_PRESETS" = true ]; then list_presets; fi
if [ "$DO_OPEN_PRESETS" = true ]; then open_presets; fi
if [ "$DO_OPEN_HTML" = true ]; then open_html; fi
if [ "$DO_CREATE_PRESET" = true ]; then create_preset; fi
if [ "$DO_REMOVE_PRESET" = true ]; then remove_preset; fi

# logs
if [ "$PUT_LOG" = true ]; then
    mkdir -p "$LOG_DIR"
    if [ "$USE_JSON" != true ] && [ "$USE_HTML" != true ]; then
        echo -e "${CYAN}The program is running and logging its output...${RED}"
    fi
    count=$(ls -1 "$LOG_DIR"/*.log 2>/dev/null | wc -l)
    new_num=$((count + 1))
    timestamp=$(date +"%Y-%m-%d_%Hh%M")
    LOG_FILE="$LOG_DIR/l${new_num}_${timestamp}.log"
fi

mkdir -p "$PRESET_DIR"
check_dependencies

#banner
log_info "${YELLOW}╔═════════════════════════════════════╗${NC}"
log_info "${YELLOW}║              ForbCheck              ║${NC}"
log_info "${YELLOW}╚═════════════════════════════════════╝${NC}"

if [ "$FORCE_SOURCE_SCAN" = true ]; then
    source_scan
fi

if [ -z "$TARGET" ]; then
    if [ "$DISABLE_AUTO" = true ]; then
        if [ "$DO_EDIT_LIST" = true ] || [ "$RUN_LIST" = true ]; then
            :
        elif [ "$USE_JSON" = true ] || [ "$USE_HTML" = true ]; then
             echo "{\"target\":\"\",\"version\":\"$VERSION\",\"error\":\"No target specified and auto-detection is disabled.\",\"status\":\"FAILURE\"}"
             safe_exit 1
        else
             log_info "${RED}Error: No target specified and auto-detection is disabled (--no-auto).${NC}"
             log_info "${CYAN}Usage: forb --no-auto <binary_name>  OR  forb --no-auto -s${NC}"
             safe_exit 1
        fi
    elif ! auto_detect_target; then
        if [ "$DO_EDIT_LIST" = true ] || [ "$RUN_LIST" = true ]; then
            :
        else
            log_info "${RED}[Auto-Detect] No binary found.${YELLOW} -> Falling back to Source Scan...${NC}\n"
            source_scan
        fi
    fi
elif [ ! -f "$TARGET" ]; then
    if [ "$DO_EDIT_LIST" = true ] || [ "$RUN_LIST" = true ]; then
        :
    else
        log_info "${YELLOW}[Warning] Target '$TARGET' not found. Falling back to Source Scan...${NC}\n"
        source_scan
    fi
fi

# 5. Pre-run Setup (Updates, Cache, Libraries)
auto_check_update
check_binary_cache
auto_detect_libraries

# 6. Load Presets
resolve_preset "binary"
load_preset "$SELECTED_PRESET"

if [ "$DO_EDIT_LIST" = true ]; then
    edit_list
fi
if [ "$RUN_LIST" = true ]; then
    process_list $LIST_FUNCS
fi

if [ "$SELECTED_PRESET" = "default" ] && [ ! -s "$ACTIVE_PRESET" ]; then
    log_info "${YELLOW}[Warning] Using 'default' preset, but it is currently empty.${NC}"
fi

RAW_PRESET=$(cat "$ACTIVE_PRESET" 2>/dev/null)
parse_preset_flags "$RAW_PRESET"

# 7. Print Execution Details
if [ -n "$TARGET" ]; then
    log_info "${BLUE}Scan Mode  :${NC} ${YELLOW}Binary${NC}"
    [ "$AUTO_BIN_DETECTED" != true ] && log_info "${BLUE}Target bin :${NC} $TARGET"
else
    log_info "${BLUE}Scan Mode  :${NC} ${YELLOW}Binary${NC}"
fi
local_preset_mode="Whitelist"
[ "$BLACKLIST_MODE" = true ] && local_preset_mode="Blacklist"
log_info "${BLUE}Preset     :${NC} ${BOLD}${SELECTED_PRESET}${NC} ${CYAN}(${local_preset_mode})${NC}"

if [ "$SET_WARNING" = true ]; then
    log_info "${YELLOW}Warning:${NC} Source content is newer than the binary."
    log_info "         The results might not reflect your latest changes."
    log_info "         Consider ${GREEN}recompiling${NC} to be sure."
fi

[ -n "$SPECIFIC_FILES" ] && log_info "${BLUE}Scope      :${NC} $SPECIFIC_FILES"

log_info "${BLUE}${BOLD}Execution:${NC}"
log_info "-------------------------------------------------"

# 8. Run Core Analysis
if [ "$IS_MAC" = true ]; then
    START_TIME=$(perl -MTime::HiRes=time -e 'print time')
else
    START_TIME=$(date +%s.%N)
fi

run_analysis
total_errors=$?

# 9. Print Results
if [ "$IS_MAC" = true ]; then
    END_TIME=$(perl -MTime::HiRes=time -e 'print time')
    DURATION=$(echo "$END_TIME - $START_TIME" | bc 2>/dev/null || echo "0")
else
    DURATION=$(echo "$(date +%s.%N) - $START_TIME" | bc 2>/dev/null || echo "0")
fi

log_info "-------------------------------------------------\n"
if [ $total_errors -eq 0 ]; then
    log_info "\t\t${GREEN}RESULT: PERFECT"
else
    log_info "\t\t${RED}RESULT: FAILURE"
fi

if [ "$SHOW_TIME" = true ]; then
    log_info "$DURATION"
fi
[ $total_errors -ne 0 ] && safe_exit 1
