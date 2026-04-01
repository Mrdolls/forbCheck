#!/bin/bash

# --- COLOR MANAGEMENT ---
if [[ -t 1 ]]; then
    BOLD="\033[1m"; GREEN="\033[0;32m"; RED="\033[0;31m"; YELLOW="\033[0;33m"; BLUE="\033[0;34m"; CYAN="\033[0;36m"; NC="\033[0m"
else
    BOLD=""; GREEN=""; RED=""; YELLOW=""; BLUE=""; CYAN=""; NC=""
fi

VERSION="1.9.2"
INSTALL_DIR="$HOME/.forb"
PRESET_DIR="$INSTALL_DIR/presets"
AUTH_FILE="$PRESET_DIR/default.preset"
USE_PRESET=0
UPDATE_URL="https://raw.githubusercontent.com/Mrdolls/forb/main/forb.sh"

SHOW_ALL=false; USE_MLX=false; USE_MATH=false; FULL_PATH=false; VERBOSE=false; TARGET=""; SPECIFIC_FILES="" ; SHOW_TIME=false ; DISABLE_AUTO=false ; DISABLE_PRESET=false

# --- FUNCTIONS ---

show_help() {
    echo -e "${BOLD}ForbCheck v$VERSION${NC}"
    echo -e "Usage: forb [options] <target> [-f <files...>]\n"

    echo -e "${BOLD}Arguments:${NC}"
    printf "  %-24s %s\n" "<target>" "Executable or library to analyze"

    echo -e "\n${BOLD}General:${NC}"
    printf "  %-24s %s\n" "-h, --help" "Show help message"
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
    printf "  %-24s %s\n" "-up, --update" "Check and install latest version"
    printf "  %-24s %s\n" "--remove" "Remove ForbCheck"
    exit 0
}

version_to_int() {
    echo "$1" | sed 's/v//' | awk -F. '{ printf("%d%03d%03d\n", $1,$2,$3); }'
}

