#!/usr/bin/perl -w

use strict;


my $old_seperator = $/;
$/ = '}';
my $largest;
my $largest_count = 0;

while(<STDIN>) {
    if( $_ =~ /{/) {
        if (length($_) > $largest_count) {
            $largest = $_;
            $largest_count = length($_);
        }
    }
}

    print "$largest\n";

