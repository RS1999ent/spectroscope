#! /usr/bin/perl -w

# $cmuPDL: ParseClusteringResults.pm,v 1.6 2009/04/27 20:14:44 source Exp $
##
# This Perl module implements routines for parsing the results
# of a clustering operation.  It takes in as input the 
# clustering results and a ranking scheme.  It then prints out
# two files
#  File 1: Ranked cluster info, which contains: 
#   <cluster num>, <num requests in s0>, <num requests in s1>, <avg. latency s0>
#   <avg. latency s1>.
#  File 2: Dot graphs of the cluster representatives, ranked according
#  to the scheme specified.
##

package ParseClusteringResults;

use strict;
use Cwd;
use Test::Harness::Assert;
use GD::Graph::boxplot;
use Statistics::Descriptive;
use diagnostics;


#### Private functions ############


## 
# Prints two boxplots within one graph.  Boxplots
# are placed in $self->{BOXPLOT_OUTPUT_DIR} and are named
# cluster_($cluter_id)_boxplot.png
#
# @param self: The object container
# @param cluster_id: The ID of the cluster for which this graph is being printed
# @parma s0_values: An array specifying the response-times for requests that
# belong to snapshot0 within this cluster
# @param s1_values: An array specifying the response-times for requests that
# belong to snapshot1 within this cluster.
##
my $_print_boxplots = sub {
    assert(scalar(@_) == 4);

    my $self = shift;
    my $cluster_id = shift;
    my $s0_values = shift;
    my $s1_values = shift;

    # Create a new boxplot object
    my $boxplot = new GD::Graph::boxplot( );

    my $output_dir = $self->{BOXPLOT_OUTPUT_DIR};

    # Make sure the output directory exists
    system("mkdir -p $output_dir");

    # Set options for the boxplot
    $boxplot->set(
                  x_label => 'Snapshot ID',
                  y_label => 'Response time in us',
                  title => "Boxplots for Cluster $cluster_id",
                  upper_percent => 70, # Default
                  lower_percent => 35, # Default
                  step_const => 1.8,   # Default
                  );
    
    # Create the boxplot dataset and plot it
    my @labels;
    my @values;

    if(scalar(@$s0_values < 4) && scalar(@$s1_values < 4)) {
        # Need to have at least four values to compute a boxplot
        return;
    }

    if (scalar(@$s0_values) > 4) {
        push(@labels, "s0");
        push(@values, $s0_values);
    }
    if (scalar(@$s1_values) > 4) {
        push(@labels, "s1");
        push(@values, $s1_values);
    }
    my @boxplot_data = (\@labels,
                        \@values);


    my $gd = $boxplot->plot(\@boxplot_data);

    # Print the boxplot to the appropriate output directory
    my $output_filename = "$output_dir/cluster_$cluster_id" . "_boxplot.png";
    open(IMG, ">$output_filename") or die $!;
    binmode IMG;
    print IMG $gd->png;
    close(IMG);
};


##
# Finds the mean and standard deviation of the data passed in
#
# @param self: The object container
# @param data_ptr: A pointer to an array of data
# 
# @return: A pointer to an array, where the first element is
# the mean and the second element is the standard deviation
##
my $_find_mean_and_stddev = sub {
    my $self = shift;
    my $data_ptr = shift;
    my @mean_and_stddev;

    if(scalar(@$data_ptr) < 4) {
        # Not enough data to compute mean/stddev
        $mean_and_stddev[0] = -1;
        $mean_and_stddev[1] = -1;
        return \@mean_and_stddev;
    }

    my $stat = Statistics::Descriptive::Full->new();
    $stat->add_data($data_ptr);

    $mean_and_stddev[0] = $stat->mean();
    $mean_and_stddev[1] = $stat->standard_deviation();

    return \@mean_and_stddev
};


