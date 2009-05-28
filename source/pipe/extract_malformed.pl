#!/usr/bin/perl -w

## 
# Simple script that iterates through all DOT graphs in an input file and outputs
# the malformed ones to STDOUT.  A malformed graph is one that does not contain
# a NFS_*_CALL_TYPE node and a corresponding NFS_*_REPLY_TYPE node.
# 
##

use strict;

my $old_seperator = $/;
$/ = '}';

while (<STDIN>) {
    my $request = $_;
    if($request =~ /NFS3_(.+)_CALL_TYPE/) {
        my $reply = "NFS3_$1_REPLY_TYPE";
        if($request =~ /$reply/) {
            next;
        }
    }
    print "$request\n";
}

        
