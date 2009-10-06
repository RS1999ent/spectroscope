#! /usr/bin/perl -w

##
# Counts the number of requests in the input file
##

my $old_seperator = $/;
$/ = '}';

my $count = 0;
while (<STDIN>) {
    $count++;
}

print "There are $count requests in this trace\n";
