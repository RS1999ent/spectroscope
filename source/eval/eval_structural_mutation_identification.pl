#! /usr/bin/perl -w

# $cmuPDL: eval_structural_mutation_identification.pl,v 1.6 2010/04/21 16:20:30 rajas Exp $

##
# @author Raja Sambasivan
#
# Given the Spectroscope results, a "mutated edge" and a "predecessor edge,"
# this perl script will evaluate the quality of the Spectroscope results for
# structural mutations.
#
# Note that the results output by Spectroscope include 'virtual categories.'  A
# single category can appear twice in the results.
#
# As output, this function will yield info about the following: 
#
#  Information about requests: 
#    * Number/fraction of virtual requests that are false-positives (false positive rate)
#    * Number/fraction of structural mutation virtual requests that are false-positives
#    * Number/fraction of response-time mutation virtual requests that are false-positives
#    * Number/fraction of requests with the mutated edge identified as structural mutations 
#      (1 - false negative rate)
#
# Information about categories
#   * Number/fraction of virtual categories identified that are false-positivessm
#   * Number/fraction of virtual structural mutation virtual categories that are false positives
#   * Number/fraction of response-time mutation virtual categories that are false positives
#   * Number/fraction of categories with the mutated edge identified as structural mutations 
#     (1 - false negative rate)
#
# Also computed is the nDCG value.  Also a bitmap indicating ranks of relevant
# results is also output.  A 1 in position N of this bitmap indicates a relevant
# result; a 0, a non-relevant result, and a -1, a non-relevant response-time
# mutation.
##

##### Package declarations #####

use strict;
use warnings;
use diagnostics;
use Test::Harness::Assert;
use Getopt::Long;
use List::Util qw(min);

use lib '../lib/';
use ParseDot::DotHelper qw[parse_nodes_from_file];


##### Global variables ####

# File containing the ranked results
my $g_combined_ranked_results_file;

# File containin gorigiantors
my $g_originating_clusters_file;

# Hash mapping byte indexes to cluster IDs in teh originators file
my %g_originators_byte_idx;

# File containing not interesting clusters
my $g_not_interesting_clusters_file;

# The mutated edge (this is the edge that 'changed' in structural mutations)
my $g_mutated_edge;

# The originating edge (this is what the mutated edge used to look like in the originators)
my $g_originator_edge;

# For each category containing structural mutations, this is the lowest ranked
# candidate originator cluster that will be examined to see if it contains the
# originator edge
my $g_lowest_ranked_originator_to_examine = 0;

my $g_threshold = 1;


###
# General accounting information about eachcluster
###
my %g_already_seen_clusters;
my $g_total_s1_reqs = 0;
my $g_num_clusters_with_mutated_edge = 0;
my $g_num_requests_with_mutated_edge = 0;

####
# These variables are computed when analyzing the combined
# ranked results file
####
my $g_num_virtual_requests = 0;
my %g_num_virtual_clusters_false_positives = ( RESPONSE_TIME => 0, STRUCTURAL => 0);
my %g_num_virtual_requests_false_positives = ( RESPONSE_TIME => 0, STRUCTURAL => 0);
my $g_num_virtual_relevant_clusters = 0;
my $g_num_virtual_relevant_requests = 0;
my $g_num_virtual_clusters_originator_not_ided = 0;
my $g_num_virtual_requests_originator_not_ided = 0;
my @g_combined_ranked_results_bitmap;

##### Functions #####

