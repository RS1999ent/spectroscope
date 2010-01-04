#!/usr/bin/perl -w

# $cmuPDL: spectroscope.pl,v, #

##
# @author Raja Sambasivan
#
# Given the Spectroscope results and a mutated node just before which a
# response-time mutation was induced, this code will evaluate the quality of the
# spectroscope results.  Specifically, it will determine:
#
# 1)Total number of categories that represent response-time mutations
#
# 2)Fraction of categories identified that are false positives 
#
# 3)Average P-Value of the false positives
# 
# 4)Total number of categories that contain the mutated node
#
# 5)Total number of categories with the mutated node identified as a response-time mutation
#
# 6)Avg. P-Value of correctly identified categories
##

#### Package declarations ################

use strict;
use warnings;
use diagnostics;
use Test::Harness::Assert;
use Getopt::Long;

use lib '../lib/';
use ParseDot::DotHelper qw[parse_nodes_from_file];


#### Global variables ####################

my $g_mutation_node;

# File containing response-time mutations
my $g_response_time_mutation_file;

# File containing structural mutations
my $g_structural_mutation_file;

# File containing originating cluster
my $g_originating_cluster_file;

# File containing 'not-interesting' clusters
my $g_not_interesting_cluster_file;

# A hash of clusters that have already been seen in a previous file
my %already_seen_clusters;

# Total number of requests in snapshot 1
my $g_total_s1_reqs = 0;


# The number of categories identified as response-time mutations
my $g_num_response_time_mutation_categories = 0;

# The number of requests identified as response-time mutations
my $g_num_response_time_mutation_requests = 0;


# The number of categories that contain the mutated node
my $g_num_categories_with_mutated_node = 0;

# The number of requests in categories that contain teh mutated node
my $g_num_requests_with_mutated_node = 0;


# Number of categories that are response-time mutations, but do not contain the offending node
my $g_num_category_false_positives = 0;

# Average p-value of the false positives
my $g_avg_p_value_false_positives = 0;

# Number of requests that correspond to false positive categories
my $g_num_requests_false_positives = 0;


# Number of categories that are correctly identified as response-time mutations
my $g_num_categories_correctly_identified = 0;

# Average P-value of these correclty identified categories
my $g_avg_p_values_correct = 0;

# Number of requests that correspond to correctly identified categories
my $g_num_requests_correctly_identified = 0;


###### Private functions #######

sub print_options {
    print "perl eval_response_time_mutation_quality.pl\n";
    print "\tresponse_time_file: File containing response-time mutations\n";
    print "\tstructural_mutation_file: File containing structural mutations\n";
    print "\toriginators_file: File containing the originators\n";
    print "\tnot_interesting_file: File containing not interesting clusters\n";
    print "\tdest_node: The name of the node before which the response-time mutation was induced\n";
}


##
# Get input options
##
sub get_options {
    
    GetOptions("response_time_file=s"            => \$g_response_time_mutation_file,
               "structural_mutation_file=s"      => \$g_structural_mutation_file,
               "originators_file=s"              => \$g_originating_cluster_file,
               "not_interesting_file=s"          => \$g_not_interesting_cluster_file,
               "dest_node=s"                     => \$g_mutation_node);
    
    if (!defined $g_response_time_mutation_file || !defined $g_structural_mutation_file ||
        !defined $g_originating_cluster_file || !defined $g_not_interesting_cluster_file ||
        !defined $g_mutation_node) {

        print_options();
        exit(-1);
    }
}


##

