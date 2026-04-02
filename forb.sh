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
VERSION="1.9.92"
readonly VERSION="1.9.92"
readonly INSTALL_DIR="$HOME/.forb"
readonly PRESET_DIR="$INSTALL_DIR/presets"
readonly UPDATE_URL="https://raw.githubusercontent.com/Mrdolls/forb/main/forb.sh"

# Global State Variables (Mutable)
AUTH_FILE="$PRESET_DIR/default.preset"
USE_JSON=false
USE_PRESET=0
SHOW_ALL=false
USE_MLX=false
USE_MATH=false
MODE_BLACKLIST=false
FULL_PATH=false
VERBOSE=false
TARGET=""
SPECIFIC_FILES=""
SHOW_TIME=false
DISABLE_AUTO=false
DISABLE_PRESET=false
SET_WARNING=false


# ==============================================================================
#  SECTION 2: UTILITY FUNCTIONS (Low-level helpers)
# ==============================================================================

log_info() {
    if [ "$USE_JSON" = false ]; then
        echo -e "$@"
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
    echo -n "\"mode\":\"$( [ "$MODE_BLACKLIST" = true ] && echo "blacklist" || echo "whitelist" )\","
    echo -n "\"results\":["

    if [ "$IS_SOURCE_SCAN" = true ]; then
        local first_loc=true
        local match_data=$(echo "$JSON_RAW_DATA" | grep "MATCH")
        while IFS= read -r line; do
            [ -z "$line" ] && continue
            [ "$first_loc" = false ] && echo -n ","
            local fname=$(echo "$line" | grep -oP '(?<=-> )\S+')
            local fpath=$(echo "$line" | grep -oP 'in \K\S+(?=:)')
            local lnum=$(echo "$line"  | grep -oP ':\K[0-9]+$')
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

# ==============================================================================
#  SECTION 3: PRESET MANAGEMENT
# ==============================================================================

select_preset() {
    local current_dir current_dir_lower preset_file base_name base_name_lower presets choice
    if [ "$DISABLE_AUTO" = "true" ] && [ "$USE_JSON" = true ]; then
        export SELECTED_PRESET="default"
        return 0
    fi
    if [ "$DISABLE_AUTO" != "true" ] && [ -z "$SELECTED_PRESET" ]; then
        current_dir=$(basename "$PWD")
        current_dir_lower=$(echo "$current_dir" | tr '[:upper:]' '[:lower:]')
        for preset_file in "$PRESET_DIR"/*.preset; do
            [ -e "$preset_file" ] || continue
            base_name=$(basename "$preset_file" .preset)
            base_name_lower=$(echo "$base_name" | tr '[:upper:]' '[:lower:]')
            if [[ "$current_dir_lower" == *"$base_name_lower"* ]]; then
                export SELECTED_PRESET="$base_name"
                log_info "${CYAN}[Auto-Detect] Project detected: ${BOLD}${base_name}${NC}"
                return 0
            fi
        done
        if find . -maxdepth 2 -name "*.cpp" -print -quit | grep -q "."; then
            if [ -f "$PRESET_DIR/cpp.preset" ]; then
                log_info "${CYAN}[Auto-Detect] C++ files detected. Loading 'cpp' preset.${NC}"
                export SELECTED_PRESET="cpp"
                return 0
            fi
        fi
    fi
    if [ "$USE_JSON" = true ] && [ -z "$SELECTED_PRESET" ]; then
        export SELECTED_PRESET="default"
        return 0
    fi
    {
        [ "$DISABLE_AUTO" == "true" ] && log_info "\n${YELLOW}${BOLD}Auto-detection disabled by --no-auto flag.${NC}"
        log_info "${CYAN}${BOLD}Select a project preset:${NC}"

        presets=($(ls "$PRESET_DIR" 2>/dev/null | grep '\.preset$' | sed 's/\.preset//'))

        if [ ${#presets[@]} -eq 0 ]; then
            log_info "${RED}Error: No presets found in $PRESET_DIR.${NC}"
            exit 1
        fi

        PS3=$'\n\033[1;36mEnter the number of your preset: \033[0m'
        select choice in "${presets[@]}"; do
            if [ -n "$choice" ]; then
                export SELECTED_PRESET="$choice"
                log_info "${GREEN}Loaded preset: ${BOLD}$SELECTED_PRESET${NC}"
                break
            fi
        done
    } >&2
}

load_preset() {
    local target_name="$1"
    local available_presets

    mkdir -p "$PRESET_DIR"
    AUTH_FILE="$PRESET_DIR/${target_name}.preset"

    if [ "$target_name" = "default" ] && [ ! -f "$AUTH_FILE" ]; then
        touch "$AUTH_FILE"
    fi

    if [ ! -f "$AUTH_FILE" ]; then
        available_presets=$(find "$PRESET_DIR" -maxdepth 1 -name "*.preset" -exec basename {} .preset \; | tr '\n' ',' | sed 's/,/, /g' | sed 's/, $//')

        if [ "$USE_JSON" = true ]; then
            echo "{\"target\":\"$TARGET\",\"version\":\"$VERSION\",\"error\":\"No preset found for '${target_name}'\",\"status\":\"FAILURE\"}"
        else
            log_info "\033[31mError: No preset found for '${target_name}'.\033[0m"
            if [ -z "$available_presets" ]; then
                log_info "\033[33mNo presets available.\033[0m"
            else
                log_info "Available presets: \033[36m$available_presets\033[0m"
            fi
        fi
        exit 1
    fi
}

list_presets() {
    local should_exit="${1:-1}"
    local available_presets

    mkdir -p "$PRESET_DIR"
    available_presets=$(find "$PRESET_DIR" -maxdepth 1 -name "*.preset" -exec basename {} .preset \; | tr '\n' ',' | sed 's/,/, /g' | sed 's/, $//')

    if [ -z "$available_presets" ]; then
        log_info "\033[33mNo presets available in $PRESET_DIR\033[0m"
    else
        log_info "Available presets: \033[36m$available_presets\033[0m"
    fi

    [ "$should_exit" -eq 1 ] && exit 0
}

get_presets() {
    local mode="$1"
    local choice added preset base_name

    if [[ "$mode" == "manual" ]]; then
        echo -ne "${YELLOW}${BOLD}Warning: This will download default presets. Any existing preset with the same name will be overwritten. Continue? (y/n): ${NC}"
        read -r choice
        case "$choice" in
            [yY][eE][sS]|[yY]) ;;
            *) log_info "${BLUE}Operation aborted.${NC}"; exit 0 ;;
        esac
    fi

    log_info "${BLUE}Downloading default presets from GitHub...${NC}"
    mkdir -p "$PRESET_DIR"

    if curl -sL "https://github.com/Mrdolls/forbCheck/archive/refs/heads/main.tar.gz" | tar -xz -C /tmp "forbCheck-main/presets" 2>/dev/null; then
        if [[ "$mode" == "manual" ]]; then
            cp -r /tmp/forbCheck-main/presets/* "$PRESET_DIR/" 2>/dev/null
            log_info "${GREEN}[✔] Default presets successfully restored!${NC}"
        else
            added=0
            for preset in /tmp/forbCheck-main/presets/*; do
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
        rm -rf "/tmp/forbCheck-main"
    else
        log_info "${RED}[✘] Error: Failed to download presets. Check your connection.${NC}"
    fi

    [ "$mode" == "manual" ] && exit 0
}

open_presets() {
    mkdir -p "$PRESET_DIR"
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
    exit 0
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
    mkdir -p "$PRESET_DIR"

    echo -ne "${BLUE}${BOLD}Enter the name of the new preset (e.g., minishell): ${NC}"
    read -r preset_name

    if [ -z "$preset_name" ]; then
        log_info "${RED}Error: Preset name cannot be empty.${NC}"
        exit 1
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

    command -v code &>/dev/null && code --wait "$new_file" || vim "$new_file" || nano "$new_file"
    log_info "${GREEN}[✔] Preset '${preset_name}' saved!${NC}"
    exit 0
}

remove_preset() {
    local preset_name target_file confirm
    list_presets 0

    echo -ne "\n${BLUE}${BOLD}Enter the name of the preset to remove: ${NC}"
    read -r preset_name

    if [ -z "$preset_name" ]; then
        log_info "${RED}Error: Preset name cannot be empty.${NC}"
        exit 1
    fi

    target_file="$PRESET_DIR/${preset_name}.preset"
    if [ ! -f "$target_file" ]; then
        log_info "${RED}Error: Preset '${preset_name}' does not exist.${NC}"
        exit 1
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
    exit 0
}

edit_list() {
    [ ! -f "$AUTH_FILE" ] && mkdir -p "$INSTALL_DIR" && touch "$AUTH_FILE"
    command -v code &>/dev/null && code --wait "$AUTH_FILE" || vim "$AUTH_FILE" || nano "$AUTH_FILE"
    exit 0
}

show_list() {
    local should_exit="${1:-1}"
    local f

    if [ ! -f "$AUTH_FILE" ] || [ ! -s "$AUTH_FILE" ]; then
        log_info "${YELLOW}No authorized functions list found. (Use -e to create one)${NC}"
        exit 0
    fi

    if [ $# -gt 1 ]; then # Greater than 1 because $1 is should_exit
        shift
        log_info "${BLUE}${BOLD}Checking functions:${NC}"
        for f in "$@"; do
            if grep -qFx "$f" <<< "$AUTH_FUNCS"; then
                log_info "   [${GREEN}OK${NC}] -> $f"
            else
                log_info "   [${RED}KO${NC}] -> $f"
            fi
        done
    else
        log_info "${BLUE}${BOLD}Authorized functions (Default):${NC} ${CYAN}(Use -e to edit)${NC}"
        log_info "---------------------------------------"
        tr ',' '\n' < "$AUTH_FILE" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | grep -v '^$' | column -c 80
    fi

    [ "$should_exit" -eq 1 ] && exit 0
}

process_list() {
    local check_args=""

    while [[ $# -gt 0 && ! $1 =~ ^- ]]; do
        check_args+="$1 "
        shift
    done

    if [ ! -f "$AUTH_FILE" ]; then
        mkdir -p "$(dirname "$AUTH_FILE")"
        touch "$AUTH_FILE"
    fi

    if [ -L "$AUTH_FILE" ]; then
        echo "Error: AUTH_FILE must be a regular file, not a symlink"
        exit 1
    fi

    if [ -f "$AUTH_FILE" ]; then
        mapfile -t AUTH_FUNCS_ARR < <(tr ',' '\n' < "$AUTH_FILE" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | grep -v '^$')
    fi
    show_list 1 $check_args
}


# ==============================================================================
#  SECTION 4: CORE ENGINE - SCAN & DETECT
# ==============================================================================

auto_detect_libraries() {
    [ "$DISABLE_AUTO" = true ] && return
    [ "$USE_MLX" = true ] && return

    if ls -R . 2>/dev/null | grep -qiE "mlx|minilibx" || [ -f "libmlx.a" ] || \
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
            TARGET="$make_target"
            log_info "${CYAN}[Auto-Detect] Target found via Makefile: $TARGET${NC}"
            return 0
        fi
    fi

    # 2. Try to detect via recent executable files
    fallback_targets=$(find . -maxdepth 1 -type f -executable ! -name "*.sh" ! -name ".*" -printf '%T@ %p\n' 2>/dev/null | sort -nr | cut -d' ' -f2 | sed 's|^\./||')

    for fallback_target in $fallback_targets; do
        if [ -n "$fallback_target" ] && [ -f "$fallback_target" ] && nm "$fallback_target" &>/dev/null; then
            TARGET="$fallback_target"
            log_info "${CYAN}[Auto-Detect] Target found via file search: $TARGET${NC}"
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
        export MODE_BLACKLIST=true
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

    if [ -z "$AUTH_FUNCS" ] && [ "$MODE_BLACKLIST" = false ]; then
        log_info "${YELLOW}[Warning] Preset loaded but function list is empty.${NC}"
    fi
}

scan_blacklist() {
    local files="$1"
    export BLACKLIST_FUNCS=$(echo "$AUTH_FUNCS" | tr '\n' ' ')
    export USE_JSON

    echo "$files" | tr '\n' '\0' | xargs -0 perl -0777 -e '
        my %forbidden = map { $_ => 1 } split(" ", $ENV{BLACKLIST_FUNCS});
        my $count = 0;
        my $json_mode = $ENV{USE_JSON};

        foreach my $file (@ARGV) {
            open(my $fh, "<", $file) or next;
            my $content = do { local $/; <$fh> };
            close($fh);

            $content =~ s{(/\*.*?\*/)}{ my $c = $1; my $n = () = $c =~ /\n/g; "\n" x $n }egs;
            $content =~ s{//.*}{}g;
            $content =~ s{("(?:\\.|[^"\\])*"|\x27(?:\\.|[^\x27\\])*\x27)}{ my $c = $1; my $n = () = $c =~ /\n/g; "\n" x $n }egs;

            my @lines = split(/\n/, $content);
            for (my $i = 0; $i < @lines; $i++) {
                my $line = $lines[$i];

                while ($line =~ /\b([a-zA-Z_]\w*)\s*\(/g) {
                    my $fname = $1;

                    if ($forbidden{$fname}) {
                        my $clean_file = $file;
                        $clean_file =~ s|^\./||;
                        if ($json_mode ne "true") {
                            printf "  \033[31m[FORBIDDEN]\033[0m -> \033[1m%-15s\033[0m in \033[34m%s:%d\033[0m\n", $fname, $clean_file, $i + 1;
                        } else {
                            print "MATCH|-> $fname|in $clean_file:$i+1\n";
                        }
                        $count++;
                    }
                }
            }
        }
        if ($json_mode ne "true") {
            if ($count == 0) {
                print "  \033[32m[OK]\033[0m No forbidden functions detected in blacklist mode.\n";
            } else {
                print "\n  \033[0;31m[!] Total: $count forbidden function(s) detected.\033[0m\n";
            }
        }
    '
}

