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

# $cmuPDL: refactor_path.pl,v 1.5 2010/04/13 05:05:38 ww2 Exp $v

##
# Given a critical path, this function 'refactors' all the contiguous nodes that
# originate from a single component into one edge.  The components to refactor
# are specified in the input.
##

#### Package declarations ###############################

use strict;
use Test::Harness::Assert;
use Getopt::Long;

use lib '../lib';
use ParseDot::StructuredGraph;

no warnings 'recursion';

##### Global variables ####

my @refactorable_components;

##### Functions ########

##
# Prints usage options
##
sub print_usage {
    
    print "refactor_path.pl --refactor\n";
    print "\t--refactor: List of refactorable components\n";
}


##
# Collects command line parameters
##
sub parse_options {
    
    my @tmp;
    
    GetOptions("refactor=s{1,10}" => \@refactorable_components);
    
    if(!defined $refactorable_components[0]) {
        print_usage();
        exit(-1);
    }
}

##
# Determines whether a component is refactorable
#
# @param component: The component
#
# @return 1 if the component is refactorable, 0 if it is not
##
sub is_refactorable {
    
    assert( scalar(@_) == 1);
    my ($component) = @_;
    
    foreach (@refactorable_components) {
        if($component eq $_) {
            return 1;
        }
    }
}


##
# Returns the component on which the instrumentation point was posted
#
# @param node_id: The node corresponding to the instrumentation pont
# @param graph: A Strucutred Graph object
#
# @return The component
##
sub get_component {
    
    assert(scalar(@_) == 2);
    my ($node_id, $graph) = @_;
    
    my $name = $graph->get_node_name($node_id);
    my $component;
    
    if ($name =~ /(e[0-9]+)__.+/) {
        $component = $1;
    }
    
    assert(defined $component);
    return $component;
}