get_user_defined_funcs() {
    local files=$(find . -maxdepth 5 -type f \( -name "*.c" -o -name "*.cpp" \))
    [ -z "$files" ] && return

    perl -0777 -ne '
        s/\/\*.*?\*\///gs;
        s/\/\/.*//g;
        while (/\b([a-zA-Z_]\w*)\s*(\((?:[^()]++|(?2))*\))\s*\{/gs) {
            print "$1\n";
        }
    ' $files 2>/dev/null | grep -vE "^(if|while|for|switch|else|return)$" | sort -u | tr '\n' ' '
}

select_preset() {
    if [ "$DISABLE_AUTO" != "true" ]; then
        local current_dir=$(basename "$PWD")
        local current_dir_lower=$(echo "$current_dir" | tr '[:upper:]' '[:lower:]')
        for preset_file in "$PRESET_DIR"/*.preset; do
            [ -e "$preset_file" ] || continue
            local base_name=$(basename "$preset_file" .preset)
            local base_name_lower=$(echo "$base_name" | tr '[:upper:]' '[:lower:]')

            if [ "$current_dir_lower" == "$base_name_lower" ]; then
                echo -e "${CYAN}Auto-detected project: ${BOLD}${base_name}${NC}"
                export SELECTED_PRESET="$base_name"
                return 0
            fi
        done
        for preset_file in "$PRESET_DIR"/*.preset; do
            [ -e "$preset_file" ] || continue
            local base_name=$(basename "$preset_file" .preset)
            local base_name_lower=$(echo "$base_name" | tr '[:upper:]' '[:lower:]')

            if [[ "$current_dir_lower" == *"$base_name_lower"* ]]; then
                echo -e "${CYAN}Smart-detected project: ${BOLD}${base_name}${NC} (from folder '${current_dir}')"
                export SELECTED_PRESET="$base_name"
                return 0
            fi
        done
    fi
    [ "$DISABLE_AUTO" == "true" ] && echo -e "\n${YELLOW}${BOLD}Auto-detection disabled by --no-auto flag.${NC}"
    echo -e "${CYAN}${BOLD}Select a project preset:${NC}"

    local presets=($(ls "$PRESET_DIR" 2>/dev/null | grep '\.preset$' | sed 's/\.preset//'))

    if [ ${#presets[@]} -eq 0 ]; then
        echo -e "${RED}Error: No presets found in $PRESET_DIR.${NC}"
        exit 1
    fi
    PS3=$'\n\033[1;36mEnter the number of your preset: \033[0m'
    select choice in "${presets[@]}"; do
        if [ -n "$choice" ]; then
            export SELECTED_PRESET="$choice"
            echo -e "${GREEN}Loaded preset: ${BOLD}$SELECTED_PRESET${NC}"
            break
        else
            echo -e "${RED}Invalid selection. Please enter a valid number.${NC}"
        fi
    done
}

source_scan() {
    select_preset
    load_preset "$SELECTED_PRESET" || { echo -e "${RED}Error: Preset not found.${NC}"; exit 1; }

    local files_list=$(find . -maxdepth 5 -type f \( -name "*.c" -o -name "*.cpp" \))
    local nb_files=$(echo "$files_list" | wc -l | tr -d ' ')
    [ "$nb_files" -eq 0 ] && exit 1

    echo -e "${BLUE}Building compiler-grade function shield...${NC}"
    local my_funcs=$(get_user_defined_funcs)

    echo -e "${BLUE}Scanning $nb_files source files...${NC}\n"

    local authorized=$(cat "$AUTH_FILE" 2>/dev/null | tr ',' ' ' | tr '\n' ' ')

    export ALLOW_MLX=0
    if [[ "$authorized" == *"ALL_MLX"* ]]; then
        export ALLOW_MLX=1
    fi

    if [[ "$authorized" == *"ALL_MATH"* ]]; then
        local math_funcs="cos sin tan acos asin atan atan2 cosh sinh tanh exp frexp ldexp log log10 modf pow sqrt ceil fabs floor fmod round trunc abs labs"
        authorized="$authorized $math_funcs"
    fi

    local keywords="if while for return sizeof switch else case default do static const volatile struct union enum typedef extern inline unsigned signed short long int char float double void bool va_arg va_start va_end va_list NULL del f"
    local macros="WIFEXITED WEXITSTATUS WIFSIGNALED WTERMSIG S_ISDIR S_ISREG"

    export WHITELIST="$authorized $my_funcs $keywords $macros"
    echo "$files_list" | tr '\n' '\0' | xargs -0 perl -0777 -e '
        my %safe = map { $_ => 1 } split(" ", $ENV{WHITELIST});
        my $allow_mlx = $ENV{ALLOW_MLX};
        my $found = 0;

        foreach my $file (@ARGV) {
            # MODIFICATION ICI : On passe au fichier suivant si c est un fichier source de la MLX
            if ($allow_mlx == 1 && ($file =~ m{/mlx_} || $file =~ m{/mlx/} || $file =~ m{/minilibx/})) {
                next;
            }

            open(my $fh, "<", $file) or next;
            my $content = do { local $/; <$fh> };
            close($fh);

            # Nettoyage
            $content =~ s{(/\*.*?\*/)}{ my $c = $1; my $n = () = $c =~ /\n/g; "\n" x $n }egs;
            $content =~ s{//.*}{}g;
            $content =~ s{("(?:\\.|[^"\\])*")}{ my $c = $1; my $n = () = $c =~ /\n/g; "\n" x $n }egs;
            $content =~ s{(\x27(?:\\.|[^\x27\\])*\x27)}{ my $c = $1; my $n = () = $c =~ /\n/g; "\n" x $n }egs;

            my @lines = split(/\n/, $content);
            for (my $i = 0; $i < @lines; $i++) {
                my $line = $lines[$i];

                while ($line =~ /\b([a-zA-Z_]\w*)\s*\(/g) {
                    my $fname = $1;

                    next if length($fname) <= 2;
                    next if $safe{$fname};

                    # MODIFICATION ICI : On pardonne les appels mlx_ dans TES fichiers
                    next if ($allow_mlx == 1 && $fname =~ /^mlx_/);

                    my $clean_file = $file;
                    $clean_file =~ s|^\./||;

                    printf "  \033[31m[FORBIDDEN]\033[0m -> \033[1m%-15s\033[0m in \033[34m%s:%d\033[0m\n", $fname, $clean_file, $i + 1;
                    $found = 1;
                }
            }
        }
        if (!$found) { print "  \033[32m[OK]\033[0m No unauthorized functions detected.\n"; }
    '

    echo -e "\n${GREEN}Source audit complete.${NC}"
    exit 0
}

