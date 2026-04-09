#!/usr/bin/perl
use strict;
use warnings;
use utf8;
binmode STDERR, ":utf8";
$| = 1; # Autoflush STDOUT
select((select(STDERR), $| = 1)[0]); # Autoflush STDERR

# Emergency cleanup handler
END { system("stty -raw echo 2>/dev/null"); print STDERR "\e[?25h"; }

# ==============================================================================
#  FORBCHECK INTERACTIVE MENU ENGINE (Perl TUI)
#  Provides a searchable interactive menu for presets and options.
# ==============================================================================

my @options = @ARGV;
my $search = "";
my $selected = 0;

if (!@options) {
    exit 0;
}

# Terminal colors and codes
my $ESC = "\e";
my $CLEAR = $ESC . "[2J" . $ESC . "[H";
my $HIDE_CURSOR = $ESC . "[?25l";
my $SHOW_CURSOR = $ESC . "[?25h";
my $CYAN = $ESC . "[1;36m";
my $BOLD = $ESC . "[1m";
my $YELLOW = $ESC . "[1;33m";
my $GREEN = $ESC . "[0;32m";
my $BLUE = $ESC . "[0;34m";
my $NC = $ESC . "[0m";

sub cleanup {
    system("stty -raw echo 2>/dev/null");
    print STDERR $ESC . "[H" . $ESC . "[J"; # Clear menu from screen
    print STDERR $SHOW_CURSOR;
}

$SIG{INT} = sub { cleanup(); exit 1; };
$SIG{TERM} = sub { cleanup(); exit 1; };

system("stty raw -echo");
print STDERR $HIDE_CURSOR;

while (1) {
    # Filter options based on search
    my @filtered = grep { $_ =~ /\Q$search\E/i } @options;

    # Adjust selection if it goes out of bounds
    if ($selected >= @filtered) { $selected = @filtered - 1; }
    if ($selected < 0) { $selected = 0; }

    # Draw menu
    print STDERR $ESC . "[H"; # Move cursor to top
    print STDERR $ESC . "[J"; # Clear down

    print STDERR "${BLUE}${BOLD}╔══════════════════════════════════════════════════════╗${NC}\r\n";
    print STDERR "${BLUE}${BOLD}║  FORBCHECK SEARCHABLE MENU                           ║${NC}\r\n";
    print STDERR "${BLUE}${BOLD}╚══════════════════════════════════════════════════════╝${NC}\r\n";
    print STDERR "\r\n";
    print STDERR "${CYAN}${BOLD} Search :${NC} ${YELLOW}$search${NC}_ \r\n";
    print STDERR " (Type to filter, Arrows to navigate, Enter to select, ESC to exit)\r\n";
    print STDERR " ------------------------------------------------------\r\n";

    if (@filtered == 0) {
        print STDERR "  ${ESC}[31mNo presets found matching '$search'${NC}\r\n";
    } else {
        my $start = 0;
        # Pagination if there are too many items
        if ($selected > 10) { $start = $selected - 5; }

        for (my $i = $start; $i < @filtered && $i < $start + 15; $i++) {
            if ($i == $selected) {
                print STDERR "  ${GREEN}${BOLD}> $filtered[$i]${NC}\r\n";
            } else {
                print STDERR "    $filtered[$i]\r\n";
            }
        }
    }

    # Handle Input
    my $char;
    sysread(STDIN, $char, 1);

    if ($char eq "\r" || $char eq "\n") {
        if (@filtered > 0) {
            cleanup();
            print STDOUT $filtered[$selected];
            exit 0;
        }
    } elsif ($char eq $ESC) {
        my $next;
        sysread(STDIN, $next, 1);
        if ($next eq "[") {
            sysread(STDIN, $next, 1);
            if ($next eq "A") { # UP
                $selected--;
            } elsif ($next eq "B") { # DOWN
                $selected++;
            }
        } else {
            cleanup();
            exit 1;
        }
    } elsif (ord($char) == 127 || ord($char) == 8) { # BACKSPACE
        chop $search;
    } elsif (ord($char) >= 32 && ord($char) <= 126) { # Normal chars
        $search .= $char;
        $selected = 0; # Reset selection on search
    } elsif (ord($char) == 3) { # Ctrl+C
        cleanup();
        exit 1;
    }
}
