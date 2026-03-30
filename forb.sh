#!/bin/bash

# --- COLOR MANAGEMENT ---
if [[ -t 1 ]]; then
    BOLD="\033[1m"; GREEN="\033[0;32m"; RED="\033[0;31m"; YELLOW="\033[0;33m"; BLUE="\033[0;34m"; CYAN="\033[0;36m"; NC="\033[0m"
else
    BOLD=""; GREEN=""; RED=""; YELLOW=""; BLUE=""; CYAN=""; NC=""
fi

VERSION="1.6.2"
INSTALL_DIR="$HOME/.forb"
AUTH_FILE="$INSTALL_DIR/authorize.txt"
UPDATE_URL="https://raw.githubusercontent.com/Mrdolls/forb/main/forb.sh"

SHOW_ALL=false; USE_MLX=false; USE_MATH=false; FULL_PATH=false; VERBOSE=false; TARGET=""; SPECIFIC_FILES="" ; SHOW_TIME=false ; DISABLE_AUTO=false

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

    echo -e "\n${BOLD}Scan Options:${NC}"
    printf "  %-24s %s\n" "-v, --verbose" "Show source code context"
    printf "  %-24s %s\n" "<target> -f <files...>" "Limit scan to specific files"
    printf "  %-24s %s\n" "-p, --full-path" "Show full paths"
    printf "  %-24s %s\n" "-a, --all" "Show authorized functions during scan"
    printf "  %-24s %s\n" "--no-auto" "Disable automatic library detection"

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

edit_list() {
    [ ! -f "$AUTH_FILE" ] && mkdir -p "$INSTALL_DIR" && touch "$AUTH_FILE"
    command -v code &>/dev/null && code --wait "$AUTH_FILE" || vim "$AUTH_FILE" || nano "$AUTH_FILE"; exit 0
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
detected=false
auto_detect_libraries() {
    [ "$DISABLE_AUTO" = true ] && return
    [ "$USE_MLX" = true ] && return

    if ls -R . 2>/dev/null | grep -qiE "mlx|minilibx" || [ -f "libmlx.a" ] || \
       nm "$TARGET" 2>/dev/null | grep -qiE "mlx_"; then
        USE_MLX=true
        detected=true
    fi
}

show_list() {
    if [ ! -f "$AUTH_FILE" ] || [ ! -s "$AUTH_FILE" ]; then
        echo -e "${YELLOW}No authorized functions list found. (Use -e to create one)${NC}"
        exit 0
    fi
    if [ $# -gt 0 ]; then
        echo -e "${BLUE}${BOLD}Checking functions:${NC}"
        for f in "$@"; do
            if grep -qx "$f" <<< "$AUTH_FUNCS"; then
                echo -e "   [${GREEN}OK${NC}] -> $f"
            else
                echo -e "   [${RED}KO${NC}] -> $f"
            fi
        done
    else
        if [ ! -f "$AUTH_FILE" ] || [ ! -s "$AUTH_FILE" ]; then
            echo -e "${YELLOW}No authorized functions list found. (Use -e to create one)${NC}"
        else
            echo -e "${BLUE}${BOLD}Authorized functions:${NC} ${CYAN}(Use -e to edit)${NC}"
            echo "---------------------------------------"
            tr ',' '\n' < "$AUTH_FILE" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | grep -v '^$' | column -c 80
        fi
    fi
    exit 0
}

run_analysis() {
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
    local pattern=$(echo "$forbidden_list" | sed 's/ /|/g; s/|$//')
    local regex_pattern="\b(${pattern})\b"
    local grep_res

    if [ -n "$SPECIFIC_FILES" ]; then
        local include_flags=""
        for f in $SPECIFIC_FILES; do include_flags+=" --include=\"$f\""; done
        grep_res=$(eval grep -rHE \"$regex_pattern\" . $include_flags -n 2>/dev/null | grep -vE "mlx|MLX")
    else
        grep_res=$(grep -rHE "$regex_pattern" . --include="*.c" -n 2>/dev/null | grep -vE "mlx|MLX")
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
                local clean_snippet=$(echo "$snippet" | sed 's|//.*||')
                if ! echo "$clean_snippet" | grep -qE "\b${f_name}\b"; then
                    continue
                fi
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

# --- MAIN ---

args=()
for arg in "$@"; do
    if [[ "$arg" == "-mlx" || "$arg" == "-lm" || "$arg" == "-up" ]]; then
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
        -v) VERBOSE=true; shift ;;
        -p|--full-path) FULL_PATH=true; shift ;;
        -a) SHOW_ALL=true; shift ;;
        -mlx) USE_MLX=true; shift ;;
        -lm) USE_MATH=true; shift ;;
        -e) edit_list ;;
        -l|--list)
            shift
            check_args=""
            while [[ $# -gt 0 && ! $1 =~ ^- ]]; do
                check_args+="$1 "
                shift
            done
            if [ ! -f "$AUTH_FILE" ]; then
                mkdir -p "$(dirname "$AUTH_FILE")"
                touch "$AUTH_FILE"
            fi
            AUTH_FUNCS=$(tr ',' ' ' < "$AUTH_FILE" 2>/dev/null | tr -s ' ' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            show_list $check_args ;;
        -t|--time) SHOW_TIME=true; shift ;;
        --remove) uninstall_script ;;
        --no-auto) DISABLE_AUTO=true; shift ;;
        -f) shift; SPECIFIC_FILES="$@"; break ;;
        -*) echo -e "${RED}Unknown option: $1${NC}"; exit 1 ;;
        *) TARGET=$1; shift ;;
    esac
