#! /usr/bin/perl -w

# $cmuPDL: IdentifyMutations.pm, v #

##
# This Perl module implements routines for identifying different mutation types
##

package IdentifyMutations;

use strict;
use Test::Harness::Assert;
#use ParseClusteringResults::CreateHypothesisTestInputs
#    qw[create_graph_structure_comparison_files];

use Data::Dumper;

our @EXPORT_OK = qw(identify_mutations get_mutation_type
                    is_response_time_change is_structural_mutation
                    is_originating_cluster is_mutation
                    get_originators);

#### Global constants ###########

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


#### Private functions ##########

##
# Identifies the type of mutation of a cluster.
# 
# @param this_cluster_info_hash_ref: A reference to hash containing statistics
#  about the cluster for which we are determining the mutation type
# @param sensitivity: The threshold factor increase or decrease in requests
# belonging to a cluster that will force this function to mark it as a
# structural mutation or originating cluster
#
# @return: An integer denoting the type of the mutation
##
sub find_mutation_type  {

    assert(scalar(@_) == 3);
    my ($this_cluster_info_hash_ref, $mutation_threshold, $total_reqs) = @_;

    my $snapshot_freqs = $this_cluster_info_hash_ref->{FREQUENCIES};
    my $mutation_type = $NO_MUTATION;
    my $avg_reqs_per_snapshot = $total_reqs/2;

    # Identify structural mutations and originating clusters
#        if($snapshot_freqs->[1] > 1) {
#            if($snapshot_freqs->[1] > $snapshot_freqs->[0]) {
    if(($snapshot_freqs->[1] - $snapshot_freqs->[0]) > $mutation_threshold) {
        $mutation_type = $STRUCTURAL_MUTATION;
    }
    
#        if ($snapshot_freqs->[0] > 1) {
#        if($snapshot_freqs->[0] > $snapshot_freqs->[1]) {
    if(($snapshot_freqs->[0] - $snapshot_freqs->[1]) > $mutation_threshold) {
        $mutation_type = $ORIGINATING_CLUSTER;
    }

    # Identify response-time mutations
    my $hypothesis_test_results = $this_cluster_info_hash_ref->{RESPONSE_TIME_STATS};
    if ($hypothesis_test_results->{REJECT_NULL} == 1) {
        $mutation_type = $mutation_type | $RESPONSE_TIME_CHANGE;
    }

    return $mutation_type;
}


## 
# Helper function for identify originators.  
# Normalizes mutation costs
#
# @param cost_hash_ref: Reference to cost matrix
# @param normalization_constant by which to normalize costs by
# 
# @return The total expected cost of the mutation
##
sub normalize_mutation_costs {
    
    assert(scalar(@_) == 2);
    my ($cost_hash_ref, $norm_const) = @_;

    my $rank = 1;
    my $total_cost = 0;
    
    foreach my $o_id (keys %{$cost_hash_ref}) {
        $cost_hash_ref->{$o_id} = $cost_hash_ref->{$o_id}/$norm_const;
        $total_cost += $cost_hash_ref->{$o_id};
    }

    return $total_cost;
}
    

