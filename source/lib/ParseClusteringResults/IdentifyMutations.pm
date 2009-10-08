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

our @EXPORT_OK = qw(identify_mutations get_mutation_type
                    is_response_time_change is_structural_mutation
                    is_originating_cluster is_mutation);

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

    assert(scalar(@_) == 2);
    my ($this_cluster_info_hash_ref, $sensitivity) = @_;
    
    my $snapshot_probs = $this_cluster_info_hash_ref->{LIKELIHOODS};
    my $mutation_type = $NO_MUTATION;

    # Identify structural mutations and originating clusters
    if($snapshot_probs->[0] > 0 && $snapshot_probs->[1] > 0) {
            if ($snapshot_probs->[1]/$snapshot_probs->[0] > $sensitivity) {
                $mutation_type = $STRUCTURAL_MUTATION;
            } elsif ($snapshot_probs->[0]/$snapshot_probs->[1] > $sensitivity) {
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
sub identify_originators {
    
    assert(scalar(@_) == 2);
    my ($cluster_info_hash_ref, $sed_obj) = @_;

    foreach my $key (sort {$a <=> $b} keys %{$cluster_info_hash_ref}) {
        
        my $this_cluster = $cluster_info_hash_ref->{$key};
        my $mutation_info = $this_cluster->{MUTATION_INFO};
        
        if (($mutation_info->{MUTATION_TYPE} & $MUTATION_TYPE_MASK) == $STRUCTURAL_MUTATION) {

            my %cocd; # "Candidate Originating Cluster Distances"
        
            # Get list of candidate originating clusters
            foreach my $key2 (sort {$a <=> $b} keys %{$cluster_info_hash_ref}) {

                my $that_cluster = $cluster_info_hash_ref->{$key2};
                my $that_mutation_info = $that_cluster->{MUTATION_INFO};

                if (($that_mutation_info->{MUTATION_TYPE} & $MUTATION_TYPE_MASK) != $ORIGINATING_CLUSTER) {
                    next;
                }

                # Only compare clusters that are of the same high-level type
                if($this_cluster->{ROOT_NODE} ne $that_cluster->{ROOT_NODE}) {
                    print "$key: $key2 cannot be an originating cluster.  Root nodes don't match\n";
                    next;
                }

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
}


#### Public functions ############


##
# Given a hash reference containing information about each cluster, this module
# identifies which clusters represent structural mutations, or response-time
# mutations.
#
# @param cluster_info_hash_ref: A hash reference containing information about
#  each cluster.  It is keyed by cluster ID and each element contains the
#  following information: 
#      cluster_info_hash_ref->{ID} = { ROOT_NODE  => string
#                                      FREQUENCIES => \@array
#                                      LIKELIHOODS => \@array
#                                      RESPONSE_TIME_STATS => \%hash_ref
#                                      EDGE_LATENCY_STATS => \%hash_ref}
# @param sed: A object that allows querying of the "distance" between
#  different objects.
# @param sensitivity: The threshold of factor at which requests will be marked
# as structural mutations or originating clusters
##
sub identify_mutations {
    
    assert(scalar(@_) == 3);
    my ($cluster_info_hash_ref, $sed, $sensitivity) = @_;
    
    # Run Chi-Squared test here to tell if we should label *anything* as a structural mutation
    
    # Identify mutation types
    for my $key (keys %{$cluster_info_hash_ref}) {
        my %mutation_info;

        $mutation_info{MUTATION_TYPE} = find_mutation_type($cluster_info_hash_ref->{$key}, $sensitivity);
        $cluster_info_hash_ref->{$key}->{MUTATION_INFO} = \%mutation_info;
    }

    # Identify originators
    identify_originators($cluster_info_hash_ref, $sed);
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
