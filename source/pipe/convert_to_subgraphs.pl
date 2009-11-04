#! /usr/bin/perl -w

# cmPDL: convert_to_subgraphs.pl
##


my $old_seperator = $/;
$/ = '}';

my $i = 0;

print "Digraph G {\n";

while (<STDIN>) {
    $_ =~ s/Digraph [0-9A-z]+/Subgraph $i/;
    print "$_\n";
    $i++;
}

print "}\n";