##
# Identifies candidate originating clusters of structural mutations.  Candiate
# originating clusters might be limited to only actual originating clusters, or
# to all clusters that contain requests from the non-problem period
#
# @param cluster_info_hash_ref: A reference to a hash containing statistics
# about each cluster
#
# @return: The $cluster_info_hash_ref->{CANDIDATE_ORIGINATING_CLUSTERS} 
# points to an array reference of cluster IDs
##
sub identify_originators_and_cost {
    
    assert(scalar(@_) == 3);
    my ($cluster_info_hash_ref, $sed_obj, $dont_enforce_one_to_n) = @_;

    foreach my $m_id (sort {$a <=> $b} keys %{$cluster_info_hash_ref}) {
        
        my $mutation = $cluster_info_hash_ref->{$m_id};
        my $mutation_info = $mutation->{MUTATION_INFO};
        
        if (($mutation_info->{MUTATION_TYPE} & $MUTATION_TYPE_MASK) == $STRUCTURAL_MUTATION) {

            my $weight; # Edit distance betweeen originator and mutation
            my %unweighted_mutation_cost;
            my %weighted_mutation_cost;
            my %inverse_sed;

            my $total_weight = 0;
            my $num_originators = 0;

            my $extra_reqs_in_mutation = $mutation->{FREQUENCIES}->[1] - $mutation->{FREQUENCIES}->[0];
            my $mutation_response_time = $mutation->{RESPONSE_TIME_STATS}->{AVGS}->[1];

            # Get list of candidate originating clusters
            foreach my $o_id (sort {$a <=> $b} keys %{$cluster_info_hash_ref}) {

                my $originator = $cluster_info_hash_ref->{$o_id};
                my $originator_mutation_info = $originator->{MUTATION_INFO};

                if (($originator_mutation_info->{MUTATION_TYPE} & $MUTATION_TYPE_MASK) != $ORIGINATING_CLUSTER) {
                    next;
                }

                my $fewer_reqs_in_originator = $originator->{FREQUENCIES}->[0] - $originator->{FREQUENCIES}->[1];
                my $originator_response_time = $originator->{RESPONSE_TIME_STATS}->{AVGS}->[1];

                # Only compare clusters that are of the same high-level type
                if($mutation->{ROOT_NODE} ne $originator->{ROOT_NODE}) {
                    print "$o_id cannot be an originating cluster of $m_id.  Root nodes don't match\n";
                    next;
                }

                if ($dont_enforce_one_to_n == 0) {
                    # Enforce 1-N relationship explicitly
                    if($extra_reqs_in_mutation > $fewer_reqs_in_originator) {
                        print "$o_id cannot be an originating cluster of $m_id\n" .
                            "\t because $m_id has increased in freq more than $o_id has decreased\n";
                        next;
                    }
                }

                $weight = 1/$sed_obj->get_sed($m_id, $o_id);
                $total_weight += $weight;
                $num_originators++;

                # Compute running cost of this structural mutation
                my $unweighted_cost = $extra_reqs_in_mutation*($mutation_response_time - $originator_response_time);

                # Store weights and distances
                $unweighted_mutation_cost{$o_id} = $unweighted_cost;
                $inverse_sed{$o_id} = $weight;
                $weighted_mutation_cost{$o_id} = $unweighted_cost * $weight,
            }

            my $total_unweighted_cost = normalize_mutation_costs(\%unweighted_mutation_cost,
                                                                 $num_originators);
            my $total_weighted_cost = normalize_mutation_costs(\%weighted_mutation_cost,
                                                               $total_weight);
            
            # Insert ranked list into information about this cluster
            $mutation_info->{DETAILS} = { WEIGHTED_ORIGINATORS   => \%weighted_mutation_cost,
                                          TOTAL_WEIGHTED_COST    => $total_weighted_cost,
                                          UNWEIGHTED_ORIGINATORS => \%unweighted_mutation_cost,
                                          TOTAL_UNWEIGHTED_COST  => $total_unweighted_cost,
                                          INVERSE_SED            => \%inverse_sed};
        }

        if (($mutation_info->{MUTATION_TYPE} & $RESPONSE_TIME_MASK) == $RESPONSE_TIME_CHANGE) {
            my $response_time_change = $mutation->{RESPONSE_TIME_STATS}->{AVGS}->[1] - 
                                        $mutation->{RESPONSE_TIME_STATS}->{AVGS}->[0];
            my $cost = $mutation->{FREQUENCIES}->[0]*($response_time_change);
            $mutation_info->{DETAILS}->{RESPONSE_TIME_COST} = $cost;
            
        }
    }
}


##
# Calculates the cost of structural mutations in the problem period

