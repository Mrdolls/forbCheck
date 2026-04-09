#!/usr/bin/perl
use strict;
use warnings;
use File::Basename;
use Getopt::Long;

# ==============================================================================
#  FORBCHECK ANALYSE ENGINE (Perl)
#  Extrait les fonctions internes/externes, localisations et contextes d'appel
# ==============================================================================

my $MODE = "all";
my $PROJECT_DIR = ".";
my $CACHE_DIR = "$ENV{HOME}/.forb/cache/analyse";

GetOptions(
    "mode=s"    => \$MODE,
    "dir=s"     => \$PROJECT_DIR,
    "help"      => sub { show_help(); exit 0; }
);

if (@ARGV) { $PROJECT_DIR = $ARGV[0]; }

# ==============================================================================
# CONFIGURATION
# ==============================================================================

# Types C valides
my $TYPES = qr/(?:int|char|float|double|long|short|unsigned|signed|void|size_t|ssize_t|pid_t|sig_atomic_t|bool|t_\w+|struct\s+\w+|enum\s+\w+|FILE|DIR|int8_t|int16_t|int32_t|int64_t|uint8_t|uint16_t|uint32_t|uint64_t)/;

# Mots-clés C à exclure
my $KEYWORDS = qr/^(if|while|for|return|else|switch|case|default|do|goto|sizeof|typedef|struct|enum|union|const|static|extern|inline|volatile|register|auto)$/;

# ==============================================================================
# FONCTIONS PRINCIPALES
# ==============================================================================

sub parse_source_files {
    my ($dir) = @_;
    my @c_files = `find "$dir" -maxdepth 5 -type f \\( -name "*.c" -o -name "*.h" -o -name "*.cpp" \\) 2>/dev/null`;
    chomp @c_files;
    return @c_files;
}

sub extract_internal_functions {
    my @files = @_;
    my %funcs;
    
    foreach my $file (@files) {
        next unless -f $file;
        open(my $fh, "<", $file) or next;
        my $content = do { local $/; <$fh> };
        close($fh);
        
        # Supprimer commentaires
        $content =~ s/\/\*.*?\*\// /gs;
        $content =~ s/\/\/.*//g;
        
        # Supprimer strings et caractères
        $content =~ s/"(?:\\.|[^"\\])*"/ /gs;
        $content =~ s/'(?:\\.|[^'\\])*'/ /gs;
        
        # Parser les définitions de fonctions
        my $skeleton = $content;
        while ($skeleton =~ s/\{[^{}]*\}/;/g) {}
        
        my @lines = split(/\n/, $skeleton);
        for (my $i = 0; $i < @lines; $i++) {
            my $line = $lines[$i];
            $line =~ s/^\s+//;
            $line =~ s/\s+$//;
            
            # Chercher définition de fonction : type name(params)
            if ($line =~ /^(.*?)\b([a-zA-Z_]\w*)\s*\((.*)\)$/ || 
                $line =~ /^(.*?)\b([a-zA-Z_]\w*)\s*\((.*)$/ ) {
                my ($prefix, $name, $params) = ($1, $2, $3);
                
                # Vérifier que le préfixe contient un type valide
                if ($prefix =~ /\b($TYPES)\b|static\s+.*|extern\s+.*|\*\s*$/ || 
                    $prefix =~ /^(\s*(?:static|extern|const|volatile|register|inline)?\s*($TYPES|\*\s*)+)\s*$/) {
                    unless ($name =~ $KEYWORDS || $name =~ /^\d/) {
                        $funcs{$name} //= {
                            file => $file,
                            line => $i + 1,
                            params => $params,
                            prefix => $prefix,
                            calls => []
                        };
                    }
                }
            }
        }
    }
    return %funcs;
}

