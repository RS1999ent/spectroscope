#! /usr/bin/perl -w

# $cmuPDL: CreateHypothesisTestInputs.pm

## 
# Helper file for ParseClusteringResults.pm.  This module implements functions
# necessary to identify response-time mutations, and for those, identify which
# edges contribution to the response-time change.  Also, contains functions
# necessary to run a chi^2 test to determine whether structural mutations exist.
##

package CreateHypothesisTestInputs;

use strict;
use warnings;
use Test::Harness::Assert;
use diagnostics;
use List::Util qw[max];
use Data::Dumper;

require Exporter;
our @EXPORT_OK = qw(add_latency_comparison get_comparison_results);


##### Global constants ########################

no define DEBUG =>;

##### Private functions #######################

## 
# Returns the row number to use when writing a sparse matrix of individual edge
# latencies.
#
# @note: Row counter is one indexed.
#
# @param edge_name: The name of the edge
# @param edge_row_num_hash: A pointer to a hash that
# maps edge names to row numbers.  
# @param reverse_edge_row_num_hash: A pointer to a hash
# that maps row numbers to edge names
#
# @return: The row number to use for this edge
##
sub get_edge_row_num {
    
    assert(scalar(@_) == 4);
    my ($edge_name, $edge_row_num_hash, 
        $reverse_edge_row_num_hash, $current_max_row_num) = @_;
    
    if(!defined $edge_row_num_hash->{$edge_name}) {
        my $row_num = $current_max_row_num + 1;
        
        if (DEBUG) {print "get_edge_row_num(): $edge_name $row_num\n"};
        
        $edge_row_num_hash->{$edge_name} = $row_num;
        $reverse_edge_row_num_hash->{$row_num} = $edge_name;
    }
    
    return $edge_row_num_hash->{$edge_name};
}


##
# Returns the column number to use when writing a sparse matrix of individual
# edge latencies.
#
# @note: Column counter is one indexed.
#
# @param edge_name: The name of the edge
# @param edge_col_num_hash: The hash-table listing the next
# column number to use for each edge
#
# @return: The column number to use for this edge
##
sub get_edge_col_num {
    assert(scalar(@_) == 2);
    my ($edge_name, $edge_col_num_hash) = @_;
    
    if(!defined $edge_col_num_hash->{$edge_name}) {
        $edge_col_num_hash->{$edge_name} = 1;
    }
    
    my $col_num = $edge_col_num_hash->{$edge_name};
    $edge_col_num_hash->{$edge_name}++;
    
    return $col_num;
}


##
# Creates files that specify that data distributions of edges for the global_ids
# passed in.  One file is created per snapshot and each row represents an edge.  
#
# @note row and column numbers are 1-indexed.
#
# @param s0_fh: File to which s0 edge latency distributions should be written
# @param s1_fh: File to which s1 edge latency distributions should be written
# @param global_ids_ptr: Edge latencies for requests specified by these IDs will be compared
# @param edge_name_to_row_num_hash_ptr: This will map edge names to their assigned row number
# @param row_num_to_edge_name_hash_ptr: This will map row numbers to their assigned column
# @param print_graphs: Object for yielding information about the request-flow graphs
##
sub write_edge_latency_distributions {
    
    assert(scalar(@_) == 6);
    my ($s0_fh, $s1_fh, 
        $global_ids_ptr,
        $edge_name_to_row_num_hash_ptr, 
        $row_num_to_edge_name_hash_ptr,
        $print_graphs ) = @_;
    
    my %col_num_hash;    
    
    my $max_row_num = max(sort {$a <=> $b} keys %{$row_num_to_edge_name_hash_ptr});
    my @fhs = ($s0_fh, $s1_fh);


    foreach (@$global_ids_ptr) {
        my @global_id = ($_);
        
        my $snapshot_ptr = $print_graphs->get_snapshots_given_global_ids(\@global_id);
        my $edge_info = $print_graphs->get_request_edge_latencies_given_global_id($global_id[0]);
        
        foreach my $key (keys %$edge_info) {
            my $row_num = get_edge_row_num($key, $edge_name_to_row_num_hash_ptr, 
                                           $row_num_to_edge_name_hash_ptr, $max_row_num);
            $max_row_num = max($row_num, $max_row_num);
            my $edge_latencies = $edge_info->{$key};
            
            foreach(@$edge_latencies) {
                my $col_num = get_edge_col_num($key,\%col_num_hash);
                my $filehandle = $fhs[$snapshot_ptr->[0]];
                printf $filehandle "%d %d %f\n", $row_num, $col_num, $_;
            }
        }
    }
}


## 
# Creates files populated with response time data distributions for use by the 
# run_hypothesis_test() function.  The files created are in matlab sparse-file 
# format -- that is, each row is of the form: <row num> <column number> <response_time>.
# row numbers and column numbers start at 1.
#
# Since we are only comparing one "category of things," only one row is created.
#
# @param s0_times_array_ref: Reference to an array of response-times for snapshot0
# @param s1_times_array_ref: Reference to an array of response-times for snapshot1
# @param s0_response_times_file: File in which response-times for s0 will be placed
# @param s1_response_times_file: File in which response-times for s1 will be placed
##
sub write_response_time_distributions {
    
    assert(scalar(@_) == 4);
    my ($s0_fh, $s1_fh,
        $s0_response_times_array_ref, $s1_response_times_array_ref) = @_;
    
    for (my $i = 0; $i < @{$s0_response_times_array_ref}; $i++) {
        # Row and column numbers start at 1!
        printf $s0_fh  "%d %d %f\n", 1, $i+1, $s0_response_times_array_ref->[$i];
    }
    
    for (my $i = 0; $i < @{$s1_response_times_array_ref}; $i++) {
        # Row and column numbers start at 1!
        printf $s1_fh "%d %d %f\n", 1, $i+1, $s1_response_times_array_ref->[$i];
    }
}


