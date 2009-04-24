#! /usr/bin/perl -w

##
# This perl module contains helper functions for use by the other perl
# modules/scripts in this directory
##

package DotHelper;

use strict;
use warnings;
use Test::Harness::Assert;
use diagnostics;
require Exporter;

our @EXPORT_OK= qw(parse_nodes_from_string parse_nodes_from_file);


##
# Creates a hash mapping unique ids of nodes to node names
#
# @param graph: A string containing the DOT representation of a graph
# @param include_label: Whether or not to include the semantic label in the name
# @param node_name_hash: The hash that will be filled in and which
# will map unique ids to nodes
#
# @return: A string containing a partially consumed DOT graph (all
# the node names will have been consumed)
##
sub parse_nodes_from_string {
    
    assert(scalar(@_) == 3);

    my $graph = shift;
    my $include_label = shift;
    my $node_name_hash = shift;
    
    while ($graph =~ m/(\d+)\.(\d+) \[label=\"(\w+)\\n(\w*)\"\]/g) {

        my $node_name;
        if (defined $4 && $include_label) {
            $node_name = $3 . "_" . $4;
        } else {
            $node_name = $3;
        }

        my $node_id = $1.$2;
        $node_name_hash->{$node_id} = $node_name;
    }
}


##
# Creates a hash mapping unique ids of nodes to node names
#
# @param in_data_fh: Pointer to a file descriptor; offset is set to the first node
# @param include_label: Whether or not to include the semantic label in the name
# @param node_name_hash: The hash that will be filled in and which
# will map unique ids to nodes
#
# @return: A string containing a partially consumed DOT graph (all
# the node names will have been consumed)
##
sub parse_nodes_from_file {

    assert(scalar(@_) == 3);
    
	my $in_data_fh = shift;
    my $include_label = shift;
	my $node_name_hash = shift;

	my $last_in_data_fh_pos;
    my $node_name;
    
	$last_in_data_fh_pos = tell($in_data_fh);
    
	while(<$in_data_fh>) {

		if(/(\d+)\.(\d+) \[label=\"(\w+)\\n(\w*)\"\]/) {

			# Add the Node name to the alphabet hash 
            if (defined $4 && $include_label) { 
                $node_name = $3 . "_" . $4; 
            } else {
                $node_name = $3;
            }
            
			# Add the node id to the node_id_hash;
			my $node_id = "$1.$2";
			$node_name_hash->{$node_id} = $node_name;
		} else {
			# Done parsing the labels attached to nodes
			seek($in_data_fh, $last_in_data_fh_pos, 0); # SEEK_SET
			last;
		}
		$last_in_data_fh_pos = tell($in_data_fh);
	}
}


1;