## 
# Returns the row number to use when writing a sparse matrix
# of individual edge latencies.
#
# @note: Row counter is one indexed.
#
# @param self: The object containe
# @param edge_name: The name of the edge
#
# @return: The row number to use for this edge
##
my $_get_edge_row_num = sub {
    assert(scalar(@_) == 2);

    my $self = shift;
    my $edge_name = shift;
    
    my $edge_row_num_hash = $self->{EDGE_ROW_NUM_HASH};
    my $reverse_edge_row_num_hash = $self->{REVERSE_EDGE_ROW_NUM_HASH};

    if(!defined $edge_row_num_hash->{$edge_name}) {
        $edge_row_num_hash->{$edge_name} = $self->{EDGE_ROW_COUNTER};
        $reverse_edge_row_num_hash->{$self->{EDGE_ROW_COUNTER}} = $edge_name;
        $self->{EDGE_ROW_COUNTER}++;
    }

    return $edge_row_num_hash->{$edge_name};
};


##
# Returns the column number to use when writing a sparse matrix
# of individual edge latencies.
#
# @note: Column counter is one indexed.
#
# @param self: The object container
# @param edge_name: The name of the edge
# @param edge_col_num_hash: The hash-table listing the next
# column number to use for each edge
#
# @return: The column number to use for this edge
##
my $_get_edge_col_num = sub {
    assert(scalar(@_) == 3);

    my $self = shift;
    my $edge_name = shift;
    my $edge_col_num_hash = shift;

    if(!defined $edge_col_num_hash->{$edge_name}) {
        $edge_col_num_hash->{$edge_name} = 1;
    }
   
    my $col_num = $edge_col_num_hash->{$edge_name};
    $edge_col_num_hash->{$edge_name}++;

    return $col_num;
};
    

##
# Creates edge comparison files
##
my $_create_edge_comparison_files = sub {
    assert(scalar(@_) == 4);

    my $self = shift;
    my $global_ids_ptr = shift;
    my $s0_edge_file = shift;
    my $s1_edge_file = shift;

    my $print_graphs = $self->{PRINT_GRAPHS_CLASS};

    my %col_num_hash;    

    open(my $s0_edge_fh, ">$s0_edge_file") or die $!;
    open(my $s1_edge_fh, ">$s1_edge_file") or die $!;
    my @fhs = ($s0_edge_fh, $s1_edge_fh);

    foreach (@$global_ids_ptr) {
        my @global_id = ($_);

        my $snapshot_ptr = $print_graphs->get_snapshots_given_global_ids(\@global_id);
        my $edge_info = $print_graphs->get_request_edge_latencies_given_global_id($global_id[0]);
        
        foreach my $key (keys %$edge_info) {
            my $row_num = $self->$_get_edge_row_num($key);
            my $edge_latencies = $edge_info->{$key};

            foreach(@$edge_latencies) {
                my $col_num = $self->$_get_edge_col_num($key,\%col_num_hash);
                my $filehandle = $fhs[$snapshot_ptr->[0]];
                printf $filehandle "%d %d %f\n", $row_num, $col_num, $_;
            }
        }
    }

    close($fhs[0]);
    close($fhs[1]);
};


##
# Compares CDFs of edge latencies by calling Matlab.  Writes an output
# file while is formatted as follows: 
#  <edge number>: <changed> <p-value>> <avg. latency s0> <stddev s0> <avg. latency s1> <stddev s1>
#
# Where "changed" is 1 if the edge latencies are statistically different between
# s0 and 1, as determined by the Kologmov - Smirginoff test.
#
# @param self: The object container
# @param s0_edges_file: Path to the sparse matrix of edge
# latencies in s0.  Each row is an edge and each column a latency
# @param s1_edges_file; Path to the sparse matrix of edge
# latencies in s1.  Each row is an edge and each column a latency
# @param output_file: The path to the file where edge comparison
# information will be written
#
##
my $_compare_edges = sub {
    assert(scalar(@_) == 4);

    my $self = shift;
    my $s0_edges_file = shift;
    my $s1_edges_file = shift;
    my $output_file = shift;
    
    my $curr_dir = getcwd();
    chdir '../lib/ParseClusteringResults';

    system("matlab -nojvm -nosplash -nodisplay -r \"compare_edges(\'$s0_edges_file\', \'$s1_edges_file\', \'$output_file\'); quit\"".
           "|| matlab -nodisplay -r \"compare_edges(\'$s0_edges_file\', \'$s1_edges_file\', \'$output_file\'); quit\"") == 0
           or die ("Could not run Matlab compare_edges script\n");

    chdir $curr_dir;
};