load_preset() {
    local target_name="$1"

    mkdir -p "$PRESET_DIR"
    AUTH_FILE="$PRESET_DIR/${target_name}.preset"

    if [ ! -f "$AUTH_FILE" ]; then
        echo -e "\033[31mError: No preset found for '${target_name}'.\033[0m"
        local available_presets
        available_presets=$(find "$PRESET_DIR" -maxdepth 1 -name "*.preset" -exec basename {} .preset \; | tr '\n' ',' | sed 's/,/, /g' | sed 's/, $//')
        if [ -z "$available_presets" ]; then
            echo -e "\033[33mNo presets available.\033[0m"
        else
            echo -e "Available presets: \033[36m$available_presets\033[0m"
        fi
        exit 1
    fi
}

list_presets() {
    local should_exit="${1:-1}"
    mkdir -p "$PRESET_DIR"
    local available_presets
    available_presets=$(find "$PRESET_DIR" -maxdepth 1 -name "*.preset" -exec basename {} .preset \; | tr '\n' ',' | sed 's/,/, /g' | sed 's/, $//')
    if [ -z "$available_presets" ]; then
        echo -e "\033[33mNo presets available in $PRESET_DIR\033[0m"
    else
        echo -e "Available presets: \033[36m$available_presets\033[0m"
    fi
    if [ "$should_exit" -eq 1 ]; then
        exit 0
    fi
}

