#! /usr/bin/perl -w

#### Package declarations ########

use strict;
use warnings; 
use diagnostics;
use Test::Harness::Assert;
use Getopt::Long;

use lib '../lib';

my $i = 0;
while(<STDIN>) {
    if (/Cluster ID: /) {
        $i++;
        if (/Specific Mutation Type: Structural mutation\\nCost: ([-0-9\.]+)/) {
            print "$i $1\n";
        }
    }
}
            
