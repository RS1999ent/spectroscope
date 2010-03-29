#! /usr/bin/perl -w

# $cmuPDL: PrintRequests.pm,v 1.27 2010/02/05 18:45:44 rajas Exp $
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

use ParseDot::DotHelper qw[parse_nodes_from_string];
use ParseDot::StructuredGraph;


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
# Overlays informaton on top of a request-flow graph
#
# @param $self: The object container
# @param $request: A string representation of the request-flow graph
# @param $overlay_hash_ref: A pointer to a hash containing the overlay info
#  This hash should contain: 
#     { SUMMARY_NODE => string specifying a summary of the graph
#       EDGE_STATS   => A reference to a hash keyed be edge name and containing
#                       the following information: 
#    edge_name = { REJECT_NULL  => <value>,
#                 P_VALUE       => <value>,
#                 AVGS => \@array,
#                 STDDEVS       => \@array}
#
# The edge name must be constructed as"source_node_name->dest_node_name"
#
# @return: A string representation of the graph w/the info overlayed
##
my $_overlay_request_info = sub {
    assert(scalar(@_) == 3);

    my ($self, $request, $overlay_hash_ref) = @_;
    
    my $summary_node = $overlay_hash_ref->{SUMMARY_NODE};
    my $edge_info_hash = $overlay_hash_ref->{EDGE_STATS};

    my %node_name_hash;
    DotHelper::parse_nodes_from_string($request, 1, \%node_name_hash);
                            
    # Split the graph into lines and insert the summary node after the "Digraph G{"
    my @mod_graph_array = split(/\n/, $request);
    @mod_graph_array = ($mod_graph_array[0], $mod_graph_array[1], $summary_node, @mod_graph_array[2..$#mod_graph_array]);

    # Iterate through edges of graph in the outer loop to implement "location-agnostic"
    # edge comparisons.  Since the edge_info_hash has unique entries for each edge name,
    # the same aggregate info might be overlayed on edges that occur multiple times
    # in the request.
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
                                                 int($edge_info_hash->{$key}->{AVGS}->[0] + .5),
                                                 int($edge_info_hash->{$key}->{AVGS}->[1] + .5),
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

                                
#### Static functions ########################################################

##
# Given key information about a cluster, this function returns a
# "summary node" in DOT format that contains this information
#
# @param cluster_id: The id of the cluster for which to print information
# @param response_time_stats: Statistics about the response-time
#    the hash that this reference points should be: 
#    { REJECT_NULL => <0 or 1>
#      P_VALUE => <integer>
#      AVGS => ref to an array denoting avg. latencies from s0, s1
#      STDDEVS => ref to an array denoting std. devs from s0, s1
#    }
# @param cluster_likelihood_array_ref: Information about the likelihood of this
#  cluster in S0 and S1
# @param frequencies: Information about the frequencies of this this cluster
#  in s0 and s1
# @param specific_mutation_type: Information about the specific mutation for which
#  information is being printed
# @param mutation_type: Overall mutation types of this cluster
# @param ranked_originators: A string containing originating clusters
#
# @return: A string containing the summary node in DOT format
##
sub create_summary_node {
    
    assert( scalar(@_) == 8);
    
    my ($cluster_id, $response_time_stats,
        $cluster_likelihood_array_ref, $frequencies_array_ref,
        $specific_mutation_type, $mutation_type, $cost, $ranked_originators) = @_;

    my $summary_node = "1 [fontcolor=\"blue\" shape=\"plaintext\" ";
    
    print "$cost\n";
    # Add cluster ID and mutation type info
    $summary_node = $summary_node . 
        sprintf("label=\"Cluster ID: %s\\nSpecific Mutation Type: %s\\n" .
                "Cost: %d\\n" .
                "Overall Mutation Type: %s\\n",
                $cluster_id, $specific_mutation_type, $cost, $mutation_type);
    
    # Add originating cluster information
    $summary_node = $summary_node . "Candidate originating clusters: $ranked_originators\\n";
    
    $summary_node = $summary_node . "\\n";

    # Add Response-time information
    $summary_node = $summary_node . 
        sprintf("Avg. response times: %d us ; %d us\\n",
                int($response_time_stats->{AVGS}->[0] + .5),
                int($response_time_stats->{AVGS}->[1] + .5));

    # Add Standard-deviation information
    $summary_node = $summary_node .
        sprintf("Standard Deviations: %d us ; %d us\\n",
                int($response_time_stats->{STDDEVS}->[0] + .5),
                int($response_time_stats->{STDDEVS}->[1] + .5));
    $summary_node = $summary_node . 
        sprintf("KS-Test2 P-value: %3.3f\\n",
                $response_time_stats->{P_VALUE});

    # Add probability information
    $summary_node = $summary_node . 
        sprintf("Cluster likelihood: %3.4f ; %3.4f\\n",
                $cluster_likelihood_array_ref->[0], $cluster_likelihood_array_ref->[1]);

    # Add frequency information
    my $total_reqs = $frequencies_array_ref->[0] + $frequencies_array_ref->[1];
    my $percent_reqs_s0 = $frequencies_array_ref->[0]/$total_reqs*100;
    my $percent_reqs_s1 = $frequencies_array_ref->[1]/$total_reqs*100;
    $summary_node = $summary_node . sprintf("Percent makeup: %d / %d\\n",
                                            int($percent_reqs_s0 + .5),
                                            int($percent_reqs_s1 + .5));

    # Add total number of requests in the clsuter
    $summary_node = $summary_node . sprintf("requests: %d ; %d\"]",
                                            $frequencies_array_ref->[0],
                                            $frequencies_array_ref->[1]);

    return $summary_node;
}
    

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
# @param overlay_hash_ref: (OPTIONAL) If desired, the caller can overlay 
#  information on top of the printed request.  A summary node can
#  be printed containing information about this request, and information
#  about edge latencies can be overlayed on top of the edges.  If specifed,
#  this parameter should point to a hash that contains: 
#    { SUMMARY_NODE => string containing a node in DOT format
#      EDGE_STATS   => reference to a hash containing information about edges
##
sub print_global_id_indexed_request {
    
    assert(scalar(@_) == 3 || scalar(@_) == 4);

    my ($self, $global_id, $output_fh, $overlay_hash_ref);
    if (scalar(@_) == 3) {
        ($self, $global_id, $output_fh) = @_;
    } else {
        ($self, $global_id, $output_fh, $overlay_hash_ref) = @_;
    }

    my $global_id_to_local_id_hash = $self->{GLOBAL_ID_TO_LOCAL_ID_HASH};
    my ($local_id, $snapshot, $filename_idx) = split(/,/, $global_id_to_local_id_hash->{$global_id});
    my $request = $self->$_get_local_id_indexed_request($local_id, $snapshot, $filename_idx);

    my $modified_req;
    if (defined $overlay_hash_ref) {
        $modified_req = $self->$_overlay_request_info($request, $overlay_hash_ref);
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
	    print "$graph_arr[0]\n";
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

    my $request_string  = $self->get_global_id_indexed_request($global_id);
    my $structured_graph = StructuredGraph::build_graph_structure($request_string);

    my $root_node_name = $structured_graph->{ROOT}->{NAME};
    return $root_node_name;
}


1;