get_presets() {
    if [[ "$1" == "manual" ]]; then
        echo -ne "${YELLOW}${BOLD}Warning: This will download default presets. Any existing preset with the same name will be overwritten. Continue? (y/n): ${NC}"
        read -r choice
        case "$choice" in
            [yY][eE][sS]|[yY]) ;;
            *)
                echo -e "${BLUE}Operation aborted.${NC}"
                exit 0
                ;;
        esac
    fi

    echo -e "${BLUE}Downloading default presets from GitHub...${NC}"
    mkdir -p "$PRESET_DIR"
    if curl -sL "https://github.com/Mrdolls/forbCheck/archive/refs/heads/main.tar.gz" | tar -xz -C /tmp "forbCheck-main/presets" 2>/dev/null; then

        if [[ "$1" == "manual" ]]; then
            cp -r /tmp/forbCheck-main/presets/* "$PRESET_DIR/" 2>/dev/null
            echo -e "${GREEN}[✔] Default presets successfully restored!${NC}"
        else
            local added=0
            for preset in /tmp/forbCheck-main/presets/*; do
                local base_name=$(basename "$preset")
                if [ ! -f "$PRESET_DIR/$base_name" ]; then
                    cp "$preset" "$PRESET_DIR/"
                    added=$((added + 1))
                fi
            done

            if [ $added -gt 0 ]; then
                echo -e "${GREEN}[✔] Added $added new preset(s) during update!${NC}"
            else
                echo -e "${GREEN}[✔] Presets checked (no user modifications overwritten).${NC}"
            fi
        fi
        rm -rf "/tmp/forbCheck-main"
    else
        echo -e "${RED}[✘] Error: Failed to download presets. Check your connection.${NC}"
    fi
    if [[ "$1" == "manual" ]]; then
        exit 0
    fi
}

open_presets() {
    mkdir -p "$PRESET_DIR"
    echo -e "\033[32mOpening presets directory: $PRESET_DIR\033[0m"
    if command -v explorer.exe > /dev/null; then
        (cd "$PRESET_DIR" && explorer.exe .)
    elif command -v xdg-open > /dev/null; then
        xdg-open "$PRESET_DIR"
    elif command -v open > /dev/null; then
        open "$PRESET_DIR"
    else
        echo -e "\033[31mError: Could not open the folder automatically. You can find it at: $PRESET_DIR\033[0m"
    fi
    exit 0
}

create_preset() {
    mkdir -p "$PRESET_DIR"
    echo -ne "${BLUE}${BOLD}Enter the name of the new preset (e.g., minishell): ${NC}"
    read -r preset_name
    if [ -z "$preset_name" ]; then
        echo -e "${RED}Error: Preset name cannot be empty.${NC}"
        exit 1
    fi
    preset_name=$(echo "$preset_name" | tr ' ' '-')

    local new_file="$PRESET_DIR/${preset_name}.preset"
    if [ -f "$new_file" ]; then
        echo -e "${YELLOW}Preset '${preset_name}' already exists. Opening it for edition...${NC}"
    else
        echo -e "${GREEN}Creating new preset '${preset_name}'...${NC}"
        touch "$new_file"
    fi
    command -v code &>/dev/null && code --wait "$new_file" || vim "$new_file" || nano "$new_file"

    echo -e "${GREEN}[✔] Preset '${preset_name}' saved!${NC}"
    exit 0
}

remove_preset() {
    list_presets 0
    echo -ne "\n${BLUE}${BOLD}Enter the name of the preset to remove: ${NC}"
    read -r preset_name
    if [ -z "$preset_name" ]; then
        echo -e "${RED}Error: Preset name cannot be empty.${NC}"
        exit 1
    fi
    local target_file="$PRESET_DIR/${preset_name}.preset"
    if [ ! -f "$target_file" ]; then
        echo -e "${RED}Error: Preset '${preset_name}' does not exist.${NC}"
        exit 1
    fi
    echo -ne "${YELLOW}Are you sure you want to delete '${preset_name}'? (y/n): ${NC}"
    read -r confirm
    case "$confirm" in
        [yY][eE][sS]|[yY])
            rm -f "$target_file"
            echo -e "${GREEN}[✔] Preset '${preset_name}' has been removed.${NC}"
            ;;
        *)
            echo -e "${BLUE}Deletion aborted.${NC}"
            ;;
    esac
    exit 0
}

edit_list() {
    [ ! -f "$AUTH_FILE" ] && mkdir -p "$INSTALL_DIR" && touch "$AUTH_FILE"
    command -v code &>/dev/null && code --wait "$AUTH_FILE" || vim "$AUTH_FILE" || nano "$AUTH_FILE"; exit 0
}

update_script() {
    echo -e "${C_BLUE}Checking for updates...${RC}"
    local raw_url="https://raw.githubusercontent.com/Mrdolls/forb/main/forb.sh"
    local tmp_file="/tmp/forb_update.sh"
    if curl -sL "$raw_url" -o "$tmp_file"; then
        local remote_version=$(grep "^VERSION=" "$tmp_file" | cut -d'"' -f2)
        if [ "$(version_to_int "$remote_version")" -gt "$(version_to_int "$VERSION")" ]; then
            echo -e "${YELLOW}New version found: $remote_version Updating...${RC}"
            mv "$tmp_file" "$0"
            chmod +x "$0"
            get_presets
            echo -e "${GREEN}ForbCheck has been updated to $remote_version!${RC}"
            exit 0
        else
            echo -e "${GREEN}ForbCheck is already up to date ($VERSION).${RC}"
            rm -f "$tmp_file"
        fi
    else
        echo -e "${RED}Error: Failed to download update from GitHub.${RC}"
        return 1
    fi
    exit 0
}

uninstall_script() {
    echo -ne "${RED}${BOLD}Warning: You are about to uninstall ForbCheck. All configurations will be lost. Continue? (y/n): ${NC}"
    read -r choice
    case "$choice" in
        [yY][eE][sS]|[yY])
            echo -e "${YELLOW}Uninstalling ForbCheck...${NC}"
            sed -i '/alias forb=/d' ~/.zshrc ~/.bashrc 2>/dev/null
            rm -rf "$INSTALL_DIR"
            echo -e "${GREEN}[✔] ForbCheck has been successfully removed.${NC}"
            exit 0
            ;;
        *)
            echo -e "${BLUE}Uninstallation aborted.${NC}"
            exit 0
            ;;
    esac
}

crop_line() {
    local func=$1; local code=$2
    if [ ${#code} -gt 65 ]; then
        echo "$code" | awk -v f="$func" '{
            pos = index($0, f);
            start = (pos > 20) ? pos - 20 : 0;
            print "..." substr($0, start, 60) "..."
        }'
    else
        echo "$code"
    fi
}
auto_detect_libraries() {
    [ "$DISABLE_AUTO" = true ] && return
    [ "$USE_MLX" = true ] && return

    if ls -R . 2>/dev/null | grep -qiE "mlx|minilibx" || [ -f "libmlx.a" ] || \
        nm "$TARGET" 2>/dev/null | grep -qiE "mlx_"; then
        USE_MLX=true
        echo -e "${CYAN}[Auto-Detect] MiniLibX detected (Use --no-auto to scan everything)${NC}"
    fi
    if [ "$USE_MATH" = false ] && [ -n "$TARGET" ]; then
        if grep -qE "\-lm\b" Makefile 2>/dev/null || \
           nm -u "$TARGET" 2>/dev/null | grep -qE "\b(sin|cos|sqrt|pow|exp|atan2)f?\b"; then
            USE_MATH=true
            echo -e "${CYAN}[Auto-Detect] Math library detected (Use --no-auto to scan everything)${NC}"
        fi
    fi
}

show_list() {
    local should_exit="${1:-1}"
    if [ ! -f "$AUTH_FILE" ] || [ ! -s "$AUTH_FILE" ]; then
        echo -e "${YELLOW}No authorized functions list found. (Use -e to create one)${NC}"
        exit 0
    fi
    if [ $# -gt 0 ]; then
        echo -e "${BLUE}${BOLD}Checking functions:${NC}"
        for f in "$@"; do
            if grep -qFx "$f" <<< "$AUTH_FUNCS"; then
                echo -e "   [${GREEN}OK${NC}] -> $f"
            else
                echo -e "   [${RED}KO${NC}] -> $f"
            fi
        done
    else
        if [ ! -f "$AUTH_FILE" ] || [ ! -s "$AUTH_FILE" ]; then
            echo -e "${YELLOW}No authorized functions list found. (Use -e to create one)${NC}"
        else
            echo -e "${BLUE}${BOLD}Authorized functions (Default):${NC} ${CYAN}(Use -e to edit)${NC}"
            echo "---------------------------------------"
            tr ',' '\n' < "$AUTH_FILE" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | grep -v '^$' | column -c 80
        fi
    fi
    if [ "$should_exit" -eq 1 ]; then
        exit 0
    fi
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
    AUTH_FUNCS=$(tr ',' ' ' < "$AUTH_FILE" 2>/dev/null | tr -s ' ' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    show_list $check_args
}

clean_code_snippet() {
    local snippet="$1"
    local f_name="$2"
    snippet=$(echo "$snippet" | sed 's|//.*||')
    snippet=$(echo "$snippet" | sed 's|/\*.*\*/||g')
    if echo "$snippet" | grep -qE "\b${f_name}\b"; then
        echo "$snippet"
        return 0
    else
        return 1
    fi
}