sub find_function_calls {
    my ($dir, $func_name) = @_;
    my @calls;
    my @files = parse_source_files($dir);
    
    foreach my $file (@files) {
        open(my $fh, "<", $file) or next;
        my $lines_ref = [];
        @$lines_ref = <$fh>;
        close($fh);
        
        for (my $i = 0; $i < @$lines_ref; $i++) {
            my $line_num = $i + 1;
            my $line = $lines_ref->[$i];
            
            # Ignorer si c'est la définition de la fonction
            next if $line =~ /^\s*(?:static|extern)?\s*.*\b$func_name\s*\(/;
            
            # Chercher les appels
            if ($line =~ /\b$func_name\s*\(/) {
                # Extraire le contexte (lignes autour)
                my $context_before = $i > 0 ? $lines_ref->[$i - 1] : "";
                my $context_after = $i < @$lines_ref - 1 ? $lines_ref->[$i + 1] : "";
                chomp($context_before);
                chomp($context_after);
                chomp($line);
                
                push @calls, {
                    file => $file,
                    line => $line_num,
                    code => $line,
                    context_before => $context_before,
                    context_after => $context_after
                };
            }
        }
    }
    return @calls;
}

sub get_file_count {
    my ($dir) = @_;
    my @files = parse_source_files($dir);
    return scalar(@files);
}

sub get_external_functions {
    my ($dir) = @_;
    my %internes = extract_internal_functions(parse_source_files($dir));
    my %externes;
    
    # Chercher les fonctions appellées mais non définies
    my @all_calls;
    foreach my $func_name (keys %internes) {
        push @all_calls, find_function_calls($dir, $func_name);
    }
    
    # Extraire les noms de fonctions appelées
    my %called;
    foreach my $call (@all_calls) {
        if ($call->{code} =~ /\b([a-zA-Z_]\w*)\s*\(/) {
            $called{$1} = 1 unless exists $internes{$1};
        }
    }
    
    return %called;
}

# ==============================================================================
# OUTPUT FORMAT
# ==============================================================================

sub output_json {
    my ($dir) = @_;
    require JSON;
    
    my @files = parse_source_files($dir);
    my %internes = extract_internal_functions(@files);
    my %externes = get_external_functions($dir);
    my $file_count = scalar(@files);
    
    my $result = {
        files => $file_count,
        internal => {},
        external => {}
    };
    
    foreach my $name (sort keys %internes) {
        my $f = $internes{$name};
        $result->{internal}{$name} = {
            file => $f->{file},
            line => $f->{line},
            params => $f->{params},
            definition => "$f->{prefix} $name($f->{params})",
            calls => []
        };
        my @calls = find_function_calls($dir, $name);
        foreach my $c (@calls) {
            push @{$result->{internal}{$name}{calls}}, {
                file => $c->{file},
                line => $c->{line},
                code => $c->{code}
            };
        }
    }
    
    foreach my $name (sort keys %externes) {
        $result->{external}{$name} = 1;
    }
    
    print JSON->new->pretty->encode($result);
}

sub output_compact {
    my ($dir) = @_;
    
    my @files = parse_source_files($dir);
    my %internes = extract_internal_functions(@files);
    my %externes = get_external_functions($dir);
    my $file_count = scalar(@files);
    
    print "FILES:$file_count\n";
    
    foreach my $name (sort keys %internes) {
        my $f = $internes{$name};
        my $def = "$f->{prefix} $name($f->{params})";
        my @calls = find_function_calls($dir, $name);
        my $call_str = join(";", map { "$_->{file}:$_->{line}" } @calls);
        print "INTERNAL:$name|$f->{file}|$f->{line}|$def|$call_str\n";
    }
    
    foreach my $name (sort keys %externes) {
        print "EXTERNAL:$name\n";
    }
}

sub show_help {
    print << "HELP";
ForbCheck Analyse Engine
Usage: analyse_engine.pl [options] [dir]

Options:
  --mode all|internal|external|files   Mode de sortie (défaut: all)
  --dir <path>                         Répertoire du projet (défaut: .)
  --help                              Cette aide

Exemples:
  ./analyse_engine.pl /path/to/project
  ./analyse_engine.pl --mode internal .
  ./analyse_engine.pl --mode files --dir ./ft_printf
HELP
}

# ==============================================================================
# MAIN
# ==============================================================================

if ($MODE eq "files") {
    my $count = get_file_count($PROJECT_DIR);
    print "$count\n";
} elsif ($MODE eq "internal") {
    my @files = parse_source_files($PROJECT_DIR);
    my %funcs = extract_internal_functions(@files);
    foreach my $name (sort keys %funcs) {
        print "$name\n";
    }
} elsif ($MODE eq "external") {
    my %funcs = get_external_functions($PROJECT_DIR);
    foreach my $name (sort keys %funcs) {
        print "$name\n";
    }
} else {
    output_compact($PROJECT_DIR);
}

exit 0;
