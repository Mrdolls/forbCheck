#!/usr/bin/perl
use strict;
use warnings;

# ==============================================================================
#  FORBCHECK TUI MENU (Perl Standalone)
# ==============================================================================

my @all_items = @ARGV;
if (!-t STDIN || !@all_items) {
    print $all_items[0] || "default";
    exit 0;
}

$| = 1; # Autoflush STDOUT
select STDERR; # Redirect UI to STDERR (not captured by shell)
$| = 1; # Autoflush STDERR

my $search = "";
my $selected_idx = 0;
my @filtered = @all_items;
my $prev_count = 0;

# Colors
my $CYAN = "\e[36m";
my $BOLD = "\e[1m";
my $NC   = "\e[0m";
my $GREEN = "\e[32m";
my $DIM   = "\e[2m";
my $UNDERLINE = "\e[4m";

# Clear screen codes
sub hide_cursor { print "\e[?25l"; }
sub show_cursor { print "\e[?25h"; }
sub clear_line { print "\e[2K\r"; }
sub move_up { my $n = shift; print "\e[${n}A" if $n > 0; }

sub render {
    my ($is_first) = @_;
    move_up($prev_count) unless $is_first;

    # Instruction & Search bar
    clear_line();
    printf "${CYAN}${BOLD}Search:${NC} %-30s\n", $search . ($search eq "" ? "${DIM}(type to filter)${NC}" : "");
    clear_line();
    print "${DIM}-----------------------------------------${NC}\n";

    # List
    my @new_filtered = grep { $_ =~ /\Q$search\E/i } @all_items;
    @filtered = @new_filtered;
    $selected_idx = 0 if $selected_idx >= scalar(@filtered);
    $selected_idx = scalar(@filtered) - 1 if $selected_idx < 0 && scalar(@filtered) > 0;

    my $current_count = 2; # Header + separator
    if (!@filtered) {
        clear_line();
        print "  ${DIM}No matches found...${NC}\n";
        $current_count++;
    } else {
        for (my $i = 0; $i < @filtered; $i++) {
            clear_line();
            if ($i == $selected_idx) {
                print " ${CYAN}>${NC} ${CYAN}${BOLD}${UNDERLINE}$filtered[$i]${NC}\n";
            } else {
                print "   $filtered[$i]\n";
            }
            $current_count++;
        }
    }
    
    # If list shortened, clear remaining lines from previous render
    if ($current_count < $prev_count) {
        for (my $i = 0; $i < ($prev_count - $current_count); $i++) {
            clear_line();
            print "\n";
        }
        move_up($prev_count - $current_count);
    }
    $prev_count = $current_count;
}

# Terminal setup
system("stty raw -echo");
hide_cursor();

render(1);

while (1) {
    my $char;
    sysread(STDIN, $char, 3);

    if ($char eq "\x03" || $char eq "\x04") { # Ctrl-C or Ctrl-D
        system("stty echo -raw");
        show_cursor();
        print "\n";
        exit 1;
    } elsif ($char eq "\x0D" || $char eq "\x0A") { # Enter
        last;
    } elsif ($char eq "\x7F" || $char eq "\x08") { # Backspace
        chop $search;
        render(0);
    } elsif ($char eq "\e[A") { # Up
        $selected_idx-- if @filtered;
        render(0);
    } elsif ($char eq "\e[B") { # Down
        $selected_idx++ if @filtered;
        render(0);
    } elsif ($char =~ /^[[:print:]]$/) { # Printable chars
        $search .= $char;
        render(0);
    }
}

system("stty echo -raw");
show_cursor();

# Cleanup output before selection result
move_up($prev_count);
for (0..$prev_count) { clear_line(); print "\n"; }
move_up($prev_count + 1);

my $result = $filtered[$selected_idx] || "default";
select STDOUT;
print "$result\n";
exit 0;
