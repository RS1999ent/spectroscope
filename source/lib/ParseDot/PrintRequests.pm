#! /usr/bin/perl -w

# $cmuPDL: PrintRequests.pm,v 1.16 2009/08/07 17:51:15 rajas Exp $
##
# This perl modules allows users to quickly extract DOT requests
# and their associated latencies.
##

package PrintRequests;

use strict;
use warnings;
use Test::Harness::Assert;
use diagnostics;
use Data::Dumper;

use ParseDot::DotHelper qw[parse_nodes_from_string parse_nodes_from_file];

#### Global Constants ##########

# Import value of DEBUG if defined
no define DEBUG =>;


#### Private functions #########

##
# Loads: 
#  $self->{SNAPSHOT0_INDEX_HASH} from $self->{SNAPSHOT0_INDEX_FILE}
#    * Maps "snapshot0_filename_index.local_id" -> byte offset of request
#  $self->{SNAPSHOT1_INDEX_HASH} from $self->{SNAPSHOT1_INDEX_FILE}
#    * Maps "snapshot1_filename_index.local_id" -> byte offset of request
#  $self->{GLOBAL_ID_TO_LOCAL_ID_HASH} from $self->{GLOBAL_ID_TO_LOCAL_ID_FILE}
#    * Maps global_id -> "local id, dataset, filename index".
#  
# @param self: The object container
##
my $_load_input_files_into_hashes = sub {
    my $self = shift;

    # Load the snapshot0 index
    open(my $snapshot0_index_fh, "<$self->{SNAPSHOT0_INDEX_FILE}")
        or die("Could not open $self->{SNAPSHOT0_INDEX_FILE}");

    my %snapshot0_index_hash;
    while (<$snapshot0_index_fh>) {
        my @data = split(/ /, $_);
        chomp;
        assert(scalar(@data) == 3);
        $snapshot0_index_hash{"$data[0].$data[1]"} = $data[2];
    }
    close($snapshot0_index_fh);
    $self->{SNAPSHOT0_INDEX_HASH} = \%snapshot0_index_hash;

    # If necessary, load the snapshot1 index
    if (defined $self->{SNAPSHOT1_INDEX_FILE}) {
        assert(defined $self->{SNAPSHOT1_FILES_REF});
    
        open(my $snapshot1_index_fh, "<$self->{SNAPSHOT1_INDEX_FILE}")
            or die("Could not open $self->{SNAPSHOT1_INDEX_FILE}");
    
        my %snapshot1_index_hash;
        while (<$snapshot1_index_fh>) {
            chomp;
            my @data = split(/ /, $_);
            assert(scalar(@data) == 3);
            $snapshot1_index_hash{"$data[0].$data[1]"} = $data[2];
        }
        close ($snapshot1_index_fh);
        $self->{SNAPSHOT1_INDEX_HASH} = \%snapshot1_index_hash;
    }

    # Load the global_id_to_local_id hash
    open(my $global_id_to_local_id_fh, "<$self->{GLOBAL_ID_TO_LOCAL_ID_FILE}")
        or die ("Could not open $self->{GLOBAL_ID_TO_LOCAL_ID_FILE}");
    
    my %global_id_to_local_id_hash;
    while(<$global_id_to_local_id_fh>) {
        chomp;
        my @data = split(/ /, $_);
        my $blah = scalar(@data);
        assert(scalar(@data) == 4);

        $global_id_to_local_id_hash{$data[0]} = join(',', ($data[1], $data[2], $data[3]));
    }
    close($global_id_to_local_id_fh);
    $self->{GLOBAL_ID_TO_LOCAL_ID_HASH} = \%global_id_to_local_id_hash;

    return 0;
};


