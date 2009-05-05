#! /usr/bin/perl -w

# $cmuPDL: MatchGraphs.pm,v 1.1 2009/04/27 20:14:44 source Exp $
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
# @param callback_fn: The callback_fn that should be called when
#  a match is found between the two graphs
# @param callback_args: The arguments that should be passed into the
# callback fn
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

    assert(scalar(@_) == 6);
    my ($graph1_node, $graph1_structure, $graph2_node, 
        $graph2_structure, $callback_fn, $callback_args) = @_;

    if($graph1_node->{NAME} eq $graph2_node->{NAME}) {
        
        # Call the callback fun w/the appropriate parameters
        my @bc_tc = split(/\./, $graph1_node->{ID});
        &$callback_fn($callback_args, $graph1_node->{NAME}, $bc_tc[0], $bc_tc[1]);

        my $node1_children_array = $graph1_node->{CHILDREN};
        my $node2_children_array = $graph2_node->{CHILDREN};

        my $node1_num_children = scalar(@$node1_children_array);
        my $node2_num_children = scalar(@$node2_children_array);

        #print Dumper @$node1_children_array;
        my $j = 0;
        for(my $i = 0; $i < $node1_num_children; $i++) {
            for (my $k = $j; $k < $node2_num_children; $k++) {

               # print "$node1_children_array->[$i]\n";
               # print "$node2_children_array->[$k]\n";
                my $node1_child = $graph1_structure->{$node1_children_array->[$i]};
                my $node2_child = $graph2_structure->{$node2_children_array->[$k]};
                # print "$node1_child->{NAME} $node2_child->{NAME}\n";
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
                                $callback_fn, $callback_args);
                    last;
                }
            }
        }
    }
    # print "Non-matching root node\n";
};


### Public functions #########

## 
# Take as as input two structured graphs and returns a pointer to an array,
# containing the names of the nodes that match when both graphs are
# traversed depth-first.  When searching a sub-path for matching nodes,
# the first non-match will cause the search to be terminated.
#
# @param graph1_container: The first structured graph
# @param graph2_container: The second structured graph
# 
# Each graph container must be the hash pointer returned by PrintGraphs->
# get_req_structure_given_global_id().  Specifically, it must have two keys: 
#    graph_container->{ROOT} = a pointer to a hash containing the root node
#    graph_container->{NODE_HASH} = a pointer to a hash containing each node of the tree
#                                   keyed by the node ID. 
#
##
sub match_graphs {
    
    assert(scalar(@_) == 4);
    my ($graph1_container, $graph2_container, $callback_fn, $callback_args) = @_;


    my @matching_nodes;
    match_nodes($graph1_container->{ROOT},
                $graph1_container->{NODE_HASH},
                $graph2_container->{ROOT},
                $graph2_container->{NODE_HASH},
                $callback_fn, 
                $callback_args);

}


1;    




