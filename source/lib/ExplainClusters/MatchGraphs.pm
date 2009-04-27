#! /usr/bin/perl -w

# $cmuPDL: MatchGraphs.pm, v $
##
# @author Raja Sambasivan
# 
# @brief Provides functions for matching graphs given
# a structured representation of them
##

package MatchGraphs;

use strict;
use warnings;
use Test::Harness::Assert;
use diagnostics;
require Exporter;
use Data::Dumper;

our @EXPORT_OK = qw(match_graphs);


### Private functions ##############

##
# Helper function for match_graphs().  This is a recursive function
# that builds a list of matching nodes given two graphs.  Matching
# is done by a depth-first traversal of the graphs and a matching
# operation along a particular sub-path is terminated as soon as a single
# non-matching node is found.
#
# @param graph1_node: The current graph1 node to be compared
# @param graph2_node: The current graph2 node to be compared
# @param graph1_structure: The structure of graph1
# @param graph2_structure: The structure of graph2
#
# graph1_node and graph2_node are hashes that are structured as follows: 
#   graphx_node => (NAME => string,
#                   CHILDREN => ptr to array of indexes into graphx_structure)
#
# The children array MUST be ordered consistently across both graphs
#
# graph1_structure and graph2_structure are hashes that are structured as follows:
#   graphx_structure->{ID} = graphx_node
# These hashes encode the structure of a request-flow graph
##
sub match_nodes {
    assert(scalar(@_) == 5);

    my $graph1_node = shift;
    my $graph1_structure = shift;
    my $graph2_node = shift;
    my $graph2_structure = shift;
    my $matching_nodes = shift;

    if($graph1_node->{NAME} eq $graph2_node->{NAME}) {
        
        # Add this to the list of matching nodes
        push(@$matching_nodes, $graph1_node->{NAME});

        my $node1_children_array = $graph1_node->{CHILDREN};
        my $node2_children_array = $graph2_node->{CHILDREN};

        my $node1_num_children = scalar(@$node1_children_array);
        my $node2_num_children = scalar(@$node2_children_array);
        print "blah blh blh\n";
        print Dumper @$node1_children_array;
        my $j = 0;
        for(my $i = 0; $i < $node1_num_children; $i++) {
            for (my $k = $j; $k < $node2_num_children; $k++) {
                print "$node1_children_array->[$i]\n";
                print "$node2_children_array->[$k]\n";
                my $node1_child = $graph1_structure->{$node1_children_array->[$i]};
                my $node2_child = $graph2_structure->{$node2_children_array->[$k]};

                if ($node1_child->{NAME} gt $node2_child->{NAME}) {
                    next;
                } 
                if ($node1_child->{NAME} lt $node2_child->{NAME}) {
                    $j = $k;
                    last;
                }
                if($node1_child->{NAME} eq $node2_child->{NAME}) {
                    $j = $k + 1;
                    match_nodes($node1_child, $graph1_structure,
                                $node2_child, $graph2_structure,
                                $matching_nodes);
                    last;
                }
            }
        }
    }
    print "Non-matching root node\n";
};


### Public functions #########

## 
# Take as as input two structured graphs and returns a pointer to an array,
# containing the names of the nodes that match when both graphs are
# traversed depth-first.  When searching a sub-path for matching nodes,
# the first non-match will cause the search to be terminated.
#
# @param graph1_root: A pointer to the root node of the first graph
# @param graph1_structure: a pointer to a hash containing a structured
# representation of the graph (as returned by get_req_structure_given_global_id)
# in the PrintDot module.
# @param graph2_root: A pointer to the root of the 2nd graph
# @param graph2_structure: A pointer to a hash containing a structured
# representation of the grpah (as returned by get_req_structure_given_global_id)
#
# @return An array of node names that matched in the two graph, ordered by a depth-first
# traversal w/children of a given node traversed in alphatical order.
##
sub match_graphs {
    
    assert(scalar(@_) == 4);

    my $graph1_root = shift;
    my $graph1_structure = shift;
    my $graph2_root = shift;
    my $graph2_structure = shift;

    my @matching_nodes;
    match_nodes($graph1_root,
                $graph1_structure,
                $graph2_root,
                $graph2_structure,
                \@matching_nodes);


    return \@matching_nodes;
}


