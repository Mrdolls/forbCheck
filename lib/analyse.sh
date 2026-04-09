#!/bin/bash

# ==============================================================================
#  FORBCHECK ANALYSE MODULE (Interactive Analysis TUI)
# ==============================================================================

# Ensure terminal state is restored on exit
trap 'stty sane 2>/dev/null; exit' EXIT INT TERM

# Colors (matching project)
CYAN="\033[0;36m"
BLUE="\033[0;34m"
BOLD="\033[1m"
YELLOW="\033[1;33m"
GREEN="\033[0;32m"
RED="\033[0;31m"
NC="\033[0m"
DIM="\033[2m"

ANALYSE_DATA=""
ANALYSE_INTERNAL=""
ANALYSE_EXTERNAL=""
ANALYSE_FILES=""

# ------------------------------------------------------------------------------
# Collect project data
# ------------------------------------------------------------------------------

analyse_collect_data() {
    local project_dir="${1:-.}"

    log_info "${CYAN}Collecting project data...${NC}"

    # Collect via perl engine
    local raw_data=$("$INSTALL_DIR/lib/analyse_engine.pl" --mode all "$project_dir" 2>/dev/null)
    
    ANALYSE_DATA="$raw_data"
    
    # Parse files count
    ANALYSE_FILES=$(echo "$raw_data" | grep "^FILES:" | cut -d: -f2)
    
    # Parse internal functions
    ANALYSE_INTERNAL=$(echo "$raw_data" | grep "^INTERNAL:" | cut -d: -f2-)
    
    # Parse external functions
    ANALYSE_EXTERNAL=$(echo "$raw_data" | grep "^EXTERNAL:" | cut -d: -f2)
}

analyse_get_stats() {
    local files=0 internal=0 external=0

    files="${ANALYSE_FILES:-0}"
    internal=$(echo "$ANALYSE_INTERNAL" | grep -c "^" 2>/dev/null || echo 0)
    external=$(echo "$ANALYSE_EXTERNAL" | grep -c "^" 2>/dev/null || echo 0)

    echo "$files|$internal|$external"
}

# ------------------------------------------------------------------------------
# Print stats summary (non-interactive)
# ------------------------------------------------------------------------------

analyse_print_stats() {
    local project_dir="${1:-.}"
    
    analyse_collect_data "$project_dir"
    
    local stats=$(analyse_get_stats)
    local nb_files=$(echo "$stats" | cut -d'|' -f1)
    local nb_internal=$(echo "$stats" | cut -d'|' -f2)
    local nb_external=$(echo "$stats" | cut -d'|' -f3)
    local total=$((nb_internal + nb_external))
    
    echo ""
    echo -e "${BLUE}${BOLD}╔══════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}${BOLD}║              ForbCheck - Analyse                    ║${NC}"
    echo -e "${BLUE}${BOLD}╚══════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  ${CYAN}Fichiers du projet :${NC} ${BOLD}$nb_files${NC}"
    echo -e "  ${CYAN}Fonctions internes :${NC} ${BOLD}$nb_internal${NC}"
    echo -e "  ${CYAN}Fonctions externes :${NC} ${BOLD}$nb_external${NC}"
    echo ""
    echo -e "  ${DIM}Total : $total fonctions${NC}"
    echo ""
    
    # Show internal functions list
    if [ "$nb_internal" -gt 0 ]; then
        echo -e "${CYAN}${BOLD}Fonctions Internes :${NC}"
        echo "$ANALYSE_INTERNAL" | while IFS='|' read -r name file line def calls; do
            [ -z "$name" ] && continue
            echo -e "  ${GREEN}>${NC} ${BOLD}$name${NC}"
            echo -e "      ${DIM}$file:$line${NC}"
        done
        echo ""
    fi
    
    # Show external functions list
    if [ "$nb_external" -gt 0 ]; then
        echo -e "${CYAN}${BOLD}Fonctions Externes :${NC}"
        echo "$ANALYSE_EXTERNAL" | while read -r name; do
            [ -z "$name" ] && continue
            echo -e "  ${YELLOW}>${NC} ${BOLD}$name${NC}"
        done
        echo ""
    fi
    
    echo -e "${DIM}Pour une navigation interactive, lancez dans un terminal.${NC}"
    echo ""
}

# ------------------------------------------------------------------------------
# Interactive menu (only works with real TTY)
# ------------------------------------------------------------------------------