# Parses the edges of a cluster representative to find instances where the
# mutated node is the destination node.  Checks to see if these edges are marked
# as response-time mutations.  
#
# @param fh: The filehandle of the file that contains the cluster rep
# @param node_name_hash: IDs to node names.
#
# @return: A pointer to a hash with two elements: 
#    NODE_FOUND: 1 if the node was found as a destination edge
#    IS_MUTATION: 1 if it was identified as a mutation
##
sub find_edge_mutation {
    my ($fh, $node_name_hash) = @_;

    my $found = 0;
    my $is_mutation = 0;

    while (<$fh>) {
        
        if(/(\d+)\.(\d+) \-> (\d+)\.(\d+) \[color=\"(\w+)\" label=\"p:([0-9\.]+)/) {
            my $src_node_id = "$1.$2";
            my $dest_node_id = "$3.$4";
            my $color = $5;
            my $p = $6;

            my $src_node_name = $node_name_hash->{$src_node_id};
            my $dest_node_name = $node_name_hash->{$dest_node_id};
            
            if ($dest_node_name =~ /$g_mutation_node/) {
                $found = 1;
                if ($p < 0.05 && $p >= 0) {
                    $is_mutation = 1;
                }
            }
        } else {
            last;
        }
    }

    return ({NODE_FOUND => $found, IS_MUTATION => $is_mutation});
}


##
# Parses requests.  Goes through each input file and collects the appropriate
# response-time mutation statistics.

#
# @param files_ref: A reference to an array of files to parse.
##
sub handle_requests {
    my ($files_ref) = @_;

    for (my $i = 0; $i < scalar(@{$files_ref}); $i++) {
        
        my $file = $files_ref->[$i];
        open(my $input_fh, "<$file") or 
            die("Could not open $file");

        while (<$input_fh>) {

            my $cluster_id;
            my $mutation_type;
            my $cost;
            my $overall_mutation_type;
            my $p_value;
            my $s1_reqs;
            my %node_name_hash;

            if(/Cluster ID: (\d+).+Specific Mutation Type: ([\w\s]+).+Cost: ([-0-9\.]+)\\nOverall Mutation Type: ([\w\s]+).+P-value: ([-0-9\.+]).*requests: \d+ ; (\d+)/) {

                $cluster_id = $1;
                $mutation_type = $2;
                $cost = $3;
                $overall_mutation_type = $4;
                $p_value = $5;
                $s1_reqs = $6;

                if (defined $already_seen_clusters{$cluster_id}) {
                    next;
                }
                    
                $already_seen_clusters{$cluster_id} = 1;
            } else {
                if(/Cluster ID: (\d+)/) {
                    print "PROBLEM: $_\n";
                }
                next;
            }
            
            # New cluster/category we have never seen before
            DotHelper::parse_nodes_from_file($input_fh, 1, \%node_name_hash);
            
            # Find the edge that's supposed to contain the response-time mutation
            my $info = find_edge_mutation($input_fh, \%node_name_hash);

            # Fill in appropriate counters;
            $g_total_s1_reqs += $s1_reqs;

            # Counter for the number of response-time mutations seen
            if ($mutation_type =~ /Response/) {
                $g_num_response_time_mutation_categories++;
                $g_num_response_time_mutation_requests += $s1_reqs;

            }

            # Counter for whether the category contains the offending edge
            if ($info->{NODE_FOUND}) {
                $g_num_categories_with_mutated_node++;
                $g_num_requests_with_mutated_node += $s1_reqs;
            }

            # Counter for whether the category was a false positive
            if(($mutation_type =~ /Response/) && ($info->{NODE_FOUND} == 0)) {
                $g_avg_p_value_false_positives = ($g_avg_p_value_false_positives*$g_num_category_false_positives + $p_value)/
                                                 ($g_num_category_false_positives + 1);
                $g_num_category_false_positives++;

                $g_num_requests_false_positives += $s1_reqs;
            }

            # Counter for whether the category was correctly identified
            if (($mutation_type =~/Response/) && ($info->{NODE_FOUND} == 1) && ($info->{IS_MUTATION} == 1)) {
                $g_avg_p_values_correct = ($g_avg_p_values_correct * $g_num_categories_correctly_identified + $p_value)
                                                  /($g_num_categories_correctly_identified + 1);
                $g_num_categories_correctly_identified++;
                $g_num_requests_correctly_identified += $s1_reqs;
            }
        }

    
        # Close current input file
        close($input_fh);
    }
}


##### Main routine ######

get_options();

my @files = ($g_response_time_mutation_file,
             $g_structural_mutation_file,
             $g_originating_cluster_file,
             $g_not_interesting_cluster_file);

handle_requests(\@files);

my $total_categories = keys %already_seen_clusters;

### Category-level information ####
print "Category-level information\n";
print "Total Number of categories: $total_categories\n";

printf "Total Number of categories that are response-time mutations: %d\n", 
    $g_num_response_time_mutation_categories;

printf "Fraction of categories identified that are false-positives: %3.2f\n", 
    $g_num_category_false_positives/$g_num_response_time_mutation_categories;

printf "Avg. P-Value of false positives: %10.6f\n",
    $g_avg_p_value_false_positives;

printf "Total number of categories that contain mutated node: %d\n",
    $g_num_categories_with_mutated_node;

printf "Total number of categories with mutated node identified as a response-tiem mutations: %3.2f\n",
    $g_num_categories_correctly_identified/$g_num_categories_with_mutated_node;

printf "Avg. P-value of correctly identified categories: %10.6f\n\n",
    $g_avg_p_values_correct;


### Request-level information ####
print "Request-level information\n";

printf "Total number of s1 requests: %d\n", 
    $g_total_s1_reqs;

printf "Total number of requests contained in response-time mutation categories: %d\n",
    $g_num_response_time_mutation_requests;

printf "Fraction of requests identified that are false-positives: %3.2f\n",
    $g_num_requests_false_positives/$g_num_response_time_mutation_requests;

printf "Total number of requests that contain the mutated node: %d\n",
    $g_num_requests_with_mutated_node;

printf "Total number of requests with mutated node identified as a response-time mutation: %3.2f\n\n",
    $g_num_requests_correctly_identified/$g_num_requests_with_mutated_node;





    

    


