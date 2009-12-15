#! /usr/bin/perl -w

# $cmuPDL: CreateHypothesisTestInputs.pm

## 
# Contains Helper functions for ParseClusteringResults.pm.  The functions in
# this file create files containing edge latency distributions and response-time
# distributions.
##

package CreateHypothesisTestInputs;

use strict;
use warnings;
use Test::Harness::Assert;
use diagnostics;
use List::Util qw[max];
use Data::Dumper;

require Exporter;
our @EXPORT_OK = qw(create_response_time_comparison_files create_edge_latency_comparison_files);


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
    

###### API functions #######################

##
# Creates files that specify that data distributions of edges for the global_ids
# passed in.  One file is created per snapshot and each row represents an edge.  
#
# @note row and column numbers are 1-indexed.
#
# @param global_ids_ptr: Edge latencies for requests specified by these IDs will be compared
# @param s0_edge_file: This file will be populated with a sparse matrix of s0 edge latencies
# @param s1_edge_file: This file will be populated with a sparse matrix of s1 edge latencies
# @param edge_name_to_row_num_hash_ptr: This will map edge names to their assigned row number
# @param row_num_to_edge_name_hash_ptr: This will map row numbers to their assigned column
# @param print_graphs: Object for yielding information about the request-flow graphs
##
sub create_edge_latency_comparison_files {

    assert(scalar(@_) == 6);
    my ($global_ids_ptr, $s0_edges_file, $s1_edges_file, 
        $edge_name_to_row_num_hash_ptr, $row_num_to_edge_name_hash_ptr,
        $print_graphs ) = @_;

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

    close($fhs[0]);
    close($fhs[1]);
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
sub create_response_time_comparison_files {
    
    assert(scalar(@_) == 4);
    my ($s0_response_times_array_ref, $s1_response_times_array_ref, 
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
    

1;
