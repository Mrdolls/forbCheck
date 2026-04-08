#!/usr/bin/perl
use strict;
use warnings;
use File::Basename;

# ForbCheck Macro Expansion Engine (Standalone)

my $target_file = shift;
my $funcs_str = shift // "";
my $is_blacklist = shift // "false";
my $json_mode = shift // "false";
my $verbose = shift // "false";
my $root_dir = dirname($target_file);

my %func_map = map { $_ => 1 } split(" ", $funcs_str);
my %keywords = map { $_ => 1 } qw(if while for return else switch case default do sizeof);
my %macros;
my %seen_files;

# 1. Recursive Include Crawler & Macro Collector
sub load_file_recursive {
    my ($file) = @_;
    return if $seen_files{$file}++;
    return unless -f $file;

    open(my $fh, "<", $file) or return;
    my $content = do { local $/; <$fh> };
    close($fh);

    $content =~ s/\\\n//g; # Mask multi-line defines
    $content =~ s#/\*.*?\*/##gs; # Remove multi-line comments
    $content =~ s#//.*##g; # Remove single-line comments

    # Find local includes
    while ($content =~ /^\s*#\s*include\s*["\x27]([^"\x27]+)["\x27]/mg) {
        my $inc_path = "$root_dir/$1";
        load_file_recursive($inc_path);
    }

    # Find defines
    while ($content =~ /^\s*#\s*define\s+(\w+(?:\([^)]*\))?)\s+(.*)/mg) {
        my ($sig, $body) = ($1, $2);
        $body =~ s/\s+$//;
        if ($sig =~ /^(\w+)\(([^)]*)\)$/) {
            my ($name, $p_str) = ($1, $2);
            $macros{$name} = { params => [split(/\s*,\s*/, $p_str)], body => $body };
        } else {
            $macros{$sig} = $body unless $body =~ /^"(?:[^"\\]|\\.)*"$/;
        }
    }
}

sub expand_func {
    my ($name, $arg_str) = @_;
    my $m = $macros{$name};
    my @args = split(/\s*,\s*/, $arg_str);
    my $body = $m->{body};
    for (my $i=0; $i<@{$m->{params}}; $i++) {
        my $p = $m->{params}->[$i];
        if ($p eq "...") {
            my $va = join(",", @args[$i..$#args]);
            $body =~ s/\b__VA_ARGS__\b/$va/g;
        } else {
            my $a = $args[$i] // "";
            $body =~ s/\b$p\b/$a/g;
        }
    }
    return $body;
}

load_file_recursive($target_file);

# 2. Global Expansion of Target File
open(my $tfh, "<", $target_file) or die "Could not open $target_file: $!";
my @orig_lines = <$tfh>;
my $content = join("", @orig_lines);
close($tfh);

$content =~ s/\\\n//g;
$content =~ s#/\*.*?\*/##gs;
$content =~ s#//.*##g;
$content =~ s/"(?:[^"\\]|\\.)*"/"_STR_"/g;

my $changed = 1;
for (1..15) {
    $changed = 0;
    foreach my $name (keys %macros) {
        if (ref $macros{$name}) {
            if ($content =~ s/\b$name\s*\((.*?)\)/expand_func($name, $1)/egs) { $changed = 1; }
        } else {
            if ($content =~ s/\b$name\b/$macros{$name}/g) { $changed = 1; }
        }
    }
    if ($content =~ s/\s*##\s*//g) { $changed = 1; }
    last unless $changed;
}

# 3. Final Universal Scan
my @expanded_lines = split("\n", $content);
my $count = 0;
for (my $i=0; $i < @expanded_lines; $i++) {
    my $line = $expanded_lines[$i];
    while ($line =~ /\b(\w+)\s*\(/g) {
        my $func = $1;
        next if $keywords{$func};
        
        my $is_illegal = 0;
        if ($is_blacklist eq "true") {
            $is_illegal = 1 if $func_map{$func};
        } else {
            $is_illegal = 1 unless $func_map{$func};
        }

        if ($is_illegal) {
            my $clean_file = $target_file; $clean_file =~ s|^\./||;
            if ($json_mode ne "true") {
                printf "   \033[31m[FORBIDDEN]\033[0m -> \033[1m%s\033[0m (via macro)\n", $func;
                printf "          \033[33m\xe2\x86\xb3 Location: \033[34m%s:%d\033[0m\n", $clean_file, $i + 1;
                if ($verbose eq "true") {
                    my $snippet = $orig_lines[$i] // ""; $snippet =~ s/^\s+//;
                    printf "          \033[33m\xe2\x86\xb3 Source:   \033[36m%s\033[0m", $snippet;
                }
            } else {
                my $lnum = $i + 1;
                print "MATCH|-> $func|in $clean_file:$lnum\n";
            }
            $count++;
        }
    }
}
exit($count > 0 ? 1 : 0);