# This is defined as:
#  sum_over_mutations(avg_resp_time_mutation_i*increase_in_frequency) -
#  sum_over_originators(avg_resp_time_originators*decrease_in_frequency);
#
# Also calculates the expected total cost of structural mutations given the
# assumptions made about originator/structural mutation relationships in
# identify_originators_and_cost().
#
# @note: Since we assume that high-level (root) types cannot change, we could
# calculate the known total cost for high-level type independently.  We might
# want to present these to the user as well as the cost of each mutation.
##
sub calculate_structural_mutation_error {

    assert(scalar(@_) == 2);
    my ($cluster_info_hash_ref, $output_dir) = @_;

    # Calculate originator cost
    my $total_originator_cost = 0;
    my $total_mutation_cost = 0;

    my $weighted_expected_cost = 0;
    my $unweighted_expected_cost = 0;

    foreach my $id (sort {$a <=> $b} keys %{$cluster_info_hash_ref}) {
        
        my $cluster_info = $cluster_info_hash_ref->{$id};
        my $mutation_info = $cluster_info->{MUTATION_INFO};

        my $total_originator_cost = 0;
        if(($mutation_info->{MUTATION_TYPE} & $MUTATION_TYPE_MASK) == $ORIGINATING_CLUSTER) {
            my $fewer_reqs_in_originator = $cluster_info->{FREQUENCIES}->[0] - $cluster_info->{FREQUENCIES}->[1];
            my $originator_response_time = $cluster_info->{RESPONSE_TIME_STATS}->{AVGS}->[1];
            $total_originator_cost += $fewer_reqs_in_originator * $originator_response_time;
        }

        if(($mutation_info->{MUTATION_TYPE} & $MUTATION_TYPE_MASK) == $STRUCTURAL_MUTATION) {
            my $extra_reqs_in_mutation = $cluster_info->{FREQUENCIES}->[1] - $cluster_info->{FREQUENCIES}->[0];
            my $mutation_response_time = $cluster_info->{RESPONSE_TIME_STATS}->{AVGS}->[1];
            $total_mutation_cost += $extra_reqs_in_mutation * $mutation_response_time;

            $weighted_expected_cost += $cluster_info->{MUTATION_INFO}->{DETAILS}->{TOTAL_WEIGHTED_COST};
            $unweighted_expected_cost += $cluster_info->{MUTATION_INFO}->{DETAILS}->{TOTAL_UNWEIGHTED_COST};
        }
    }

    my $total_cost = $total_mutation_cost - $total_originator_cost;

    my $unweighted_error = 0;
    my $weighted_error = 0;

    if($total_cost != 0) { 
        $unweighted_error = abs($total_cost - $unweighted_expected_cost)/$total_cost;
        $weighted_error = abs($total_cost - $weighted_expected_cost)/$total_cost;
    }
        
    my $output_file = "$output_dir/costs.dat\n";
    open (my $output_fh, ">$output_file") or die ("Could not open output file\n");
    printf "Total Cost: %3.2f\n", $total_cost;
    printf $output_fh "Total cost of structural mutations: %3.4f\n", $total_cost;

    printf $output_fh  "Expected cost of structural mutations (unweighted): %3.4f\n (%3.4f)\n",
    $unweighted_expected_cost, $unweighted_error;

    printf $output_fh "Expected cost of structural mutations (weighted): %3.4f\n (%3.4f)\n",
    $weighted_expected_cost, $weighted_error;

    close ($output_fh);
}


##
# Runs a X^2 hypothesis test to determine if structural mutations exist
#
# @param cluster_info_hash_ref: Information about each cluster
# @param sed: An object specifying distances between clusters
# @param output_dir: Input files created by this function for use by
#  MATLAB will be placed in this directory
# 
# @return: 1 if structural mutations exist, 0 otherwise.
##
sub determine_if_structural_mutations_exist {

    assert(scalar(@_) == 3);
    my ($cluster_info_hash_ref, $sed, $output_dir) = @_;

    my $s0_cluster_frequencies_file = "$output_dir/s0_cluster_frequencies.dat";
    my $s1_cluster_frequencies_file = "$output_dir/s1_cluster_frequencies.dat";
    
    CreateHypothesisTestInputs::create_cluster_frequency_comparison_files($cluster_info_hash_ref,
                                                                          $s0_cluster_frequencies_file,
                                                                          $s1_cluster_frequencies_file);

    # Run hypothesis test
    #my $test = new HypothesisTest($s0_cluster_frequencies_file,
    #                              $s1_cluster_frequencies_file,
    #                              "category_count_comparisons",
    #                              $output_dir);

    #$test->run_chi_squared($sed->get_distance_matrix_file());

    print "Determining if structural mutations exist\n";
    #my $results = $test->get_hypothesis_test_results();

    return 1;  #$results->{1}->{REJECT_NULL};
}

#### Public functions ############


##
# Given a hash reference containing information about each cluster, this module
# identifies which clusters represent structural mutations, or response-time
# mutations, and the cost of these mutations.
#
# @param cluster_info_hash_ref: A hash reference containing information about
#  each cluster.  It is keyed by cluster ID and each element contains the
#  following information: 
#      cluster_info_hash_ref->{ID} = { ROOT_NODE  => string
#                                      FREQUENCIES => \@array
#                                      LIKELIHOODS => \@array
#                                      RESPONSE_TIME_STATS => \%hash_ref
#                                      EDGE_LATENCY_STATS => \%hash_ref}
# @param sed: A object that allows querying of the "distance" between clusters
# @param output_dir: The output directory in which to write data files created
#  while identifying mutations
#
#
# @return: 
#   * The total cost of the mutation period.  
#   * A field MUTATION_INFO is added to each element of cluster_info_hash_ref.
#     it contains a reference to a hash with the following fields:
#       * MUTATION_TYPE: The type of mutation represented by this cluster
#       * STRUCTURAL_MUTATION_INFO: A hash reference specifying the cost of each 
#         structural mutation and the expected contribution to that cost by each
#         possible originator.  This hash reference contains the fields: 
#       * RESPONSE_TIME_CHANGE_INFO: A hash reference specifying the cost of each
#         response-time change
##
sub identify_mutations {
    
    assert(scalar(@_) == 6);
    my ($cluster_info_hash_ref, $sed, $output_dir, 
        $dont_enforce_one_to_n, $mutation_threshold, $total_reqs) = @_;
    
    # Run Chi-Squared test here to tell if we should label *anything* as a structural mutation
    #my $structural_mutations_exist = determine_if_structural_mutations_exist($cluster_info_hash_ref,
    #                                                                         $sed,
    #                                                                         $output_dir);

    # Identify mutation types
    for my $key (keys %{$cluster_info_hash_ref}) {
        my %mutation_info;
        $mutation_info{MUTATION_TYPE} = find_mutation_type($cluster_info_hash_ref->{$key}, 
                                                           $mutation_threshold,
                                                           $total_reqs);

        $cluster_info_hash_ref->{$key}->{MUTATION_INFO} = \%mutation_info;
    }

    # Identify originators and cost of mutations
    identify_originators_and_cost($cluster_info_hash_ref, $sed, $dont_enforce_one_to_n);
    calculate_structural_mutation_error($cluster_info_hash_ref, $output_dir);
}


