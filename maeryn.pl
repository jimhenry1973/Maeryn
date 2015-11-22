#! /usr/bin/perl

=pod

Maeryn

by Jim Henry III.  GPL license.
http://jimhenry.conlang.org

Maeryn is an automatic lexicon-builder.  It takes as input a list of
words generated by a random word generator such as Boris, Lexifer,
Gleb, etc., plus a definitions file and an optional format file.
Examples of definition and format files are included,
small-lexicon.txt and lusanja.weight.  The rules of a format file are
of the form:

<numeric weight> <one or more tokens>;

that is, a real number followed by whitespace followed by one or more
letters or digraphs (or trigraphs or n-graphs if you like) separated
by whitespace, followed by a semicolon.  The words from the wordlist
file (which defaults to standard input) are then sorted based on the
total weight of their phonemes, with "lightest" words first.

The definitions file can either be a pre-sorted list of definitions,
or a file where each line is a numeric weight, some whitespace, and
a definition.  If you are using a pre-sorted definition list, use the
-s / --sorted command-line option.  The lowest numbers should be given
to definitions of the probably most common words, which will then
be matched with short/lightweight wordforms, and written to standard
output or a specified output file with a tab between the word and
its definition.

(A definition can have more complex internal structure if you like,
for instance a semantic or syntactic category tag followed by the
definition.  Maeryn doesn't care as long as the weight (if any) comes
first.)

If the optional format file is omitted, Maeryn will assume that one
letter matches to one phoneme and all phonemes of equal weight.

=cut

# $Log$

use strict;
use warnings;
use utf8;

use constant LEVEL => 1;
use constant FORMAT => 2;


use Getopt::Long;
Getopt::Long::Configure('bundling');

my $debug = 0;
my $help = 0;
my $mode = FORMAT;
my $format_file = "";
my $wordlist_file = "";
my $output_file = "";
my $definitions_file = "";
my $already_sorted = 0;
my $polysemy_rate = 0;		##TODO make configurable and use this later

my %token_weights = ();
my @sorted_tokens = ();

sub usage {
    print STDERR <<HELP;

Usage: $0   [-f <filename>] [-w <filename>] [-d <filename>] [-o <filename>] [-D] [-s]

-f
--format	format file with weights for each token
-w
--wordlist	file with list of words  (default stdin)
-o
--output	output file (default stdout)
-d
--definitions	file with list of definitions to match with 
		weight-sorted word list
-s
--sorted	definition list is already sorted
-D
--debug		debug mode

If -s / --sorted is not specified, then $0 assumes that 
the definitions file consists lines with a numeric weight,
followed by whitespace, followed by a definition.  The weights
column will be discarded in output.

HELP

}

sub read_format {
    my $file = shift;

    open FMT, $file	or die "can't open $file for reading\n";
    my @lines = <FMT>;
    my $fmt = join " ", @lines;
    $fmt =~ s/#.*\n//g;	# remove comments
    $fmt =~ s/\s+/ /g;		# collapse whitespace sequences
    my @rules = split ';', $fmt;
    foreach ( @rules ) {
	s/^ //;
	s/ $//;
	next if m/^$/;
	if ( m/\$[A-Za-z0-9_] *=/ ) {
	    warn "unsupported rule type, ignoring it\n$_\n";
	    next;
	}
	my @tokens = split " ";
	my $weight = $tokens[0];
	if ( $weight !~ m/[0-9.]+/ ) {
	    warn "unsupported rule type, ignoring it\n$_\n";
	    next;
	}

	shift @tokens;
	foreach ( @tokens ) {
	    $token_weights{ $_ } = $weight;
	}
    }

    if ( $debug ) {
	print STDERR map { "$_ : $token_weights{ $_ } \n" } keys %token_weights;
    }

    if ( 0 == scalar keys %token_weights ) {
	die "no valid rules found\n";
    }

    @sorted_tokens = sort {length $b <=> length $a} keys %token_weights;

    close FMT;
}

