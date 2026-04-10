#!/usr/bin/perl
use strict;
use warnings;
use File::Basename;
use utf8;

# ==============================================================================
#  FORBCHECK ANALYSE TUI (v1.16.0) - UTF-8 & COLLISION STABLE
# ==============================================================================

binmode STDOUT, ":utf8";
$| = 1;

my $data_file = shift || exit 1;

# --- Data loading ---
my %meta          = ();
my @funcs_int     = ();
my @funcs_ext     = ();
my @macros        = ();
my %locs          = ();
my %file_to_funcs = ();

open(my $fh, "<:encoding(UTF-8)", $data_file) or die "Cannot open $data_file: $!";
while (<$fh>) {
    chomp;
    my ($type, @p) = split /\|/, $_;
    next unless defined $type;
    if    ($type eq "META")     { $meta{$p[0]} = $p[1]; }
    elsif ($type eq "FUNC_INT") { push @funcs_int, { name => $p[0], file => $p[1], line => $p[2], def => $p[3] }; push @{$file_to_funcs{$p[1]}}, $p[0]; }
    elsif ($type eq "FUNC_EXT") { push @funcs_ext, { name => $p[0], call_count => $p[1], type => ($p[2] // "FUNC") }; }
    elsif ($type eq "MACRO")    { push @macros,    { name => $p[0], file => $p[1], line => $p[2], type => $p[3], body => $p[4] }; }
    elsif ($type eq "LOC")      { push @{$locs{$p[0]}}, { file => $p[1], line => $p[2], context => $p[3] }; }
    elsif ($type eq "FILE")     { $file_to_funcs{$p[0]} //= []; }
}
close $fh;

my @funcs_all   = sort { lc($a->{name}) cmp lc($b->{name}) } (@funcs_int, @funcs_ext);
my @macros_all  = sort { lc($a->{name}) cmp lc($b->{name}) } @macros;
my @files_meta  = map  { { name => $_, file => $_ } } sort keys %file_to_funcs;

# --- Colors ---
my ($NC, $BOLD, $CYAN, $BLUE, $GREEN, $DIM, $WHITE) =
    ("\e[0m", "\e[1m", "\e[36m", "\e[34m", "\e[32m", "\e[2m", "\e[37m");

# --- Terminal size ---
my ($T_H, $T_W) = (24, 80);

sub fetch_size {
    for my $fh (\*STDIN, \*STDOUT, \*STDERR) {
        my $buf = "\0" x 8;
        if (ioctl($fh, 0x5413, $buf)) {
            my ($r, $c) = unpack "S2", $buf;
            return ($r, $c) if $r > 4 && $c > 10;
        }
    }
    my $s = `stty size 2>/dev/null` // ""; chomp $s;
    return ($1, $2) if $s =~ /^(\d+)\s+(\d+)$/;
    return (24, 80);
}

($T_H, $T_W) = fetch_size();
my $needs_redraw = 1;
$SIG{WINCH} = sub { ($T_H, $T_W) = fetch_size(); $needs_redraw = 1; };

# --- ANSI helpers ---
sub at { "\e[$_[0];$_[1]H" }
sub vlen {
    my $s = shift; $s =~ s/\e\[[0-9;]*[mK]//g;
    return length($s);
}

sub vpad {
    my ($s, $w) = @_;
    my $len = vlen($s);
    my $p = $w - $len; $p = 0 if $p < 0;
    return $s . ($p ? $NC . " " x $p : "");
}

sub vtrunc {
    my ($str, $max) = @_;
    my ($out, $vis, $i) = ("", 0, 0);
    $str =~ s/\t/    /g; # Replace tabs
    while ($i < length $str) {
        if (substr($str, $i) =~ /^(\e\[[0-9;]*[mK])/) {
            $out .= $1; $i += length $1;
        } else {
            last if $vis >= $max;
            $out .= substr($str, $i, 1); $vis++; $i++;
        }
    }
    return $out . ($vis ? $NC : "");
}

# --- State ---
my $state        = "MAIN";
my $sel          = 0;
my $search       = "";
my @filtered     = ();
my $scroll       = 0;
my $dirty_filter = 1;
my $macro_filter_idx = 0;
my @macro_tab_names  = ("ALL", "HEADERS", "NUMERIC", "STRINGS", "OTHERS");
my @macro_tab_types  = ("", "Header Guard", "Numeric Constant", "String Constant", "others");

sub state_meta {
    return ("Internal Functions",  \@funcs_int,  "func")  if $state eq "LIST_INT";
    return ("External Functions",  \@funcs_ext,  "func")  if $state eq "LIST_EXT";
    if ($state eq "LIST_MACROS") {
        my $target_type = $macro_tab_types[$macro_filter_idx];
        my @filtered_macros;
        if ($target_type eq "") {
            @filtered_macros = @macros;
        } elsif ($target_type eq "others") {
            @filtered_macros = grep { $_->{type} !~ /Header|Numeric|String/ } @macros;
        } else {
            @filtered_macros = grep { ($_->{type} // "") eq $target_type } @macros;
        }
        return ("Constants & Macros", \@filtered_macros, "macro");
    }
    return ("All Functions",       \@funcs_all,   "func")  if $state eq "LIST_ALL";
    return ("Project Files",       \@files_meta,  "file")  if $state eq "LIST_FILES";
    return ("", [], "");
}

sub render {
    my ($h, $w) = ($T_H, $T_W);
    my $out = "\e[2J"; 

    if ($state eq "MAIN") {
        my $sw   = ($w > 82 ? 78 : $w - 4); $sw = 40 if $sw < 40;
        my $col  = int(($w - $sw) / 2) + 1;
        my $title  = "FORBCHECK - PROJECT ANALYSIS DASHBOARD";
        my $tl     = length $title;
        my $pad_l  = int(($sw - 2 - $tl) / 2); $pad_l = 0 if $pad_l < 0;
        my $pad_r  = $sw - 2 - $tl - $pad_l;   $pad_r = 0 if $pad_r < 0;

        $out .= at(1,$col) . "${CYAN}┌" . "─" x ($sw-2) . "┐${NC}";
        $out .= at(2,$col) . "${CYAN}│${NC}" . " " x $pad_l . "${CYAN}${BOLD}$title${NC}" . " " x $pad_r . "${CYAN}│${NC}";
        $out .= at(3,$col) . "${CYAN}└" . "─" x ($sw-2) . "┘${NC}";

        my @items = (
            [ "Internal Functions",  scalar @funcs_int   ],
            [ "External Functions",  scalar @funcs_ext   ],
            [ "Constants & Macros",    scalar @macros      ],
            [ "All Functions",       scalar @funcs_all   ],
            [ "Files of Project",    scalar @files_meta  ],
        );

        for (my $i = 0; $i < @items; $i++) {
            my $row = 6 + $i;
            last if $row >= $h;
            my $count = sprintf("(%d)", $items[$i][1]);
            my $label = sprintf("%-24s %s", $items[$i][0], $count);
            if ($i == $sel) {
                $out .= at($row, $col + 4) . "${GREEN}●${NC} ${GREEN}${BOLD}$label${NC}";
            } else {
                $out .= at($row, $col + 4) . "  ${CYAN}$label${NC}";
            }
        }
        $out .= at($h, $col + 4) . "${DIM}[↑↓] Navigate | [Enter] Select | [ESC] Exit${NC}";

    } else {
        my ($title, $items_ref, $type) = state_meta();
        if ($dirty_filter) {
            @filtered    = grep { $_->{name} && $_->{name} =~ /\Q$search\E/i } @$items_ref;
            $dirty_filter = 0;
            $sel = 0 if !@filtered || $sel >= @filtered;
        }

        # Dynamic Width Allocation (v2.5)
        my $list_w = int($w * 0.35); $list_w = 20 if $list_w < 20;
        my $bx     = $list_w + 5;
        my $bw     = $w - $bx - 1;
        my $max_rows = $h - 8;

        # Title & Search
        $out .= at(1, 2) . "${CYAN}${BOLD}[ " . uc($title) . " ]${NC}";
        if ($state eq "LIST_MACROS") {
            my $tab_bar = "  ";
            for my $i (0..$#macro_tab_names) {
                my $dot = ($i == $macro_filter_idx) ? "${CYAN}●${NC}" : "${DIM}○${NC}";
                my $name = $macro_tab_names[$i];
                if ($i == $macro_filter_idx) {
                    $tab_bar .= "$dot ${CYAN}${BOLD}$name${NC}   ";
                } else {
                    $tab_bar .= "$dot ${DIM}$name${NC}   ";
                }
            }
            $out .= at(2, 2) . $tab_bar;
        }
        $out .= at(3, 2) . "${CYAN}${BOLD}Filter:${NC} " . $search . "${WHITE}_${NC}";
        $out .= at(4, 2) . "${DIM}" . "─" x ($list_w + 3) . $NC;

        if (!@filtered) {
            $out .= at(6, 4) . "${DIM}(no results)${NC}";
        } else {
            $sel    = $#filtered if $sel > $#filtered;
            $scroll = $sel if $sel < $scroll;
            $scroll = $sel - $max_rows + 1 if $sel >= $scroll + $max_rows;
            $scroll = 0 if $scroll < 0;

            for (my $i = 0; $i < $max_rows; $i++) {
                my $idx = $i + $scroll;
                last if $idx >= @filtered;
                my $row  = 6 + $i;
                my $item = $filtered[$idx];
                my $prefix = ($item->{type} && $item->{type} eq "MACRO") ? "${DIM}[M] ${NC}" : "";
                my $name   = $prefix . vtrunc($item->{name} // "", $list_w - vlen($prefix));
                
                if ($item->{is_header}) {
                    $out .= at($row, 2) . "${DIM}  $name${NC}";
                } elsif ($idx == $sel) {
                    $out .= at($row, 2) . "${GREEN}${BOLD}▶ $name${NC}"; 
                } else {
                    $out .= at($row, 2) . "  ${CYAN}$name${NC}";
                }
            }
        }
        $out .= at($h, 2) . "${DIM}[↑↓] Navigate | [ESC] Back${NC}";

        # Right detail bubble (only if enough space)
        if ($w > 60 && @filtered && defined $filtered[$sel]) {
            my $it = $filtered[$sel];
            my $bi = $bw - 4;
            my $hr = "─" x ($bw - 2);
            my $name_str = uc(basename($it->{name} // "N/A"));

            $out .= at(5, $bx) . "${CYAN}┌${hr}┐${NC}";
            $out .= at(6, $bx) . "${CYAN}│${NC} " . vpad("${CYAN}${BOLD}" . vtrunc($name_str, $bi) . $NC, $bi) . " ${CYAN}│${NC}";
            $out .= at(7, $bx) . "${CYAN}├${hr}┤${NC}";

            my @det;
            if ($type eq "macro") {
                my $m_type = $it->{type} // "Macro";
                my $m_val  = $it->{body} // ""; $m_val =~ s/^\s+|\s+$//g;
                
                @det = ("Type   : $m_type", 
                        "Source : " . vtrunc(basename($it->{file} // "N/A"), $bi - 10));
                
                # Dynamic Value Display: Hide for empty Header Guards
                if (!($m_type eq "Header Guard" && $m_val eq "")) {
                    push @det, "Value  : " . vtrunc($m_val, $bi - 10);
                }
            } elsif ($type eq "file") {
                @det = ("Path : " . vtrunc($it->{file} // "", $bi - 7));
                my @f_list = @{$file_to_funcs{$it->{file}//""}//[]};
                if (@f_list) {
                    push @det, "────────────────────────────", "FUNCTIONS IN FILE :";
                    for my $fn (sort @f_list) {
                        last if scalar(@det) > ($h - 10);
                        push @det, " ${CYAN}●${NC} $fn";
                    }
                }
            } else {
                # Internal or External Function
                if ($it->{file}) {
                    @det = ("DEFINITION : " . vtrunc(basename($it->{file}), $bi - 13),
                            "LINE       : " . ($it->{line} // 0));
                } else {
                    @det = ("TOTAL CALLS : " . ($it->{call_count} // "0"));
                }
                
                # Add Call Context from %locs
                if ($locs{$it->{name}}) {
                    push @det, "────────────────────────────";
                    push @det, "      PROJECT USAGES";
                    push @det, "────────────────────────────";
                    for my $l (@{$locs{$it->{name}}}) {
                        last if scalar(@det) > ($h - 10);
                        push @det, "${CYAN}" . vtrunc(basename($l->{file}) . ":" . $l->{line}, $bi) . "${NC}";
                        # COMPRESS: Remove leading whitespace and collapse multiple spaces
                        my $ctx = $l->{context} // "";
                        $ctx =~ s/^\s+//; $ctx =~ s/\s+/ /g;
                        push @det, "${DIM}" . vtrunc($ctx, $bi) . "${NC}";
                    }
                }
            }
            my $row = 8;
            for my $d (@det) {
                last if $row >= $h - 1;
                $out .= at($row, $bx) . "${BLUE}│${NC} " . vpad($d, $bi) . " ${BLUE}│${NC}";
                $row++;
            }
            while ($row < $h - 1) {
                $out .= at($row, $bx) . "${BLUE}│" . " " x ($bw-2) . "│${NC}";
                $row++;
            }
            $out .= at($h-1, $bx) . "${BLUE}└${hr}┘${NC}";
        }
    }
    print $out;
}

sub read_key {
    my ($key, $rin) = ("", "");
    vec($rin, fileno(STDIN), 1) = 1;
    return "" unless select($rin, undef, undef, 0.05);
    sysread(STDIN, $key, 1);
    if ($key eq "\x1B") {
        my $seq = "";
        while (1) {
            my $r2 = ""; vec($r2, fileno(STDIN), 1) = 1;
            last unless select($r2, undef, undef, 0.01);
            my $b; sysread(STDIN, $b, 1);
            $seq .= $b; last if $b =~ /[a-zA-Z~]/;
        }
        $key .= $seq;
    }
    return $key;
}

system("stty raw -echo");
print "\e[?25l";

# Initial load
render();

while (1) {
    render() if $needs_redraw;
    $needs_redraw = 0;
    my $key = read_key();
    next unless $key;
    if ($key eq "\x1B" || $key eq "q") {
        last if $state eq "MAIN";
        ($state, $sel, $scroll, $search, $dirty_filter, $needs_redraw) = ("MAIN", 0, 0, "", 1, 1);
    }
    elsif ($key eq "\x03") { last; }
    elsif ($key eq "\x0D" || $key eq "\x0A") {
        if ($state eq "MAIN") {
            my @map = qw(LIST_INT LIST_EXT LIST_MACROS LIST_ALL LIST_FILES);
            $state = $map[$sel] // "MAIN";
            ($sel, $scroll, $search, $dirty_filter) = (0, 0, "", 1);
            # Skip initial header
            my ($t, $items, $type) = state_meta();
            $sel++ while ($sel < $#$items && $items->[$sel]{is_header});
        }
        $needs_redraw = 1;
    }
    elsif ($key eq "\e[A") { # UP
        if ($sel > 0) {
            $sel--;
            # Note: headers are gone in v3.2 so we just decrement
        }
        $needs_redraw = 1;
    }
    elsif ($key eq "\e[B") { # DOWN
        my $limit = ($state eq "MAIN" ? 4 : $#filtered);
        $sel++ if $sel < $limit;
        $needs_redraw = 1;
    }
    elsif ($key eq "\e[C") { # RIGHT
        if ($state eq "LIST_MACROS") {
            $macro_filter_idx = ($macro_filter_idx + 1) % scalar(@macro_tab_names);
            ($sel, $scroll, $search, $dirty_filter) = (0, 0, "", 1);
            $needs_redraw = 1;
        }
    }
    elsif ($key eq "\e[D") { # LEFT
        if ($state eq "LIST_MACROS") {
            $macro_filter_idx = ($macro_filter_idx - 1) % scalar(@macro_tab_names);
            ($sel, $scroll, $search, $dirty_filter) = (0, 0, "", 1);
            $needs_redraw = 1;
        }
    }
    elsif (($key eq "\x7F" || $key eq "\x08") && $state ne "MAIN") {
        chop $search; $dirty_filter = 1; $needs_redraw = 1;
    }
    elsif ($key =~ /^[[:print:]]$/ && $state ne "MAIN") {
        $search .= $key; $dirty_filter = 1; $needs_redraw = 1;
    }
}

system("stty echo -raw");
print "\e[?25h\e[2J\e[H";
exit 0;