##
# Returns the mutation type of a cluster
#
# @param cluster_info_hash_ref: Hash reference containing info about each cluster
# @param cluster_id: The ID of the cluster for which to return the mutation type
#
# @return: Any combination of the following:
#     "Structural_Mutation"
#     "Originating_Cluster"
#     "Response_Time_Change"
##
sub get_mutation_type {

    assert(scalar(@_) == 2);
    my ($cluster_info_hash_ref, $cluster_id) = @_;

    my $mutation_type = $cluster_info_hash_ref->{$cluster_id}->{MUTATION_INFO}->{MUTATION_TYPE};
    my $mutation_type_string;

    if (($mutation_type & $MUTATION_TYPE_MASK) == $STRUCTURAL_MUTATION) {
        $mutation_type_string = "Structural_Mutation";
    } elsif (($mutation_type & $MUTATION_TYPE_MASK) == $ORIGINATING_CLUSTER) {
        $mutation_type_string = "Originating_Cluster";
    }

    if (($mutation_type & $RESPONSE_TIME_MASK) == $RESPONSE_TIME_CHANGE) {
        if (defined $mutation_type_string) {
            $mutation_type_string = $mutation_type_string . " and_Response_Time_Change";
        } else {
            $mutation_type_string = "Response_Time_Change";
        }
    }

    if (!defined $mutation_type_string) {
        $mutation_type_string = "None";
    }

    return $mutation_type_string;
}    


##
# Returns whether or not a given cluster represents a response-time change
#
# @param cluster_info_hash_ref: Hash ref containing info about each cluster
# @param cluster_id: The ID of the cluster for which we want info
#
# @return 1 if this is a response-time change, 0 if this is not
##
sub is_response_time_change {
    assert(scalar(@_) == 2);
    my ($cluster_info_hash_ref, $cluster_id) = @_;

    my $this_cluster_info = $cluster_info_hash_ref->{$cluster_id};
    my $mutation_info = $this_cluster_info->{MUTATION_INFO};

    if (($mutation_info->{MUTATION_TYPE} & $RESPONSE_TIME_MASK) == $RESPONSE_TIME_CHANGE) {
        return 1;
    }

    return 0;
}


##
# Returns whether or not a given cluster represents a structural mutation
#
# @param cluster_info_hash_ref: Hash ref containing info about each cluster
# @param cluster_id: The ID of the cluster for which we want info
#
# @return 1 if this is a structural mutation, 0 if this is not
##
sub is_structural_mutation {
    assert(scalar(@_) == 2);
    my ($cluster_info_hash_ref, $cluster_id) = @_;

    my $this_cluster_info = $cluster_info_hash_ref->{$cluster_id};
    my $mutation_info = $this_cluster_info->{MUTATION_INFO};


    if (($mutation_info->{MUTATION_TYPE} & $MUTATION_TYPE_MASK) == $STRUCTURAL_MUTATION) {
        return 1;
    }

    return 0;
}


##
# Returns whether or not a given cluster represents an originating cluster
#
# @param cluster_info_hash_ref: Hash ref containing info about each cluster
# @param cluster_id: The ID of the cluster for which we want info
#
# @return 1 if this is an originating cluster, 0 if this is not
##
sub is_originating_cluster {
    assert(scalar(@_) == 2);
    my ($cluster_info_hash_ref, $cluster_id) = @_;

    my $this_cluster_info = $cluster_info_hash_ref->{$cluster_id};
    my $mutation_info = $this_cluster_info->{MUTATION_INFO};


    if (($mutation_info->{MUTATION_TYPE} & $MUTATION_TYPE_MASK) == $ORIGINATING_CLUSTER) {
        return 1;
    }

    return 0;
}


