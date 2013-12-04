#! /usr/bin/perl -w

#
# Copyright (c) 2013, Carnegie Mellon University.
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
# 1. Redistributions of source code must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in the
#    documentation and/or other materials provided with the distribution.
# 3. Neither the name of the University nor the names of its contributors
#    may be used to endorse or promote products derived from this software
#    without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
# ``AS IS'' AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
# LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
# A PARTICULAR PURPOSE ARE DISCLAIMED.  IN NO EVENT SHALL THE COPYRIGHT
# HOLDERS OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
# INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING,
# BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS
# OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED
# AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
# LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY
# WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
# POSSIBILITY OF SUCH DAMAGE.
#

# $cmuPDL: DotHelper.pm,v 1.6 2009/08/26 21:28:36 rajas Exp $
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

our @EXPORT_OK= qw(parse_nodes_from_string parse_nodes_from_file find_dot_node);

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
        if (defined $4 && $include_label && $4 ne "") {
            $node_name = $3 . "_" . $4;
        } else {
            $node_name = $3;
        }

        my $node_id = "$1.$2";
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