##
# Reads in a file of edge comparisons of the form: 
# <edge row number> <changed> <p-value> <avg. latency s0> stddev s0> <avg. latency s1> <stddev s1>
# and inserts this info into an edge_info_hash, which is of the form
# edge_info_hash{edge_row_num} -> { CHANGED,
#                                   AVG_LATENCIES,
#                                   STDDEVS };
#
# @param self: The object container
# @param edge_comparisons_file: The file containing edge comparisons
#
# @return: The edge_info_hash.
##                             
my $_load_edge_info_hash = sub {
    assert(scalar(@_) == 2);
    
    my $self = shift;
    my $edge_comparisons_file = shift;

    my %edge_info_hash;
    my $reverse_edge_row_num_hash = $self->{REVERSE_EDGE_ROW_NUM_HASH};
    
    open(my $edge_comparisons_fh, "<$edge_comparisons_file")
        or die ("Could not open $edge_comparisons_file: $!\n");
    
    while (<$edge_comparisons_fh>) {
        # This regexp must match the output specified by compare edges
        if(/(\d+) (\d+) ([\-0-9\.]+) ([0-9\.]+) ([0-9\.]+) ([0-9\.]+) ([0-9\.]+)/) {
            my $edge_row_num = $1;
            my $reject_null = $2;
            my $p_value = $3;
            my @avg_latencies = ($4, $6);
            my @stddevs = ($5, $7);
            
            assert(defined $reverse_edge_row_num_hash->{$edge_row_num});
            
            $edge_info_hash{$edge_row_num} = { REJECT_NULL => $reject_null,
                                               P_VALUE => $p_value,
                                               AVG_LATENCIES => \@avg_latencies,
                                               STDDEVS => \@stddevs };
        } else {
            print $_;
            assert(0);
        }
    }
    
    close($edge_comparisons_fh);
    
    return \%edge_info_hash;
};


##
# Computes information about edges seen for a set of global IDs
##
my $_compute_edge_info = sub {
    assert(scalar(@_) == 3);

    my $self = shift;
    my $global_ids_ptr = shift;
    my $cluster_id = shift;

    my $print_graphs = $self->{PRINT_GRAPHS_CLASS};


    my $output_dir = $self->{INTERIM_OUTPUT_DIR};

    # Make sure the output directory exists
    system("mkdir -p $output_dir");

    my $s0_edge_file = "$output_dir/s0_cluster_$cluster_id" . 
                       "_edge_latencies.dat";
    my $s1_edge_file = "$output_dir/s1_cluster_$cluster_id" .
                       "_edge_latencies.dat";
    my $comparison_results_file = "$output_dir/$cluster_id" .
                                   "_comparisons.dat";
    
    $self->$_create_edge_comparison_files($global_ids_ptr, $s0_edge_file, $s1_edge_file);
    $self->$_compare_edges($s0_edge_file, $s1_edge_file, 
                           $comparison_results_file);
    my $edge_info = $self->$_load_edge_info_hash($comparison_results_file);

    return $edge_info;
};


##
# Given an input vector id, this function returns the global ids that map to it
#
# @param self: The object identifier
# @param input_vector_id: The input vector id
#
# @return a pointer to an array of global ids that map to the input
# vector id passed in
##
my $_get_global_ids = sub {
    
    assert(scalar(@_) == 2);

    my $self = shift;
    my $input_vector_id = shift;

    my $input_vec_to_global_ids_hash = $self->{INPUT_VEC_TO_GLOBAL_IDS_HASH};
    my $global_ids_string = $input_vec_to_global_ids_hash->{$input_vector_id};
    my @global_ids = split(/,/, $global_ids_string);
    
    assert(scalar(@global_ids) > 0);

    return \@global_ids;
};


