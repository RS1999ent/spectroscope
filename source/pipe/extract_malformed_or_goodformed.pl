#!/usr/bin/perl -w

##
# Simple script that iterates through all input DOT graphs and makes sure that
# all intra-component CALL nodes have a matching REPLY node.
##

use strict;
use Test::More;
use Test::Deep::NoTest;

#### Global variables #######

my $extract_malformed = 0;


##### Functions #######

sub parse_options {
    GetOptions("malformed+", => \$extract_malformed);
}


##### Main routine ######

my $old_seperator = $/;
$/ = '}';

while(<STDIN>) {

    my %call_type_entities;
    my %reply_type_entities;
    my $request = $_;

    # Get all call type nodes
    while($request =~ /e(\d+)__(.*)CALL_TYPE/g) {
        $call_type_entities{$1}++;
    }

    while($request =~ /e(\d+)__(.*)REPLY_TYPE/g) {
        $reply_type_entities{$1}++;
    }

    if(eq_deeply(\%call_type_entities, \%reply_type_entities) == 0) {        
        if ($extract_malformed) {
            print "$request";            
        }
    } elsif ($extract_malformed == 0) {
        print "$request";
    }
}


