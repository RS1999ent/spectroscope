#! /usr/bin/perl -w

# $cmuPDL: StructuredGraphs.pm, v$

## 
# Given a dot graph, this module builds a structured version of it and the structure
##

package StructuredGraphs;

use strict;
use warnings;
use Test::Harness::Assert;

use ParseDot::DotHelper qw[parse_nodes_from_string];

require Exporter;
our @EXPORT_OK = qw(build_graph_structure);

#### Global Constants #########

# Import value of DEBUG if defined
no define DEBUG =>;


#### Private functions ########

##
# Sorts the children array of each node in the graph_structure
# hash by the name of the node.  
#
# @param graph_structure_hash: A pointer to a hash containing the nodes
# of a request-flow graph.
##
sub sort_graph_structure_children {
    
    assert(scalar(@_) == 1);

    my $graph_structure_hash = shift;

    foreach my $key (keys %$graph_structure_hash) {
        my $node = $graph_structure_hash->{$key};
        my @children = @{$node->{CHILDREN}};

        my @sorted_children = sort {$children[$a] cmp $children[$b]} @children;
        $node->{CHILDREN} = \@sorted_children;
    }
};


#### API functions ############

##
# Builds a tree representation of a DOT graph passed in as a string and
# returns a hash containing each of the nodes of tree, along with 
# a pointer to the root node.
# 
# Each node of the tree looks like
#  node = { NAME => string,
#           CHILDREN => \@array of node IDs}
#
# The hash representing the entire tree returned is a hash of nodes, indexed
# by the node ID.
#
# @note: This function expects the input DOT representation to have been
# printed using a depth-first traversal.  Specifically, the source node
# of the first edge printed MUST be the root.
#
# @param graph: A string representation of the DOT graph
#
# @return a pointer to a hash comprised of 
#   { ROOT => Pointer to root node
#     NODE_HASH => Hash of all nodes, indexed by ID}
##
sub build_graph_structure {
    
    assert(scalar(@_) == 1);

    my ($graph) = @_;

    my %graph_node_hash;
    # @note DO NOT include semantic labels when parsing nodes from the string
    # in this case
    DotHelper::parse_nodes_from_string($graph, 0, \%graph_node_hash);
    
    my %graph_structure_hash;
    my $first_line = 1;
    my $root_ptr;

    my @graph_array = split(/\n/, $graph);

    # Build up the graph structure hash by iterating through
    # the edges of the graph structure
    foreach(@graph_array) {
        my $line = $_;
        
        if ($line =~m/(\d+)\.(\d+) \-> (\d+)\.(\d+)/) {
            my $src_node_id = "$1.$2";
            my $dest_node_id = "$3.$4";
            
            my $src_node_name = $graph_node_hash{$src_node_id};
            my $dest_node_name = $graph_node_hash{$dest_node_id};
            
            if(!defined $graph_structure_hash{$dest_node_id}) {
                my @children_array;
                my %dest_node = (NAME => $dest_node_name,
                                 CHILDREN => \@children_array,
                                 ID => $dest_node_id);
                $graph_structure_hash{$dest_node_id} = \%dest_node;
            }
            
            if (!defined $graph_structure_hash{$src_node_id}) {
                my @children_array;
                my %src_node =  ( NAME => $src_node_name,
                                  CHILDREN => \@children_array,
                                  ID => $src_node_id);
                $graph_structure_hash{$src_node_id} = \%src_node;
            }
            my $src_node_hash_ptr = $graph_structure_hash{$src_node_id};

            # If this is the first edge parsed in the graph, then this is 
            # also the root of the graph.  
            if($first_line == 1) {
                $root_ptr = $src_node_hash_ptr;
                $first_line = 0;
            }
            push(@{$src_node_hash_ptr->{CHILDREN}}, $dest_node_id);
        }
    }
    
    # Finally, sort the children array of each node in the graph structure
    # alphabetically
    sort_graph_structure_children(\%graph_structure_hash);
    
    return {ROOT =>$root_ptr, NODE_HASH =>\%graph_structure_hash};
};