##
# Computes statistics on each cluster and stores them in 
# $self->{CLUSTER_INFO_HASH}.  Specifically, 
# $self->{CLUSTER_INFO_HASH} stores a hash for each cluster
# that is keyed by cluster_id and which contains the following 
# information: 
#
#    \@frequencies: Distribution of requests from s0 and s1 in this cluster.
#    \@avg_latency: The average latency of requests from s0 and s1
#    \@edges: A index showing the edges in this cluster, their average
#             latency in each snaphot, and the result of a statistical test
#             that indicates whether the edge latencies for the edge are
#             statistically different
#
# In addition to computer the cluster_info_hash, this function computes
# two boxplots for each cluster.  The first boxplot shows response times
# for requests from s0 and the second from s1.
#
# @param self: The object-container
##
my $_compute_cluster_info = sub {

    assert(scalar(@_) == 1);

    my $self = shift;    
    my $cluster_assignment_hash = $self->{CLUSTER_HASH};
    my $graph_info = $self->{PRINT_GRAPHS_CLASS};
    my %cluster_info_hash;

    foreach my $key (sort {$a <=> $b} keys %$cluster_assignment_hash) {
        print "Processing statistics for Cluster $key...\n";

        my @input_vec_ids = split(/,/, $cluster_assignment_hash->{$key});

        my %this_cluster_info;
        my @global_ids;

        # Iterate through the input vectors that are assigned to each cluster
        # and build a list of matching global IDs.
        foreach(@input_vec_ids) {

            my $input_vector_id = $_;
            # Get the global IDs that map to this input_vec_id
            my $input_vec_global_ids = $self->$_get_global_ids($input_vector_id);
            # Add global ids to the list of global IDs for this cluster
            @global_ids = (@global_ids, @$input_vec_global_ids);
        }

        # Compute statistics for this cluster
        my $snapshot_frequencies = $graph_info->get_snapshot_frequencies_given_global_ids(\@global_ids);
        
        my $response_times = $graph_info->get_response_times_given_global_ids(\@global_ids);


        my $s0_mean_and_stddev = $self->$_find_mean_and_stddev($response_times->{S0_RESPONSE_TIMES});

        my $s1_mean_and_stddev = $self->$_find_mean_and_stddev($response_times->{S1_RESPONSE_TIMES});

        $self->$_print_boxplots($key, 
                                $response_times->{S0_RESPONSE_TIMES}, 
                                $response_times->{S1_RESPONSE_TIMES});
        undef $response_times;

        my $edge_info = $self->$_compute_edge_info(\@global_ids, $key);
        
        # Fill in the %this_cluster_info_hash and add it to the the %cluster_info_hash
        $this_cluster_info{FREQUENCIES} = $snapshot_frequencies;
        $this_cluster_info{AVG_RESPONSE_TIMES} = [$s0_mean_and_stddev->[0],
                                                    $s1_mean_and_stddev->[0]];
        $this_cluster_info{STDDEVS} = [$s0_mean_and_stddev->[1],
                                             $s1_mean_and_stddev->[1]];
        $this_cluster_info{EDGE_INFO} = $edge_info;
        
        $cluster_info_hash{$key} = \%this_cluster_info;
    }
     
    $self->{CLUSTER_INFO_HASH} = \%cluster_info_hash;
};


##
# Loads the following input files into hashes for use by
# the other functions in this class: 
#    $self->{CLUSTERS_FILE} is loaded into $self->{CLUSTER_HASH}
#    $self->{INPUT_VEC_TO_GLOBAL_IDS_FILE} is loaded into 
#    $self->{INPUT_VEC_TO_GLOBAL_IDS_HASH}
#
# $self->{CLUSTERS_FILE} contains information about each cluster.  Each
# row represents a cluster and contains INPUT_VECTOR_IDs of the requests
# assigned to that cluster.
#
# Each line of $self->{INPUT_VEC_TO_GLOBAL_IDS_FILE} reprresents a 
# INPUT_VECTOR_ID and the numbers on each line represent the GLOBAL_IDs
# that map to the INPUT_VECTOR_IDs
#
# It is assumed that cluster ids and input vector ids are 1-indexed
#
# @param self: The object-container
##
my $_load_files_into_hashes = sub {
    assert(scalar(@_) == 1);

    my $self = shift;
    
    # Open input file
    open (my $clusters_fh, "<$self->{CLUSTERS_FILE}") 
        or die("Could not open $self->{CLUSTERS_FILE}\n");
    open (my $input_vec_to_global_ids_fh, "<$self->{INPUT_VEC_TO_GLOBAL_IDS_FILE}")
        or die("Could not open $self->{INPUT_VEC_TO_GLOBAL_IDS_FILE}");
    
    # load $self->{CLUSTERS_FILE};
    my %cluster_hash;
    my $cluster_num = 1;
    while(<$clusters_fh>) {
        chomp;
        my @cluster_items = split(' ', $_);
        my $hash_item = join(',', @cluster_items);
        
        $cluster_hash{$cluster_num} = $hash_item;
        $cluster_num++;
    }
    close($clusters_fh);
    $self->{CLUSTER_HASH} = \%cluster_hash;
    
    # load $self->{INPUT_VEC_TO_GLOBAL_IDS_HASH}
    my %input_vec_to_global_ids_hash;
    my $input_vec_num = 1;
    while (<$input_vec_to_global_ids_fh>) {
        chomp;
        my @hash_item = split(/ /, $_);

        $input_vec_to_global_ids_hash{$input_vec_num} = join(',', @hash_item);
        $input_vec_num++;
    }
    close($input_vec_to_global_ids_fh);
    $self->{INPUT_VEC_TO_GLOBAL_IDS_HASH} = \%input_vec_to_global_ids_hash;
    
    
    $self->{INPUT_HASHES_LOADED} = 1;
};


