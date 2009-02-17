#!/usr/bin/perl -w

use strict;

my $name = $ARGV[0];

my $old_seperator = $/;
$/ = '}';

while(<STDIN>) {
    if($_ =~/$name/) {
        print STDOUT "$_\n";
    }
}
$/ = $old_seperator;