##
# Prints usage
##
sub print_usage {
    print "perl eval_structural_mutation_identification.pl\n";
    print "\tcombined_ranked_results_file: File containing combined ranked results\n";
    print "\toriginators_file: File containing the originators\n";
    print "\tnot_interesting_file: File containing not interesting clusters\n";
    print "\tmutated_edge: Edge that is the root cause of the mutation\n";
    print "\toriginator_edge: What the mutated edge originated from\n";
    print "\tlowest_ranked_originator: For each mutation category, this is the lowest\n";
    print "\t\tthat will be examined to see if it contains the originator edge (OPTIONAL)\n";
    print "\tthreshold: Minimum number of edges of the type specified that must be found\n";
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
# Get input options
##
sub get_options {

    GetOptions("combined_ranked_results_file=s"  => \$g_combined_ranked_results_file,
               "originators_file=s"              => \$g_originating_clusters_file,
               "not_interesting_file=s"          => \$g_not_interesting_clusters_file,
               "mutated_edge=s"                  => \$g_mutated_edge,
               "originator_edge=s"              => \$g_originator_edge,
               "lowest_ranked_originator:i"      => \$g_lowest_ranked_originator_to_examine,
               "threshold:i"                     => \$g_threshold);

    if (!defined $g_combined_ranked_results_file || !defined $g_originating_clusters_file
        || !defined $g_not_interesting_clusters_file || !defined $g_mutated_edge ||
        !defined $g_originator_edge || !defined $g_lowest_ranked_originator_to_examine) {
        print_usage();
        exit(-1);
    }
}


##
# This function is called for each virtual cluster in the ranked results file.
# It computes statistics about the cluster --- whether the cluster is relevant
# to the injected problem, whether it is a false positive, etc.
#
# @param cluster_id: The ID of the virtual cluster being examined
# @param mutation_type: The specific mutation type of the virtual cluster
# @param mutation_edge_found: Whether this virtual cluster contains the mutated edge
# @param originator_edge_found: Whether candidate originators of this edge contain
#  the originator edge (what the mutated edge used to look like in the non-problem period)
# @param s1_reqs: The number of requests contained in this cluster from s1
##
sub compute_combined_ranked_results_stats {
    assert(scalar(@_) == 5);
    my ($cluster_id, $mutation_type, 
        $mutation_edge_found, 
        $originator_edge_found, $s1_reqs) = @_;

    # Determine if this is a structural mutation
    my $is_structural_mutation = ($mutation_type =~ /structural/i);

    # Increment the number of 'virtual requests'
    $g_num_virtual_requests += $s1_reqs;

    # Case where we have a response-time mutation --- this is a false positive
    if ($is_structural_mutation == 0) { 
        $g_num_virtual_clusters_false_positives{RESPONSE_TIME}++;
        $g_num_virtual_requests_false_positives{RESPONSE_TIME} += $s1_reqs;
        push(@g_combined_ranked_results_bitmap, -1);
        
        return;
    }
    
    # The virtual cluster contains structural mutations
    if ($mutation_edge_found == 0) {
        # A structural mutation was identified, but it does not contain the mutated edge
        $g_num_virtual_clusters_false_positives{STRUCTURAL}++;
        $g_num_virtual_requests_false_positives{STRUCTURAL} += $s1_reqs;
        push(@g_combined_ranked_results_bitmap, 0);

    } else {
        if ($originator_edge_found == 0) { 
            # Case where category contains the mutated edge, but its originators
            # do not contain what the mutated edge looked like in the non-problem period
            $g_num_virtual_clusters_originator_not_ided++;
            $g_num_virtual_requests_originator_not_ided += $s1_reqs;
            push(@g_combined_ranked_results_bitmap, 0);
        } else {
            # Case where category contains the mutated edge and its originator(s) contain
            # what that edge looked like in the non-problem period
            $g_num_virtual_relevant_clusters++;
            $g_num_virtual_relevant_requests += $s1_reqs;
            push(@g_combined_ranked_results_bitmap, 1);
        }
    }
}


##
# Updates accounting info about the number of categories and requests that
# contain the mutated edge
#
# @param mutation_edge_found: Whether the category contains the mutated edge
# @param s1_reqs: The number of requests in s1 that belong to the category
##
sub update_mutation_accounting_info {
    assert(scalar(@_) == 2);
    my ($mutation_edge_found, $s1_reqs) = @_;

    if ($mutation_edge_found) {
        $g_num_clusters_with_mutated_edge++;
        $g_num_requests_with_mutated_edge += $s1_reqs;
    }
}    


##
# Builds in index mapping byte offset -> location of an originating cluster in
# $g_originating_clusters_file and stores it in $g_originators_byte_idx
##
sub build_index_on_originators_file {
    
    open(my $fh, "<$g_originating_clusters_file") or
        die("Could not open $g_originating_clusters_file");

    my $old_offset = 0;

    while(<$fh>) {

        if (/\# \d+  R: [0-9\.]+/) {
            # This is the start of a new request

            # Skip the 'Digraph G {' line
            $_ = <$fh>;

            # Next line should be information about this cluster
            $_ = <$fh>;            
            assert(/Cluster ID: (\d+)/);
            
            $g_originators_byte_idx{$1} = $old_offset;
        } else {
            $old_offset = tell($fh);
        }
    }
    close($fh);
}


##
# Given a filehandle of a file that contains DOT graphs and whose current offset
# points to the edges of a specific graph, this function attempts to find an edge
# in that graph that matches the edge passed in
#
# @param fh: The filehandle
# @param node_name_hash_ref: A reference to a hash mapping node ids to node names
# @param search_edge: The edge to be found
#
# @return: 1 if the edge is found, 0 otherwise
##
sub search_for_edge_in_graph {
    assert(scalar(@_) == 4);
    my ($fh, $node_name_hash_ref, $search_edge, $threshold) = @_;

    my $count = 0;

    while (<$fh>) {
        if(/(\d+)\.(\d+) \-> (\d+)\.(\d+) \[color=\"(\w+)\" label=\"p:([-0-9\.]+)\\n.*a: ([-0-9\.]+)us \/ ([-0-9\.]+)us/) {
            my $src_node_id = "$1.$2";
            my $dest_node_id = "$3.$4";
            my $src_node_name = $node_name_hash_ref->{$src_node_id};
            my $dest_node_name = $node_name_hash_ref->{$dest_node_id};
            my $edge = "$src_node_name->$dest_node_name";

            if( $edge =~ /$search_edge/) { 
                $count++;
            }
        } else {
            last;
        }
    }

    if ($count >= $threshold) {
        return 1;
    }

    return 0;
}


##
# Given a list of originating clusters, this function indexes into the
# $g_originating_clusters_file, retreives the graph for each cluster, and
# examines it to see if it can find the edge passed in
#
# @param originators_array_ref: A reference to an array of cluster IDs of originators
# @param last_rank_to_explore: Only originators up to this rank will be explored
# @param search_edge: The edge to find
##
sub find_edge_in_originator {
    assert(scalar(@_) == 3);
    my ($originators_array_ref, $last_rank_to_explore, $search_edge) = @_;
    
    my $found = 0;

    # Open the originators file
    open (my $fh, "<$g_originating_clusters_file") or
        die("Could not open $g_originating_clusters_file");

    $last_rank_to_explore = ($last_rank_to_explore == 0) ? 
        scalar(@{$originators_array_ref}) : min($last_rank_to_explore, scalar(@{$originators_array_ref}));

    for (my $i = 0; $i < $last_rank_to_explore; $i++) {

        my $cid = $originators_array_ref->[$i];
        my $offset = $g_originators_byte_idx{$cid};        
        seek($fh, $offset, 0);
        
        # Read the header, the digraph line, and the cluster summary line
        $_ = <$fh>; $_ = <$fh>; $_ = <$fh>;
        
        my %node_name_hash;
        DotHelper::parse_nodes_from_file($fh, 1, \%node_name_hash);
        $found = search_for_edge_in_graph($fh, \%node_name_hash, $search_edge, 1);

        if ($found) {last};
    }

    return $found;
}
            


##
# Parses requests in different input files and builds up the metric values 
##
sub handle_requests {
    assert(scalar(@_) == 2);
    my($file, $is_combined_ranked_results_file) = @_;

    open(my $fh, "<$file") or die("Could not open file");

    while(<$fh>) {
        if(/Cluster ID: (\d+).+Specific Mutation Type: ([\w\s]+).+Cost: ([-0-9\.]+)\\nOverall Mutation Type: ([\w\s]+).+Candidate originating clusters: ([-\s\(\)0-9\.]*)\\n\\n.+P-value: ([-0-9\.+]).*requests: \d+ ; (\d+)/) {
            my $cluster_id = $1;
            my $mutation_type = $2;
            my $cost = $3;
            my $originators = $5;
            my $s1_reqs = $7;

            if($is_combined_ranked_results_file && $cost <= 0) {
                next;
            }

            $originators =~ s/\([-0-9\.]+\)//g;
            my @originators_array = split(' ', $originators);

            my %node_name_hash;
            DotHelper::parse_nodes_from_file($fh, 1, \%node_name_hash);
            my $mutation_edge_found = search_for_edge_in_graph($fh, \%node_name_hash, $g_mutated_edge, $g_threshold);

            my $originator_edge_found = find_edge_in_originator(\@originators_array, $g_lowest_ranked_originator_to_examine, 
                                                                $g_originator_edge);

            if ($is_combined_ranked_results_file) {
                compute_combined_ranked_results_stats($cluster_id, $mutation_type, 
                                                      $mutation_edge_found, $originator_edge_found, 
                                                      $s1_reqs);                
            }

            # If this cluster was never seen before, add to s1 totals
            if (!defined $g_already_seen_clusters{$cluster_id}) {
                update_mutation_accounting_info($mutation_edge_found, $s1_reqs);
                $g_total_s1_reqs += $s1_reqs;
                $g_already_seen_clusters{$cluster_id} = 1;
            }
        }
    }
    close($fh);
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


##
# Prints out request-level statistics
##
sub print_request_level_info {
    print "Request-level information\n";

    printf "Total number of s1 requests: %d\n", $g_total_s1_reqs;
    
    printf "Total number of virtual requests identified: %d\n", $g_num_virtual_requests;

    ### Precision info
    my $false_positives = $g_num_virtual_requests_false_positives{STRUCTURAL} + 
        $g_num_virtual_requests_false_positives{RESPONSE_TIME};

    printf "Number/fraction of virtual requests identified that are false-positives: %d (%3.2f)\n",
    $false_positives, $false_positives/$g_num_virtual_requests;

    printf "Number/fraction of structural mutation virtual requests that are false positives: %d (%3.2f)\n",
    $g_num_virtual_requests_false_positives{STRUCTURAL},
    $g_num_virtual_requests_false_positives{STRUCTURAL}/$g_num_virtual_requests;

    printf "Number/fraction of response-time mutation mutation virtual requests that are false positives: %d (%3.2f)\n",
    $g_num_virtual_requests_false_positives{RESPONSE_TIME},
    $g_num_virtual_requests_false_positives{RESPONSE_TIME}/$g_num_virtual_requests;

    printf "Number/fraction of virtual requests contained in the results, that were identified as\n" .
        "relevant structural mutations, but for which originators did not contain the originator edge: %d (%3.2f)\n\n",
        $g_num_virtual_requests_originator_not_ided, $g_num_virtual_requests_originator_not_ided/$g_num_virtual_requests;
    
    # Coverage info
    printf "Total number of requests that contain the mutated node: %d\n", $g_num_requests_with_mutated_edge;
    printf "Fraction of requests with mutated node identified as relevant: %3.2f\n", 
    $g_num_virtual_relevant_requests/$g_num_requests_with_mutated_edge;
}


##
# Prints out cluster (category-level) statistics
##
sub print_cluster_level_info {
    
    my $num_clusters = keys %g_already_seen_clusters;
    my $num_virtual_clusters = scalar(@g_combined_ranked_results_bitmap);
    
    ### Category-level information ####
    print "Cluster-level information\n";
    print "Total number of clusters: $num_clusters\n";
    print "Total number of virtual clusters: $num_virtual_clusters\n";

    # Precision info
    my $false_positive_clusters = $g_num_virtual_clusters_false_positives{STRUCTURAL} +
        $g_num_virtual_clusters_false_positives{RESPONSE_TIME};

    printf "Number/fraction of virtual clusters in the ranked results that are false-positives: %d (%3.2f)\n",
    $false_positive_clusters, $false_positive_clusters/$num_virtual_clusters;

    printf "Number/fraction of virtual structural mutation clusters in the ranked results\n" .
        "that are false posities: %d (%3.2f)\n", 
        $g_num_virtual_clusters_false_positives{STRUCTURAL}, 
        $g_num_virtual_clusters_false_positives{STRUCTURAL}/$num_virtual_clusters;

    printf "Number/fraction of virtual response-time mutation categories in the ranked results that are\n" .
        "false positives: %d (%3.2f)\n",
        $g_num_virtual_clusters_false_positives{RESPONSE_TIME},
        $g_num_virtual_clusters_false_positives{RESPONSE_TIME}/$num_virtual_clusters;

    printf "Number/fraction of virtual categories that were identified as relevant\n" .
        "structural mutations, but for which originators did not contain the originator edge: %d (%3.2f)\n",
        $g_num_virtual_clusters_originator_not_ided, $g_num_virtual_clusters_originator_not_ided/$num_virtual_clusters;

    # Compute dcg
    my $dcg = compute_dcg(\@g_combined_ranked_results_bitmap);
    my @best_results = sort {$b <=> $a} @g_combined_ranked_results_bitmap;
    my $normalizer = compute_dcg(\@best_results);
    printf "The nDCG value: %3.3f\n", $dcg/$normalizer;

    # Coverage info: 
    printf "Total number of clusters that contain the mutated edge: %d\n",
    $g_num_clusters_with_mutated_edge;

    printf "Total number of categories with mutated edge identified as structural mutations: %3.2f\n",
    $g_num_virtual_relevant_clusters/$g_num_clusters_with_mutated_edge;

    print "Ranked-results bitmap\n";
    print @g_combined_ranked_results_bitmap;

    print "\n\n";
}


##### Main routine #####
get_options();
build_index_on_originators_file();

handle_requests($g_combined_ranked_results_file, 1);
handle_requests($g_originating_clusters_file, 0);
handle_requests($g_not_interesting_clusters_file, 0);
print_cluster_level_info();
print_request_level_info();


