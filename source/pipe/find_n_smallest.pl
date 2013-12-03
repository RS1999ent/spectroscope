#!/usr/bin/perl -w

use strict;

my $old_seperator = $/;
$/ = '}';
my @smallest_count = (-1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1);
my @smallest = ("", "", "", "", "", "");

while(<STDIN>) {
    my $graph = $_;
    if( $graph =~ /{/) {
        my $i = 0;
        foreach(@smallest_count) {
            if (length($graph) < $_ || $_ < 0) {
                $smallest[$i] = $graph;
                $smallest_count[$i] = length($graph);
                last;
            }
            $i++;
        }
    }
}

foreach(@smallest) {
    print "$_\n\n";
}