auto_detect_target() {
    if [ -f "Makefile" ]; then
        local make_target=$(grep -m 1 -E "^NAME[[:space:]]*=" Makefile | cut -d '=' -f2 | tr -d ' ' | tr -d '"' | tr -d "'")
        if [ -n "$make_target" ] && [ -f "$make_target" ] && nm "$make_target" &>/dev/null; then
            TARGET="$make_target"
            echo -e "${CYAN}[Auto-Detect] Target found via Makefile: $TARGET${NC}"
            return 0
        fi
    fi
    local fallback_targets=$(find . -maxdepth 1 -type f -executable ! -name "*.sh" ! -name ".*" -printf '%T@ %p\n' 2>/dev/null | sort -nr | cut -d' ' -f2 | sed 's|^\./||')

    for fallback_target in $fallback_targets; do
        if [ -n "$fallback_target" ] && [ -f "$fallback_target" ] && nm "$fallback_target" &>/dev/null; then
            TARGET="$fallback_target"
            echo -e "${CYAN}[Auto-Detect] Target found via file search: $TARGET${NC}"
            return 0
        fi
    done

    return 1
}

run_analysis() {
    cache_file="$INSTALL_DIR/.forb_cache"
    mkdir -p "$INSTALL_DIR"
    [ ! -f "$cache_file" ] && touch "$cache_file"
    local raw_funcs=$(nm -u "$TARGET" 2>/dev/null | awk '{print $NF}' | sed -E 's/@.*//' | sort -u)
    local forbidden_list=""
    local errors=0

    local single_file_mode=false
    if [ -n "$SPECIFIC_FILES" ] && [ $(echo "$SPECIFIC_FILES" | wc -w) -eq 1 ]; then
        single_file_mode=true
    fi
    while read -r func; do
        [ -z "$func" ] && continue
        [[ "$func" =~ ^(_|ITM|edata|end|bss_start) ]] && continue
        [ "$USE_MLX" = true ] && [[ "$func" =~ ^(X|shm|gethostname|puts|exit|strerror) ]] && continue
        [ "$USE_MATH" = true ] && [[ "$func" =~ ^(abs|cos|sin|sqrt|pow|exp|log|fabs|floor)f?$ ]] && continue

        grep -qx "$func" <<< "$MY_DEFINED" && continue

        if grep -qx "$func" <<< "$AUTH_FUNCS"; then
            [ "$SHOW_ALL" = true ] && printf "   [${GREEN}OK${NC}]         -> %s\n" "$func"
        else
            if grep -qE " U ${func}$" <<< "$ALL_UNDEFINED"; then
                forbidden_list+="${func} "
                if [ -z "$SPECIFIC_FILES" ]; then errors=$((errors + 1)); fi
            fi
        fi
    done <<< "$raw_funcs"
    local grep_res=""

        if [ -n "$SPECIFIC_FILES" ]; then
            local include_flags=""
            IFS=' ' read -ra FILES_ARRAY <<< "$SPECIFIC_FILES"
        for f in "${FILES_ARRAY[@]}"; do
            if [[ "$f" =~ \.\. ]] || [[ "$f" =~ ^/ ]]; then
                echo "Error: Invalid file path: $f"
                exit 1
            fi
            f_escaped=$(printf '%s\n' "$f" | sed 's/[[\.*^$/]/\\&/g')
            include_flags+=" --include=\"$f_escaped\""
        done

            for f_name in $forbidden_list; do
            grep_res+=$(grep -rHE \"\\b${f_name}\\b\" . $include_flags -n 2>/dev/null | grep -vE "mlx|MLX")$'\n'
            done
    else
        for f_name in $forbidden_list; do
            grep_res+=$(grep -rHE "\b${f_name}\b" . --include="*.c" -n 2>/dev/null | grep -vE "mlx|MLX")$'\n'
        done
    fi
        for f_name in $forbidden_list; do
            local specific_locs=$(grep -E ":.*\b${f_name}\b" <<< "$grep_res")

        if [ -n "$specific_locs" ]; then
            printf "   [${RED}FORBIDDEN${NC}] -> %s\n" "$f_name"
            [ -n "$SPECIFIC_FILES" ] && errors=$((errors + 1))

            while read -r line; do
                [ -z "$line" ] && continue
                local f_path=$(echo "$line" | cut -d: -f1)
                local l_num=$(echo "$line" | cut -d: -f2)
                local snippet=$(echo "$line" | cut -d: -f3- | sed 's/^[[:space:]]*//')

                if ! clean_code_snippet "$snippet" "$f_name" > /dev/null; then
                        continue
                fi
                local clean_snippet=$(clean_code_snippet "$snippet" "$f_name")
                local display_name=$( [ "$FULL_PATH" = true ] && echo "$f_path" | sed 's|^\./||' || basename "$f_path" )

                local loc_prefix=$( [ "$single_file_mode" = true ] && [ "$VERBOSE" = false ] && echo "line ${l_num}" || echo "${display_name}:${l_num}" )

                if [ "$VERBOSE" = true ]; then
                    local s_crop=$(crop_line "$f_name" "$snippet")
                    echo -e "          ${YELLOW}↳ Location: ${BLUE}${loc_prefix}${NC}: ${CYAN}${s_crop}${NC}"
                else
                    echo -e "          ${YELLOW}↳ Location: ${BLUE}${loc_prefix}${NC}"
                fi
            done <<< "$specific_locs"

        elif [ -z "$SPECIFIC_FILES" ]; then
            printf "   [${YELLOW}WARNING${NC}]   -> %s\n" "$f_name"

            local files=$(grep -E " U ${f_name}$" <<< "$ALL_UNDEFINED" | awk -F: '{split($1, path, "/"); print path[length(path)]}' | sort -u | tr '\n' ' ')
            echo -ne "          ${YELLOW}↳ Found in objects: ${BLUE}${files}${NC}"

            if [[ "$f_name" =~ ^(strlen|memset|memcpy|printf|puts|putchar)$ ]]; then
                echo -e " ${CYAN}(Use -fno-builtin in your gcc flags to silence this)${NC}"
            else
                echo -e " ${CYAN}(Recompile to sync binary)${NC}"
            fi
        fi
    done
    if [ $errors -eq 0 ] && [ "$forbidden_list" = "" ]; then
        echo -e "\t${GREEN}No forbidden functions detected.${NC}"
    fi
    return $errors
}

auto_check_update() {
    local raw_url="https://raw.githubusercontent.com/Mrdolls/forb/main/forb.sh"

    # Silent curl with 1-second timeout to prevent lag
    local remote_version
    remote_version=$(curl -s --max-time 1 "$raw_url" | grep "^VERSION=" | head -n 1 | cut -d'"' -f2)

    # If a version was successfully fetched
    if [ -n "$remote_version" ]; then
        if [ "$(version_to_int "$remote_version")" -gt "$(version_to_int "$VERSION")" ]; then
            echo -ne "${YELLOW}New version of ForbCheck (v${remote_version}) is available! Update now? (y/n): ${NC}"
            read -r choice
            case "$choice" in
                [yY][eE][sS]|[yY])
                    update_script
                    ;;
                *)
                    echo -e "${BLUE}Update skipped. Starting analysis...${NC}\n"
                    ;;
            esac
        fi
    fi
}

