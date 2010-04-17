#!/usr/bin/perl -w

use strict;


my $old_seperator = $/;
$/ = '}';
my $highest_response_time_graph;
my $highest_response_time = 0;

while(<STDIN>) {
    if(/\#.+R: ([0-9\.]+) usecs/) {
        my $response_time = $1;
        
        if ($response_time > $highest_response_time) {
            $highest_response_time = $response_time;
            $highest_response_time_graph = $_;
        }
    }
}

print "$highest_response_time_graph";