scan_whitelist() {
    local files="$1"
    local user_funcs="$2"
    local keywords="if while for return sizeof switch else case default do static const volatile struct union enum typedef extern inline unsigned signed short long int char float double void bool va_arg va_start va_end va_list NULL del f"
    local macros="WIFEXITED WEXITSTATUS WIFSIGNALED WTERMSIG S_ISDIR S_ISREG"
    export USE_JSON

    export ALLOW_MLX=0
    [ "$USE_MLX" = true ] && export ALLOW_MLX=1

    export WHITELIST="$(echo "$AUTH_FUNCS" | tr '\n' ' ') $user_funcs $keywords $macros"

    echo "$files" | tr '\n' '\0' | xargs -0 perl -0777 -e '
        my %safe = map { $_ => 1 } split(" ", $ENV{WHITELIST});
        my $allow_mlx = $ENV{ALLOW_MLX};
        my $count = 0;
        my $json_mode = $ENV{USE_JSON};

        foreach my $file (@ARGV) {
            if ($allow_mlx == 1 && ($file =~ m{/mlx_} || $file =~ m{/mlx/} || $file =~ m{/minilibx/})) {
                next;
            }
            open(my $fh, "<", $file) or next;
            my $content = do { local $/; <$fh> };
            close($fh);

            $content =~ s{(/\*.*?\*/)}{ my $c = $1; my $n = () = $c =~ /\n/g; "\n" x $n }egs;
            $content =~ s{//.*}{}g;
            $content =~ s{("(?:\\.|[^"\\])*"|\x27(?:\\.|[^\x27\\])*\x27)}{ my $c = $1; my $n = () = $c =~ /\n/g; "\n" x $n }egs;

            my @lines = split(/\n/, $content);
            for (my $i = 0; $i < @lines; $i++) {
                my $line = $lines[$i];

                while ($line =~ /\b([a-zA-Z_]\w*)\s*\(/g) {
                    my $fname = $1;

                    next if length($fname) <= 2;
                    next if $safe{$fname};
                    next if ($allow_mlx == 1 && $fname =~ /^mlx_/);

                    my $clean_file = $file;
                    $clean_file =~ s|^\./||;
                    if ($json_mode ne "true") {
                        printf "  \033[31m[FORBIDDEN]\033[0m -> \033[1m%-15s\033[0m in \033[34m%s:%d\033[0m\n", $fname, $clean_file, $i + 1;
                    } else {
                        print "MATCH|-> $fname|in $clean_file:$i+1\n";
                    }
                    $count++;
                }
            }
        }
        if ($json_mode ne "true") {
            if ($count == 0) {
                print "  \033[32m[OK]\033[0m No unauthorized functions detected.\n";
            } else {
                print "\n  \033[0;31m[!] Total: $count unauthorized function(s) detected.\033[0m\n";
            }
        }
    '
}

source_scan() {
    select_preset
    load_preset "$SELECTED_PRESET" || { log_info "${RED}Error: Preset not found.${NC}"; exit 1; }

    local files_list=$(find . -maxdepth 5 -type f \( -name "*.c" -o -name "*.cpp" \))
    local nb_files=$(echo "$files_list" | wc -l | tr -d ' ')
    [ "$nb_files" -eq 0 ] && exit 1

    local raw_preset=$(cat "$AUTH_FILE" 2>/dev/null)
    parse_preset_flags "$raw_preset"

    log_info "${BLUE}Scanning $nb_files source files...${NC}\n"
    local scan_output
    if [ "$MODE_BLACKLIST" = true ]; then
        scan_output=$(scan_blacklist "$files_list")
    else
        local my_funcs=$(get_user_defined_funcs)
        scan_output=$(scan_whitelist "$files_list" "$my_funcs")
    fi

    if [ "$USE_JSON" = true ]; then
        export JSON_RAW_DATA="$scan_output"
        export IS_SOURCE_SCAN=true
        generate_json_output
    else
        echo -e "$scan_output"
        log_info "\n${GREEN}Source audit complete.${NC}"
    fi
    exit 0
}

extract_undefined_symbols() {
    raw_funcs=$(nm -u "$TARGET" 2>/dev/null | awk '{print $NF}' | sed -E 's/@.*//' | sort -u)

    NM_RAW_DATA=$(find . -not -path '*/.*' -type f \( -name "*.o" -o -name "*.a" \) ! -name "$TARGET" ! -path "*mlx*" ! -path "*MLX*" -print0 2>/dev/null | xargs -0 -P4 nm -A 2>/dev/null)
    ALL_UNDEFINED=$(grep " U " <<< "$NM_RAW_DATA")
    MY_DEFINED=$(grep -E ' [TRD] ' <<< "$NM_RAW_DATA" | awk '{print $NF}' | sort -u)
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

        if [ "$MODE_BLACKLIST" = true ]; then
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
            printf "   [${RED}FORBIDDEN${NC}] -> %s\n" "$f_name"
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
                        echo -e "          ${YELLOW}↳ Location: ${BLUE}${loc_prefix}${NC}: ${CYAN}${s_crop}${NC}"
                    else
                        echo -e "          ${YELLOW}↳ Location: ${BLUE}${loc_prefix}${NC}"
                    fi
                fi
            done <<< "$specific_locs"
        elif [ -z "$SPECIFIC_FILES" ]; then
            # Warning block (Found in binary but not in .c)
            printf "   [${YELLOW}WARNING${NC}]   -> %s\n" "$f_name"
            local objects=$(grep -E " U ${f_name}$" <<< "$ALL_UNDEFINED" | awk -F: '{split($1, path, "/"); print path[length(path)]}' | sort -u | tr '\n' ' ')
            echo -ne "          ${YELLOW}↳ Found in objects: ${BLUE}${objects}${NC}"
            [[ "$f_name" =~ ^(strlen|memset|memcpy|printf|puts|putchar)$ ]] && echo -e " ${CYAN}(Builtin?)${NC}" || echo -e " ${CYAN}(Sync?)${NC}"
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

    if [ "$USE_JSON" = true ]; then
        generate_json_output "$count"
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

    current_src_data=$(find . -name "*.c" -not -path '*/.*' -type f -exec stat -c "%s" {} + 2>/dev/null | awk '{s+=$1} END {print s}')
    current_src_lines=$(find . -name "*.c" -not -path '*/.*' -type f -exec wc -l {} + 2>/dev/null | awk '{s+=$1} END {print s}')
    bin_mtime=$(stat -c %Y "$TARGET" 2>/dev/null)
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
    printf "  %-24s %s\n" "-s, --source" "Scan source files for unauthorized C functions (use after --no-auto to force menu)"

    echo -e "\n${BOLD}Library Filters:${NC}"
    printf "  %-24s %s\n" "-mlx" "Ignore MiniLibX internal calls"
    printf "  %-24s %s\n" "-lm" "Ignore Math library internal calls"

    echo -e "\n${BOLD}Maintenance:${NC}"
    printf "  %-24s %s\n" "-t, --time" "Show execution duration"
    printf "  %-24s %s\n" "--version" "Show version's forbCheck"
    printf "  %-24s %s\n" "-up, --update" "Check and install latest version"
    printf "  %-24s %s\n" "--remove" "Remove ForbCheck"
    exit 0
}

update_script() {
    local tmp_file="/tmp/forb_update.sh"
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
                exit 0
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
        return 1
    fi
    exit 0
}

auto_check_update() {
    # Skip interactive update check if running in JSON mode (prevents CI hangs)
    [ "$USE_JSON" = true ] && return

    local remote_version choice

    # Silent curl with 1-second timeout to prevent lag
    remote_version=$(curl -s --max-time 1 "$UPDATE_URL" | grep "^VERSION=" | head -n 1 | cut -d'"' -f2)

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
            sed -i '/alias forb=/d' ~/.zshrc ~/.bashrc 2>/dev/null
            rm -rf "$INSTALL_DIR"
            log_info "${GREEN}[✔] ForbCheck has been successfully removed.${NC}"
            exit 0
            ;;
        *)
            log_info "${BLUE}Uninstallation aborted.${NC}"
            exit 0
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
        exit 1
    fi
}

# ==============================================================================
#  SECTION 6: MAIN DISPATCHER & EXECUTION
# ==============================================================================

# 1. Pre-process arguments (handle split/combined flags)
args=()
for arg in "$@"; do
    if [[ "$arg" == "-mlx" || "$arg" == "-lm" || "$arg" == "-up" || "$arg" == "-op" || "$arg" == "-lp" || "$arg" == "-cp" || "$arg" == "-rp" || "$arg" == "-gp" || "$arg" == "-np" ]]; then
        args+=("$arg")
    elif [[ "$arg" == "--"* ]]; then
        args+=("$arg")
    elif [[ "$arg" =~ ^-[a-zA-Z]{2,}$ ]]; then
        for (( i=1; i<${#arg}; i++ )); do
            args+=("-${arg:$i:1}")
        done
    else
        args+=("$arg")
    fi
done
set -- "${args[@]}"

# 2. Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help) show_help ;;
        --version) log_info "V$VERSION"; exit 0;;
        --json) USE_JSON=true; shift ;;
        -up|--update) update_script ;;
        --remove) uninstall_script ;;
        --no-auto) DISABLE_AUTO=true; shift ;;
        -b|--blacklist) export MODE_BLACKLIST=true; shift ;;
        -s|--scan-source) FORCE_SOURCE_SCAN=true; shift ;;
        -v) VERBOSE=true; shift ;;
        -p|--full-path) FULL_PATH=true; shift ;;
        -a) SHOW_ALL=true; shift ;;
        -mlx) USE_MLX=true; shift ;;
        -lm) USE_MATH=true; shift ;;
        --preset|-P) USE_PRESET=1; shift ;;
        -np|--no-preset) DISABLE_PRESET=true; shift ;;
        -gp|--get-presets) get_presets "manual";;
        -lp|--list-presets) list_presets ;;
        -op|--open-presets) open_presets ;;
        -cp|--create-presets) create_preset ;;
        -rp|--remove-preset) remove_preset ;;
        -e) edit_list ;;
        -l|--list) shift; process_list "$@" ;;
        -t|--time) SHOW_TIME=true; shift ;;
        -f)
            shift
            while [[ $# -gt 0 && ! "$1" =~ ^- ]]; do
                SPECIFIC_FILES+="$1 "
                shift
            done
            continue
            ;;
        -*) echo -e "${RED}Unknown option: $1${NC}"; exit 1 ;;
        *) TARGET=$1; shift ;;
    esac