##
# Prints the cluster representative of the cluster specified
#
# @param self: The object-container
# @param cluster_id: The cluster to print
# @param edge_info: The information about edges that should be
#  super-imposed on top of the request
# @param out_fh: The filehandle to which the graph should be printed
##

my $_print_graph = sub {
    assert(scalar(@_) == 4);

    my $self = shift;
    my $cluster_id = shift;
    my $edge_info = shift;
    my $out_fh = shift;

    my $print_graphs_class = $self->{PRINT_GRAPHS_CLASS};

    # Get the graph representation of the cluster.  This is the request
    # that corresponds to the first input vector id specified in the
    # cluster hash.
    my $cluster_hash = $self->{CLUSTER_HASH};
    my $input_vec_to_global_ids_hash = $self->{INPUT_VEC_TO_GLOBAL_IDS_HASH};
    my @input_vecs = split(/,/, $cluster_hash->{$cluster_id});
    my @global_ids = split(/,/, $input_vec_to_global_ids_hash->{$input_vecs[0]});

    # Print the graph
    $print_graphs_class->print_global_id_indexed_request($global_ids[0], 
                                                         $out_fh,
                                                         $edge_info, 
                                                         $self->{REVERSE_EDGE_ROW_NUM_HASH});
                                                         
};


#### Private sort routines #######

##
# For each cluster, this function creates a metric:
#   (num_reqs_from_s1 - num_requests_in_s0)/total_requests_in_cluster
# and then ranks clusters in descending order.
#
# @param $self: The object container
# @param $a: The first key
# @param $b: THe second key
##
my $_sort_clusters_by_frequency_difference = sub {
    assert(scalar(@_) == 3);

    my $self = shift;
    my $a = shift;
    my $b = shift;

    my $cluster_info_hash = $self->{CLUSTER_INFO_HASH};
    
    my $a_frequencies = $cluster_info_hash->{$a}->{FREQUENCIES};
    my $b_frequencies = $cluster_info_hash->{$b}->{FREQUENCIES};
    
    my $a_s0_reqs = $a_frequencies->[0];
    my $a_s1_reqs = $a_frequencies->[1];
    my $a_rank = ($a_s1_reqs - $a_s0_reqs)/($a_s0_reqs + $a_s1_reqs);
    
    my $b_s0_reqs = $b_frequencies->[0];
    my $b_s1_reqs = $b_frequencies->[1];
    my $b_rank = ($b_s1_reqs - $b_s0_reqs)/($b_s0_reqs + $b_s1_reqs);
    
    if($b_rank > $a_rank) {
        return 1;
    }
    if($b_rank < $a_rank) {
        return -1;
    }
    if($b_s1_reqs > $a_s1_reqs) {
        return 1;
    }
    
    return 0;
};


## 
# Wrapper function for choosing how clusters
# will be ranked.  
#
# @param self: The object container
##
my $_sort_clusters_wrapper = sub { 
    assert(scalar(@_) == 1);

    my $self = shift;

    if ($self->{RANK_FORMAT} =~ /req_difference/) {
        $self->$_sort_clusters_by_frequency_difference($a, $b);
    } else {
        # Nothing else supported now :(
        assert (0);
    }
};


#### API functions ################

