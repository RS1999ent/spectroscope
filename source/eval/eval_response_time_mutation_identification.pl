#!/usr/bin/perl -w

#
# Copyright (c) 2013, Carnegie Mellon University.
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
# 1. Redistributions of source code must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in the
#    documentation and/or other materials provided with the distribution.
# 3. Neither the name of the University nor the names of its contributors
#    may be used to endorse or promote products derived from this software
#    without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
# ``AS IS'' AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
# LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
# A PARTICULAR PURPOSE ARE DISCLAIMED.  IN NO EVENT SHALL THE COPYRIGHT
# HOLDERS OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
# INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING,
# BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS
# OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED
# AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
# LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY
# WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
# POSSIBILITY OF SUCH DAMAGE.
#

# $cmuPDL: eval_response_time_mutation_identification.pl,v 1.13 2010/05/03 20:34:22 rajas Exp $ #

##
# @author Raja Sambasivan
#
# Given the Spectroscope results and a mutated node just before which a
# response-time mutation was induced, this code will evaluate the quality of the
# spectroscope results.  Specifically, it will determine:
#
# Note that virtual categories and requests exist because the combined ranked
# results file splits categories into virtual categories if they contain both
# structural mutations *and* response-time mutations.
#
# 7)Total number of categories containing the mutated node
# 8)Total number of requests containing the mutated node
#
# As output, it will yield as info about the combined ranked results file:
#   * Number of false-positive virtual categories
#     "" requests
#   * Number of virtual categories identified as response-time mutations, but
#    for which the relevant mutated edge was not identified
#     "" requests
#   * Total number of virtual categories
#     "" requests
#   * NCDG value

# It will also yield coverage information: 
#   * Percent of total categories identified correctly
#     "" requests
#
# And information about the mutated edge:
#   * Avg. S0 latency of mutated edge
#   * Avg. S1 latency of mutated edge.
##

#### Package declarations ################

use strict;
use warnings;
use diagnostics;
use Test::Harness::Assert;
use Getopt::Long;

use lib '../lib/';
use ParseDot::DotHelper qw[parse_nodes_from_file];
use List::Util qw(sum);


#### Global variables ####################

#####
# The input files
#####
my $g_combined_ranked_results_file;
my $g_originating_clusters_file;
my $g_not_interesting_clusters_file;

# The node before which the response-time mutation was induced
my $g_mutation_node;

# Another before which the response-time mutation can be induced
my $g_mutation_node_2;

######
# General accounting information about each cluster
######
my %g_already_seen_clusters;
my $g_total_s1_reqs = 0;
my $g_num_categories_with_mutated_node = 0;
my $g_num_requests_with_mutated_node = 0;
my $g_avg_s0_edge_latency = 0;
my $g_avg_s1_edge_latency = 0;
my $g_num_s0_edges_found = 0;
my $g_num_s1_edges_found = 0;
my $g_avg_s0_edge_var = 0;
my $g_avg_s1_edge_var = 0;
my $g_avg_edge_p_value = 0;
my $g_num_p_values = 0;

my $g_s0_response_time = 0;
my $g_s1_response_time = 0;


#####
# These variables are computed when analyzing the combined
# ranked results file.
#####
my $g_num_virtual_requests = 0;
my %g_num_virtual_categories_false_positives = ( RESPONSE_TIME => 0, STRUCTURAL => 0);
my %g_num_virtual_requests_false_positives = ( RESPONSE_TIME => 0, STRUCTURAL => 0);
my $g_num_virtual_relevant_categories = 0;
my $g_num_virtual_relevant_requests = 0;
my $g_num_virtual_categories_edge_not_identified = 0;
my $g_num_virtual_requests_edge_not_identified = 0;
my @g_combined_ranked_results_bitmap;


###### Private functions #######

##
# Prints input options
##
sub print_options {
    print "perl eval_response_time_mutation_identification.pl\n";
    print "\tcombined_ranked_results_file: File containing combined ranked results\n";
    print "\toriginators_file: File containing the originators\n";
    print "\tnot_interesting_file: File containing not interesting clusters\n";
    print "\tmutation_node: The name of the node before which the response-time mutation was induced\n";
    print "\tmutation_node_2: The name of the second node before which the response-time mutation was induced\n";
}