# --- MAIN ---

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

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help) show_help ;;
        -up|--update) update_script ;;
        --remove) uninstall_script ;;
        --no-auto) DISABLE_AUTO=true; shift ;;
        -s|--scan-source) source_scan ;;
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
        -f) shift; SPECIFIC_FILES="$@"; break ;;
        -*) echo -e "${RED}Unknown option: $1${NC}"; exit 1 ;;
        *) TARGET=$1; shift ;;
    esac
done

SET_WARNING=false
clear -x
echo -e "${YELLOW}╔═════════════════════════════════════╗${NC}"
echo -e "${YELLOW}║              ForbCheck              ║${NC}"
echo -e "${YELLOW}╚═════════════════════════════════════╝${NC}"
if [ -z "$TARGET" ]; then
    auto_detect_target

    if [ -z "$TARGET" ]; then
        echo -e "${RED}[Auto-Detect] No binary found.${YELLOW} -> Falling back to Source Scan...${NC}\n"
        source_scan
    fi
elif [ ! -f "$TARGET" ]; then
    echo -e "${YELLOW}[Warning] Target '$TARGET' not found. Falling back to Source Scan...${NC}\n"
    source_scan
fi

if ! nm "$TARGET" &>/dev/null; then
    echo -e "${RED}Error: $TARGET is not a valid binary or object file.${NC}"
    exit 1