##
# Constructor for the ParseClusteringResults class
#
# @param proto: The class identifier
#
# @param clusters_file: File containing cluster assignments
# 
# @param input_vector_file: File containing MATLAB compatible
# representations of requests and how many requests from
# each snapshot map to each representation.  Each row
# of this file looks like:
#  <# of s0 reqs> <# of s1 reqs> <MATLAB compatible rep>
#
# @param input_vec_to_global_ids_file: File mapping MATLAB
# compatible representations of requests to the Global IDs
# of those requests
# 
# @param rank_format: One of "req_difference,"
# "avg_latency_difference," or "total_latency_difference"
#
# @param print_graphs_class: The class used to print and
# obtain information about the input request-flow gaphs

# @param output_dir: The directory in which the output files 
# should be placed
##
sub new {
    my $proto = shift;

    my $clusters_file = shift;
    my $input_vector_file = shift;
    my $input_vec_to_global_ids_file = shift;

    my $rank_format = shift;
    my $print_graphs_class = shift;
    my $output_dir = shift;

    assert ($rank_format =~ m/req_difference/);
    # Will add in the following later.
    #        $rank_format eq "avg_latency_difference" ||
    #        $rank_foramt eq "total_latency_difference");

    my $class = ref($proto) || $proto;
    my $self = {};

    $self->{CLUSTERS_FILE} = $clusters_file;
    $self->{INPUT_VECTOR_FILE} = $input_vector_file;
    $self->{INPUT_VEC_TO_GLOBAL_IDS_FILE} = $input_vec_to_global_ids_file;
    $self->{RANK_FORMAT} = $rank_format;
    $self->{OUTPUT_DIR} = $output_dir;
    $self->{PRINT_GRAPHS_CLASS} = $print_graphs_class;
    
    # Hashes that will be maintained.  These hashes
    # are loaded from text files.
    $self->{CLUSTER_HASH} = undef;
    $self->{INPUT_VEC_TO_GLOBAL_IDS_HASH} = undef;
    $self->{INPUT_HASHES_LOADED} = 0;

    # These hashes are computed by the cluster
    $self->{EDGE_ROW_NUM_HASH} = { };
    $self->{REVERSE_EDGE_ROW_NUM_HASH} = { };
    $self->{CLUSTER_INFO_HASH} = undef;

    # Counter maintained by this cluster
    $self->{EDGE_ROW_COUNTER} = 1;

    # Some derived outputs
    $self->{BOXPLOT_OUTPUT_DIR} = "$output_dir/boxplots";
    $self->{INTERIM_OUTPUT_DIR} = "$output_dir/interm_cluster_data";
    
    
    bless($self, $class);
    
    return $self;
}


##
# Clears this object of any data it has computed
# 
# @param self: The object container
##
sub clear {
    assert(scalar(@_) == 1);

    my $self = shift;

    # Undef hashes of input files
    undef $self->{CLUSTER_HASH};
    undef $self->{INPUT_VEC_TO_GLOBAL_IDS_HASH};
    undef $self->{INPUT_HASHES_LOADED} = 0;

    # undef hashes computed by this cluster
    $self->{EDGE_ROW_NUM_HASH} = {};
    $self->{REVERSE_EDGE_ROW_NUM_HASH} = {};
    undef $self->{CLUSTER_INFO_HASH};

    $self->{EDGE_ROW_COUNTER} = 1;
}