##
# Returns the request with local id in a string in DOT format
#
# @param self: The object container
# @param local_id: The local id of the request
# @param snapshot: The snapshot to which the req belongs
#
# @return: The request in DOT format in a string.
##
my $_get_local_id_indexed_request = sub {

    assert(scalar(@_) == 4);
    my ($self, $local_id, $snapshot, $filename_idx) = @_;

    assert($snapshot == 0 || $snapshot == 1);

    my $snapshot_fh;
    if($snapshot == 0) {
        my $snapshot_index = $self->{SNAPSHOT0_INDEX_HASH};
        assert($filename_idx < scalar(@{$self->{SNAPSHOT0_FILES_REF}}));
        open($snapshot_fh, "<@{$self->{SNAPSHOT0_FILES_REF}}[$filename_idx]");
        seek($snapshot_fh, $snapshot_index->{"$filename_idx.$local_id"}, 0); # SEEK_SET
    }
    
    if($snapshot == 1) {
        assert(defined $self->{SNAPSHOT1_FILES_REF} &&
               defined $self->{SNAPSHOT1_INDEX_FILE});
        
        my $snapshot_index = $self->{SNAPSHOT1_INDEX_HASH};
        assert($filename_idx < scalar(@{$self->{SNAPSHOT1_FILES_REF}}));        
        open($snapshot_fh, "<@{$self->{SNAPSHOT1_FILES_REF}}[$filename_idx]");
        seek($snapshot_fh, $snapshot_index->{"$filename_idx.$local_id"}, 0); # SEEK_SET
    }

    # Print the request
    my $old_terminator = $/;
    $/ = '}';
    my $request = <$snapshot_fh>;
    $/ = $old_terminator;
    close($snapshot_fh);

    return $request;
};


