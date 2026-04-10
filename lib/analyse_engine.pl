#!/usr/bin/perl
use strict;
use warnings;
use File::Basename;

# ==============================================================================
#  FORBCHECK ANALYSE ENGINE (v1.16.1 - Refactored)
# ==============================================================================

my @files = <STDIN>;
chomp @files;
my $total_files = scalar @files;
exit 0 if $total_files == 0;

my %internal_funcs = (); 
my %external_funcs = (); 
my %macros = ();
my %loc_data = ();       
my %file_to_macros = ();

# Progress Bar Settings
$| = 1; # Autoflush
my $bar_width = 40;

sub draw_progress {
    my ($current, $total) = @_;
    my $percent = int(($current / $total) * 100);
    my $filled = int(($current / $total) * $bar_width);
    my $unfilled = $bar_width - $filled;
    printf STDERR "\r\e[36m[Analyse]\e[0m [\e[32m%s%s\e[0m] %d%% (%d/%d files)", 
        "#" x $filled, "-" x $unfilled, $percent, $current, $total;
}

# --- Logging Setup ---
my $log_file = "$ENV{HOME}/.forb/logs/analyse_engine.log";
open(my $log_fh, ">", $log_file); # Use > to overwrite each run
sub v_log { print $log_fh "[LOG] " . join(" ", @_) . "\n"; }

# --- Keywords and Types to ignore ---
my $types = qr/(?:int|char|float|double|long|short|unsigned|signed|void|size_t|ssize_t|pid_t|sig_atomic_t|bool|t_\w+|struct\s+\w+|enum\s+\w+|FILE|DIR)/;
my $kw = qr/^(if|while|for|return|else|switch|case|default|do|sizeof|typedef|static|extern|inline|const|volatile|void|char|int|long|short|float|double|unsigned|signed|struct|enum|union|size_t|del|f|va_arg|va_start|va_end|va_list)$/;

# --- Macro Typing Logic ---
sub detect_macro_type {
    my ($sig, $body) = @_;
    my $b = $body // ""; $b =~ s/^\s+|\s+$//g;
    return "Header Guard"      if $sig =~ /_H$/ && $b eq "";
    return "Function-like"     if $sig =~ /\(/;
    return "String Constant"    if $b =~ /^"(\\.|[^"\\])*"$/;
    return "Numeric Constant"   if $b =~ /^-?(\d+|0x[0-9a-fA-F]+)$/i;
    return "Macro Definition"   if $b ne "";
    return "Simple Definition";
}

