#!/usr/bin/perl
use strict;
use warnings;

# ForbCheck Symbol Filtering Engine
# Processes NM output against whitelist/blacklist in bulk for maximum performance.

my ($raw_funcs_str, $auth_funcs_str, $is_blacklist, $use_mlx, $use_math, $my_defined_str, $show_all) = @ARGV;

my %auth_funcs = map { $_ => 1 } split(" ", $auth_funcs_str // "");
my %my_defined = map { $_ => 1 } split("\n", $my_defined_str // "");
my @raw_funcs = split("\n", $raw_funcs_str // "");

my @forbidden;

# Simple color codes
my $GREEN = "\033[0;32m";
my $NC    = "\033[0m";

foreach my $func (@raw_funcs) {
    next if $func eq "" || $func =~ /^(_|ITM|edata|end|bss_start|__)/;
    
    # Library specific filters
    if ($use_mlx eq "true") {
        next if $func =~ /^(X|shm|gethostname|puts|exit|strerror|mlx_)/;
    }
    if ($use_math eq "true") {
        next if $func =~ /^(abs|cos|sin|sqrt|pow|exp|log|fabs|floor)f?$/;
    }
    
    # Internal project functions
    next if $my_defined{$func};

    my $is_auth = 0;
    if ($is_blacklist eq "true") {
        $is_auth = 1 unless $auth_funcs{$func} || $auth_funcs{"_$func"};
    } else {
        $is_auth = 1 if $auth_funcs{$func} || $auth_funcs{"_$func"};
    }

    if ($is_auth) {
        if ($show_all eq "true") {
            printf "   [${GREEN}OK${NC}]         -> %s\n", $func;
        }
    } else {
        push @forbidden, $func;
    }
}

# Output the forbidden list prefixed by a separator
print "FORBIDDEN_LIST:" . join(" ", @forbidden) . "\n";
