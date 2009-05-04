#!/usr/bin/perl -w

# $cmuPDL: CreateClusteringInput.pm,v 1.6 2009/05/02 23:31:29 source Exp $
##
# @author Raja Sambasivan
#
# This perl script translates the DOT-format requests output from Ursa Minor's
# ATC into a set of matrices that can be input into a tool such as MATLAB.
#
# Input: 
#  snapshot0: The DOT graphs that correspond to the non-problem dataset
#  snapshot1: The DOT graphs that correspond to the problem dataset
#  output_dir: The directory in which output should be placed
#
# Input request-flow graphs should adhere to the following format:
#
#   # <unique ID>    R: <overall latency>
#   begin digraph G {
#      <First node unique ID> [Label="<Node Name>\n<Optype>]       
#       ...
#      <Last node unique ID> [Label="<Node Name>\n<Optype>]
#      <unique ID> -> <Unique ID> [Label="R: <Latency>]
#        ...
#      <Unique ID> -> <Unique ID> [Label="R: <Latency>]
#   }
#
# Output: 
#  input_vector: This file is populated with a string
#  representation of all the unique requests (as determined by their
#  structure) in the input datasets.  The first two columns of each
#  row is the number of times the corresponding unique request
#  structure was seen in the two datasets.
#
#  input_vec_to_glabal_ids: A mapping of each unique request structure
#  contained in the input_vector to the global IDs of
#  the requests that display this structure.  The global ID is unique
#  across all datasets input into this script.
#
#  alphabet_mapping_file: This file contains a listing of the original
#  node names and the encoding (character) to which it corresponds in
#  the input_vector.
##

package CreateClusteringInput;

use strict;
use Test::Harness::Assert;


# Global variables ########################################


#### Internal functions  ########################################

##
# Prints the mapping from characters to node names.
#
# Each row of the output file contains the following info:
# <character representation> <node name>
# 
# @param self: The object-container
##
my $_print_alphabet_mapping = sub {
	my $self = shift;

	open(my $alphabet_mapping_fh, ">$self->{ALPHABET_MAPPING_FILE}");

    my $alphabet_hash = $self->{ALPHABET_HASH};
	
	foreach my $node_name (sort {$alphabet_hash->{$a} <=> $alphabet_hash->{$b}} keys %$alphabet_hash) {
		my $alphabet_val = $alphabet_hash->{$node_name};
		print $alphabet_mapping_fh "$alphabet_val -> $node_name\n";
	}

    close($alphabet_mapping_fh);
};


##
# Prints the string representation of each unique request to the
# output file specified by $self->{INPUT_VECTOR_FILE}.  This file is formatted
# as follows: 
#   <number of reqs in s0> <number of reqs in s1> <string>
# 
# Additionally, a mapping from the string to the global IDs of the requests it
# matches is printed, to the file specified in $self->{STRING_REP_MAPPING}.  Each
# line corresponds to a string representation and contains the global IDs.
#
# @param self: The object-container
##
my $_print_string_rep_hash = sub {
    my $self = shift;

    print "$self->{INPUT_VECTOR_FILE}\n\n\n\n";
    print "$self->{INPUT_VEC_TO_GLOBAL_IDS_FILE}\n\n\n";

	open(my $string_rep_fh, ">$self->{INPUT_VECTOR_FILE}");
	open(my $string_rep_mapping_fh, ">$self->{INPUT_VEC_TO_GLOBAL_IDS_FILE}");

    my $string_rep_hash = $self->{STRING_REP_HASH};
    my $string_rep_mapping = $self->{STRING_REP_MAPPING};

	foreach my $key (keys %$string_rep_hash) {

		# Print the string_rep_hash
		my @arr = @{$string_rep_hash->{$key}};
		print $string_rep_fh "$arr[0] $arr[1] $key\n";

		# Print the mapping from string representation to global IDs
		print $string_rep_mapping_fh "@{$string_rep_mapping->{$key}}\n";
	}

    close($string_rep_fh);
    close($string_rep_mapping_fh);
};


