#! /usr/bin/perl -w

# $cmuPDL: DotHelper.pm,v 1.6.14.3 2011/05/30 06:04:49 rajas Exp $
##
# This perl module contains helper functions for use by the other perl
# modules/scripts in this directory
##

package DotHelper;

use strict;
use warnings;
use Test::Harness::Assert;
use diagnostics;
use Storable;


### Internal functions ################

##
# Creates a unique filename to store the node ID -> node name mapping
#
# @param self: The object container
# @param global_id: The global ID of the request
##
my $_create_filename = sub {
    assert(scalar(@_) == 2);
    my ($self, $global_id) = @_;

    return $self->{OUTPUT_DIR} . $global_id . ".hash";
};


### API functions ########################

##
# Returns 1 if the node passed in to this function exists in the graph spcified
#
# @param node: A string indicating the name of the node
# @param request: A string containing a graph in DOT format
##
sub find_dot_node {

    assert(scalar(@_) == 2);
    my ($node, $request) = @_;

    if ($request =~ /$node/) {
        return 1;
    } 

    return 0;
}


##
# Creates a hash mapping unique ids of nodes to node names
#
# @glboal_id: Global ID of the request 
# @param in_data_fh: Offset to the first node in the DOT graph of the request
# @param include_label: Whether or not to include the semantic label in the name.  
#
# Side effect: The file offset pointer (in_data_fh) will be set to the line
# after the last node declaration in the DOT graph.

# @return: A reference to a hash table mapping node IDs to node names.
##
sub parse_nodes_from_file {

    assert(scalar(@_) == 4);
    my ($self, $global_id, $in_data_fh, $include_label) = @_;
    
    my $node_name;
    my %node_name_hash;
	my $last_in_data_fh_pos = tell($in_data_fh);
    
	while(<$in_data_fh>) {

        # This regular expression match might be slow due to backtracing
        if(/(\d+)\.(\d+) \[label=\"(\w+)[\\n]*(\w*)\"\]/) {
            # Add the Node name to the alphabet hash 
            if ((defined $4) && ($4 ne "")  && $include_label) { 
                $node_name = $3 . "_" . $4; 
            } else {
                $node_name = $3;
            }
            
            # Add the node id to the node_id_hash;
            my $node_id = "$1.$2";
            $node_name_hash{$node_id} = $node_name;
        } else {
            # Done parsing the labels attached to nodes
            seek($in_data_fh, $last_in_data_fh_pos, 0); # SEEK_SET
            last;
        }
        $last_in_data_fh_pos = tell($in_data_fh);
	}

    # Write mapping of node IDs to node names to disk so that they can be
    # retrieved later
    my $hash_file = $self->$_create_filename($global_id);
    store \%node_name_hash, $hash_file unless -r $hash_file;
    return \%node_name_hash;
}


##
# Creates a hash mapping unique ids of nodes to node names
#
# @param global_id: The glboal ID of the request
# @param graph: A string containing the DOT representation of teh request's graph
# @param include_label: Whether or not to include the semantic label in the name
# 
# @return: A reference to a hash table mapping from node IDs to node names
##
sub parse_nodes_from_string {
    
    assert(scalar(@_) == 4);
    my ($self, $global_id, $graph, $include_label) = @_;

    # Check to see if the node ID -> node name mappin has already been stored
    my $hash_file = $self->$_create_filename($global_id);
    if (-e $hash_file) {
        my $retrieved_hash = retrieve($hash_file);
        return $retrieved_hash;
    }

    # Mapping was not already stored.  Create it.
    my %node_name_hash;
    while ($graph =~ m/(\d+)\.(\d+) \[label=\"(\w+)[\\n]*(\w*)\"\]/g) {
        my $node_name;
        if ((defined $4) && ($4 ne "") && $include_label) {
            $node_name = $3 . "_" . $4;
        } else {
            $node_name = $3;
        }

        my $node_id = "$1.$2";
        $node_name_hash{$node_id} = $node_name;
    }

    # Store and return mapping
    store \%node_name_hash, $hash_file unless -r $hash_file;
    return \%node_name_hash;
}

##
# Object constructor
#
# @param proto: Object constructor internals 
# @param node_name_output_dir: Output directory in which mappings from node IDs
# to node names will be cached
##
sub new {
    assert(scalar(@_) == 2);
    my ($proto, $node_name_output_dir) = @_;

    my $class = ref($proto) || $proto;

    my $self = {};
    $self->{OUTPUT_DIR} = "$node_name_output_dir/node_hash/";

    system("mkdir -p $self->{OUTPUT_DIR}");

    bless ($self, $class);
    return $self;
}



1;
