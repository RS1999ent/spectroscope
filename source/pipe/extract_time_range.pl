#! /usr/bin/perl -w

##
# Extracts all request w/relative timestamp less than the value specified
#
# @param max_time: The upper-bound on time, specified in ms.
##

use strict;

my $max_time = $ARGV[0];
my $old_seperator = $/;
$/ = '}';

while (<STDIN>) {

    my $request = $_;

    if ($request =~ /\# (\d+)  R: ([0-9\.]+) usecs RT: ([0-9\.]+) usecs/) {

        # Get time offset of this request in ms.
        my $relative_time = $3/1000;
        
        if ($relative_time <= $max_time) {
            print "$request\n";
        } else {
            last;
        }
    }        
}
