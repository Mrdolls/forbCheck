#!/bin/bash

# ==============================================================================
#  FORBCHECK ANALYSE MODULE (Interactive Analysis TUI)
# ==============================================================================

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
# Menu principal (stats + navigation)
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
    
    # Launch interactive menu perl
    local selected
    selected=$(printf '%s\n' "${categories[@]}" | \
        perl -ane '
            $| = 1;
            select((select(STDERR), $| = 1)[0]);
            
            my @items = @ARGV;
            my $search = "";
            my $idx = 0;
            
            system("stty raw -echo 2>/dev/null");
            print STDERR "\e[?25l"; # hide cursor
            
            my $CYAN = "\e[36m";
            my $BOLD = "\e[1m";
            my $BLUE = "\e[34m";
            my $NC = "\e[0m";
            my $DIM = "\e[2m";
            my $GREEN = "\e[32m";
            
            sub render {
                my ($first) = @_;
                
                if (!$first) {
                    print STDERR "\e[3A"; # move up
                    print STDERR "\e[J";   # clear down
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
                print STDERR "  ${DIM}Total : $total fonctions  |  $nb_files fichiers${NC}\n";
                print STDERR "  ${DIM}↑↓ Naviguer / Entrée valider / ESC quitter${NC}\n";
            }
            
            render(1);
            
            while (1) {
                my $char;
                sysread(STDIN, $char, 1);
                
                if (ord($char) == 3 || ord($char) == 4) { # Ctrl+C/D
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
                        if ($next eq "A") { $idx-- if @_; render(0); }
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
# Sous-menu avec liste + bulle d'info
# ------------------------------------------------------------------------------

analyse_show_func_list() {
    local type="$1"  # "internal" or "external"
    local project_dir="${2:-.}"

    local funcs=""
    local title=""
    
    if [ "$type" = "internal" ]; then
        funcs="$ANALYSE_INTERNAL"
        title="Fonctions Internes"
    else
        funcs="$ANALYSE_EXTERNAL"
        title="Fonctions Externes"
    fi

    # Convertir en liste perl pour le menu
    local func_count=$(echo "$funcs" | grep -c "^" 2>/dev/null || echo 0)
    
    if [ "$func_count" -eq 0 ]; then
        log_info "${YELLOW}Aucune fonction $type trouvee${NC}"
        return
    fi

    # Extraire juste les noms pour le menu
    local func_names=$(echo "$funcs" | cut -d'|' -f1 | sort)
    
    # Lancer le menu avec bulle d'info
    local selected_func
    selected_func=$(echo "$func_names" | perl -ane '
        $| = 1;
        select((select(STDERR), $| = 1)[0]);
        
        my @items = @ARGV;
        my $search = "";
        my $idx = 0;
        my $cols = $ENV{COLUMNS} // 120;
        
        system("stty raw -echo 2>/dev/null");
        print STDERR "\e[?25l";
        
        my $CYAN = "\e[36m";
        my $BOLD = "\e[1m";
        my $BLUE = "\e[34m";
        my $NC = "\e[0m";
        my $DIM = "\e[2m";
        my $GREEN = "\e[32m";
        my $YELLOW = "\e[33m";
        
        my $max_left = $cols < 100 ? 40 : 50;
        
        sub render {
            my ($first, $selected_item) = @_;
            
            if (!$first) {
                print STDERR "\e[" . ($max_left + 5) . "A";
                print STDERR "\e[J";
            }
            
            my @filtered = grep { /\Q$search\E/i } @items;
            if ($idx >= @filtered) { $idx = @filtered - 1; }
            if ($idx < 0) { $idx = 0; }
            my $item = $filtered[$idx] // "";
            
            my $left = " " x 2;
            if ($cols >= 100) {
                # Layout gauche/droite
                print STDERR "\n";
                print STDERR "${BLUE}${BOLD}╔${"═" x ($max_left - 2)}╗";
                print STDERR "  ╔${"═" x ($cols - $max_left - 6)}╗\n";
                print STDERR "${BOLD}${left}║${CYAN}  $title${NC}" . (" " x ($max_left - length($title) - 5)) . "║";
                print STDERR "  ║${CYAN}  Info${NC}" . (" " x ($cols - $max_left - 11)) . "║\n";
                print STDERR "${BLUE}${BOLD}╠${"═" x ($max_left - 2)}╣";
                print STDERR "  ╠${"═" x ($cols - $max_left - 6)}╣\n";
                
                # Search
                print STDERR "${left}║  ${CYAN}Recherche :${NC} ${DIM}$search${NC}_" . (" " x ($max_left - length($search) - 18)) . "║";
                print STDERR "  ║\n";
                print STDERR "${BLUE}${left}╠${"═" x ($max_left - 2)}╣";
                print STDERR "  ║\n";
                
                # Liste
                my $start = $idx > 10 ? $idx - 5 : 0;
                for (my $i = $start; $i < @filtered && $i < $start + 15; $i++) {
                    my $name = $filtered[$i];
                    my $disp = length($name) > $max_left - 6 ? substr($name, 0, $max_left - 9) . "..." : $name;
                    my $prefix = $i == $idx ? "${CYAN}>${NC} " : "  ";
                    print STDERR "${left}║${prefix}${GREEN}${BOLD}$disp${NC}";
                    print STDERR (" " x ($max_left - length($disp) - 4)) . "║";
                    
                    if ($i == $idx && $selected_item) {
                        print STDERR "  ║  ${CYAN}${BOLD}$selected_item${NC}";
                        print STDERR (" " x ($cols - $max_left - length($selected_item) - 9)) . "║\n";
                    } else {
                        print STDERR "  ║\n";
                    }
                }
                
                # Footer
                print STDERR "${BLUE}${left}╚${"═" x ($max_left - 2)}╝";
                print STDERR "  ╚${"═" x ($cols - $max_left - 6)}╝\n";
                print STDERR "${DIM}  ↑↓ Scroll  |  Entrée voir detail  |  ESC retour${NC}";
                
            } else {
                # Compact pour petit terminal
                print STDERR "\n";
                print STDERR "${BLUE}${BOLD}╔══════════════════════════════╗${NC}\n";
                print STDERR "${BLUE}${BOLD}║${CYAN}  $title${NC}" . (" " x (29 - length($title))) . "${BLUE}║${NC}\n";
                print STDERR "${BLUE}${BOLD}╠══════════════════════════════╣${NC}\n";
                print STDERR "${left}  ${CYAN}Recherche :${NC} ${DIM}$search${NC}_\n";
                print STDERR "${BLUE}  ╠══════════════════════════════╣${NC}\n";
                
                my @filtered = grep { /\Q$search\E/i } @items;
                for (my $i = 0; $i < @filtered && $i < 12; $i++) {
                    my $name = $filtered[$i];
                    my $disp = length($name) > 30 ? substr($name, 0, 27) . "..." : $name;
                    if ($i == $idx) {
                        print STDERR "${left}  ${CYAN}>${NC} ${GREEN}${BOLD}$disp${NC}";
                        print STDERR (" " x (30 - length($disp))) . "\n";
                    } else {
                        print STDERR "${left}    ${DIM}$disp${NC}\n";
                    }
                }
                print STDERR "${DIM}  ↑↓ Scroll  |  ESC quitter${NC}\n";
            }
        }
        
        # Info extraction helper
        my %func_data;
        while (<>) {
            chomp;
            my ($name, $file, $line, $def, $calls) = split(/\|/, $_, 5);
            $func_data{$name} = {
                file => $file // "",
                line => $line // "",
                def => $def // "",
                calls => $calls // ""
            };
        }
        
        my $selected_info = "";
        render(1, "");
        
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
                    if ($next eq "A") { $idx-- if @items; }
                    elsif ($next eq "B") { $idx++; }
                } else {
                    system("stty -raw echo 2>/dev/null");
                    print STDERR "\e[?25h";
                    exit 0;
                }
            } elsif (ord($char) == 127 || ord($char) == 8) {
                chop $search; $idx = 0;
            } elsif (ord($char) >= 32 && ord($char) <= 126) {
                $search .= $char; $idx = 0;
            }
            
            my @filtered = grep { /\Q$search\E/i } @items;
            my $item = $filtered[$idx] // "";
            my $info = "";
            if (exists $func_data{$item}) {
                $info = "$func_data{$item}{file}:$func_data{$item}{line} - $func_data{$item}{def}";
                $info .= " | Appels: $func_data{$item}{calls}" if $func_data{$item}{calls};
            }
            render(0, $info);
        }
    ' 2>/dev/null)
    
    echo "$selected_func"
}

# ------------------------------------------------------------------------------
# Point d'entrée principal --analyse
# ------------------------------------------------------------------------------

run_analyse_mode() {
    local project_dir="${1:-.}"

    # Collecter les données
    analyse_collect_data "$project_dir"

    # Afficher le menu principal
    local selection
    selection=$(analyse_show_menu "$project_dir")

    if [ -z "$selection" ]; then
        return
    fi

    # Determiner le type basé sur la selection
    if echo "$selection" | grep -q "internes"; then
        analyse_show_func_list "internal" "$project_dir"
    elif echo "$selection" | grep -q "externes"; then
        analyse_show_func_list "external" "$project_dir"
    else
        log_info "${CYAN}Fichiers du projet : $ANALYSE_FILES fichiers${NC}"
    fi
}