done

SET_WARNING=false

if [ -z "$TARGET" ] || [ ! -f "$TARGET" ]; then
    echo -e "${RED}Error: Target invalid.${NC}" && exit 1
fi

if ! nm "$TARGET" &>/dev/null; then
    echo -e "${RED}Error: $TARGET is not a valid binary or object file.${NC}"
    exit 1
fi

if [ -f "$TARGET" ]; then
    current_src_data=$(find . -name "*.c" -not -path '*/.*' -type f -exec stat -c "%s" {} + 2>/dev/null | awk '{s+=$1} END {print s}')
    current_src_lines=$(find . -name "*.c" -not -path '*/.*' -type f -exec wc -l {} + 2>/dev/null | awk '{s+=$1} END {print s}')
    bin_mtime=$(stat -c %Y "$TARGET" 2>/dev/null)
    target_name=$(basename "$TARGET")
     cache_file="$INSTALL_DIR/.forb_cache"
    ref_data=$(grep "^$target_name:" "$cache_file" 2>/dev/null)
    ref_lines=$(echo "$ref_data" | cut -d: -f2)
    ref_size=$(echo "$ref_data" | cut -d: -f3)
    ref_bin_date=$(echo "$ref_data" | cut -d: -f4)
    if [[ "$bin_mtime" != "$ref_bin_date" ]]; then
        sed -i "/^$target_name:/d" "$cache_file" 2>/dev/null
        echo "$target_name:$current_src_lines:$current_src_data:$bin_mtime" >> "$cache_file"
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

START_TIME=$(date +%s.%N)
AUTH_FUNCS=$(tr ',' ' ' < "$AUTH_FILE" 2>/dev/null | tr -s ' ' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

echo -e "${YELLOW}╔═════════════════════════════════════╗${NC}"
echo -e "${YELLOW}║          ForbCheck Detector         ║${NC}"
echo -e "${YELLOW}╚═════════════════════════════════════╝${NC}"
echo -e "${BLUE}Target bin :${NC} $TARGET"
auto_detect_libraries
if [ "$detected" = true ]; then
    echo -e "${CYAN}MiniLibX detected (Use --no-auto to scan everything)${NC}"
fi
if [ "$SET_WARNING" = true ]; then
        echo -e "${YELLOW}Warning:${NC} Source content is newer than the binary."
        echo -e "         The results might not reflect your latest changes."
        echo -e "         Consider ${GREEN}recompiling${NC} to be sure."
fi
[ -n "$SPECIFIC_FILES" ] && echo -e "${BLUE}Scope      :${NC} $SPECIFIC_FILES"
echo "-------------------------------------------------"

NM_RAW_DATA=$(find . -not -path '*/.*' -type f \( -name "*.o" -o -name "*.a" \) ! -name "$TARGET" ! -path "*mlx*" ! -path "*MLX*" -print0 2>/dev/null | xargs -0 -P4 nm -A 2>/dev/null)
ALL_UNDEFINED=$(grep " U " <<< "$NM_RAW_DATA")
MY_DEFINED=$(grep -E ' [TRD] ' <<< "$NM_RAW_DATA" | awk '{print $NF}' | sort -u)

run_analysis
total_errors=$?

DURATION=$(echo "$(date +%s.%N) - $START_TIME" | bc 2>/dev/null || echo "0")
echo "-------------------------------------------------"
if [ $total_errors -eq 0 ]; then
    echo -ne "\t\t${GREEN}RESULT: PERFECT"
else
    [ $total_errors -gt 1 ] && s="s" || s=""
    echo -ne "\t\t${RED}RESULT: FAILURE"
fi

if [ "$SHOW_TIME" = true ]; then
    DURATION=$(echo "$(date +%s.%N) - $START_TIME" | bc 2>/dev/null || echo "0")
    printf " (%0.2fs)" "$DURATION"
fi

echo -e "${NC}"

[ $total_errors -ne 0 ] && exit 1
