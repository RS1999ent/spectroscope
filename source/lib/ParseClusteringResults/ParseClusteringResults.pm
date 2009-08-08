#! /usr/bin/perl -w

# $cmuPDL: ParseClusteringResults.pm,v 1.17 2009/08/07 17:51:15 rajas Exp $

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
use List::Util qw[max sum];
use diagnostics;
use Data::Dumper;
use SedClustering::Sed;


#### Global constants #############

# Import value of DEBUG if defined
no define DEBUG =>;

# Denotes that this cluster is not mutated
my $NO_MUTATION = 0x000;

# Denotes a structural mutation
my $STRUCTURAL_MUTATION =  0x001;

# Denotes an explicit originating cluster
my $ORIGINATING_CLUSTER = 0x010;

# Denotes a response-time change
my $RESPONSE_TIME_CHANGE = 0x100;

# Masks out RESPONSE_TIME_CHANGE info
my $MUTATION_TYPE_MASK = 0x011;

# Masks out the mutation type
my $RESPONSE_TIME_MASK = 0x100;

# if p(r|problem)/p(r|non-problem) > g_sensitivity
# then r is a structural mutation
# if p(r|non-problem)/p(r|problem) > g_sensitivity
# then r is a originating cluster
my $g_sensitivity = 2;


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
    my ($self, $cluster_id, $s0_values, $s1_values) = @_;

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

    if (scalar(@{$s0_values}) >= 4) {
        push(@labels, "s0");
        push(@values, $s0_values);
    }
    if (scalar(@{$s1_values}) >= 4) {
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
# Returns the row number to use when writing a sparse matrix of individual edge latencies.
#
# @note: Row counter is one indexed.
#
# @param self: The object containe
# @param edge_name: The name of the edge
# @param edge_row_num_hash: A pointer to a hash that
# maps edge names to row numbers.  
# @param reverse_edge_row_num_hash: A pointer to a hash
# that maps row numbers to edge names
#
# @return: The row number to use for this edge
##
my $_get_edge_row_num = sub {
    assert(scalar(@_) == 5);

    my $self = shift;
    my $edge_name = shift;
    my $edge_row_num_hash = shift;
    my $reverse_edge_row_num_hash = shift;
    my $current_max_row_num = shift;

    if(!defined $edge_row_num_hash->{$edge_name}) {
        my $row_num = $current_max_row_num + 1;
        
        if (DEBUG) {print "get_edge_row_num(): $edge_name $row_num\n"};

        $edge_row_num_hash->{$edge_name} = $row_num;
        $reverse_edge_row_num_hash->{$row_num} = $edge_name;
    }

    return $edge_row_num_hash->{$edge_name};
};


##
# Returns the column number to use when writing a sparse matrix of individual edge latencies.
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
# Creates files that specify that data distributions of edges for the global_ids
# passed in.  One file is created per snapshot and each row represents an edge.  
#
# @note Row and Column numbers are 1-indexed.
#
# @param self: The object container
# @param global_ids_ptr: Edge latencies for requests specified by these IDs will be compared
# @param s0_edge_file: This file will be populated with a sparse matrix of s0 edge latencies
# @param s1_edge_file: This file will be populated with a sparse matrix of s1 edge latencies
# @param edge_name_to_row_num_hash_ptr: This will map edge names to their assigned row number
# @param row_num_to_edge_name_hash_ptr: This will map row numbers to their assigned column
##
my $_create_edge_comparison_files = sub {
    assert(scalar(@_) == 6);
    my ($self, $global_ids_ptr, $s0_edges_file, $s1_edges_file, 
        $edge_name_to_row_num_hash_ptr, $row_num_to_edge_name_hash_ptr) = @_;

    my $print_graphs = $self->{PRINT_GRAPHS_CLASS};

    my %col_num_hash;    

    open(my $s0_edge_fh, ">$s0_edges_file") or 
        die "create_edge_comparison_files(): could not open $s0_edges_file: $!\n";
    open(my $s1_edge_fh, ">$s1_edges_file") or 
        die "create_edge_comparison_files(): could not $s1_edges_file: $!\n";;

    my @fhs = ($s0_edge_fh, $s1_edge_fh);

    my $max_row_num = 0;
    foreach (@$global_ids_ptr) {
        my @global_id = ($_);

        my $snapshot_ptr = $print_graphs->get_snapshots_given_global_ids(\@global_id);
        my $edge_info = $print_graphs->get_request_edge_latencies_given_global_id($global_id[0]);
        
        foreach my $key (keys %$edge_info) {
            my $row_num = $self->$_get_edge_row_num($key, $edge_name_to_row_num_hash_ptr, 
                                                    $row_num_to_edge_name_hash_ptr, $max_row_num);
            $max_row_num = max($row_num, $max_row_num);
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
# Runs a hypothesis test comparing the data distributions in corresponding rows
# of the input files.  Results of the hypothesis test are written to the output file
# specified and is of the following format: 
# 
#  <row number>: <changed> <p-value>> <avg. latency s0> <stddev s0> <avg. latency s1> <stddev s1>
#
# Where "changed" is 1 if the distributions for the data in row i of the input files
# are statistically different.  Note that rows are 1-indexed.
# 
# @param self: The object container
# @param null_distrib-file: Path to the file containing the null data distributions
# @param test_distrib_file: Path to the file containing the test distributions
# @param output_file: The path to the file where results of the hypothesis test
# will be written
##
my $_run_hypothesis_test = sub {
    assert(scalar(@_) == 4);
    my ($self, $null_distrib_file, $test_distrib_file, $output_file) = @_;
    
    my $curr_dir = getcwd();
    chdir '../lib/ParseClusteringResults';

    system("matlab -nojvm -nosplash -nodisplay -r \"compare_edges(\'$null_distrib_file\', \'$test_distrib_file\', \'$output_file\'); quit\"".
           "|| matlab -nodisplay -r \"compare_edges(\'$null_distrib_file\', \'$test_distrib_file\', \'$output_file\'); quit\"") == 0
           or die ("Could not run Matlab compare_edges script\n");

    chdir $curr_dir;
};


##
# Reads in the results of the hypothesis test conducted by the
# "_run_hypothesis_test" function and returns a reference to a hash of the form:
#
# hyp_test_results_hash{name} =  { REJECT_NULL         => <value>,
#                                  P_VALUE             => <value>,
#                                  AVG_LATENCIES       => \@array,
#                                  STDDEVS             => \@array}
#
# @param self: The object container
# @param hyp_tests_results_file: The file containing results of the hypothesis test
# @param row_num_to_edge_name_hash: (OPTIONAL) Maps row numbers in the results file
#  to caller-specified names.  If this parameter is not specified, the keys of the hash 
#  returned will be row numbers.  These row numbers are 1-indexed.
#
# @return: The hyp_test_results_hash
##                             
my $_load_hypothesis_test_results = sub {    

    assert(scalar(@_) == 2 || scalar(@_) == 3);
    my ($self, $hyp_test_results_file, $row_num_to_name_hash);

    if(scalar(@_) == 2) {
        ($self, $hyp_test_results_file) = @_;
    } else {
        ($self, $hyp_test_results_file, $row_num_to_name_hash) = @_;
    }

    my %hyp_test_results_hash;
    
    open(my $edge_comparisons_fh, "<$hyp_test_results_file")
        or die ("Could not open $hyp_test_results_file: $!\n");

    while (<$edge_comparisons_fh>) {
        # This regexp must match the output specified by _run_hypothesis_test()
        if(/(\d+) (\d+) ([\-0-9\.]+) ([0-9\.]+) ([0-9\.]+) ([0-9\.]+) ([0-9\.]+)/) {
            my $edge_row_num = $1;
            my $reject_null = $2;
            my $p_value = $3;
            my @avg_latencies = ($4, $6);
            my @stddevs = ($5, $7);
            
            my $row_name;
            if (defined $row_num_to_name_hash) {
                $row_name = $row_num_to_name_hash->{$edge_row_num};
            }
            else {
                $row_name = $edge_row_num;
            }
            assert(defined $row_name);

            $hyp_test_results_hash{$row_name} = { REJECT_NULL => $reject_null,
                                               P_VALUE        => $p_value,
                                               AVG_LATENCIES  => \@avg_latencies,
                                               STDDEVS        => \@stddevs };
        } else {
            print "_load_hypothesis_test_results(): Cannot parse line in" .
                " $hyp_test_results_file\n $_";
            assert(0);
        }
    }
    
    close($edge_comparisons_fh);
    
    return \%hyp_test_results_hash;
};


##
# Computes statistics about edges seen for a set of requests,
# given their global IDs.
# 
# @param self: The object container
# @param global_ids_ptr: A pointer to an array of global ids
# @param cluster_id: The cluster to which the global IDs belong
#
# @return a pointer to a hash of information about each edge in the
# cluster.  This hashed is structured as follows: 
#
# edge_name = { REJECT_NULL => <value>,
#               P_VALUE => <value>,
#               AVG_LATENCIES => \@array,
#               STDDEVS => \@array}
# where edge_name is "src_node_name->dest_node_name"
##
my $_compute_edge_statistics = sub {
    assert(scalar(@_) == 3);

    my $self = shift;
    my $global_ids_ptr = shift;
    my $cluster_id = shift;

    my $print_graphs = $self->{PRINT_GRAPHS_CLASS};

    my $output_dir = $self->{INTERIM_OUTPUT_DIR};

    my %edge_name_to_row_num_hash;
    my %row_num_to_edge_name_hash;

    # Make sure the output directory exists
    system("mkdir -p $output_dir");

    my $s0_edge_file = "$output_dir/s0_cluster_$cluster_id" . 
                       "_edge_latencies.dat";
    my $s1_edge_file = "$output_dir/s1_cluster_$cluster_id" .
                       "_edge_latencies.dat";
    my $comparison_results_file = "$output_dir/$cluster_id" .
                                   "_edge_comparisons.dat";
    
    $self->$_create_edge_comparison_files($global_ids_ptr, $s0_edge_file, $s1_edge_file,
                                          \%edge_name_to_row_num_hash, \%row_num_to_edge_name_hash);
    $self->$_run_hypothesis_test($s0_edge_file, $s1_edge_file, 
                           $comparison_results_file);
    my $edge_info = $self->$_load_hypothesis_test_results($comparison_results_file, \%row_num_to_edge_name_hash);

    return $edge_info;
};


## 
# Creates files populated with response time data distributions for use by the 
# run_hypothesis_test() function.  The files created are in matlab sparse-file 
# format -- that is, each row is of the form: <row num> <column number> <response_time>.
# row numbers and column numbers start at 1.
#
# Since we are only comparing one "category of things," only one row is created.
#
# @param self: The object container
# @param s0_times_array_ref: Reference to an array of response-times for snapshot0
# @param s1_times_array_ref: Reference to an array of response-times for snapshot1
# @param s0_response_times_file: File in which response-times for s0 will be placed
# @param s1_response_times_file: File in which response-times for s1 will be placed
##
my $_create_response_time_comparison_files = sub {
    
    assert(scalar(@_) == 5);
    my ($self, $s0_response_times_array_ref, $s1_response_times_array_ref, 
        $s0_response_times_file, $s1_response_times_file) = @_;

    open(my $fh, ">$s0_response_times_file")
        or die ("_create_response_time_comparison_files(): Could not open "
                . "$s0_response_times_file.  $!\n");

    for (my $i = 0; $i < @{$s0_response_times_array_ref}; $i++) {
        # Row and column numbers start at 1!
        printf $fh  "%d %d %f\n", 1, $i+1, $s0_response_times_array_ref->[$i];
    }
    close($fh);

    open($fh, ">$s1_response_times_file")
        or die ("_create_response_time_comparison_files(): Could not open "
                . "$s1_response_times_file.  $!\n");

    for (my $i = 0; $i < @{$s1_response_times_array_ref}; $i++) {
        # Row and column numbers start at 1!
        printf $fh "%d %d %f\n", 1, $i+1, $s1_response_times_array_ref->[$i];
    }
    close($fh);
};
    

## 
# Runs a hypothesis test comparing the distributions of the response times of
# requests in a cluster
#
# @param self: The object container
# @param s0_times_array_ref: Response times from snapshot0
# @param s1_times_array_ref: Response times from snapshot1
# @param cluster_id: THe cluster id
#
# @return: A pointer to a hash of statistics about the response times of requests 
# from each snapshot.  This hash is structured as follows: 
#
# $reponse_time_stats{REJECT_NULL   => <value>,
#                     P_VALUE       => <value>,
#                     AVG_LATENCIES => \@array
#                     STDDEVS       => \@array}
##
my $_compute_response_time_statistics = sub {
    
    assert(scalar(@_) == 4);
    my ($self, $s0_times_array_ref, $s1_times_array_ref, $cluster_id) = @_;

    my $output_dir = $self->{INTERIM_OUTPUT_DIR};
    my $s0_response_times_file = "$output_dir/s0_cluster_$cluster_id" . 
                                  "_response_time_comparisons.dat";
    my $s1_response_times_file = "$output_dir/s1_cluster_$cluster_id" . 
                                  "_response_time_comparisons.dat";
    my $comparison_results_file = "$output_dir/$cluster_id" . 
                                     "_response_time_comparisons.dat";

    $self->$_create_response_time_comparison_files($s0_times_array_ref,
                                                   $s1_times_array_ref,
                                                   $s0_response_times_file, 
                                                   $s1_response_times_file);
    

    $self->$_run_hypothesis_test($s0_response_times_file,
                                 $s1_response_times_file,
                                 $comparison_results_file);
    my $response_time_stats = $self->$_load_hypothesis_test_results($comparison_results_file);

    return $response_time_stats->{1};
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
# Returns the global IDs of all requests assugned to a cluster
#
# @param self: The object-container
# @param cluster_id: The global IDs of requests that
#  belong to this cluster will be returned
#
# @return A reference to an array of global IDs
##
my $_get_global_ids_of_reqs_in_cluster = sub {
    
    assert(scalar(@_) ==2);
    my ($self, $cluster_id) = @_;
    
    my $cluster_assignment_hash = $self->{CLUSTER_HASH};
    
    my @input_vec_ids = split(/,/, $cluster_assignment_hash->{$cluster_id});
    
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
    
    return \@global_ids;
};


##
# Identifies the type of mutation of a cluster.  Inserts this information
# into $self->{CLUSTER_INFO_HASH}->{MUTATION_INFO}.
# 
# @param self: The object container
# @param this_cluster_info_hash_ref: A reference to hash containing statistics
#  about the cluster for which we are determining the mutation type
#
# @return: An integer denoting the type of the mutation

#                    
##
my $_identify_mutation_type = sub {

    assert(scalar(@_) == 2);
    my ($self, $this_cluster_info_hash_ref) = @_;
    
    my $snapshot_probs = $this_cluster_info_hash_ref->{CLUSTER_PROBS};
    my $mutation_type = $NO_MUTATION;

    # Identify structural mutations and originating clusters
    if($snapshot_probs->[0] > 0 && $snapshot_probs->[1] > 0) {
            if ($snapshot_probs->[1]/$snapshot_probs->[0] > $g_sensitivity) {
                $mutation_type = $STRUCTURAL_MUTATION;
            } elsif ($snapshot_probs->[0]/$snapshot_probs->[1] > $g_sensitivity) {
                $mutation_type = $ORIGINATING_CLUSTER;
            }
        } else {
            $mutation_type = ($snapshot_probs->[0] > 0)? $ORIGINATING_CLUSTER: $STRUCTURAL_MUTATION;
        }
    
    # Identify response-time mutations
    my $hypothesis_test_results = $this_cluster_info_hash_ref->{RESPONSE_TIME_STATS};
    if ($hypothesis_test_results->{REJECT_NULL} == 1) {
        $mutation_type = $mutation_type | $RESPONSE_TIME_CHANGE;
    }

    printf "Mutation_type: %x\n", $mutation_type;
    return $mutation_type;
};


##
# Identifies candidate originating clusters of structural mutations.  Candiate
# originating clusters might be limited to only actual originating clusters, or
# to all clusters that contain requests from the non-problem period
#
# @param cluster_info_hash_ref: A reference to a hash containing statistics
# about each cluster
# @param candidate_originators: Either "all" or "originating_only"
#
# @return: The $cluster_info_hash_ref->{CANDIDATE_ORIGINATING_CLUSTERS} 
# points to an array reference of cluster IDs
##
my $_identify_originators = sub {
    
    assert(scalar(@_) == 2);
    my ($self, $candidate_originators) = @_;

    my $cluster_info_hash_ref = $self->{CLUSTER_INFO_HASH};
    my $sed_obj = $self->{SED_CLASS};

    foreach my $key (sort {$a <=> $b} keys %{$cluster_info_hash_ref}) {
        
        my $this_cluster = $cluster_info_hash_ref->{$key};
        my $mutation_info = $this_cluster->{MUTATION_INFO};
        
        if (($mutation_info->{MUTATION_TYPE} & $MUTATION_TYPE_MASK) == $STRUCTURAL_MUTATION) {

            print "$key is a structural mutation\n";

            my %cocd; # "Candidate Originating Cluster Distances"
        
            # Get list of candidate originating clusters
            foreach my $key2 (sort {$a <=> $b} keys %{$cluster_info_hash_ref}) {
                print "$key: Checking if $key2 is a originating cluster\n";
                # Can't be a structural mutation of itself
                if($key == $key2) {
                    print "$key: $key2 cannot be an originating cluster\n";
                    next;
                }

                my $that_cluster = $cluster_info_hash_ref->{$key2};
                my $that_mutation_info = $that_cluster->{MUTATION_INFO};

                # User might has asked that we compare only originating clusters
                if($candidate_originators eq "originating_only" &&
                   ($that_mutation_info->{MUTATION_TYPE} & $MUTATION_TYPE_MASK) != $ORIGINATING_CLUSTER) {
                    print "$key: $key2 cannot be a candidate originating cluster; asked for originating only\n";
                    next;
                }

                # Only compare clusters that are of the same high-level type
                if($this_cluster->{ROOT_NODE} ne $that_cluster->{ROOT_NODE}) {
                    print "$key: $key2 cannot be an originating cluster.  Root nodes don't match\n";
                    next;
                }

                print "$key: found candidate originating cluster: $key2\n";
                $cocd{$key2} = $sed_obj->get_sed($key, $key2);
                assert(defined $cocd{$key2});
            }

            # Rank the list
            my $max_originating_clusters = 10;
            my $idx = 0;
            my @ranked_originating_clusters;
            foreach my $candidate_cluster_id (sort {$cocd{$a} <=> $cocd{$b}} keys %cocd) {
                
                if($idx >= $max_originating_clusters) {
                    last;
                }
                $ranked_originating_clusters[$idx++] = $candidate_cluster_id;
                
            }

            # Insert ranked list into information about this cluster
            $mutation_info->{CANDIDATE_ORIGINATORS} = \@ranked_originating_clusters;
        }
    }
};


##
# Computes the probability of a cluster in a period
#
# @param $part: Num requests belonging to the 
#  input cluster from the requisite period(s)
# @param $whole: Number of reqs seen in the period(s)
##
my $_compute_cluster_prob = sub {

    assert(scalar(@_) == 3);
    my ($self, $part, $whole) = @_;
    
    my $prob;

    $part = $part + 1;
    $whole = $whole + 1;

    return $part/$whole;
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

    assert(scalar(@_) == 2);
    my ($self, $candidate_originators) = @_;

    my $cluster_assignment_hash = $self->{CLUSTER_HASH};
    my $graph_info = $self->{PRINT_GRAPHS_CLASS};
    my %cluster_info_hash;

    # Get the total number of requests in each dataset
    my $total_requests = $graph_info->get_snapshot_frequencies();

    foreach my $key (sort {$a <=> $b} keys %$cluster_assignment_hash) {
        print "Processing statistics for Cluster $key...\n";

        my @global_ids = @{$self->$_get_global_ids_of_reqs_in_cluster($key)};

        # Get frequencies and probability of occurence of this cluster in each snapshot
        my $cluster_freqs = $graph_info->get_snapshot_frequencies_given_global_ids(\@global_ids);
        my @cluster_probs;
        $cluster_probs[0] = $self->$_compute_cluster_prob($cluster_freqs->[0], $total_requests->[0]);
        $cluster_probs[1] = $self->$_compute_cluster_prob($cluster_freqs->[1], $total_requests->[1]);

        # Compute response time statistics
        my $response_times = $graph_info->get_response_times_given_global_ids(\@global_ids);
        my $response_time_stats = 
            $self->$_compute_response_time_statistics($response_times->{S0_RESPONSE_TIMES},
                                                      $response_times->{S1_RESPONSE_TIMES},
                                                      $key);
        # Print boxplots of reponse times        
        $self->$_print_boxplots($key, 
                                $response_times->{S0_RESPONSE_TIMES}, 
                                $response_times->{S1_RESPONSE_TIMES});
        undef $response_times;

        # Compute edge latency statistics
        my $edge_latency_stats = $self->$_compute_edge_statistics(\@global_ids, $key);

        # Fill in the %this_cluster_info_hash
        my %this_cluster_info;

        # Get the root node of the representative for this cluster
        my $gid = $self->get_global_id_of_cluster_rep($key);
        $this_cluster_info{ROOT_NODE} = $graph_info->get_root_node_given_global_id($gid);

        $this_cluster_info{FREQUENCIES} = $cluster_freqs;
        $this_cluster_info{CLUSTER_PROBS} = \@cluster_probs;
        
        $this_cluster_info{RESPONSE_TIME_STATS} = $response_time_stats;
        $this_cluster_info{EDGE_LATENCY_STATS} = $edge_latency_stats;

        $this_cluster_info{ID} = $key;
    
        # Determine if this cluster is a mutation
        my %mutation_info;
        $mutation_info{MUTATION_TYPE} = $self->$_identify_mutation_type(\%this_cluster_info);
        $this_cluster_info{MUTATION_INFO} = \%mutation_info;
        

        $cluster_info_hash{$key} = \%this_cluster_info;
    }
     
    $self->{CLUSTER_INFO_HASH} = \%cluster_info_hash;
    $self->$_identify_originators($candidate_originators);

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
    my $cluster_num = 0;
    while(<$clusters_fh>) {
        $cluster_num++;
        chomp;
        my @cluster_items = split(' ', $_);
        my $hash_item = join(',', @cluster_items);
        
        $cluster_hash{$cluster_num} = $hash_item;
    }
    close($clusters_fh);
    $self->{CLUSTER_HASH} = \%cluster_hash;
    $self->{NUM_CLUSTERS} = $cluster_num;

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
# @param cluster_info: Aggregate information about this cluster
#  super-imposed on top of the request
# @param out_fh: The filehandle to which the graph should be printed
##

my $_print_graph = sub {
    assert(scalar(@_) == 4);

    my $self = shift;
    my $cluster_id = shift;
    my $cluster_info = shift;
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
                                                         $cluster_info);

};


                              
#### Private sort routines #######

##
# Orders the input clusters based on the metric
#  (num_reqs_from_s0 - num_reqs_in_s1)/total_requests_in_cluster
# 
# Clusters are ordered according to the input metric in descending order

# @param $self: The object container
# @param $a: The first key
# @param $b: THe second key
#
# @return: 
#  -1: if metric($a) > metric($b)
#   0: if metric($a) == metric($b)
#   1: if (metric($a) < metric($b)
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
    my $a_metric = ($a_s1_reqs - $a_s0_reqs)/($a_s0_reqs + $a_s1_reqs);
    
    my $b_s0_reqs = $b_frequencies->[0];
    my $b_s1_reqs = $b_frequencies->[1];
    my $b_metric = ($b_s1_reqs - $b_s0_reqs)/($b_s0_reqs + $b_s1_reqs);
    
    if($b_metric > $a_metric) {
        return 1;
    }
    if($b_metric < $a_metric) {
        return -1;
    }
    if($b_s1_reqs > $a_s1_reqs) {
        return 1;
    }
    
    return 0;
};


##
# Orders the input clusters based on the problem period response time
# 
# @param self: The object container
# @param $a: The first cluster ID
# @param $b: The second cluster ID
#
# @return: 
#   -1 if metric($a) > metric($b)
#    0 if metric($a) == metric($b)
#    1 if metric($a) < metric($b)
##
my $_sort_clusters_by_problem_period_avg_response_time = sub {

    assert(scalar(@_) == 3);
    my ($self, $a, $b) = @_;

    my $a_response_time_stats= $self->{CLUSTER_INFO_HASH}{$a}{RESPONSE_TIME_STATS};
    my $b_response_time_stats = $self->{CLUSTER_INFO_HASH}{$b}{RESPONSE_TIME_STATS};

    if($a_response_time_stats->{AVG_LATENCIES} >
       $b_response_time_stats->{AVG_LATENCIES}) {

        return -1;

    } elsif ($a_response_time_stats->{AVG_LATENCIES} <
             $b_response_time_stats->{AVG_LATENCIES}) {

        return 1;
        
    } 

    return 0;
};


##
# Sorts clusters in descending order by the metric:
#     P(cluster|problem-period(s))/p(cluster|non-problem period(s))
#
# @param: $a: The first cluster ID
# @param: $b: The 2nd cluster ID
#
# @return: 
#   -1 if metric($a) > metric($b)
#    1 if metric($a) < metric($b)
#    1 if metric($a) == metric($b)
##
my $_sort_clusters_by_probability_factor = sub {
    
    assert(scalar(@_) == 3);
    my ($self, $a, $b) = @_;

    my $a_probs = $self->{CLUSTER_INFO_HASH}->{$a}->{CLUSTER_PROBS};
    my $b_probs = $self->{CLUSTER_INFO_HASH}->{$b}->{CLUSTER_PROBS};

    my $a_metric = $a_probs->[1]/$a_probs->[0];
    my $b_metric = $b_probs->[1]/$b_probs->[0];

    if($a_metric > $b_metric) {
        return -1;
    }
    if ($a_metric < $b_metric) {
        return 1;
    }
    
    # @bug: Since probability factor is equal, should sort by total frequency
    return 0;
};


## 
# Wrapper function for ordering clusters according to an input metric
#
# @param self: The object container
# @param metric: Can be any of the following: 
#     req_difference -- The metric used is:
#              (problem period(s) freqs - non-problem period(s) freq)
#               ---------------------------------------------
#             (problem period(s) frequency + non-problem period(s) freq)
#     prob_response_time -- The metric used is:
#             (problem period response time)
#
# Clusters are ordered according to the input metric in descending order
#
# @return:
#  -1 if metric($a) > metric($b)
#   0 if metric($a) == metric($b)
#   1 if metric($a) < metric($b)

#
# @return: 1 if $self-{CLUSTER_INFO_HASH}->{$b} is ranked higher than 
# $self->{CLUSTER_INFO_HASH}->{$a}, 0 if equal, or -1 otherwise
##
my $_sort_clusters_wrapper = sub { 
    assert(scalar(@_) == 2);
    my ($self, $metric) = @_;


    if ($metric =~ /req_difference/) {
        $self->$_sort_clusters_by_frequency_difference($a, $b);
    } elsif($metric =~ /prob_response_time/) {
        $self->$_sort_clusters_by_problem_period_avg_response_time($a, $b);
    } elsif($metric =~ /prob_factor/) {
        $self->$_sort_clusters_by_probability_factor($a, $b);
    } else {
        # Nothing else supported now :(
        assert (0);
    }
};


##
# Prints all clusters marked as being of type "RESPONSE_TIME_CHANGE"
#
# @param self: The object-container
##
my $_print_graphs_of_clusters_with_response_time_changes = sub {

    assert(scalar(@_) == 1);
    my ($self) = @_;

    my $output_file = $self->{RESPONSE_TIME_CHANGES_GRAPH_FILE};
    my $cluster_info = $self->{CLUSTER_INFO_HASH};

    open(my $output_fh, ">$output_file");

    for my $key (sort {$self->$_sort_clusters_wrapper("prob_response_time")} keys %{$cluster_info}) {

        my $this_cluster_info = $cluster_info->{$key};
        my $mutation_info = $this_cluster_info->{MUTATION_INFO};

        if (($mutation_info->{MUTATION_TYPE} & $RESPONSE_TIME_MASK) == $RESPONSE_TIME_CHANGE) {
            $self->$_print_graph($key, $this_cluster_info, $output_fh);
        }
    }
};


##
# Prints all structural mutations and originating clusters
#
# @param self: The object-container
##
my $_print_graphs_of_clusters_with_structural_mutations = sub {

    assert(scalar(@_) == 1);
    my($self) = @_;

    my $mutation_file = $self->{STRUCTURAL_MUTATIONS_GRAPH_FILE};
    my $originating_file = $self->{ORIGINATING_CLUSTERS_GRAPH_FILE};

    my $cluster_info = $self->{CLUSTER_INFO_HASH};
    my %originating_printed_hash;

    open(my $mutation_fh, ">$mutation_file") or 
        die "_print_graphs_of_clusters_with_structural_mutations(): Could not open " .
        " $mutation_file.  $!\n";
    open(my $originating_fh, ">$originating_file") or 
        die "_print_graphs_of_clusters_with_structural_mutations(): Could not open " .
        " $originating_file.  $!\n";

    for my $key (sort {$self->$_sort_clusters_wrapper("prob_factor")} keys %{$cluster_info}) {
        
        my $this_cluster_info = $cluster_info->{$key};
        my $mutation_info = $this_cluster_info->{MUTATION_INFO};

        if (($mutation_info->{MUTATION_TYPE} & $MUTATION_TYPE_MASK) == $STRUCTURAL_MUTATION) {
            $self->$_print_graph($key, $this_cluster_info, $mutation_fh);
            my $candidate_originators = $mutation_info->{CANDIDATE_ORIGINATORS};
            
            foreach(@{$candidate_originators}) {
                print "Structural Mutation: $key, Candidate Originator: $_\n";
                if(!defined $originating_printed_hash{$_}) {
                    my $candidate_originator_info = $cluster_info->{$_};
                    $self->$_print_graph($_, $candidate_originator_info, $originating_fh);
                    $originating_printed_hash{$_} = 1;
                }
            }
        }
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

    assert(scalar(@_) == 4);

    my ($proto, $convert_data_dir, 
        $print_graphs_class, $output_dir) = @_;


    my $class = ref($proto) || $proto;
    my $self = {};

    $self->{CLUSTERS_FILE} = "$convert_data_dir/clusters.dat",
    $self->{INPUT_VECTOR_FILE} = "$convert_data_dir/input_vector.dat",
    $self->{INPUT_VEC_TO_GLOBAL_IDS_FILE} = "$convert_data_dir/input_vec_to_global_ids.dat",;
    $self->{OUTPUT_DIR} = $output_dir;
    $self->{PRINT_GRAPHS_CLASS} = $print_graphs_class;

    # @bug: Abstraction violation, this class should not know that
    # the clusters are the same as the input vector
    $self->{SED_CLASS} = new Sed("$convert_data_dir/input_vector.dat", 
                                 "$convert_data_dir/clusters_distance_matrix.dat");
    assert($self->{SED_CLASS}->do_output_files_exist() == 1);
    
    # Hashes that will be maintained.  These hashes
    # are loaded from text files.
    $self->{CLUSTER_HASH} = undef;
    $self->{INPUT_VEC_TO_GLOBAL_IDS_HASH} = undef;
    $self->{INPUT_HASHES_LOADED} = 0;

    $self->{NUM_CLUSTERS} = undef;

    # These hashes are computed by the cluster
    $self->{CLUSTER_INFO_HASH} = undef;

    # Some derived outputs
    $self->{BOXPLOT_OUTPUT_DIR} = "$output_dir/boxplots";
    $self->{INTERIM_OUTPUT_DIR} = "$output_dir/interim_cluster_data";
    $self->{RESPONSE_TIME_CHANGES_GRAPH_FILE} = "$output_dir/response_time_changes.dot";
    $self->{STRUCTURAL_MUTATIONS_GRAPH_FILE} = "$output_dir/structural_mutations.dot";
    $self->{ORIGINATING_CLUSTERS_GRAPH_FILE} = "$output_dir/originating_clusters.dot";

    # Create the interim output directory
    system("mkdir -p $self->{INTERIM_OUTPUT_DIR}") == 0 or 
        die ("ParseClusteringResults.pm: new: Could not create" .
             " $self->{INTERIM_OUTPUT_DIR}.  $!\n");
    

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
    $self->{INPUT_HASHES_LOADED} = 0;

    undef $self->{NUM_CLUSTERS};

    # undef hashes computed by this cluster
    undef $self->{CLUSTER_INFO_HASH};
}


##
# Prints ranked cluster information.
#
# @param self: The object-container
##
sub print_ranked_clusters {
    assert(scalar(@_) == 2);
    
    my ($self, $candidate_originators) = @_;

    assert ($candidate_originators =~ m/all/ ||
            $candidate_originators =~ m/originating_only/);
    
    if($self->{INPUT_HASHES_LOADED} == 0) {
        $self->$_load_files_into_hashes();
    }
    if(!defined $self->{CLUSTER_INFO_HASH}) {
        $self->$_compute_cluster_info($candidate_originators);
    }

    $self->$_print_graphs_of_clusters_with_response_time_changes();
    $self->$_print_graphs_of_clusters_with_structural_mutations();
}


##
# Returns the total number of clusters that exist
# 
# @param self: The object-container
#
# @return: The number of clusters managed by this object
##
sub get_num_clusters {

    assert(scalar(@_) == 1);
    my ($self) = @_;

    if($self->{INPUT_HASHES_LOADED} == 0) {
        $self->$_load_files_into_hashes();
    }
    assert(defined $self->{NUM_CLUSTERS});
    return $self->{NUM_CLUSTERS};
}


##
# Returns the total number of requests assigned to a cluster
#
# @param self: The object container
# @param cluster_id: The number of requests belonging to this
#  cluster will be returned
#
# @return: The number of requests belonging to the cluster
##
sub get_num_requests_in_cluster {

    assert(scalar(@_) == 2);
    my ($self, $cluster_id) = @_;

    if($self->{INPUT_HASHES_LOADED} == 0) {
        $self->$_load_files_into_hashes();
    }

    my @global_ids = @{$self->$_get_global_ids_of_reqs_in_cluster($cluster_id)};
    
    return scalar(@global_ids);
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
    my ($self, $cluster_id) = @_;

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
# Returns the cluster representative graph in a string
#
# @param self: The object-container
# @param cluster_id: The cluster whose representative will
#  be returned
#
# @return: A string containing the cluster representative
##
sub get_cluster_representative {
  
    assert(scalar(@_) == 2);
    my ($self, $cluster_id) = @_;

    if($self->{INPUT_HASHES_LOADED} == 0) { 
        $self->$_load_files_into_hashes();
    }

    my $print_graphs = $self->{PRINT_GRAPHS_CLASS};

    my $cluster_rep_id  = get_global_id_of_cluster_rep($self, $cluster_id);
    my $cluster_rep = $print_graphs->get_global_id_indexed_request($cluster_rep_id);
    
    return $cluster_rep;
}
  

##
# Returns the global IDs of requests in a cluster
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


    


            
    