##
# This function adds the nodes of a request to two hash tables.
# First, $self->{ALPHABET_HASH}, which keeps a global mapping
# from Node Name -> character it is assigned.  Second,
# the $node_name_hash, which is a per-request hash that keeps
# a mapping from node id -> node name.
#
# @param self: The object-container
# @param in_data_fh: The filehandle of the file containing
# requests.  Its offset is set to the start of the nodes.
# @param node_name_hash: A pointer to the per-request hash 
# mapping name names to their corresponding alphabet.
##
my $_handle_nodes = sub {
    my $self = shift;

	my $in_data_fh = shift;
	my $node_name_hash = shift;
	my $last_in_data_fh_pos;
    my $node_name;

    my $alphabet_hash = $self->{ALPHABET_HASH};

	$last_in_data_fh_pos = tell($in_data_fh);

	while(<$in_data_fh>) {

		if(/(\d+)\.(\d+) \[label=\"(\w+)\\n(\w*)\"\]/) {

			# Add the Node label to the alphabet hash 
            if (defined $4) { 
                $node_name = $3 . "_" . $4; 
            } else {
                $node_name = $3;
            }

			if(!defined $alphabet_hash->{$node_name}) {
				$alphabet_hash->{$node_name} = $self->{ALPHABET_COUNTER}++;

				#if($self->{ALPHABET_COUNTER} >= 126) {
				#	print "USED LAST POSSIBLE CHARACTER!!!\n";
				#	assert(0);
				#}
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

};


##
# Given the edge of a request-flow graph, this function appends the
# source node to the string representation of the request.  The destination
# node is not added because it will be seen again as a source node.
##
my $_get_alphabetized_edge  = sub {
    my $self = shift;

	my $src_node_name = shift;
	my $dest_node_name = shift;
	my $string_rep = shift;

    my $alphabet_hash = $self->{ALPHABET_HASH};

	#my $src_node_alphabet = chr($alphabet_hash->{$src_node_name});
    my $src_node_alphabet = $alphabet_hash->{$src_node_name};
	my $dest_node_alphabet = $alphabet_hash->{$dest_node_name};
	
	$$string_rep = $$string_rep . " " . "$src_node_alphabet" . " " . 
        "$dest_node_alphabet";
};


##
# Adds a request to the hash of string representations of requests
# ($self->{STRING_REP_HASH}), which stores a mapping 
# string -> <number of reqs in s0, number of reqs in s1>.
# This function also appends to $self->{STRING_REP_MAPPING}, which
# keeps a mapping from string represntation to global ids of requests
# that map to this string.
#
# @param self: The object-container
# @param string: The string representation of the request
# @param dataset: The snapshot to which the request belongs
# @param global_id: The global id of the request
## 
my $_add_to_string_rep_hash = sub {
    my $self = shift;

	my $string = shift;
	my $dataset = shift;
	my $global_id = shift;

    my $string_rep_hash = $self->{STRING_REP_HASH};
    my $string_rep_mapping = $self->{STRING_REP_MAPPING};

	if(!defined $string_rep_hash->{$string}) {
		my @arr = (0, 0);
		$string_rep_hash->{$string} = \@arr;
	} 
   
	my $arr = $string_rep_hash->{$string};
	$arr->[$dataset]++;

	push @{$string_rep_mapping->{$string}}, $global_id;
};


##
# Creates the string representation for this request.  Also, appends to the
# mapping of unique string representation of a request -> Global IDs of
# requests that map to this representation.
#
# @param self: The object-container
# @param in_data_fh: The filehandle of the file containing graphs.  Its offset
# is set to the start of the edges for this request.  
# @param node_name_hash: A hash mapping <node id> -> <node name>.
# @param global_id: The global id of the current request
# @param dataset: The snapshot to which this request belongs
##
my $_handle_edges = sub {
    my $self = shift;

	my $in_data_fh = shift;
	my $node_name_hash = shift;
	my $global_id = shift;
	my $dataset = shift;

	my $string_rep = '';

	while(<$in_data_fh>) {
 
		if(/(\d+)\.(\d+) \-> (\d+)\.(\d+) \[label=\"R: ([0-9\.]+) us\".*\]/) {
		
			my $src_node_id = "$1.$2";
			my $dest_node_id = "$3.$4";

			my $src_node_name = $node_name_hash->{$src_node_id};
			my $dest_node_name = $node_name_hash->{$dest_node_id};
			
			$self->$_get_alphabetized_edge($src_node_name, $dest_node_name, \$string_rep);
		} else {
			$self->$_add_to_string_rep_hash($string_rep, $dataset, $global_id);
			last;
		}
	} 
};


##
# Iterates through each request seen in the input snapshot
# and performs the necessary work to convert them to MATLAB
# compatibile output.  
#
# @param self: The object-container
# @param snapshot_file: The file from which to read requests
# @param dataset: The snapshot (0 or 1)
##
my $_handle_requests = sub {
	my $self = shift;

	my $snapshot_file = shift;
	my $dataset = shift;

    assert($dataset == 0 || $dataset == 1);

	open(my $snapshot_fh, "<$snapshot_file");

	while(<$snapshot_fh>) {
		my %node_name_hash;

		if(/\# (\d+)  R: ([0-9\.]+)/) {
            # Great!!!
		} else {
			# This is not the start of a request
			next;
		}
							   
		# Skip the "{" line
		$_ = <$snapshot_fh>;
		
		# Append to the alphabet
		$self->$_handle_nodes($snapshot_fh, \%node_name_hash);
							   
		# Print edges names and latencies
		$self->$_handle_edges($snapshot_fh, \%node_name_hash,
					 $self->{GLOBAL_ID}, $dataset);

		$self->{GLOBAL_ID} = $self->{GLOBAL_ID} + 1;
	}

    close($snapshot_fh);
};


## 
# Computes the distance between the unique string
# representation of requests.
my $_compute_distance_matrix = sub {
    my $self = shift;
    
    ##### ADDDDDDDD!!!!
};


## 
# Removes the files created by this perl modue, if they already
# exist in the output directory.
##
my $_remove_existing_files = sub {
    my $self = shift;

	if(-e $self->{INPUT_VECTOR_FILE}) {
		print("Deleting old $self->{INPUT_VECTOR_FILE}\n");
		system("rm -f $self->{INPUT_VECTOR_FILE}") == 0
			or die("Could not delete old $self->{INPUT_VECTOR_FILE}\n");
	}

	if(-e $self->{ALPHABET_MAPPING_FILE}) {
		print("Deleting old $self->{ALPHABET_MAPPING_FILE}\n");
		system("rm -f $self->{ALPHABET_MAPPING_FILE}") == 0 
			or die("Could not delete old $self->{ALPHABET_MAPPING_FILE}\n");
	}
    
    if(-e $self->{INPUT_VEC_TO_GLOBAL_IDS_FILE}) {
		print "Deleting old $self->{INPUT_VEC_TO_GLOBAL_IDS_FILE}\n";
		system("rm -f $self->{INPUT_VEC_TO_GLOBAL_IDS_FILE}") == 0
			or die("Could not delete old $self->{INPUT_VEC_TO_GLOBAL_IDS_FILE}\n");
	}

    if(-e $self->{DISTANCE_MATRIX_FILE}) {
        print "Deleting old $self->{DISTANCE_MATRIX_FILE}\n";
        system("rm -f $self->{DISTANCE_MATRIX_FILE}") == 0
            or die("Could not delete old $self->{DISTANCE_MATRIX_FILE}");
    }
};


#### API functions ##########################################

sub new {
    my $proto = shift;
    my $snapshot0_file;
    my $snapshot1_file;
    my $output_dir;


    # Get constructor parameters
    $snapshot0_file = shift;
    if ($#_ == 1)  {
        $snapshot1_file = shift;
        $output_dir = shift;
    } elsif ($#_ == 0) {
        $output_dir = shift;
    } else {
        print "Invalid instantiaton of this object!\n";
        assert(0);
    }
    
    my $class = ref($proto) || $proto;
    
    my $self = {};
    
    $self->{SNAPSHOT0_FILE} = $snapshot0_file;
    if(defined $snapshot1_file) {
        $self->{SNAPSHOT1_FILE} = $snapshot1_file;
    } else {
        $self->{SNAPSHOT1_FILE} = undef;
    }
    $self->{INPUT_VECTOR_FILE} = "$output_dir/input_vector.dat";
    $self->{INPUT_VEC_TO_GLOBAL_IDS_FILE} = "$output_dir/input_vec_to_global_ids.dat";

    # Hash of String representation for each unique request seen
    $self->{STRING_REP_HASH} = {};
    # Mapping of individual requests to their representation in the above hash.
    $self->{STRING_REP_MAPPING} = {};
    # Mapping from alphabet to node name
    $self->{ALPHABET_MAPPING_FILE} = "$output_dir/alphabet_mapping.dat";

    # Hash table describing mapping between characters and node names
    $self->{ALPHABET_HASH} = {};
    # The first valid alphabet counter
    $self->{ALPHABET_COUNTER} = 1;

    # Specifies the distance between requests for clustering
    $self->{DISTANCE_MATRIX_FILE} = "$output_dir/distance_matrix.dat";
    
    # Global IDs.  Global IDs are one-indexed!
    $self->{STARTING_GLOBAL_ID} = 1;
    $self->{GLOBAL_ID} = $self->{STARTING_GLOBAL_ID};

    bless ($self, $class);
    return $self;
}
 

##
# Returns 1 if the files this class will create already exist
###
sub do_output_files_exist {
    my $self = shift;

    if( -e($self->{INPUT_VECTOR_FILE}) &&
        -e($self->{ALPHABET_MAPPING_FILE}) &&
        -e($self->{INPUT_VEC_TO_GLOBAL_IDS_FILE})) {
        #&& -e($self->{DISTANCE_MATRIX_FILE})) {
        return 1;
    }
    return 0;
}
           

##
# Takes input graphs and converts them into a format usable
# by MATLAB.  Also computes the distance matrix for each request.
##        
sub create_clustering_input {
    my $self = shift;

    $self->$_remove_existing_files();

    $self->$_handle_requests($self->{SNAPSHOT0_FILE}, 0);
    if(defined $self->{SNAPSHOT1_FILE}) {
        $self->$_handle_requests($self->{SNAPSHOT1_FILE}, 1);
    }

    $self->$_compute_distance_matrix();
    
    # Print out files representing the converted data
    $self->$_print_string_rep_hash();
    $self->$_print_alphabet_mapping();
}		


1;