##
# Get input options
##
sub get_options {
    
    GetOptions("combined_ranked_results_file=s"  => \$g_combined_ranked_results_file,,
               "originators_file=s"              => \$g_originating_clusters_file,
               "not_interesting_file=s"          => \$g_not_interesting_clusters_file,
               "mutation_node=s"                 => \$g_mutation_node,
               "mutation_node_2=s"               => \$g_mutation_node_2);   
     
    
    if(!defined $g_combined_ranked_results_file || 
        !defined $g_originating_clusters_file || 
       !defined $g_not_interesting_clusters_file ||
        !defined $g_mutation_node) {

        print_options();
        exit(-1);
    }
}


##
# Calculate base2 logarithm
#
# @param val: Will calculate log2(val)
# @return: log2(val)
##
sub log2 {
    assert(scalar(@_) == 1);
    my ($val) = @_;

    return log($val)/log(2);
}


##
# Parses the edges of a cluster representative to find instances where the
# mutation node is the destination node.  Checks to see if these edges are marked
# as response-time mutations.  
#
# @param fh: The filehandle of the file that contains the cluster rep
# @param node_name_hash: Hash containing IDs to node names.
#
# @return: A pointer to a hash with elements:
#    NODE_FOUND: 1 if the node was found as a destination edge
#    IS_MUTATION: 1 if the dest edge was identified as a mutation
#    S0_LATENCIES: if NODE_FOUND is 1, this contains a reference
#    to a pointer containing the array of s0 edge latencies for the dest edge
#    S1_LATENCIES: if NODE_COUNT is 1, this contains a reference
#    to a pointer containing th earray of s1 edge latencies for the dest edge
##
sub find_edge_mutation {
    my ($fh, $node_name_hash) = @_;

    my $found = 0;
    my $is_mutation = 0;
    my @s0_edge_latencies;
    my @s1_edge_latencies;
    my @s0_edge_variances;
    my @s1_edge_variances;
    my @p_values;

    while (<$fh>) {
        
        if(/(\d+)\.(\d+) \-> (\d+)\.(\d+) \[color=\"\w+\" label=\"p:([-0-9\.]+)\\n.*a: ([-0-9\.]+)us \/ ([-0-9\.]+)us.*s: ([-0-9\.]+)us \/ ([0-9\.]+)us/) {
            my $src_node_id = "$1.$2";
            my $dest_node_id = "$3.$4";
            my $p = $5;
            my $s0_edge_latency = $6;
            my $s1_edge_latency = $7;
            my $s0_stddev = $8;
            my $s1_stddev = $9;
            my $src_node_name = $node_name_hash->{$src_node_id};
            my $dest_node_name = $node_name_hash->{$dest_node_id};
            
            if ($dest_node_name =~ /$g_mutation_node/) {#|| $dest_node_name =~ /$g_mutation_node_2/) {
                $found = 1;
                print "Relevant edge found: $s0_edge_latency $s1_edge_latency\n";
                if ($s0_edge_latency > 0) { push(@s0_edge_latencies, $s0_edge_latency);}
                if ($s1_edge_latency > 0) { push(@s1_edge_latencies, $s1_edge_latency);}
                if ($s0_edge_latency > 0) {push(@s0_edge_variances, $s0_stddev*$s0_stddev)};
                if ($s1_edge_latency > 0) {push(@s1_edge_variances, $s1_stddev*$s1_stddev)};

                if ($p < 0.05 && $p >= 0) {
                    $is_mutation = 1;
                }
                if($p >= 0) {
                    push(@p_values, $p);
                }
            }
        } else {
            last;
        }
    }

    return ({NODE_FOUND => $found, IS_MUTATION => $is_mutation, 
             S0_LATENCIES => \@s0_edge_latencies, S1_LATENCIES => \@s1_edge_latencies,
             S0_VARIANCES => \@s0_edge_variances, S1_VARIANCES => \@s1_edge_variances,
             P_VALUES => \@p_values});
}


##
# Updates accounting information about the number of categories and requests
# that contain the mutation node.  Should be called once per category.
#
# @param s1_reqs: The number of requests from s1 in the category
# @param mutation_info: Information about whether the category contains requests that
# contain the mutation node.
##
sub update_mutation_accounting_info {
    assert(scalar(@_) == 4);
    my ($s1_reqs, $mutation_info, $s0_response_time, $s1_response_time) = @_;
    
    my $s0_edge_latencies = $mutation_info->{S0_LATENCIES};
    my $s1_edge_latencies = $mutation_info->{S1_LATENCIES};

    my $s0_edge_variances = $mutation_info->{S0_VARIANCES};
    my $s1_edge_variances = $mutation_info->{S1_VARIANCES};

    my $p_values = $mutation_info->{P_VALUES};

    if (scalar(@{$s0_edge_latencies}) > 0) { 
        $g_avg_s0_edge_latency = ($g_avg_s0_edge_latency * $g_num_s0_edges_found + sum(0, @{$s0_edge_latencies}))/
            ($g_num_s0_edges_found + scalar(@{$s0_edge_latencies}));
        $g_num_s0_edges_found += scalar(@{$s0_edge_latencies});
    }

    if (scalar(@{$s0_edge_variances}) > 0) {
        $g_avg_s0_edge_var = ($g_avg_s0_edge_var * $g_num_s0_edges_found + sum(0, @{$s0_edge_variances}))/
            ($g_num_s0_edges_found + scalar(@{$s0_edge_variances}));
    }

    if (scalar(@{$s1_edge_latencies}) > 0) {
        $g_avg_s1_edge_latency = ($g_avg_s1_edge_latency * $g_num_s1_edges_found + sum(0, @{$s1_edge_latencies}))/
            ($g_num_s1_edges_found + scalar(@${s1_edge_latencies}));
        $g_num_s1_edges_found += scalar(@{$s1_edge_latencies});
    }

    if (scalar(@{$s1_edge_variances}) > 0) {
        $g_avg_s1_edge_var = ($g_avg_s1_edge_var * $g_num_s1_edges_found + sum(0, @{$s1_edge_variances}))/
            ($g_num_s1_edges_found + scalar(@${s1_edge_variances}));
    }


    if (scalar(@{$p_values}) > 0) {
        $g_avg_edge_p_value = ($g_avg_edge_p_value * $g_num_p_values + sum(0, @{$p_values}))/
            ($g_num_p_values + scalar(@${p_values}));
        $g_num_p_values += scalar(@{$p_values});
    }
    
    $g_s0_response_time += $s0_response_time;
    $g_s1_response_time += $s1_response_time;
    $g_num_categories_with_mutated_node++;
    $g_num_requests_with_mutated_node += $s1_reqs;
}

    
##
# Parses the combined ranked results file and extracts information
# necessary to extract the number of relevant virtual categories and
# requests, the number of false-positives, and the NDCG value.
#
# @param cluster_id: The cluster_id
# @param mutation_type: The specific mutation of this result
# @param cost: The cost of this virtual mutation category
# @param overall_mutation_type: The overall mutation category type
# @param p_value: The p-value of ths virtual mutation category
# @param s1_reqs: The number of requests from s1 in this virtual
# @param mutation_info: Information about whether this virtual category contains
# requests that contain the mutation node
##
sub compute_combined_ranked_results_stats {
    assert(scalar(@_) == 7);

    my ($cluster_id, $mutation_type, 
        $cost, $overall_mutation_type,
        $p_value, $s1_reqs, $mutated_info) = @_;

    # Determine if this is a response-time mutation
    my $is_response_time_mutation = ($mutation_type =~ /Response/i);

    # Increment the number of 'virtual requests'
    $g_num_virtual_requests += $s1_reqs;

    # Case where we have a structural mutation --- this is a false positive
    if ($is_response_time_mutation == 0) {
        $g_num_virtual_categories_false_positives{STRUCTURAL}++;
        $g_num_virtual_requests_false_positives{STRUCTURAL} += $s1_reqs;
        push(@g_combined_ranked_results_bitmap, -1);

        return;
    }

    # Virtual category contains response-time mutations

    if ($mutated_info->{NODE_FOUND} == 0) {
        # Case where we have identified a response-time mutation, but it does
        # not contain the mutated node
        $g_num_virtual_categories_false_positives{RESPONSE_TIME}++;
        $g_num_virtual_requests_false_positives{RESPONSE_TIME} += $s1_reqs;
        push(@g_combined_ranked_results_bitmap, 0);

    } elsif ($mutated_info->{NODE_FOUND} == 1 && 
              $mutated_info->{IS_MUTATION} == 0) {
        # Weird case where a category containing the mutated node
        # is identified as a response-time mutation, but the specific
        # edge we care about is not
        $g_num_virtual_categories_edge_not_identified++;
        $g_num_virtual_requests_edge_not_identified += $s1_reqs;
        push(@g_combined_ranked_results_bitmap, 0);

    } elsif($mutated_info->{NODE_FOUND} == 1 &&
            $mutated_info->{IS_MUTATION} == 1) {
        # Case where the category is identified as a response-time
        # mutation, 
        $g_num_virtual_relevant_categories++;
        $g_num_virtual_relevant_requests += $s1_reqs;
        push(@g_combined_ranked_results_bitmap, 1);
    }
}


##                                          
# Parses categories in the input file
#
# @param file: The file to process
# @param is_combined_ranked_results_file: is this the combined ranked results file?
##
sub handle_requests {
    assert(scalar(@_) == 2);
    my ($file, $is_combined_ranked_results_file) = @_;

    open(my $input_fh, "<$file") or 
        die("Could not open $file");
    
    while (<$input_fh>) {
        
        my $cluster_id;
        my $mutation_type;
        my $cost;
        my $overall_mutation_type;
        my $p_value;
        my $s1_reqs;
        my $s0_avg_time;
        my $s1_avg_time;
        my %node_name_hash;
        
        if(/Cluster ID: (\d+).+Specific Mutation Type: ([\w\s]+).+Cost: ([-0-9\.]+)\\nOverall Mutation Type: ([\w\s]+).*Avg\. response times: (\d+) us ; (\d+) us.+P-value: ([-0-9\.+]).*requests: \d+ ; (\d+)/) {
            
            $cluster_id = $1;
            $mutation_type = $2;
            $cost = $3;
            $overall_mutation_type = $4;
            $s0_avg_time = $5;
            $s1_avg_time = $6;
            $p_value = $7;
            
            $s1_reqs = $8;
            my %node_name_hash;

            if ($is_combined_ranked_results_file && $cost <= 0) {
               next;
           } 
            
            DotHelper::parse_nodes_from_file($input_fh, 1, \%node_name_hash);

            my $mutation_info = find_edge_mutation($input_fh, \%node_name_hash);
            
            if($is_combined_ranked_results_file) {
                compute_combined_ranked_results_stats($cluster_id, $mutation_type, 
                                                      $cost, $overall_mutation_type,
                                                      $p_value, $s1_reqs, $mutation_info);
            }
            # If this cluster was never seen before, add to s1 totals
            if (!defined $g_already_seen_clusters{$cluster_id}) {
                if ($mutation_info->{NODE_FOUND} == 1) {
                    update_mutation_accounting_info($s1_reqs, $mutation_info, $s0_avg_time, $s1_avg_time);
                }
                $g_total_s1_reqs += $s1_reqs;
            }
            $g_already_seen_clusters{$cluster_id} = 1;
        }
        else {
            if(/Cluster ID: (\d+)/) {
                print "PROBLEM: $_\n";
            }
            next;
        }
    }
    
    # Close current input file
    close($input_fh);
}


##
# computes the DCG value.  It is computed as: 
# rel_p = rel_0 + sum(1, p, rel_i/log(i+1))
#
# @param results_bitmap: Pointer to an array of 1s and 0s indicating whether the
# corresponding position in the ranked results file was relevant
##
sub compute_dcg {
    assert(scalar(@_) == 1);
    my ($results_bitmap) = @_;

    my $score = $results_bitmap->[0];

    for(my $i = 1; $i < scalar(@{$results_bitmap}); $i++) {
        my $contrib = ($results_bitmap->[$i] == 1)? 1: 0;
        $score += $contrib/log2($i+1);
    }

    return $score;
}


##### Functions to print out results ####

##
# Prints category-level statistics
##
sub print_category_level_info {
    
    my $num_categories = keys %g_already_seen_clusters;
    my $num_virtual_categories = scalar(@g_combined_ranked_results_bitmap);
    
    ### Category-level information ####
    print "Category-level information\n";
    print "Total Number of categories: $num_categories\n";
    print "Total Number of Virtual categories: $num_virtual_categories\n";

   # Precision info
    my $false_positive_categories = $g_num_virtual_categories_false_positives{STRUCTURAL} + 
        $g_num_virtual_categories_false_positives{RESPONSE_TIME};

    printf "Number/Fraction of categories in the ranked results that are false-positives: %d (%3.2f)\n", 
    $false_positive_categories,
    $false_positive_categories/$num_virtual_categories;

    printf "Fraction of structural mutation categories in the ranked results that are false-positives: %d, (%3.2f)\n",
    $g_num_virtual_categories_false_positives{STRUCTURAL},
    $g_num_virtual_categories_false_positives{STRUCTURAL}/$num_virtual_categories;

    printf "Fraction of response-time mutation categories in the ranked results that are false-positives: %d, (%3.2f)\n",
    $g_num_virtual_categories_false_positives{RESPONSE_TIME},
    $g_num_virtual_categories_false_positives{RESPONSE_TIME}/$num_virtual_categories;
    
    printf "Number/fraction of categories in the ranked results that were identified as\n" .
        " Response-time mutations, but for which the edge was not identified: %d (%3.2f)\n",
        $g_num_virtual_categories_edge_not_identified,
        $g_num_virtual_categories_edge_not_identified/$num_virtual_categories;

    # Compute dcg
    my $dcg = compute_dcg(\@g_combined_ranked_results_bitmap);
    my @best_results = sort {$b <=> $a} @g_combined_ranked_results_bitmap;
    my $normalizer = compute_dcg(\@best_results);
    if ($normalizer == 0) {
        printf "The nDCG is zero: $dcg, $normalizer\n";
    } else {
        printf "The NDCG value: %3.3f\n", $dcg/$normalizer;
    }

    # Coverage info: 
    printf "Total number of categories that contain mutated node: %d\n",
    $g_num_categories_with_mutated_node;
    
    printf "Total number of categories with mutated node identified as a response-time mutations: %3.2f\n\n",
    $g_num_virtual_relevant_categories/$g_num_categories_with_mutated_node;

    printf "Average response time of categories with mutated node: %3.2f, %3.2f",
    $g_s0_response_time/$g_num_categories_with_mutated_node, $g_s1_response_time/$g_num_categories_with_mutated_node;

    print "Ranked-results bitmap\n";
    print @g_combined_ranked_results_bitmap;

    print "\n\n";
}


##
# Prints request-level statistics
##
sub print_request_level_info {
    ### Request-level information ####
    print "Request-level information\n";
    
    printf "Total number of s1 requests: %d\n", 
    $g_total_s1_reqs;
    
    my $num_virtual_requests = 
        $g_num_virtual_requests_false_positives{STRUCTURAL} + 
        $g_num_virtual_requests_false_positives{RESPONSE_TIME} +
        $g_num_virtual_relevant_requests + 
        $g_num_virtual_requests_edge_not_identified;
    
    printf "Total number of virtual requests identified: %d\n",
    $num_virtual_requests;
    
    ### Precision info
    my $false_positives = $g_num_virtual_requests_false_positives{STRUCTURAL} + 
        $g_num_virtual_requests_false_positives{RESPONSE_TIME};
    
    printf "Number/fraction of results identified that are false-positives: %d (%3.2f)\n",
    $false_positives, 
    ($false_positives/$num_virtual_requests);
    
    printf "Number/fraction of structural mutation requests that are false positives: %d (%3.2f)\n",
    $g_num_virtual_requests_false_positives{STRUCTURAL},
    $g_num_virtual_requests_false_positives{STRUCTURAL}/$num_virtual_requests;
    
    printf "Number/fraction of response-time mutation requests that are false positives: %d (%3.2f)\n",
    $g_num_virtual_requests_false_positives{RESPONSE_TIME},
    $g_num_virtual_requests_false_positives{RESPONSE_TIME}/$num_virtual_requests;
    
    printf "Number/fraction of requests contained in the results, that were identified\n" .
        " as response-time mutations, for for which the right edge was not identified: %d (%3.2f)\n",
        $g_num_virtual_requests_edge_not_identified,
        ($g_num_virtual_requests_edge_not_identified/$num_virtual_requests);
    
    printf "Total number of requests that contain the mutated node: %d\n",
    $g_num_requests_with_mutated_node;
    
    ### Coverage info: 
    printf "Fraction of requests with mutated node identified as a response-time mutation: %3.2f\n\n",
    $g_num_virtual_relevant_requests/$g_num_requests_with_mutated_node;
}


##
# Print edge-level info
##
sub print_edge_level_info {
    
    ### Edge information
    print "Edge-level information\n";
    printf "Average s0 latency of edges containing the mutation node: %3.2f\n",
    $g_avg_s0_edge_latency;
    
    printf "Average s1 latency of edges containing the mutation node: %3.2f\n\n",
    $g_avg_s1_edge_latency;

    printf "Average variance of edges containing the mutation node in s0: %3.2f\n",
    $g_avg_s0_edge_var;

    printf "Average variance of edges containing the mutation node in s1: %3.2f\n",
    $g_avg_s1_edge_var;

    printf "Average p-value of edges containing the mutation node: %3.2f\n",
    $g_avg_edge_p_value;
        
}


##### Main routine ######

get_options();

handle_requests($g_combined_ranked_results_file, 1);
handle_requests($g_originating_clusters_file, 0);
handle_requests($g_not_interesting_clusters_file, 0);

print_category_level_info();
print_request_level_info();
print_edge_level_info();
















    

    