##
# Prints ranked cluster information.
#
# @param self: The object-container
##
sub print_clusters {
    assert(scalar(@_) == 1);
    
    my $self = shift;
    
    if($self->{INPUT_HASHES_LOADED} == 0) {
        $self->$_load_files_into_hashes();
    }
    
    if(!defined $self->{CLUSTER_INFO_HASH}) {
        $self->$_compute_cluster_info();
    }
    
    my $cluster_info_hash = $self->{CLUSTER_INFO_HASH};
    
    # First print the text file
    open(my $ranked_clusters_fh, 
         ">$self->{OUTPUT_DIR}/ranked_clusters_by_$self->{RANK_FORMAT}.dat")
        or die ("Could not open ranked clusters file: $!\n");
    
    # Print header to ranked_cluster_fh
    printf $ranked_clusters_fh "%-15s %-15s %-15s %-15s %-15s %-15s %-15s %-15s\n",
    "rank", "cluster_id", "s0_freq", "s1_freq", "s0_avg_lat", "s0_stddev", "s1_avg_lat", "s1_stddev";
    
    # Print information about each cluster ranked appropriately
    my $rank = 1;
    for my $key (sort {$self->$_sort_clusters_wrapper()} keys %$cluster_info_hash) {
        
        my $this_cluster_info_hash = $cluster_info_hash->{$key};
        
        my $freqs = $this_cluster_info_hash->{FREQUENCIES};
        my $avg_response_times = $this_cluster_info_hash->{AVG_RESPONSE_TIMES};
        my $stddevs = $this_cluster_info_hash->{STDDEVS};
        
        # Write rank cluster_id s0_frequency s1_frequency s0_avg_lat s0_stddev s1_avg_lat s1_stddev
        printf $ranked_clusters_fh "%-15d %-15d %-15d %-15d %-12.3f %-12.3f %-12.3f %-12.3f\n",
        $rank, $key, $freqs->[0], $freqs->[1], $avg_response_times->[0], $stddevs->[0],
        $avg_response_times->[1], $stddevs->[1];

        $rank++;
    }
    close ($ranked_clusters_fh);

    
    # Now print the graph representation in ascending Cluster ID order
    open(my $ranked_clusters_graph_fh,
         ">$self->{OUTPUT_DIR}/ranked_graphs_by_$self->{RANK_FORMAT}.dot")
        or die("Could not open ranked clusters file\n");
        
    for my $key (sort {$a <=> $b} keys %$cluster_info_hash) {
        my $this_cluster_info_hash = $cluster_info_hash->{$key};
        
        my $edge_info = $this_cluster_info_hash->{EDGE_INFO};
        $self->$_print_graph($key, $edge_info, $ranked_clusters_graph_fh);
    }
    close($ranked_clusters_graph_fh);
    
}


##
# Returns the cluster representative of a cluster, given its ID
#
# @param cluster_id: [1...N]
#
# @return the global ID of the cluster representative
#
# @note: This function is pretty hacked up; should make it more formal
# $self->{CLUSTER_HASH} should contain the global_id of the cluster rep,
# or if the cluster representative is not a traditional request-flow graph,
# a pointer to a string representative of it.  This functio should return
# a string containing the representative
##
sub get_global_id_of_cluster_rep {

    assert(scalar(@_) == 2);
    
    my $self = shift;
    my $cluster_id = shift;

    if($self->{INPUT_HASHES_LOADED} == 0) {
        $self->$_load_files_into_hashes();
    }

    my $cluster_hash = $self->{CLUSTER_HASH};
    my $input_vec_to_global_ids_hash = $self->{INPUT_VEC_TO_GLOBAL_IDS_HASH};
    my @input_vecs = split(/,/, $cluster_hash->{$cluster_id});
    my @global_ids = split(/,/, $input_vec_to_global_ids_hash->{$input_vecs[0]});

    return $global_ids[0];

}


##
# Returns the global ID of a cluster
#
# @param self: The object container
# @param cluster_id: The cluster ID
# @param cookie_ptr: A pointer to an opaque cookie that
# allows the user to call this function iteratively in order
# to get all the global IDs of requests that belong to this cluster.
# Initially, the caller should set this to zero; on further iterations
# the user should pass back the value of the cookie returned by this fn.
#
# @bug: *Needs to be modified for the case where there are multiple input vecs
# per cluster (right now, just one to one mapping)*
#
# @return: The global ID of the next request in this cluster
##
sub get_cluster_requests {
    assert(scalar(@_) == 3);

    my $self = shift;
    my $cluster_id = shift;
    my $cookie_ptr = shift;

    if ($self->{INPUT_HASHES_LOADED} == 0) {
        $self->$_load_files_into_hashes();
    }

    my $cluster_hash = $self->{CLUSTER_HASH};
    my $input_vec_to_global_ids_hash = $self->{INPUT_VEC_TO_GLOBAL_IDS_HASH};
    my @input_vecs = split(/,/, $cluster_hash->{$cluster_id});

    my @global_ids = split(/,/, $input_vec_to_global_ids_hash->{$input_vecs[0]});

    if(${$cookie_ptr} == scalar(@global_ids)) {
        return -1;
    }
    
    my $retval =  $global_ids[${$cookie_ptr}];
    ${$cookie_ptr}++;

    return $retval;
}
    

1;    


    


            
    