fi

if [ -n "$TARGET" ]; then
    auto_check_update
fi
if [ -f "$TARGET" ]; then
    cache_file="$INSTALL_DIR/.forb_cache"
    mkdir -p "$INSTALL_DIR"
    [ ! -f "$cache_file" ] && touch "$cache_file"
    current_src_data=$(find . -name "*.c" -not -path '*/.*' -type f -exec stat -c "%s" {} + 2>/dev/null | awk '{s+=$1} END {print s}')
    current_src_lines=$(find . -name "*.c" -not -path '*/.*' -type f -exec wc -l {} + 2>/dev/null | awk '{s+=$1} END {print s}')
    bin_mtime=$(stat -c %Y "$TARGET" 2>/dev/null)
    target_name=$(basename "$TARGET")
     cache_file="$INSTALL_DIR/.forb_cache"
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
fi
auto_detect_libraries
START_TIME=$(date +%s.%N)
if [ "$USE_PRESET" -eq 0 ] && [ "$DISABLE_PRESET" = false ] && [ -n "$TARGET" ]; then
    target_name=$(basename "$TARGET")
    if [ -f "$PRESET_DIR/${target_name}.preset" ]; then
        USE_PRESET=1
        echo -e "${CYAN}[Auto-Detect] Preset '${target_name}.preset' detected and loaded automatically.${NC}"
    fi