done

check_dependencies

if [ "$USE_JSON" = false ]; then
    clear -x
    log_info "${YELLOW}╔═════════════════════════════════════╗${NC}"
    log_info "${YELLOW}║              ForbCheck              ║${NC}"
    log_info "${YELLOW}╚═════════════════════════════════════╝${NC}"
fi

# 4. Target Validation & Fallback
if [ "$FORCE_SOURCE_SCAN" = true ]; then
    source_scan
fi

if [ -z "$TARGET" ]; then
    if ! auto_detect_target; then
        log_info "${RED}[Auto-Detect] No binary found.${YELLOW} -> Falling back to Source Scan...${NC}\n"
        source_scan
    fi
elif [ ! -f "$TARGET" ]; then
    log_info "${YELLOW}[Warning] Target '$TARGET' not found. Falling back to Source Scan...${NC}\n"
    source_scan
fi

if ! nm "$TARGET" &>/dev/null; then
    if [ "$USE_JSON" = true ]; then
         echo "{\"target\":\"$TARGET\",\"version\":\"$VERSION\",\"error\":\"$TARGET is not a valid binary or object file.\",\"status\":\"FAILURE\"}"
    else
         log_info "${RED}Error: $TARGET is not a valid binary or object file.${NC}"
    fi
    exit 1