##
# Creates hypothesis test input files for comparing counts of the number of
# requests assigned to each cluster between the problem and non-problem period.
# 
# @param cluster_info_hash_ref: Information about each cluster
# @param s0_cluster_frequencies_file: Name of input file to create for s0
# @param s1_cluster_frequencies_file: Name of input file to create for s1
##
sub create_cluster_frequency_comparison_files {
    
    assert(scalar(@_) == 3);
    my ($cluster_info_hash_ref,
        $s0_cluster_frequencies_file, 
        $s1_cluster_frequencies_file) = @_;
    
    open (my $s0_fh, ">$s0_cluster_frequencies_file")
        or die ("create_cluster_frequency_comparison_files(): Could not open "
                . "$s0_cluster_frequencies_file");
    
    open (my $s1_fh, ">$s1_cluster_frequencies_file")
        or die ("create_cluster_frequency_comparison_files(): Could not open "
                . "$s1_cluster_frequencies_file");
    
    foreach my $id (sort {$a <=> $b} keys %{$cluster_info_hash_ref}) {
        printf $s0_fh "%d %d %s\n",
        $id, 
        $cluster_info_hash_ref->{$id}->{FREQUENCIES}->[0],
        $cluster_info_hash_ref->{$id}->{ROOT_NODE};
        
        printf $s1_fh "%d %d %s\n",
        $id, 
        $cluster_info_hash_ref->{$id}->{FREQUENCIES}->[1],
        $cluster_info_hash_ref->{$id}->{ROOT_NODE};
    }
    
    close($s0_fh);
    close($s1_fh);
}


#### API functions #############

##
# Given a hypothesis test object and select information about a cluster, this
# function adds a comparison within the hypothesis test for comparing the
# response time distribution of requests from snapshot0 versus that of snapshot1
# and for comparing corresponding edge latencies
#
# @param cid: The cluster ID
# @param global_ids: A reference to an array of global IDs of cluster requests
# @param response_times: A hash reference to 2 arrays of response times for S0 & S1
# @param edge_name_to_row_num: Mapping from edge names to row numbers
# @param row_num_to_edge_name: Mapping from row numbers to edge names
# @param hyp_test: A hypothesis test object
# @param graph_info: An object of type PrintGraphs
# @param directory to which distribution data should be written
#
# @return: A comparison ID for retrieving results of the hypothesis tests
##
sub add_latency_comparison {

    assert(scalar(@_) == 7);
    my ($cluster_id, $global_ids, $response_times,
        $edge_name_to_row_num, $row_num_to_name,
        $hyp_test, $graph_info) = @_;

    my $output_dir = $hyp_test->get_output_dir();

    my $s0_file = "$output_dir/$cluster_id" . "_s0_times.dat";
    my $s1_file = "$output_dir/$cluster_id" . "_s1_times.dat";
    
    open(my $s0_fh, ">$s0_file") or die("Could not open $s0_file");
    open(my $s1_fh, ">$s1_file") or die("could not open $s1_file");

    # Write response time distributions to the files 
    write_response_time_distributions($s0_fh, $s1_fh, 
                                      $response_times->{S0_RESPONSE_TIMES},
                                      $response_times->{S1_RESPONSE_TIMES});
    if (!defined $row_num_to_name->{1}) {
        $row_num_to_name->{1} = "RESPONSE_TIMES";
        $edge_name_to_row_num->{RESPONSE_TIMES} = 1;
    }
    

    # Write edge latency distributions to the tile
    write_edge_latency_distributions($s0_fh, $s1_fh,
                                     $global_ids, $edge_name_to_row_num,
                                     $row_num_to_name, $graph_info);

    close($s0_fh);
    close($s1_fh);

    # Add comparison to hypothesis test object
    my $comparison_id = $hyp_test->add_comparison($s0_file, $s1_file, "$cluster_id" . "_times");

    return $comparison_id;
}


##
# Returns results of comparing response times and edge latencies to see if they
# are statistically different
#
# @param comp_id: The ID of the statistical comparison set
# @param row_num_to_name: Mapping between row numbers and names
# @param hyp_test: The hypothesis test object containing the results.  The
# caller must have already called the fn necessary to compute the results
# 
# @return a hash reference containing two elements: 
#    RESPONSE_TIME_STATS => { REJECT_NULL => <value>,
#                             P_VALUE     => <value>,
#                             AVGS        => \@array,
#                             STDDEVS     => \@array }
#
#   EDGE_LATENCY_STATS   => { REJECT_NULL => <value>,
#                             P_VALUE     => <value>,
#                             AVGS        => \@array,
#                             STDDEVS     => \@array } 
##
sub get_comparison_results {
    assert(scalar(@_) == 3);
    my ($comp_id, $row_num_to_name, $hyp_test) = @_;

    my $temp = $hyp_test->get_hypothesis_test_results($comp_id, $row_num_to_name);
    
    my %results;
    
    $results{RESPONSE_TIME_STATS} = $temp->{RESPONSE_TIMES};
    delete $temp->{RESPONSE_TIMES};
    
    $results{EDGE_LATENCY_STATS} = $temp;

    return \%results;
}
    
1;