##
# Handles case 2 of refactoring graphs.  In this case, original_req_inf->{DEST_ID} contains
# a node posted on the same component as the node pointed to by refactored->{ID}.  There
# are two main subcases: 
#    1)The component is refactorable and has children.  In this case, additional latency
#      is simply added to the edge that spans this component in the refactored graph.
#    2)The component is refactorable and has no children.  In this case, an end node
#      must be created and the accumulated latency transferred to the 
#      component_start->component_end edge.
#    3)The component is not refactorable.  In this case, the destination node of the 
#      original graph simply needs to be copied over to the new graph.
#
# @param orig_req_info: Reference to hash w/info about hte original request 
# @param refactored_req_info: Reference to hash w/info about the refactored request
# @param accum_latency: A pointer to a integer that collects the accumulated
#  latency at the current component, if the component is refactorable.  This
#  value can be modified by this function
# @param orig_to_refactored: A hash mapping original IDs of original destination
#  nodes to their refactored equivalent.  This is used to find paths already
#  traversed when refactoring graphs w/concurrency and joins.
# @param comp: The component on which the original graph's destination node is
# posted
# @param refactored_comp: The component of the current outstanding node in the
# refactored graph.
#
# @return: A hash w/three elements: {NEW_ACCUM_LATENCY, TRAVERSE_CHILDREN, NEW_REFACTORED_ID}
##
sub handle_case_2 {
    assert(scalar(@_) == 6);
    my ($orig_req_info,
        $refactored_req_info,
        $accum_latency,
        $orig_to_refactored,
        $comp,
        $refactored_comp) = @_;
    
    my $orig_graph = $orig_req_info->{GRAPH};
    my $refactored_graph = $refactored_req_info->{GRAPH};
    
    my ($new_accum_latency, $traverse_children, $new_refactored_node_id);
    
    my $children_ids = $orig_graph->get_children_ids($orig_req_info->{DEST_ID});
    my $parents_ids = $orig_graph->get_parent_ids($orig_req_info->{DEST_ID});

    my $edge_latency = $orig_graph->get_edge_latency($orig_req_info->{SRC_ID}, 
                                                     $orig_req_info->{DEST_ID});

    if (is_refactorable($comp) && scalar(@{$children_ids} > 0)) {
        # Case A: The component is refactorable.  S
        if (defined $orig_to_refactored->{$orig_req_info->{DEST_ID}}) {
            # This is a join
            $new_refactored_node_id = $orig_to_refactored->{$orig_req_info->{DEST_ID}};
            $refactored_graph->add_existing_child($refactored_req_info->{ID},
                                                  $new_refactored_node_id,
                                                  $accum_latency + $edge_latency);
            $traverse_children = 0;
            $new_accum_latency = 0;

        } elsif(scalar(@{$parents_ids} > 1) || scalar(@{$children_ids} > 1)) {
            # Need to create a join node and add it to the $orig_to_refactored.  This is necessary
            # to properly account for joins within a component
            my $node_postpend = (scalar(@{$parents_ids}) > 1 && scalar(@{$children_ids} > 1)) ? "__JOINSPLIT" :
                ((scalar@{$parents_ids}) > 1)? "__JOIN" : "__SPLIT";
            $new_refactored_node_id = $refactored_graph->add_child($refactored_req_info->{ID},
                                                                   $refactored_comp . $node_postpend,
                                                                   $accum_latency + $edge_latency);
            $orig_to_refactored->{$orig_req_info->{DEST_ID}} = $new_refactored_node_id;                                         
            $traverse_children = 1;
            $new_accum_latency = 0;
        } else {           
            # Simply accumualte the edge latnecy
            $new_accum_latency = $accum_latency + $edge_latency;
            $new_refactored_node_id = $refactored_req_info->{ID};
            $traverse_children = 1;
        }
        
    } elsif (is_refactorable($comp)) {
        # Case B: Original_req_info->{DEST_ID} has no children, so we have to create an "END" node
        if (defined $orig_to_refactored->{$orig_req_info->{DEST_ID}}) {
            # Case where the path rooted at $orig_req_info->{DEST_ID} has already been traversed.  
            # Find corresponding refactored node and simply add it as a child            
            $new_refactored_node_id = $orig_to_refactored->{$orig_req_info->{DEST_ID}};
            $refactored_graph->add_existing_child($refactored_req_info->{ID},
                                                  $new_refactored_node_id,
                                                  $accum_latency + $edge_latency);
            $traverse_children = 0;
        } else {
            # Path rooted at $orig_req_info->{DEST_ID} has not been traversed yet.
            # Add a new child and traverse $orig_req_info->{DEST_ID}s children.
            $new_refactored_node_id = $refactored_graph->add_child($refactored_req_info->{ID},
                                                                   $refactored_comp . "__END",
                                                                   $accum_latency + $edge_latency);
            $traverse_children = 1;
        }
        $new_accum_latency = 0;
        
    } else {                                                     
        # Case C: The component is not refactorable.  Simply copy over edge
        assert($accum_latency == 0);
        if (defined $orig_to_refactored->{$orig_req_info->{DEST_ID}}) {
            # Path rooted at $orig_req_info->{DEST_ID} has already been traversed.
            # Find corresponding refactored node and simply add it as a child
            $new_refactored_node_id = $orig_to_refactored->{$orig_req_info->{DEST_ID}};
            $refactored_graph->add_existing_child($refactored_req_info->{ID},
                                                  $new_refactored_node_id,
                                                  $edge_latency); 
            $traverse_children = 0;
        } else {	
            # Path rooted at $orig_req_info->{DEST_ID} has already been traversed.
            # Add a new child andtraverse $orig_req_info->{DEST_ID}s children.
            my $name = $orig_graph->get_node_name($orig_req_info->{DEST_ID});
            $new_refactored_node_id = $refactored_graph->add_child($refactored_req_info->{ID}, $name, $edge_latency);
            $orig_to_refactored->{$orig_req_info->{DEST_ID}} = $new_refactored_node_id;
            $traverse_children = 1;
        }
        $new_accum_latency = 0;
    }
    
    return { NEW_REFACTORED_NODE_ID => $new_refactored_node_id,
             NEW_ACCUM_LATENCY => $new_accum_latency,
             TRAVERSE_CHILDREN => $traverse_children};
}


