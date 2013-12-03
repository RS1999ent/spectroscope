#!/usr/bin/perl -w

# $cmuPDL: extract_node_names.pl, v #
##
# This perl script extracts node names from a set of files containing request-flow graphs in dot format.
##

use strict;
use warnings; 
use diagnostics;
use Test::Harness::Assert;
use lib '../lib';
use ParseDot::DotHelper qw[parse_nodes_from_string];

my $old_seperator = $/;
$/ = '}';
my %node_id_hash;
my %node_name_hash;

while (<STDIN>) {
    my $graph = $_;
    DotHelper::parse_nodes_from_string($graph, 1, \%node_id_hash);
}

# Print values of node name hash to stddout
foreach my $key (keys %node_id_hash) {
    my $node_name = $node_id_hash{$key};
    $node_name =~ s/e.+__t3__//;
    if (!defined $node_name_hash{$node_name}) {
        print "$node_name\n";
        $node_name_hash{$node_name} = 1;
    }
}

$/ = $old_seperator;