##
# Returns whether or not a given cluster represents any sort of mutation
#
# @param cluster_info_hash_ref: Hash ref containing info about each cluster
# @param cluster_id: The ID of the cluster for which we want info
#
# @return 1 if this is some sort of mutation, 0 otherwise
##
sub is_mutation {
    assert(scalar(@_) == 2);
    my ($cluster_info_hash_ref, $cluster_id) = @_;

    my $this_cluster_info = $cluster_info_hash_ref->{$cluster_id};
    my $mutation_info = $this_cluster_info->{MUTATION_INFO};


    if (($mutation_info->{MUTATION_TYPE}) == $NO_MUTATION) {
        return 1;
    }

    return 1;
}


##
# Returns a string of the ranked originating request-flows of a structural 
# mutation.  If the input item is not a structural mutation, this function
# will assert.
#
# @param cluster_info_hash_ref: Information about each request-flow
# @param cluster_id: The Id of the cluster
# @param use_weighted_costs: Whether originator ranks should be weighted
#  by the string-edit distance between the mutation and the originators
#
# @return A string containing the IDs of the originating request-flows if the
# Id passed in represents a structural mutation.  Else, an empty string.
##
sub get_originators {

    assert(scalar(@_) == 3);
    my ($cluster_info_hash_ref, $cluster_id, $use_weighted_costs) = @_;

    my $this_cluster_info = $cluster_info_hash_ref->{$cluster_id};
    my $mutation_info = $this_cluster_info->{MUTATION_INFO};

    my $originator_string = "";

    assert(($mutation_info->{MUTATION_TYPE} & $MUTATION_TYPE_MASK) == $STRUCTURAL_MUTATION);
    
    my $originators;
    if ($use_weighted_costs == 1) {
#        $originators = $mutation_info->{DETAILS}->{WEIGHTED_ORIGINATORS};
        $originators = $mutation_info->{DETAILS}->{INVERSE_SED};
    }
    else {
        $originators = $mutation_info->{DETAILS}->{UNWEIGHTED_ORIGINATORS};
    }

    # Rank in descending order
    for my $o_id (sort {$originators->{$b} <=> $originators->{$a}}
                  keys %{$originators}) {
        
        my $cost = $originators->{$o_id};
        $originator_string = $originator_string . "$o_id ($cost) ";
    }
    
    return $originator_string;
}


##
# Returns the total mutation cost of a structural mutation
# 
# @param cluster_info_hash_ref: Information about each cluster
# @param cluster_id: The id of the cluster being considered
# @param used_weighted_costs: Whether originator ranks should
#  be weighted by string-edit distance between the mutation and originators
#
# @return: The expected mutation cost of the structural mutation
##
sub get_structural_mutation_cost {

    assert(scalar(@_) == 3);
    my ($cluster_info_hash_ref, $cluster_id, $use_weighted_costs) = @_;

    my $this_cluster_info = $cluster_info_hash_ref->{$cluster_id};
    my $mutation_info = $this_cluster_info->{MUTATION_INFO};

    assert(($mutation_info->{MUTATION_TYPE} & $MUTATION_TYPE_MASK) == $STRUCTURAL_MUTATION);

    my $cost;

    if ($use_weighted_costs == 1) {
        $cost = $mutation_info->{DETAILS}->{TOTAL_WEIGHTED_COST};
    } else  {
        $cost = $mutation_info->{DETAILS}->{TOTAL_UNWEIGHTED_COST};
    }

    assert (defined $cost);

    return $cost;
}


##
# Returns the total cost of a response-time change
#
# @param cluster_info_hash_ref: Information about each cluster
# @param cluster_id: The id of the cluster being considered
# 
# @return the total cost of the resposne-time change
##
sub get_response_time_change_cost {
    
    assert(scalar(@_) == 2);
    my ($cluster_info_hash_ref, $cluster_id) = @_;

    my $this_cluster_info = $cluster_info_hash_ref->{$cluster_id};
    my $mutation_info = $this_cluster_info->{MUTATION_INFO};

    assert(($mutation_info->{MUTATION_TYPE} & $RESPONSE_TIME_MASK) == $RESPONSE_TIME_CHANGE);
    assert(defined $mutation_info->{DETAILS}->{RESPONSE_TIME_COST});

    return $mutation_info->{DETAILS}->{RESPONSE_TIME_COST};
}


    
