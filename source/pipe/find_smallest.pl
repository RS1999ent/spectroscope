#! /usr/bin/perl -w

use strict;

my $old_seperator = $/;
$/ = '}';
my $smallest;
my $smallest_count = 999999999;

while (<STDIN>) {
    if ($_ =~ /{/) {
        if (length($_) < $smallest_count) {
            $smallest = $_;
            $smallest_count = length($_);
        }
    }
}

print "$smallest\n";
