#! /usr/bin/perl -w

##
# This perl modules allows users to quickly extract DOT requests
# and their associated latencies.
##

package PrintRequests;

use strict;
use Test::Harness::Assert;
use diagnostics;


#### Private functions #########

##
# Loads: 
#  $self->{SNAPSHOT0_INDEX_HASH} from $self->{SNAPSHOT0_INDEX_FILE}
#  $self->{SNAPSHOT1_INDEX_HASH} from $self->{SNAPSHOT1_INDEX_FILE}
#  $self->{GLBOAL_ID_TO_LOCAL_ID_HASH} from $self->{GLOBAL_ID_TO_LOCAL_ID_FILE}
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
        $snapshot0_index_hash{$data[0]} = $data[1];
    }
    close($snapshot0_index_fh);
    $self->{SNAPSHOT0_INDEX_HASH} = \%snapshot0_index_hash;


    # If necessary, load the snapshot1 index
    if (defined $self->{SNAPSHOT1_INDEX_FILE}) {
        assert(defined $self->{SNAPSHOT1_FILE});
    
        open(my $snapshot1_index_fh, "<$self->{SNAPSHOT1_INDEX_FILE}")
            or die("Could not open $self->{SNAPSHOT1_INDEX_FILE}");
    
        my %snapshot1_index_hash;
        while (<$snapshot1_index_fh>) {
            chomp;
            my @data = split(/ /, $_);
            $snapshot1_index_hash{$data[0]} = $data[1];
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
        assert($#data == 2);

        $global_id_to_local_id_hash{$data[0]} = join(',', ($data[1], $data[2]));
    }
    close($global_id_to_local_id_fh);
    $self->{GLOBAL_ID_TO_LOCAL_ID_HASH} = \%global_id_to_local_id_hash;

    $self->{HASHES_LOADED} = 1;
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

    assert(scalar(@_) == 3);

    my $self = shift;
    my $local_id = shift;
    my $snapshot = shift;

    assert($snapshot == 0 || $snapshot == 1);

    if($self->{HASHES_LOADED} == 0) {
        $self->$_load_input_files_into_hashes();
    }

    my $snapshot_fh;
    if($snapshot == 0) {
        my $snapshot_index = $self->{SNAPSHOT0_INDEX_HASH};
        open($snapshot_fh, "<$self->{SNAPSHOT0_FILE}");
        seek($snapshot_fh, $snapshot_index->{$local_id}, 0); # SEEK_SET
    }
    
    if($snapshot == 1) {
        assert(defined $self->{SNAPSHOT1_FILE} &&
               defined $self->{SNAPSHOT1_INDEX_FILE});
        
        my $snapshot_index = $self->{SNAPSHOT1_INDEX_HASH};
        open($snapshot_fh, "<$self->{SNAPSHOT1_FILE}");
        seek($snapshot_fh, $snapshot_index->{$local_id}, 0); # SEEK_SET
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
# Creates a hash mapping unique ids of nodes to node names
#
# @param self: The object container
# @param graph: A string containing the DOT representation of a graph
# @param node_name_hash: The hash that will be filled in and which
# will map unique ids to nodes
#
# @return: A string containing a partially consumed DOT graph (all
# the node names will have been consumed)
##
my $_parse_nodes = sub {
    
    assert(scalar(@_) == 3);

    my $self = shift;
    my $graph = shift;
    my $node_name_hash = shift;
    
    while ($graph =~ m/(\d+)\.(\d+) \[label=\"(\w+)\\n(\w*)\"\]/g) {

        my $node_name;
        if (defined $4) {
            $node_name = $3 . "_" . $4;
        } else {
            $node_name = $4;
        }

        my $node_id = $1.$2;
        $node_name_hash->{$node_id} = $node_name;
    }
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

    while ($graph =~m/(\d+)\.(\d+) \-> (\d+)\.(\d+) \[label=\"R: ([0-9\.]+) us\"\]/g) {

        my $src_node_id = $1.$2;
        my $dest_node_id = $3.$4;

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
# edge_num => { REJECT_NULL = <value>,
#             P_VALUE = <value>,
#             AVG_LATENCIES = \@array,
#             STDDEVS = \@array}
#
# @param $edge_num_to_edge_name_hash: maps edge numbers used
# as the key in the edge_info_hash to actual edge names
#
# @return: A string representation of the graph w/the appropriate info
# overlayed.
##
my $_overlay_edge_info = sub {
    assert(scalar(@_) == 4);

    my $self = shift;
    my $request = shift;
    my $edge_info_hash = shift;
    my $edge_num_to_edge_name_hash = shift;

    my %node_name_hash;
    $self->$_parse_nodes($request, \%node_name_hash);

    my @mod_graph_array = split(/\n/, $request);

    for my $key (keys %$edge_info_hash) {

        my $edge_name = $edge_num_to_edge_name_hash->{$key};
        assert(defined $edge_name);

        my $color;
        $color = ($edge_info_hash->{$key}->{REJECT_NULL} == 1)?"red":"black";
        my $edge_info_line = sprintf("[color=\"%s\" label=\"p:%3.2f\\n   a: %3.2f/%3.2f\\n   s: %3.2f/%3.2f\"\]",
                                     $color, 
                                     $edge_info_hash->{$key}->{P_VALUE}, 
                                     $edge_info_hash->{$key}->{AVG_LATENCIES}->[0],
                                     $edge_info_hash->{$key}->{AVG_LATENCIES}->[1],
                                     $edge_info_hash->{$key}->{STDDEVS}->[0],
                                     $edge_info_hash->{$key}->{STDDEVS}->[1]);
        
        # Iterate through graph looking for this edge
        for (my $i = 0; $i < scalar(@mod_graph_array); $i++) {
            my $line = $mod_graph_array[$i];

            if ($line =~m/(\d+)\.(\d+) \-> (\d+)\.(\d+)/) { #\[label=\"R: ([0-9\.]+) us\"\]/) {
                my $src_node_id = $1.$2;
                my $dest_node_id = $3.$4;
                
                my $src_node_name = $node_name_hash{$src_node_id};
                my $dest_node_name = $node_name_hash{$dest_node_id};
                
                if("$src_node_name->$dest_node_name" eq $edge_name) {
                    #$line =~ s/\[label=\"R: [0-9\.]+ us\"\]/$edge_info_line/g;
                    $line =~ s/\[.*\]/$edge_info_line/g;
                    $mod_graph_array[$i] = $line;
                    last;
                }
            }
        }
    }

    my $mod_graph = join("\n", @mod_graph_array);

    return $mod_graph;
};

    
#### API functions #############

##
# Class constructor.  Obtains locations of files needed
# for this class to work.
##
sub new {
    my $proto = shift;

    my $global_id_to_local_id_file = shift;
    my $global_req_edge_latencies_file = shift;
    my $snapshot0_file = shift;
    my $snapshot0_index = shift;

    my $snapshot1_file;
    my $snapshot1_index;
    if ($#_ == 1) {
        $snapshot1_file = shift;
        $snapshot1_index = shift;
    }
     
    # There should be no more input arguments
    assert($#_ == -1);
        
    my $class = ref($proto) || $proto;

    my $self = {};

    $self->{GLOBAL_ID_TO_LOCAL_ID_FILE} = $global_id_to_local_id_file;

    $self->{REQ_EDGE_LATENCIES_FILE} = $global_req_edge_latencies_file;

    $self->{SNAPSHOT0_FILE} = $snapshot0_file;
    $self->{SNAPSHOT0_INDEX_FILE} = $snapshot0_index;

    if (defined $snapshot1_file) {
        $self->{SNAPSHOT1_FILE} = $snapshot1_file;
        assert(defined $snapshot1_index);
        $self->{SNAPSHOT1_INDEX_FILE} = $snapshot1_index;
    }
    
    $self->{SNAPSHOT0_INDEX_HASH} = undef;
    $self->{SNAPSHOT1_INDEX_HASH} = undef;
    $self->{GLOBAL_ID_TO_LOCAL_ID_HASH} = undef;
    $self->{HASHES_LOADED} = 0;

    bless($self, $class);
    return $self;
}


##
# Prints a request indexed by the global id specified to
# the output filehandle specified
#
# @param self: The object container
# @param global_id: The global id of the request to print
# @param edge_info: Information to overlay on request
# @param edge_num_to_name_hash: Maps edge numbers to names
# @param output_fh: The output filehandle
##
sub print_global_id_indexed_request {
    
    assert(scalar(@_) == 5);
    
    my $self = shift;
    my $global_id = shift;
    my $edge_info = shift;
    my $edge_num_to_name_hash = shift;
    my $output_fh = shift;

    my $global_id_to_local_id_hash = $self->{GLOBAL_ID_TO_LOCAL_ID_HASH};
    my @local_info = split(/,/, $global_id_to_local_id_hash->{$global_id});
    my $request = $self->$_get_local_id_indexed_request($local_info[0], $local_info[1]);

    my $modified_req = $self->$_overlay_edge_info($request, $edge_info, $edge_num_to_name_hash);

    print $output_fh "$modified_req\n";
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

    # Assert that two arguments are passed in
    assert(scalar(@_) == 2);

    my $self = shift;
    my $global_ids_ptr = shift;
    my @snapshots;

    # Make sure all input files are loaded into classes
    if($self->{HASHES_LOADED} == 0) {
        $self->$_load_input_files_into_hashes();
        assert($self->{HASHES_LOADED} == 1);
    }

    my $global_id_to_local_id_hash = $self->{GLOBAL_ID_TO_LOCAL_ID_HASH};
    foreach (@$global_ids_ptr) {
        my @local_info = split(/,/, $global_id_to_local_id_hash->{$_});
        push(@snapshots, $local_info[1]);
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
    
    my $self = shift;
    my $global_ids_ptr = shift;
    my @frequencies;

    if ($self->{HASHES_LOADED} == 0) {
        $self->$_load_input_files_into_hashes();
        assert($self->{HASHES_LOADED} == 1);
    }

    my $global_id_to_local_id_hash = $self->{GLOBAL_ID_TO_LOCAL_ID_HASH};
    my $s1_reqs = 0;
    foreach (@$global_ids_ptr) {
        my @local_info = split(/,/, $global_id_to_local_id_hash->{$_});
        $s1_reqs += $local_info[1];
    }


    $frequencies[0] = scalar(@$global_ids_ptr) - $s1_reqs;
    $frequencies[1] = $s1_reqs;

    return \@frequencies;
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
    assert(scalar(@_) == 2 || scalar(@_) == 3);

    my $self = shift;
    my $global_ids_ptr = shift;
    
    my %response_time_hash;
    my @s0_response_times;
    my @s1_response_times;

    my $global_id_to_local_id_hash = $self->{GLOBAL_ID_TO_LOCAL_ID_HASH};

    foreach (@$global_ids_ptr) {
        my @local_info = split(/,/, $global_id_to_local_id_hash->{$_});
        my $graph = $self->$_get_local_id_indexed_request($local_info[0],
                                                          $local_info[1]);

        my $local_id;
        my $response_time;
        my @graph_arr = split(/\n/, $graph);

        if ($graph_arr[0] =~ /\# (\d+)  R: ([0-9\.]+)/) {
            $local_id = $1;
            $response_time = $2;
        } else {
            assert(0);
        }
        assert ($local_id == $local_info[0]);
        
        
        if($local_info[1] == 0) {
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

    my $self = shift;
    my $global_id = shift;

    my $global_id_to_local_id_hash = $self->{GLOBAL_ID_TO_LOCAL_ID_HASH};
    my @local_info = split(/,/, $global_id_to_local_id_hash->{$_});
    my $graph = $self->$_get_local_id_indexed_request($local_info[0],
                                                      $local_info[1]);

    my %node_name_hash;
    $self->$_parse_nodes($graph, \%node_name_hash);
    my $edge_latency_hash = $self->$_obtain_graph_edge_latencies($graph, \%node_name_hash);

    return $edge_latency_hash;
}
    

1;