fi

if [ "$USE_PRESET" -eq 1 ]; then
    load_preset "$TARGET"
else
    AUTH_FILE="$PRESET_DIR/default.preset"
    if [ ! -f "$AUTH_FILE" ] || [ ! -s "$AUTH_FILE" ]; then
        mkdir -p "$HOME/.forb"
        touch "$AUTH_FILE"
        echo -e "${YELLOW}[Warning] No preset loaded and default.preset is empty. Using empty list.${NC}"
    fi
fi
AUTH_FUNCS=$(cat "$AUTH_FILE" 2>/dev/null | tr ',' ' ' | tr -s ' ' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
echo -e "${BLUE}Target bin:${NC} $TARGET\n"

if [ "$SET_WARNING" = true ]; then
        echo -e "${YELLOW}Warning:${NC} Source content is newer than the binary."
        echo -e "         The results might not reflect your latest changes."
        echo -e "         Consider ${GREEN}recompiling${NC} to be sure."
fi
[ -n "$SPECIFIC_FILES" ] && echo -e "${BLUE}Scope      :${NC} $SPECIFIC_FILES"
echo -e "${BLUE}${BOLD}Execution:${NC}"
echo "-------------------------------------------------"

NM_RAW_DATA=$(find . -not -path '*/.*' -type f \( -name "*.o" -o -name "*.a" \) ! -name "$TARGET" ! -path "*mlx*" ! -path "*MLX*" -print0 2>/dev/null | xargs -0 -P4 nm -A 2>/dev/null)
ALL_UNDEFINED=$(grep " U " <<< "$NM_RAW_DATA")
MY_DEFINED=$(grep -E ' [TRD] ' <<< "$NM_RAW_DATA" | awk '{print $NF}' | sort -u)

run_analysis
total_errors=$?

DURATION=$(echo "$(date +%s.%N) - $START_TIME" | bc 2>/dev/null || echo "0")
echo -e "-------------------------------------------------\n"
if [ $total_errors -eq 0 ]; then
    echo -ne "\t\t${GREEN}RESULT: PERFECT\n"
else
    [ $total_errors -gt 1 ] && s="s" || s=""
    echo -ne "\t\t${RED}RESULT: FAILURE\n"
fi

if [ "$SHOW_TIME" = true ]; then
    DURATION=$(echo "$(date +%s.%N) - $START_TIME" | bc 2>/dev/null || echo "0")
    printf " (%0.2fs)" "$DURATION"
fi

echo -e "${NC}"

[ $total_errors -ne 0 ] && exit 1