fi

# 5. Pre-run Setup (Updates, Cache, Libraries)
auto_check_update
check_binary_cache
auto_detect_libraries

# 6. Load Presets
if [ "$USE_PRESET" -eq 0 ] && [ "$DISABLE_PRESET" = false ] && [ -n "$TARGET" ]; then
    target_name=$(basename "$TARGET")
    if [ -f "$PRESET_DIR/${target_name}.preset" ]; then
        USE_PRESET=1
        log_info "${CYAN}[Auto-Detect] Preset '${target_name}.preset' detected and loaded automatically.${NC}"
    fi
fi

if [ "$USE_PRESET" -eq 1 ]; then
    load_preset "$(basename "$TARGET")"
else
    AUTH_FILE="$PRESET_DIR/default.preset"
    if [ ! -f "$AUTH_FILE" ] || [ ! -s "$AUTH_FILE" ]; then
        mkdir -p "$HOME/.forb"
        touch "$AUTH_FILE"
        log_info "${YELLOW}[Warning] No preset loaded and default.preset is empty. Using empty list.${NC}"
    fi
fi
RAW_PRESET=$(cat "$AUTH_FILE" 2>/dev/null)
parse_preset_flags "$RAW_PRESET"

# 7. Print Execution Details
log_info "${BLUE}Target bin:${NC} $TARGET\n"

if [ "$SET_WARNING" = true ]; then
    log_info "${YELLOW}Warning:${NC} Source content is newer than the binary."
    log_info "         The results might not reflect your latest changes."
    log_info "         Consider ${GREEN}recompiling${NC} to be sure."
fi

[ -n "$SPECIFIC_FILES" ] && log_info "${BLUE}Scope      :${NC} $SPECIFIC_FILES"

log_info "${BLUE}${BOLD}Execution:${NC}"
log_info "-------------------------------------------------"

# 8. Run Core Analysis
START_TIME=$(date +%s.%N)

run_analysis
total_errors=$?

# 9. Print Results
DURATION=$(echo "$(date +%s.%N) - $START_TIME" | bc 2>/dev/null || echo "0")

log_info "-------------------------------------------------\n"
if [ $total_errors -eq 0 ]; then
    log_info "\t\t${GREEN}RESULT: PERFECT"
else
    log_info "\t\t${RED}RESULT: FAILURE"
fi

if [ "$SHOW_TIME" = true ]; then
    [ "$USE_JSON" = false ] && printf " (%0.2fs)" "$DURATION"
fi

log_info "${NC}"

[ $total_errors -ne 0 ] && exit 1
