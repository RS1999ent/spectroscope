#! /usr/bin/perl -w

##
# Given a critical path, this function 'refactors' all the contiguous nodes that
# originate from a single component into one edge.  The components to refactor
# are specified in the input.
##

use strict;
use warnings;
use Test::Harness::Assert;
use Getopt::Long;

use lib '../lib';
use ParseDot::StructuredGraph;


##### Global variables ####

my $refactorable_components;


##### Functions ########

##
# Prints usage options
##
sub print_usage {
    
    print "refactor_critical_path.pl --refactor\n";
    print "\t--refactor: List of refactorable components\n";
}


##
# Collects command line parameters
##
sub parse_options {
    
    my @tmp;
    
    GetOptions("refactor=s{1,10}"       => \@tmp);
    
    if(!defined $tmp[0]) {
        print_usage();
        exit(-1);
    }
    
    $refactorable_components = join(' ', @tmp);
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
    
    if ($refactorable_components =~ /$component/) {
        return 1;
    }
    
    return 0;
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

    if ($name =~ /(.+)__.*/) {
        $component = $1;
    }

    assert(defined $component);

    return $component;
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
# @param traversed: Whether the path rooted at DEST_ID has already been traversed
##
sub refactor_graph {
    
    assert(scalar(@_) == 5);
    my ($orig_req_info, $refactored_req_info, $accum_latency, $traversed) = @_;

    my $orig_graph = $orig_req_info->{GRAPH};
    my $refactored_graph = $orig_req_info->{GRAPH};
    my $new_accum_latency;

    my $comp = get_component($orig_req_info->{DEST_ID}, $orig_graph);

    # Case 1: refactored_req_info's root is undefined.  Create root and
    # and recursively call this fn on $orig_req_info->{DEST_ID}'s children
    if (!defined $refactored_req_info->{ID}) {
        my $root;

        if (is_refactorable($comp)) {
            # Case 1A: Root node of original request is refactorable
            $root = $refactored_graph->add_root("$comp" . "_START");
        } else {
            # Case 1B: Root node of original request is refactorable
            my $name = $orig_graph->get_node_name($orig_req_info->{DEST_ID});
            $root = $refactored_graph->add_root($name);
        }

        $refactored_req_info->{ID} = $root;
        $new_accum_latency = 0;

        goto traverse_children;
    }

    my $refactored_comp = get_component($refactored_req_info->{ID}, $refactored_graph);

    # Case 2: Original_req_info->{DEST_ID} contains a node posted on the same
    # component as the node pointed to by refactored->{ID}
    if ($refactored_comp eq $comp) {
        
        if (is_refactorable($comp)) {
            # Case 2A: The component is refactorable.  Simply accomulate the edge latency
            my $new_accum_latency = $accum_latency + 
                $orig_graph->get_edge_latency($orig_req_info->{SRC_ID}, $orig_req_info->{DEST_ID});
        } else {
            # Case 2B: The component is not refactorable.  Simply copy over edge
            assert($accum_latency == 0);
            my $name = $orig_graph->get_node_name($orig_req_info->{DEST_ID});
            my $latency = $orig_graph->get_edge_latency($orig_req_info->{SRC_ID}, $orig_req_info->{DEST_ID});
            my $new_node_id = $refactored_graph->add_child($refactored_req_info->{ID}, $name, $latency);

            $refactored_req_info->{ID} = $new_node_id;
            $new_accum_latency = 0;
        }
        
        goto traverse_children;
    }

    # Case 3: Original_req_info->{DEST_ID} was posted on a different component than the
    # last node created for $refactored_req_info->{ID}
    if (!($refactored_comp eq $comp)) {
        
        my $new_node_id;

        # Case 3-0: The refactored graph's node is stuck on a refactorable component.  End it.
        if(is_refactorable($refactored_comp)) {
            $new_node_id = $refactored_graph->add_child($refactored_req_info->{ID},
                                                           "$refactored_comp" . "_END",
                                                           $accum_latency);
            $refactored_req_info->{ID} = $new_node_id;
            $new_accum_latency = 0;
        }

        my $edge_latency = $orig_graph->get_edge_latency($orig_req_info->{SRC_ID},
                                                         $orig_req_info->{DEST_ID});

        # Case 3A: The original request node is refactorable.  Create a new start node
        if(is_refactorable($comp)) {
            $new_node_id = $refactored_graph->add_child($refactored_req_info->{ID},
                                                                "$comp" . "_START",
                                                                $edge_latency);
            $refactored_req_info->{ID} = $new_node_id            
        } else {
            # Case 3C: Original request node is not refactorable.  Create a new facsimile node.
            my $name = $orig_graph->get_node_name($orig_req_info->{DEST_ID});
            $new_node_id = $refactored_graph->add_child($refactored_req_info->{ID},
                                                           $name,
                                                           $edge_latency);            
        }

        $refactored_req_info->{ID} = $new_node_id;
        $new_accum_latency = 0;
    }

  traverse_children:
    my $children_ids = $orig_graph->get_children_ids($orig_req_info->{DEST_ID});
    my $new_src_node = $orig_req_info->{DEST_ID};
    foreach (@{$children_ids}) {
        my $new_orig_req = {SRC_ID => $orig_graph->{DEST_ID},
                            DEST_ID => $_,
                            GRAPH => $orig_graph->{GRAPH}};
        refactor_graph($new_orig_req, $refactored_req_info, $new_accum_latency, $traversed);
    }
}

    
##### Main routine #####

parse_options();

my $old_seperator = $/;
$/ = '}';    

while (<STDIN>) {
    my $dot_request = $_;

    my $orig_req_graph = new StructuredGraph($dot_request);
    my $orig_req_info = { SRC_ID => undef,
                          GRAPH => $orig_req_graph,
                          DEST_ID => $orig_req_graph->get_root_node_id()
                      };
    my $refactored_req_graph = new StructuredGraph();
    my $refactored_req_info = { ID => undef,
                                GRAPH => $refactored_req_graph };
    my %traversed;
    
    refactor_graph($orig_req_info, $refactored_req_info, 0, \%traversed);

    #$refactored_req_graph->PrintDot();}
}