sub weight_total {
    my $word = shift;
    my $orig_word = $word;
    my $total = 0;

    my $lastlen = 0;
    # use the longest tokens first
WHILE:    while ( length $word ) {
	for ( my $i = 0; $i < scalar @sorted_tokens ; $i++ ) {
	    my $t = $sorted_tokens[ $i ];
	    print STDERR "word $word, token $t\n"   if $debug;
	    if ( $word =~ m/^$t/ ) {
		$total += $token_weights{$t};
		$word = substr $word, length($t);
		next WHILE;
	    }
	}
	if ( length $word == $lastlen ) {
	    die "no token recognized at position: $word\n"
	} else {
	    $lastlen = length $word;
	}
    }
    if ($debug) {
	print STDERR "$orig_word weight $total\n";
    }
    return $total;
}

sub weight_sort {
#    return $a <=> $b; 	# placeholder
    return &weight_total($a) <=> &weight_total($b);
}

sub def_sort {
    $a =~ m/^\s*([0-9.]+)\s+/;
    my $p = $1;
    $b =~ m/^\s*([0-9.]+)\s+/;
    my $q = $1;
    return $p <=> $q;
}

#+++++ main +++++

my $rc = GetOptions(
	'f|format=s'	=> \$format_file,
	'w|wordlist=s'	=> \$wordlist_file,
    	'o|output=s'	=> \$output_file,
        'D|debug'	=> \$debug,
    	'd|definitions=s'	=> \$definitions_file,
    	's|sorted'	=> \$already_sorted,
    	'h|help'	=> \$help,
);

if ( not $rc or $help ) {
    &usage;
    exit(0);
}

if ( "" eq $definitions_file ) {
    print STDERR "-d / --definitions option is required\n";
    &usage;
    exit(1);
}

if ( $output_file ) {
    open OUTPUT, ">" . $output_file		
	or die "can't open $output_file for writing\n";
    select OUTPUT;
} else {
    $| = 1;		# force autoflush on stdout
}

if ( $format_file ) {
    &read_format( $format_file );
} else {
    # maybe set a mode where all chars have weight 1?
    $mode = LEVEL;
}

my @words = ();

if ( $wordlist_file ) {
    print STDERR "reading wordlist file\n" if $debug;
    open WORDS, $wordlist_file	or die "can't open $wordlist_file for reading\n";
    while ( <WORDS> ) { 
	chomp; 
	push @words, $_; 
    }
    close WORDS;
} else {
    while ( <> ) { 
	chomp; 
	push @words, $_; 
    }
}

if ( $mode == FORMAT ) {
    @words = sort weight_sort @words;
} else {
    @words = sort { length $a <=> length $b } @words;
}

print STDERR "after reading/sorting words\n" if $debug;

#print join "\n", @words;

open DEFS, $definitions_file	or die "can't open $definitions_file for reading\n";
my @defs = <DEFS>;
close DEFS;

print STDERR "after reading defs\n" if $debug;

if ( not $already_sorted ) {
    for ( my $j = 0; $j < scalar @defs; $j++) {
	if ( $defs[ $j] !~ m/^\s*([0-9.]+)\s+/ ) {
	    die "line " . ($j+1) . " of definitions file doesn't seem to begin with a numeric weight\n";
	}
    }
	
    @defs = sort def_sort @defs;
}

print STDERR "after sorting defs\n" if $debug;

if ( scalar @defs > scalar @words ) {
    warn "too many definitions, not enough words\n";
}

for ( my $i = 0; $i < scalar @words ; $i++ ) {
    if ( $i >= scalar @defs ) {
	exit;
    }

    my $thisdef = "";
    if ( not $already_sorted ) {
	$defs[$i] =~  m/^\s*[0-9.]+\s+(.*)/;
	$thisdef = $1  . "\n";
    } else {
	$thisdef = $defs[$i]
    }

    print $words[$i] . "\t" . $thisdef;

    ##TODO if rand < $polysemy_rate then match another def with this word
}