##
# This function parses the input graph and returns the individual edge
# latencies for each edge in the graph.  The hash looks like: 
# { EDGE_NAME 1 => \@edge_latencies,
#   ..
#   EDGE_NAME K => \@edge_latencies }
#
# @param self: The object container
# @param graph: The graph to parse
# @param node_name_hash: A hash of node names keyed by unique ID
#
# @return a pointer to the hash described above
##
my $_obtain_graph_edge_latencies = sub {
    
    assert(scalar(@_) == 3);

    my $self = shift;
    my $graph = shift;
    my $node_name_hash = shift;
    
    my %graph_edge_latencies_hash;

    while ($graph =~m/(\d+)\.(\d+) \-> (\d+)\.(\d+) \[label=\"R: ([0-9\.]+) us\".*\]/g) {

        my $src_node_id = "$1.$2";
        my $dest_node_id = "$3.$4";

        my $src_node_name = $node_name_hash->{$src_node_id};
        my $dest_node_name = $node_name_hash->{$dest_node_id};

        my $edge_latency = $5;

        my $key = "$src_node_name->$dest_node_name";

        if(!defined $graph_edge_latencies_hash{$key}) {
            my @arr;
            $graph_edge_latencies_hash{$key} = \@arr;
        }

        my $latency_array = $graph_edge_latencies_hash{$key};
        push(@$latency_array, $edge_latency);
    }

    return \%graph_edge_latencies_hash;
};


##
# Overlays information about edges specified by the caller onto
# the input graph
#
# @param $self: The object container
# @param $request: A string representation of the request-flow graph
# @param $edge_info_hash: A pointer to a hash containing information
# about various edges.  The hash is constructed as follows: 
#
# edge_name = { REJECT_NULL => <value>,
#             P_VALUE => <value>,
#             AVG_LATENCIES => \@array,
#             STDDEVS => \@array}
#
# The edge name must be "source_node_name->dest_node_name"
#
# @return: A string representation of the graph w/the appropriate info
# overlayed.
##
my $_overlay_cluster_info = sub {
    assert(scalar(@_) == 3);

    my $self = shift;
    my $request = shift;
    my $cluster_info_hash_ptr = shift;

    my %node_name_hash;
    DotHelper::parse_nodes_from_string($request, 1, \%node_name_hash);

    # Construct a "fake node" w/summary information
    my $summary_node = "1 [fontcolor=\"blue\" shape=\"plaintext\" ";
    $summary_node = $summary_node . 
        sprintf("label=\"Cluster ID: %d\\nAvg. response times: %dus / %dus\\n",
                $cluster_info_hash_ptr->{ID}, 
                int($cluster_info_hash_ptr->{RESPONSE_TIME_STATS}->{AVG_LATENCIES}->[0] + .5),
                int($cluster_info_hash_ptr->{RESPONSE_TIME_STATS}->{AVG_LATENCIES}->[1] + .5));

    $summary_node = $summary_node . sprintf("Stddevs: %dus / %dus\\n",
                                            int($cluster_info_hash_ptr->{RESPONSE_TIME_STATS}->{STDDEVS}->[0] + .5),
                                            int($cluster_info_hash_ptr->{RESPONSE_TIME_STATS}->{STDDEVS}->[1] + .5));

    my $total_reqs = $cluster_info_hash_ptr->{FREQUENCIES}->[0] + $cluster_info_hash_ptr->{FREQUENCIES}->[1];
    my $percent_reqs_s0 = $cluster_info_hash_ptr->{FREQUENCIES}->[0]/$total_reqs*100;
    my $percent_reqs_s1 = $cluster_info_hash_ptr->{FREQUENCIES}->[1]/$total_reqs*100;
    $summary_node = $summary_node . sprintf("Percent makeup: %d / %d\\n",
                                            int($percent_reqs_s0 + .5),
                                            int($percent_reqs_s1 + .5));
    
    $summary_node = $summary_node . sprintf("Total requests: %d\"]",
                                            $total_reqs);
                            
    # Split the graph into lines and insert the summary node after the "Digraph G{"
    my @mod_graph_array = split(/\n/, $request);
    @mod_graph_array = ($mod_graph_array[0], $mod_graph_array[1], $summary_node, @mod_graph_array[2..$#mod_graph_array]);

    # Iterate through edges of graph in the outer loop to implement "location-agnostic"
    # edge comparisons.  Since the edge_info_hash has unique entries for each edge name,
    # the same aggregate info might be overlayed on edges that occur multiple times
    # in the request.
    my $edge_info_hash = $cluster_info_hash_ptr->{EDGE_LATENCY_STATS};

    for (my $i = 0; $i < scalar(@mod_graph_array); $i++) {
        my $line = $mod_graph_array[$i];

        if ($line =~m/(\d+)\.(\d+) \-> (\d+)\.(\d+)/) { #\[label=\"R: ([0-9\.]+) us\"\]/) {
            
            my $src_node_id = "$1.$2";
            my $dest_node_id = "$3.$4";
            
            my $src_node_name = $node_name_hash{$src_node_id};
            my $dest_node_name = $node_name_hash{$dest_node_id};
            
            my $found = 0;
            for my $key (keys %{$edge_info_hash}) {
                my $edge_name = $key;

                if (DEBUG) {
                    print "looking for: $src_node_name->$dest_node_name  $edge_name\n";
                }

                if("$src_node_name->$dest_node_name" eq $edge_name) {
                    
                    my $color;
                    $color = ($edge_info_hash->{$key}->{REJECT_NULL} == 1)?"red":"black";
                    
                    # Print info for this edge; round average and stddev of latency to nearest integer
                    my $edge_info_line = sprintf("[color=\"%s\" label=\"p:%3.2f\\n   a: %dus / %dus\\n   s: %dus / %dus\"\]",
                                                 $color, 
                                                 $edge_info_hash->{$key}->{P_VALUE}, 
                                                 int($edge_info_hash->{$key}->{AVG_LATENCIES}->[0] + .5),
                                                 int($edge_info_hash->{$key}->{AVG_LATENCIES}->[1] + .5),
                                                 int($edge_info_hash->{$key}->{STDDEVS}->[0] + .5),
                                                 int($edge_info_hash->{$key}->{STDDEVS}->[1] + .5));
                    
                    $line =~ s/\[.*\]/$edge_info_line/g;
                    $mod_graph_array[$i] = $line;
                    $found = 1;

                    if (DEBUG) {print "found: $edge_name\n"};
                    last;
                }
            }
            if($found == 0) {
                print "Request edge: $src_node_name->$dest_node_name not found!\n";
                assert(0);
            }
        }
    }    
    
    my $mod_graph = join("\n", @mod_graph_array);

    return $mod_graph;
};


##
# Sorts the children array of each node in the graph_structure
# hash by the name of the node.  
#
# @param self: The object container
# @param graph_structure_hash: A pointer to a hash containing the nodes
# of a request-flow graph.
##
my $_sort_graph_structure_children = sub {
    
    assert(scalar(@_) == 2);

    my $self = shift;
    my $graph_structure_hash = shift;

    foreach my $key (keys %$graph_structure_hash) {
        my $node = $graph_structure_hash->{$key};
        my @children = @{$node->{CHILDREN}};

        my @sorted_children = sort {$children[$a] cmp $children[$b]} @children;
        $node->{CHILDREN} = \@sorted_children;
    }
};
                                 
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
# @param self: The object container
# @param graph: A string representation of the DOT graph
# @param graph_node_hash: Names of each node, indexed by Nodie ID
#
# @return a hash comprised of 
#   { ROOT => Pointer to root node
#     NOE_HASH => Hash of all nodes, indexed by ID}
##
my $_build_graph_structure = sub {
    
    assert(scalar(@_) == 3);

    my $self = shift;
    my $graph = shift;
    my $graph_node_hash = shift;
    
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
            
            my $src_node_name = $graph_node_hash->{$src_node_id};
            my $dest_node_name = $graph_node_hash->{$dest_node_id};
            
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
    $self->$_sort_graph_structure_children(\%graph_structure_hash);
    
    return {ROOT =>$root_ptr, NODE_HASH =>\%graph_structure_hash};
};
    

#### API functions ############################################################

##
# Class constructor.  Obtains locations of files needed
# for this class to work.
##
sub new {

    assert(scalar(@_) == 3 || scalar(@_) == 4);

    my $proto, my $convert_reqs_dir, my $snapshot0_files_ref, my $snapshot0_index;
    my $snapshot1_files_ref, my $snapshot1_index;
    
    if(scalar(@_) == 3) {
        ($proto, $convert_reqs_dir, $snapshot0_files_ref) = @_;
        $snapshot0_index = "$convert_reqs_dir/s0_request_index.dat";        
    } else {
        ($proto, $convert_reqs_dir, $snapshot0_files_ref,
         $snapshot1_files_ref) = @_;
        $snapshot0_index = "$convert_reqs_dir/s0_request_index.dat";        
        $snapshot1_index = "$convert_reqs_dir/s1_request_index.dat";
    }
         
    my $class = ref($proto) || $proto;

    my $self = {};

    $self->{GLOBAL_ID_TO_LOCAL_ID_FILE} = "$convert_reqs_dir/global_ids_to_local_ids.dat";

    $self->{SNAPSHOT0_FILES_REF} = $snapshot0_files_ref;
    $self->{SNAPSHOT0_INDEX_FILE} = $snapshot0_index;

    if (defined $snapshot1_files_ref) {
        $self->{SNAPSHOT1_FILES_REF} = $snapshot1_files_ref;
        assert(defined $snapshot1_index);
        $self->{SNAPSHOT1_INDEX_FILE} = $snapshot1_index;
    } else {
        $self->{SNAPSHOT1_FILES_REF} = undef;
        $self->{SNAPSHOT1_INDEX} = undef;
    }

    $self->{SNAPSHOT0_INDEX_HASH} = undef;
    $self->{SNAPSHOT1_INDEX_HASH} = undef;
    $self->{GLOBAL_ID_TO_LOCAL_ID_HASH} = undef;

    if($self->$_load_input_files_into_hashes() != 0) {
        print "Unable to load input files into hashes\n";
        assert(0);
    }

    bless($self, $class);
    return $self;
}


##
# Prints a request indexed by the global id specified to
# the output filehandle specified
#
# @param self: The object container
# @param global_id: The global id of the request to print
# @param output_fh: The output filehandle
# @param cluster_info: (OPTIONAL)Information to overlay on request,
# keyed by edge name ("src_node_name->$dest_node_name"
##
sub print_global_id_indexed_request {
    
    assert(scalar(@_) == 3 || scalar(@_) == 4);

    my $self, my $global_id, my $output_fh;
    my $cluster_info;
    if (scalar(@_) == 3) {
        ($self, $global_id, $output_fh) = @_;
    } else {
        ($self, $global_id, $output_fh, $cluster_info) = @_;
    }

    my $global_id_to_local_id_hash = $self->{GLOBAL_ID_TO_LOCAL_ID_HASH};
    my ($local_id, $snapshot, $filename_idx) = split(/,/, $global_id_to_local_id_hash->{$global_id});
    my $request = $self->$_get_local_id_indexed_request($local_id, $snapshot, $filename_idx);

    my $modified_req;
    if (defined $cluster_info) {
        $modified_req = $self->$_overlay_cluster_info($request, $cluster_info);
    } else {
        $modified_req = $request;
    }

    print $output_fh "$modified_req\n";
}


##
# Returns a global ID indexed request in string-format
#
# @param self: The object container
# @param global_id: The global_id of the request
# 
# @return a Sring containing the request
##
sub get_global_id_indexed_request { 

    assert(scalar(@_) == 2);
    my ($self, $global_id) = @_;

    my $global_id_to_local_id_hash = $self->{GLOBAL_ID_TO_LOCAL_ID_HASH};
    my ($local_id, $snapshot, $filename_idx) = split(/,/, $global_id_to_local_id_hash->{$global_id});
    my $request = $self->$_get_local_id_indexed_request($local_id, $snapshot, $filename_idx);

    return $request;
}


##
# Prints the local ID indexed request specified
# to the output filehandle specified
#
# @param self: The object container
# @param local_id: The local id of the request to print
# @param snapshot: The snapshot to which the request belongs (0 or 1)
# @param output_fh: The output filehandle
##
sub print_local_id_indexed_request {
    
    assert(scalar(@_) == 4);

    my $self = shift;
    my $local_id = shift;
    my $snapshot = shift;
    my $output_fh = shift;

    assert($snapshot == 0 || $snapshot == 1);

    my $request = $self->$_get_local_id_indexed_request($local_id, $snapshot);

    print $output_fh $request;
}


##
# Returns the snapshots (0 or 1) to which a set of global id
# indexed requests belong
#
# @param self: The object container
# @param global_id_ptr: A pointer to an array of global ids
#
# @return: A pointer to an array.  array[i] indicates
# the dataset to which global_id_ptr->[i] belongs. 
##
sub get_snapshots_given_global_ids {

    assert(scalar(@_) == 2);
    my ($self, $global_ids_ptr) = @_;

    my @snapshots;

    my $global_id_to_local_id_hash = $self->{GLOBAL_ID_TO_LOCAL_ID_HASH};
    foreach (@$global_ids_ptr) {
        
        my ($local_id, $snapshot, $filename_idx) = split(/,/, $global_id_to_local_id_hash->{$_});
        push(@snapshots, $snapshot);
    }
    
    return \@snapshots;
}


##
# Returns the number of requests that belong to snapshot0 vs. snapshot1 in
# an array
#
# @param self: The object container
# @param global_ids_ptr: A pointer to an array of global ids.
#
# @return a pointer to an array; array[0] is the number of requests
# that belong to snapshot0, arrray[1] is the number of requests that
# belong to snapshot1.
##
sub get_snapshot_frequencies_given_global_ids {
    
    # Assert that two arguments are passed in
    assert(scalar(@_) == 2);
    my ($self, $global_ids_ptr) = @_;

    my @frequencies;

    my $global_id_to_local_id_hash = $self->{GLOBAL_ID_TO_LOCAL_ID_HASH};
    my $s1_reqs = 0;
    foreach (@$global_ids_ptr) {
        my ($local_id, $snapshot, $filename_idx) = split(/,/, $global_id_to_local_id_hash->{$_});
        $s1_reqs += $snapshot;
    }


    $frequencies[0] = scalar(@$global_ids_ptr) - $s1_reqs;
    $frequencies[1] = $s1_reqs;

    return \@frequencies;
}

##
# Returns the number of requests in S0 and S1.                                                                   
#
# @return a pointer to an array w/two elements.
#  ret[0] contains the number of requests from S0 and
#  ret[1] contains the number of requests from S1
##
sub get_snapshot_frequencies {

    assert(scalar(@_) == 1);
    my ($self) = @_;

    my @ret;
    $ret[0] = keys %{$self->{SNAPSHOT0_INDEX_HASH}};
    $ret[1] = keys %{$self->{SNAPSHOT1_INDEX_HASH}};

    return \@ret;
}
    
    
##
# Returns the response times seen for the requests passed in.
# The return structure is a hash, which is constructed as follows: 
#
# hash { S0_RESPONSE_TIMES => \@s0_response_times,
#        S1_RESPONSE_TIMES => \@s1_response_times }
#
# @param self: The object container
# @param global_ids_ptr: A pointer to an array of global ids
#
# @bug: This function retrieves the DOT representation of 
# each graph and then does a regexp match for the response
# time.  This could be made much faster if we had a index
# on the response time given a global id (or local id and dataset).
#
# @return: A hash that is constructed as listed above
##         
sub get_response_times_given_global_ids {
    
    # Assert that two arguments are passed in
    assert(scalar(@_) == 2);
    my ($self, $global_ids_ptr) = @_;
    
    my %response_time_hash;
    my @s0_response_times;
    my @s1_response_times;

    my $global_id_to_local_id_hash = $self->{GLOBAL_ID_TO_LOCAL_ID_HASH};

    foreach (@$global_ids_ptr) {
        my ($local_id, $snapshot, $filename_idx) = split(/,/, $global_id_to_local_id_hash->{$_});

        my $graph = $self->$_get_local_id_indexed_request($local_id,
                                                          $snapshot,
                                                          $filename_idx);
        my $graph_local_id;
        my $response_time;
        my @graph_arr = split(/\n/, $graph);

        if ($graph_arr[0] =~ /\# (\d+)  R: ([0-9\.]+)/) {
            $graph_local_id = $1;
            $response_time = $2;
        } else {
            assert(0);
        }

        assert ($local_id == $graph_local_id);
        
        
        if($snapshot == 0) {
            # Request is from snapshot0
            push(@s0_response_times, $response_time);
        } else{ 
            # Request is from snapshot1
            push(@s1_response_times, $response_time);
        }
    }


    $response_time_hash{S0_RESPONSE_TIMES} = \@s0_response_times;
    $response_time_hash{S1_RESPONSE_TIMES} = \@s1_response_times;

    return \%response_time_hash;
}
    

##
# Returns a pointer to a hash that contains information
# about the edges in the graph whose global id is specified
#
# The return hash is structured as follows
# hash->{$EDGE_NAME} = \@latencies.
#
# Where EDGE_NAME is the name of an edge seen in the request
# and @latencies is an array of edge latencies seen for that
# edge in the request.
#
# @param self: The object container
# @param global_id: The global_id of the request to examine
##
sub get_request_edge_latencies_given_global_id {
    
    assert(scalar(@_) == 2);
    my ($self, $global_id) = @_;

    my $global_id_to_local_id_hash = $self->{GLOBAL_ID_TO_LOCAL_ID_HASH};
    my ($local_id, $snapshot, $filename_idx) = split(/,/, $global_id_to_local_id_hash->{$global_id});
    my $graph = $self->$_get_local_id_indexed_request($local_id,
                                                      $snapshot,
                                                      $filename_idx);

    my %node_name_hash;
    DotHelper::parse_nodes_from_string($graph, 1, \%node_name_hash);
    my $edge_latency_hash = $self->$_obtain_graph_edge_latencies($graph, \%node_name_hash);

    return $edge_latency_hash;
}


##
# Returns the name of the root node of a request given its global id
#
# @param self: The object container
# @param global_id: The global ID of the request
##
sub get_root_node_given_global_id {

    assert(scalar(@_) == 2);
    my ($self, $global_id) = @_;

    
    my $req_container = $self->get_req_structure_given_global_id($global_id);
    my $root_node_name = $req_container->{ROOT}->{NAME};
    return $root_node_name;
}


##
# Returns a structured graph representation of a request-flow
# graph given its global ID.
#
# @param self: The object container
# @param global_id: The global ID
#
# @return: A pointer to a hash that contains the root node and a pointer to a hash 
# containing the graph structure.  Specifically,
#    container = { ROOT,
#                  NODE_LIST
#
# Node list contains a pointer to a hash, where each element is a node keyed by its ID.
# Specifically: 
# 
#   node id => {NAME => string,
#               CHILDREN => \@array containing NODE IDs of children,
#               ID => node_id}
##               
sub get_req_structure_given_global_id {

    assert(scalar(@_) == 2);
    my ($self, $global_id) = @_;
    
    my $global_id_to_local_id_hash = $self->{GLOBAL_ID_TO_LOCAL_ID_HASH};
    my ($local_id, $snapshot, $filename_idx) = split(/,/, $global_id_to_local_id_hash->{$global_id});
    my $graph = $self->$_get_local_id_indexed_request($local_id,
                                                      $snapshot,
                                                      $filename_idx);

    my %node_name_hash;
    # @note DO NOT include semantic labels when parsing nodes from the string
    # in this case
    DotHelper::parse_nodes_from_string($graph, 0, \%node_name_hash);
    
    my $graph_container_hash_ptr = $self->$_build_graph_structure($graph,
                                                                  \%node_name_hash);

    #print Dumper %$graph_container_hash_ptr;

    return $graph_container_hash_ptr;
}


1;
