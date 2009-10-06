#! /usr/bin/perl -w

##
# Counts the number of occurences of a node in the trace
#
# @param node_name: The node name (perl regexps are valid)
# @param unique_only: 1 if multiple occurences of a node name within a 
#  request should be counted only once
##

use strict;

my $node_name = $ARGV[0];
my $unique_only = $ARGV[1];

my $old_seperator = $/;
$/ = '}';

my $node_count = 0;

while (<STDIN>) {
    my $request = $_;

    if($unique_only == 1) {
        if($request =~ /$node_name/) {
            $node_count++;
        }
    } else {
        while($request =~/$node_name/g) {
            $node_count++;
        }
    }
}

print "$node_name found $node_count times\n";
    
    