##
# Handles case 3 of refactoring graphs.  In this case, the node pointed to by
# original_req_info->{DEST_ID} was posted on a different component than the
# current outstanding node in the refactored graph.  There are 3 subcases.
#    1)Deal with whether the refactored graph's outstanding node was refactorable.  If so, a new
#      "END" node needs to be added.  
#    2)Deal with $orig_req_info->{DEST_NODE}
#     A)The node poiinted to by $original_req_info->{DEST_ID} is refactorable.  A new start node
#       needs to be created.
#     B)The node pointed to by $original_req_info->{DEST_ID} is not refactorable.  The node
#       needs to be copied over to the refactored graph.
#
# @param orig_req_info: Reference to hash w/info about the original request 
# @param refactored_req_info: Reference to hash w/info about the refactored request
# @param accum_latency: A pointer to a integer that collects the accumulated
#  latency at the current component, if the component is refactorable.  This
#  value can be modified by this function
# @param orig_to_refactored: A hash mapping original IDs of original destination
#  nodes to their refactored equivalent.  This is used to find paths already
#  traversed when refactoring graphs w/concurrency and joins.
# @param comp: The component on which the original graph's destination node is
# posted
# @param refactored_comp: The component of the current outstanding node in the
# refactored graph.
#
# @return: A hash w/three elements: {NEW_ACCUM_LATENCY, TRAVERSE_CHILDREN, NEW_REFACTORED_ID} 
##
sub handle_case_3 {
    
    assert(scalar(@_) == 6);
    my ($orig_req_info,
        $refactored_req_info,
        $accum_latency,
        $orig_to_refactored,
        $comp,
        $refactored_comp) = @_;

    my $orig_graph = $orig_req_info->{GRAPH};
    my $refactored_graph = $refactored_req_info->{GRAPH};
    
    my ($traverse_children, $new_refactored_node_id);        
    
    my $edge_latency = $orig_graph->get_edge_latency($orig_req_info->{SRC_ID},
                                                     $orig_req_info->{DEST_ID});
    
    if(is_refactorable($refactored_comp)) {
        # Case 1A: Outstanding node on refactored graph is stuck on a
        # refactorable component.  Add a "end" node.        
        $new_refactored_node_id = $refactored_graph->add_child($refactored_req_info->{ID},
                                                               "$refactored_comp" . "__END",
                                                               $accum_latency);
        $orig_to_refactored->{$orig_req_info->{SRC_ID}} = $new_refactored_node_id;
    } else {
        # Case 1B: Outstanding node on refactorable graph is not on a refactorable component
        # No need to do anything.
        $new_refactored_node_id = $refactored_req_info->{ID};
        $orig_to_refactored->{$orig_req_info->{SRC_ID}} = $new_refactored_node_id;
    }
    
    if(is_refactorable($comp)) {
        # Case 3A: The original request node is refactorable.  Create a new start node
        if (defined $orig_to_refactored->{$orig_req_info->{DEST_ID}}) {
            # $orig_req_info->{DEST_ID} has already been traversed.  The start node already
            # exists in the refactored graph.  Simply hook into it.
            my $src_node_id = $new_refactored_node_id;
            $new_refactored_node_id = $orig_to_refactored->{$orig_req_info->{DEST_ID}};
            $refactored_graph->add_existing_child($src_node_id,
                                                  $new_refactored_node_id,
                                                  $edge_latency);
            $traverse_children = 0;
        } else {	 
            # $orig_req_info->{DEST_ID} has not been traversed yet.  The start node does not
            # exist.  Need to create it.
            $new_refactored_node_id = $refactored_graph->add_child($new_refactored_node_id,
                                                                   "$comp" . "__START",
                                                                   $edge_latency);
            $orig_to_refactored->{$orig_req_info->{DEST_ID}} = $new_refactored_node_id;
            $traverse_children = 1;
        }
    } else {
        # Case 3B: Original request node is not refactorable.  Create a new facsimile node.
        if (defined $orig_to_refactored->{$orig_req_info->{DEST_ID}}) {
            # $orig_req_info->{DEST_ID} has already been taversed.  The facsimile node
            # already exists in the refactored graph.  Simply hook into it.
            my $src_node_id = $new_refactored_node_id;
            $new_refactored_node_id = $orig_to_refactored->{$orig_req_info->{DEST_ID}};
            $refactored_graph->add_existing_child($src_node_id,
                                                  $new_refactored_node_id,
                                                  $edge_latency);
            $traverse_children = 0;
        } else {
            # $orig_req_info->{DEST_ID} has not already been traversed.  The facsimile
            # node needs to be created.
            my $name = $orig_graph->get_node_name($orig_req_info->{DEST_ID});
            $new_refactored_node_id = $refactored_graph->add_child($new_refactored_node_id,
                                                                   $name,
                                                                   $edge_latency);            
            $orig_to_refactored->{$orig_req_info->{DEST_ID}} = $new_refactored_node_id;
            $traverse_children = 1;
        }
    }

    return { NEW_REFACTORED_NODE_ID => $new_refactored_node_id,
             NEW_ACCUM_LATENCY => 0,
             TRAVERSE_CHILDREN => $traverse_children };
}
        
        
##
# Refactors graphs into a component-based view.  All sequential nodes
# posted on a component that is on the refactored list are combined into
# a "combined edge."  When this function returns, $refactored_req_info contains
# the refactored request-flow graph
#
# @param orig_req_info: Ponter to a hash w/the following elements
#    { SRC_ID => ID of the source node of the request to be refactored
#      DEST_ID => ID of the dest node of the request to be refactored
#      GRAPH => Reference to a structured graph object }
# @param refactored_req_info: Ref to a hash w/the following elemnts
#    { ID => Last node created for the refactored req
#      GRAPH => Reference to a structured graph object }
# @param accum_latency: Combined latency of nodes being refactored
# @param orig_to_refactored: Keeps a mapping of Node IDs in the original graphs
# to corresponding refactored node ids
##
sub refactor_graph {
    assert(scalar(@_) == 4);
    my ($orig_req_info, $refactored_req_info, $accum_latency, $orig_to_refactored) = @_;

    my $orig_graph = $orig_req_info->{GRAPH};
    my $refactored_graph = $refactored_req_info->{GRAPH};

    my $new_accum_latency;
    my $new_refactored_node_id;
    my $traverse_children;

    my $comp = get_component($orig_req_info->{DEST_ID}, $orig_graph);

    if (!defined $refactored_req_info->{ID}) {
        # Case 1: refactored_req_info's root is undefined.  Create root and
        # and recursively call this fn on $orig_req_info->{DEST_ID}'s children
        my $name = $orig_graph->get_node_name($orig_req_info->{DEST_ID});

        $new_refactored_node_id = $refactored_graph->add_root($name);
        $orig_to_refactored->{$orig_req_info->{DEST_ID}} = $new_refactored_node_id;

        $new_accum_latency = 0;
        $traverse_children = 1;

    } else {
        # Handle cases 2 and 3
        my $refactored_comp = get_component($refactored_req_info->{ID}, $refactored_graph);
        my $results;
        
        # Call functions to handle (complicated) cases 2 and 3
        if ($refactored_comp eq $comp) {
            $results = handle_case_2($orig_req_info, $refactored_req_info, $accum_latency,
                                     $orig_to_refactored, $comp, $refactored_comp);
        } else {
            $results = handle_case_3($orig_req_info, $refactored_req_info, $accum_latency,
                                     $orig_to_refactored, $comp, $refactored_comp);
        }

        $new_accum_latency = $results->{NEW_ACCUM_LATENCY};
        $new_refactored_node_id = $results->{NEW_REFACTORED_NODE_ID};
        $traverse_children = $results->{TRAVERSE_CHILDREN};
    }
        
    # Traverse children, if the graph rooted at $orig_req_info->{DEST_ID} has
    # already not been traversed
    if ($traverse_children) {
        my $children_ids = $orig_graph->get_children_ids($orig_req_info->{DEST_ID});
        my $new_src_node = $orig_req_info->{DEST_ID};
        my $num = scalar(@{$children_ids});
        
        foreach (@{$children_ids}) {
            
            my %new_orig_req_info = (SRC_ID => $new_src_node,
                                     DEST_ID => $_,
                                     GRAPH => $orig_graph);
            
            my %new_refactored_req_info = ( ID => $new_refactored_node_id,
                                            GRAPH => $refactored_graph );
            
            refactor_graph(\%new_orig_req_info, \%new_refactored_req_info, 
                           $new_accum_latency, $orig_to_refactored);
        }
    }
}


##### Main routine #####

parse_options();

my $old_seperator = $/;
$/ = '}';    

my $count = 0;
while (<STDIN>) {
    my $dot_request = $_;
    
    my $header;
    if ($dot_request =~ /(\#.*)\n/)  {
        $header = $1;
    } else {
        next;
    }
    assert (defined $header);
    
    $count++;
    print STDERR "Processing new request: $count\n";
    
    my $orig_req_graph = new StructuredGraph($dot_request, 0);
    my %orig_req_info = ( SRC_ID => undef,
                          GRAPH => $orig_req_graph,
                          DEST_ID => $orig_req_graph->get_root_node_id());

    my $refactored_req_graph = new StructuredGraph($count);
    my %refactored_req_info = ( ID => undef,
                                GRAPH => $refactored_req_graph);
    my %orig_to_refactored;
    
    refactor_graph(\%orig_req_info, \%refactored_req_info, 0, \%orig_to_refactored);

    print "$header\n";
    $refactored_req_graph->print_dot(\*STDOUT);
    print "\n";

}