# --- STEP 1: Find definitions & Macros ---
my $count = 0;
foreach my $file (@files) {
    next unless -f $file;
    $count++;
    draw_progress($count, $total_files);
    v_log("Processing file: $file");
    print "FILE|$file\n";

    open(my $fh, "<", $file) or next;
    my $content = do { local $/; <$fh> };
    close($fh);
    
    my @orig_lines = split(/\n/, $content);
    
    # 1.1 Strip comments (Robust logic) - PRESERVE STRINGS for macros
    $content =~ s/\r//g; 
    $content =~ s{(/\*.*?\*/)}{ my $c = $1; my $n = () = $c =~ /\n/g; "\n" x $n }egs;
    $content =~ s{//.*}{}g;

    # 1.2 Extract Macros
    while ($content =~ /^\s*#\s*define\s+(\w+(?:\([^)]*\))?)[ \t]*([^\r\n]*)/mg) {
        my ($sig, $body) = ($1, $2);
        my $line_num = (substr($content, 0, $-[0]) =~ tr/\n//) + 1;
        my $type = detect_macro_type($sig, $body);
        push @{$file_to_macros{$file}}, { name => $sig, line => $line_num, body => $body, type => $type };
        $macros{$sig} = { file => $file, body => $body, type => $type };
    }
    
    # 1.3 Strip strings for function detection
    $content =~ s{("(?:\\.|[^"\\])*"|\x27(?:\\.|[^\x27\\])*\x27)}{ my $c = $1; my $n = () = $c =~ /\n/g; "\n" x $n }egs;

    # 1.4 Skeleton Parsing (v4.0 CONVERGENCE)
    # This matches the robust logic of the core scanner
    my $skeleton = $content;
    while ($skeleton =~ s/\{[^{}]*\}/;/gs) {} 

    foreach my $line (split /;/, $skeleton) { 
        $line =~ s/^\s+|\s+$//g;
        next if $line =~ /^\s*$/;

        # Signature detection v4.5: Added /s for multiline type/name support
        if ($line =~ /^(.*?)(\b[a-zA-Z_]\w*\b)\s*\(/s) {
            my ($avant, $name) = ($1, $2);
            # Check if there is a type or a pointer star before the name (allowing newlines)
            if ($avant =~ /\b(?:$types|static|extern|inline)\b|\*/s) {
                next if $name =~ $kw;
                
                # Dynamic line number resolution
                my $line_num = 1;
                my $safe_name = quotemeta($name);
                if ($content =~ /\b$safe_name\b\s*\(/) {
                    $line_num = (substr($content, 0, $-[0]) =~ tr/\n//) + 1;
                }
                
                v_log("  -> [INTERNAL] Found: $name at line $line_num");
                $internal_funcs{$name} = { file => $file, line => $line_num, def => $orig_lines[$line_num-1] // "" };
            }
        }
    }
}
print STDERR "\n";

# --- STEP 2: Mapping Calls ---
$count = 0;
print STDERR "\e[34m[Analyse] Mapping calls...\e[0m\n";

foreach my $file (@files) {
    next unless $file =~ /\.(c|cpp|h|hpp)$/; 
    open(my $fh, "<", $file) or next;
    my $content = do { local $/; <$fh> };
    close($fh);

    # Robust multi-line stripping (matches Step 1)
    my $stripped = $content;
    $stripped =~ s/\r//g; 
    $stripped =~ s{(/\*.*?\*/)}{ my $c = $1; my $n = () = $c =~ /\n/g; "\n" x $n }egs;
    $stripped =~ s{//.*}{}g;
    $stripped =~ s{("(?:\\.|[^"\\])*"|\x27(?:\\.|[^\x27\\])*\x27)}{ my $c = $1; my $n = () = $c =~ /\n/g; "\n" x $n }egs;

    my @lines_orig = split(/\n/, $content);
    my @lines_clean = split(/\n/, $stripped);

    for (my $i = 0; $i < @lines_clean; $i++) {
        my $lnum = $i + 1;
        my $clean = $lines_clean[$i];
        my $orig  = $lines_orig[$i];

        # 2.1 Basic check
        while ($clean =~ /\b([a-zA-Z_]\w*)\s*\(/g) {
            my $fname = $1;
            next if $fname =~ $kw || length($fname) <= 2;
            next if $macros{$fname}; # If it's a macro, we expand it next
            
            if (!$internal_funcs{$fname}) {
                push @{$external_funcs{$fname}}, { file => $file, line => $lnum, context => $orig };
            }
            push @{$loc_data{$fname}}, { file => $file, line => $lnum, context => $orig };
        }
        
        # 2.2 Macro-Expansion check (v4.0)
        foreach my $m_name (keys %macros) {
            next unless ($macros{$m_name}->{type} // "") =~ /Macro|Function/;
            if ($clean =~ /\b$m_name\b/) {
                my $body = $macros{$m_name}->{body} // "";
                while ($body =~ /\b([a-zA-Z_]\w*)\s*\(/g) {
                    my $fname = $1;
                    next if $fname =~ $kw || length($fname) <= 2;
                    if (!$internal_funcs{$fname}) {
                        push @{$external_funcs{$fname}}, { file => $file, line => $lnum, context => $orig . " (via $m_name)" };
                    }
                    push @{$loc_data{$fname}}, { file => $file, line => $lnum, context => $orig . " (via $m_name)" };
                }
            }
        }
    }
}

# --- STEP 3: Format Output & Logging ---
v_log("--- EXTERNAL FUNCTIONS FOUND ---");
foreach my $fname (sort keys %external_funcs) {
    my $count = scalar(@{$external_funcs{$fname}});
    v_log("  [EXT] $fname ($count calls)");
}
v_log("-------------------------------");

print "META|total_files|$total_files\n";
print "META|total_internal|" . scalar(keys %internal_funcs) . "\n";
print "META|total_external|" . scalar(keys %external_funcs) . "\n";
print "META|total_macros|" . scalar(keys %macros) . "\n";
print "META|auth_funcs|" . ($ENV{AUTH_FUNCS} // "") . "\n";
print "META|blacklist_mode|" . ($ENV{BLACKLIST_MODE} // "false") . "\n";
print "META|preset_name|" . uc($ENV{SELECTED_PRESET} // "default") . "\n";

foreach my $f (sort keys %internal_funcs) {
    my $d = $internal_funcs{$f};
    my $def = $d->{def}; $def =~ s/^\s+//; chomp $def;
    print "FUNC_INT|$f|$d->{file}|$d->{line}|$def\n";
}

foreach my $f (sort keys %external_funcs) {
    # Final check: if we found an internal definition, it CANNOT be external
    next if $internal_funcs{$f};
    
    # Identify if it's a known system macro
    # This list covers standard macros that shouldn't be treated as forbidden functions
    my $type = "FUNC";
    if ($f =~ /^(WIFEXITED|WEXITSTATUS|WIFSIGNALED|WTERMSIG|S_ISDIR|S_ISREG|S_ISLNK|S_ISCHR|S_ISBLK|S_ISFIFO|S_ISSOCK)$/) {
        $type = "MACRO";
    }
    
    next if $type eq "MACRO"; # Exclude system macros from External Functions list
    print "FUNC_EXT|$f|" . scalar(@{$external_funcs{$f}}) . "|$type\n";
}

foreach my $m (sort keys %macros) {
    my $d = $macros{$m};
    my $body = $d->{body} // ""; chomp $body;
    my $type = $d->{type} // "Macro";
    print "MACRO|$m|$d->{file}|0|$type|$body\n";
}

foreach my $f (keys %loc_data) {
    foreach my $loc (@{$loc_data{$f}}) {
        my $ctx = $loc->{context}; $ctx =~ s/^\s+//; chomp $ctx;
        print "LOC|$f|$loc->{file}|$loc->{line}|$ctx\n";
    }
}
