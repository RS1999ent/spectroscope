#! /usr/bin/perl -w

# $cmuPDL: refactor_path.pl,v 1.4 2009/11/04 02:04:19 rajas Exp $v

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
my %orig_to_refactored = ();


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
    assert(scalar(@_) == 4);
    my ($orig_req_info, $refactored_req_info, $accum_latency, $traversed) = @_;

    my $orig_graph = $orig_req_info->{GRAPH};
    my $refactored_graph = $refactored_req_info->{GRAPH};
    my $new_accum_latency;
    my $new_refactored_node_id;

    my $comp = get_component($orig_req_info->{DEST_ID}, $orig_graph);

    # Case 1: refactored_req_info's root is undefined.  Create root and
    # and recursively call this fn on $orig_req_info->{DEST_ID}'s children
    if (!defined $refactored_req_info->{ID}) {
        # Case 1B: Root node of original request is refactorable
        my $name = $orig_graph->get_node_name($orig_req_info->{DEST_ID});
        $new_refactored_node_id = $refactored_graph->add_root($name);
				$orig_to_refactored{$orig_req_info->{DEST_ID}} = $new_refactored_node_id;
        $new_accum_latency = 0;

        goto traverse_children;
    }

    my $refactored_comp = get_component($refactored_req_info->{ID}, $refactored_graph);

    # Case 2: Original_req_info->{DEST_ID} contains a node posted on the same
    # component as the node pointed to by refactored->{ID}
    if ($refactored_comp eq $comp) {

        my $children_ids = $orig_graph->get_children_ids($orig_req_info->{DEST_ID});
        my $edge_latency = $orig_graph->get_edge_latency($orig_req_info->{SRC_ID}, 
                                                         $orig_req_info->{DEST_ID});
        
        if (is_refactorable($comp) && scalar(@{$children_ids} > 0)) {
            # Case 2A: The component is refactorable.  Simply accomulate the edge latency
            $new_accum_latency = $accum_latency + $edge_latency;
            $new_refactored_node_id = $refactored_req_info->{ID};
        } elsif (is_refactorable($comp)) {
            # Case 2B: Original_req_info->{DEST_ID} has no children, so we have to create an "END" node
						if (defined $orig_to_refactored{$orig_req_info->{DEST_ID}}) {
							$new_refactored_node_id = $orig_to_refactored{$orig_req_info->{DEST_ID}};
							$refactored_graph->add_existing_child($refactored_req_info->{ID},
							                                      $new_refactored_node_id,
																										$accum_latency + $edge_latency);
						} else {
            	$new_refactored_node_id = $refactored_graph->add_child($refactored_req_info->{ID},
                                                                      $refactored_comp . "__END",
                                                                      $accum_latency + $edge_latency);
							$orig_to_refactored{$orig_req_info->{DEST_ID}} = $new_refactored_node_id;
						}
            $new_accum_latency = 0;
        } else {                                                     
            # Case 2C: The component is not refactorable.  Simply copy over edge
            assert($accum_latency == 0);
						if (defined $orig_to_refactored{$orig_req_info->{DEST_ID}}) {
							$new_refactored_node_id = $orig_to_refactored{$orig_req_info->{DEST_ID}};
							$refactored_graph->add_existing_child($refactored_req_info->{ID},
							                                      $new_refactored_node_id,
																										$edge_latency); 
					  } else {	
            	my $name = $orig_graph->get_node_name($orig_req_info->{DEST_ID});
            	$new_refactored_node_id = $refactored_graph->add_child($refactored_req_info->{ID}, $name, $edge_latency);
							$orig_to_refactored{$orig_req_info->{DEST_ID}} = $new_refactored_node_id;
						}
            $new_accum_latency = 0;
        }
        
        goto traverse_children;
    }

    # Case 3: Original_req_info->{DEST_ID} was posted on a different component than the
    # last node created for $refactored_req_info->{ID}
    if (!($refactored_comp eq $comp)) {
        
        # Case 3-0: The refactored graph's node is stuck on a refactorable component.  End it.
        if(is_refactorable($refactored_comp)) {
						if (defined $orig_to_refactored{$orig_req_info->{SRC_ID}}) {
							$new_refactored_node_id = $orig_to_refactored{$orig_req_info->{SRC_ID}};
							$refactored_graph->add_existing_child($refactored_req_info->{ID},
							                                      $new_refactored_node_id,
																										$accum_latency); 
					  } else {	 
            	$new_refactored_node_id = $refactored_graph->add_child($refactored_req_info->{ID},
                                                                   	"$refactored_comp" . "__END",
                                                                   	 $accum_latency);
							$orig_to_refactored{$orig_req_info->{SRC_ID}} = $new_refactored_node_id;
						}
            $new_accum_latency = 0;
        } else {
            $new_refactored_node_id = $refactored_req_info->{ID};
					  $orig_to_refactored{$orig_req_info->{SRC_ID}} = $new_refactored_node_id;
        }

        my $edge_latency = $orig_graph->get_edge_latency($orig_req_info->{SRC_ID},
                                                         $orig_req_info->{DEST_ID});

        # Case 3A: The original request node is refactorable.  Create a new start node
        if(is_refactorable($comp)) {
						if (defined $orig_to_refactored{$orig_req_info->{DEST_ID}}) {
							my $src_node_id = $new_refactored_node_id;
							$new_refactored_node_id = $orig_to_refactored{$orig_req_info->{DEST_ID}};
							$refactored_graph->add_existing_child($src_node_id,
							                                      $new_refactored_node_id,
																										$edge_latency);
					  } else {	 
            	$new_refactored_node_id = $refactored_graph->add_child($new_refactored_node_id,
                                                                	"$comp" . "__START",
                                                                	$edge_latency);
					    $orig_to_refactored{$orig_req_info->{DEST_ID}} = $new_refactored_node_id;
						}
        } else {
            # Case 3C: Original request node is not refactorable.  Create a new facsimile node.
						if (defined $orig_to_refactored{$orig_req_info->{DEST_ID}}) {
							my $src_node_id = $new_refactored_node_id;
							$new_refactored_node_id = $orig_to_refactored{$orig_req_info->{DEST_ID}};
							$refactored_graph->add_existing_child($src_node_id,
							                                      $new_refactored_node_id,
																										$edge_latency);
					  } else {
            	my $name = $orig_graph->get_node_name($orig_req_info->{DEST_ID});
            	$new_refactored_node_id = $refactored_graph->add_child($new_refactored_node_id,
                                                           	$name,
                                                           	$edge_latency);            
					    $orig_to_refactored{$orig_req_info->{DEST_ID}} = $new_refactored_node_id;
						}
        }

        $new_accum_latency = 0;
    }
    
  traverse_children:
    my $children_ids = $orig_graph->get_children_ids($orig_req_info->{DEST_ID});
    my $new_src_node = $orig_req_info->{DEST_ID};
    my $num = scalar(@{$children_ids});

    foreach (@{$children_ids}) {

        my %new_orig_req_info = (SRC_ID => $orig_req_info->{DEST_ID},
                            DEST_ID => $_,
                            GRAPH => $orig_graph);

        my %new_refactored_req_info = ( ID => $new_refactored_node_id,
                                        GRAPH => $refactored_graph );

        refactor_graph(\%new_orig_req_info, \%new_refactored_req_info, 
                       $new_accum_latency, $traversed);
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
    if ($dot_request =~ /(\# .*)\n/)  {
        $header = $1;
    } else {
        next;
    }
    assert (defined $header);

    print STDERR "Processing new request\n";
    $count++;
    my $orig_req_graph = new StructuredGraph($dot_request, 0);
    my %orig_req_info = ( SRC_ID => undef,
                          GRAPH => $orig_req_graph,
                          DEST_ID => $orig_req_graph->get_root_node_id());

    my $refactored_req_graph = new StructuredGraph($count);
    my %refactored_req_info = ( ID => undef,
                                GRAPH => $refactored_req_graph);
    my %traversed;
    
    refactor_graph(\%orig_req_info, \%refactored_req_info, 0, \%traversed);

    print "$header\n";
    $refactored_req_graph->print_dot(\*STDOUT);
    print "\n";

}



