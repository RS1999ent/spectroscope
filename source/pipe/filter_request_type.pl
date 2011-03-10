#!/usr/bin/perl -w

use strict;

my $name = $ARGV[0];
my $include = $ARGV[1];

my $old_seperator = $/;
$/ = '}';

while(<STDIN>) {
    if($_ =~/$name/) {
        if ($include)  {
            print STDOUT "$_\n";
        }
    } else {
        if ($include == 0) {
            print STDOUT "$_\n";
        }
    }
}
$/ = $old_seperator;