analyse_show_menu() {
    local project_dir="${1:-.}"
    local stats=$(analyse_get_stats)
    local nb_files=$(echo "$stats" | cut -d'|' -f1)
    local nb_internal=$(echo "$stats" | cut -d'|' -f2)
    local nb_external=$(echo "$stats" | cut -d'|' -f3)
    local total=$((nb_internal + nb_external))

    # Menu categories
    local categories=(
        "Fonctions internes ($nb_internal)"
        "Fonctions externes ($nb_external)"
        "Fichiers du projet ($nb_files)"
    )
    
    # Launch interactive menu perl - pass categories as args, not via stdin
    local selected
    export TOTAL_FUNCS="$total" TOTAL_FILES="$nb_files"
    selected=$(perl -T -e '
        $| = 1;
        select((select(STDERR), $| = 1)[0]);
        
        my @items = @ARGV;
        my $search = "";
        my $idx = 0;
        my $total_funcs = $ENV{TOTAL_FUNCS} // 0;
        my $total_files = $ENV{TOTAL_FILES} // 0;
        
        # Non-interactive fallback: if no items, use first; if no tty, use first
        if (!@items || !-t STDIN) {
            print STDOUT $items[0] // "default";
            exit 0;
        }
        
        system("stty raw -echo 2>/dev/null");
        print STDERR "\e[?25l";
        
        my $CYAN = "\e[36m";
        my $BOLD = "\e[1m";
        my $BLUE = "\e[34m";
        my $NC = "\e[0m";
        my $DIM = "\e[2m";
        my $GREEN = "\e[32m";
        
        sub render {
            my ($first) = @_;
            
            if (!$first) {
                print STDERR "\e[3A";
                print STDERR "\e[J";
            }
            
            print STDERR "\n";
            print STDERR "${BLUE}${BOLD}╔══════════════════════════════════════════════════════╗${NC}\n";
            print STDERR "${BLUE}${BOLD}║              ForbCheck - Analyse                    ║${NC}\n";
            print STDERR "${BLUE}${BOLD}╚══════════════════════════════════════════════════════╝${NC}\n";
            print STDERR "\n";
            
            print STDERR "${CYAN}${BOLD}  Recherche :${NC} ${DIM}$search${NC}_\n";
            print STDERR "  ${DIM}────────────────────────────────────────────────────${NC}\n";
                
            my @filtered = grep { /\Q$search\E/i } @items;
            if ($idx >= @filtered) { $idx = @filtered - 1; }
            if ($idx < 0) { $idx = 0; }
                
            for (my $i = 0; $i < @filtered; $i++) {
                if ($i == $idx) {
                    print STDERR "  ${CYAN}>${NC} ${GREEN}${BOLD}$filtered[$i]${NC}\n";
                } else {
                    print STDERR "    ${DIM}$filtered[$i]${NC}\n";
                }
            }
                
            print STDERR "\n";
            print STDERR "  ${DIM}Total : $total_funcs fonctions  |  $total_files fichiers${NC}\n";
            print STDERR "  ${DIM}↑↓ Naviguer / Entrée valider / ESC quitter${NC}\n";
        }
            
        render(1);
            
        while (1) {
            my $char;
            sysread(STDIN, $char, 1);
                
            if (ord($char) == 3 || ord($char) == 4) {
                system("stty -raw echo 2>/dev/null");
                print STDERR "\e[?25h";
                exit 1;
            } elsif ($char eq "\r" || $char eq "\n") {
                my @filtered = grep { /\Q$search\E/i } @items;
                if (@filtered > 0) {
                    system("stty -raw echo 2>/dev/null");
                    print STDERR "\e[?25h";
                    print STDOUT $filtered[$idx];
                    exit 0;
                }
            } elsif ($char eq "\e") {
                my $next;
                sysread(STDIN, $next, 1);
                if ($next eq "[") {
                    sysread(STDIN, $next, 1);
                    if ($next eq "A") { $idx-- if @items; render(0); }
                    elsif ($next eq "B") { $idx++; render(0); }
                } else {
                    system("stty -raw echo 2>/dev/null");
                    print STDERR "\e[?25h";
                    exit 1;
                }
            } elsif (ord($char) == 127 || ord($char) == 8) {
                chop $search; render(0);
            } elsif (ord($char) >= 32 && ord($char) <= 126) {
                $search .= $char; $idx = 0; render(0);
            }
        }
    ' "${categories[@]}" 2>/dev/null)
    
    echo "$selected"
}

# ------------------------------------------------------------------------------
# Point d'entrée principal --analyse
# ------------------------------------------------------------------------------

run_analyse_mode() {
    local project_dir="${1:-.}"

    # Collecter les données
    analyse_collect_data "$project_dir"

    # Check if we have a real TTY
    if [ -t 0 ]; then
        # Try interactive mode
        local selection
        selection=$(analyse_show_menu "$project_dir")

        if [ -z "$selection" ]; then
            return
        fi

        # Determiner le type basé sur la selection
        if echo "$selection" | grep -q "internes"; then
            echo -e "${CYAN}Showing internal functions (interactive mode not fully implemented)${NC}"
        elif echo "$selection" | grep -q "externes"; then
            echo -e "${CYAN}Showing external functions (interactive mode not fully implemented)${NC}"
        else
            local stats=$(analyse_get_stats)
            local nb_files=$(echo "$stats" | cut -d'|' -f1)
            echo -e "${CYAN}Fichiers du projet : $nb_files fichiers${NC}"
        fi
    else
        # Non-interactive: just print stats
        analyse_print_stats "$project_dir"
    fi
}
