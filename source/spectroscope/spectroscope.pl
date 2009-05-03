#!/usr/bin/perl -w

# $cmuPDL: spectroscope.pl,v 1.3 2009/04/26 23:48:44 source Exp $

##
# @author Raja Sambasivan and Alice Zheng
#
# Type perl spectroscope -h or ./spectroscope for help
##


#### Package declarations #########################

use strict;
use warnings;
use diagnostics;
use Test::Harness::Assert;

use Getopt::Long;

use lib '../lib';
use SedClustering::CreateClusteringInput;
use ParseDot::ParseRequests;
use ParseDot::PrintRequests;
use PassThrough::PassThrough;
use ParseClusteringResults::ParseClusteringResults;
use CompareEdges::CompareIndivEdgeDistributions;


#### Global variables ############################

# The directory in which output should be placed
my $g_output_dir;

# The directory the output of hte ConvertRequests module should be placed
my $g_convert_reqs_output_dir;

# The file containing DOT requests from the non-problem period
my $g_snapshot0_file;

# The file containing DOT requests from the problem period
my $g_snapshot1_file;

# If clustering is enabled, these parameters will be used as the 
# parameters for the clustering algorithm
my %g_clustering_params = ( MIN_K => 15,
                            MAX_K => 30,
                            K_INTERVAL => 5);

# Allow user to skip re-converting the input DOT files to the
# format required for this program, if this has been done before.
my $g_reconvert_reqs = 0;

# Allow user to "skip" clustering and simply group requests by
# structure
my $g_pass_through = 0;

# Specify the ranking of clusters for printing output
my $g_cluster_output_ranking;

# The module for converting requests into MATLAB compatible format
# for use in the clustering algorithm
my $g_create_clustering_input;

# The module for parsing requests
my $g_parse_requests;

# The names of the files that must be returned by the convert data script
#my %converted_req_names => (MATLAB_INPUT_VECTOR => "",
#                            MAPPING_FROM_INPUT_VECTOR_TO_GLOBAL_IDS => "",
#                            MAPPING_FROM_GLOBAL_IDS_TO_LOCAL_ID => "",
#                           DISTANCE_MATRIX => "");

#my %clustering_output_names => (CENTERS => "",
#                                ASSIGNMENTS => "",
#                                DISTANCES => "");
                                    

#### Main routine #########

# Get input arguments
parse_options();

if (defined $g_snapshot1_file) {
    $g_create_clustering_input = new CreateClusteringInput($g_snapshot0_file,
                                                           $g_snapshot1_file,
                                                           $g_convert_reqs_output_dir);

    $g_parse_requests = new ParseRequests($g_snapshot0_file,
                                          $g_snapshot1_file,
                                          $g_convert_reqs_output_dir);
} else {
    $g_create_clustering_input = new CreateClusteringInput($g_snapshot0_file,
                                                           $g_convert_reqs_output_dir);

    $g_parse_requests = new ParseRequests($g_snapshot0_file,
                                          $g_snapshot1_file,
                                          $g_convert_reqs_output_dir);
}

## Determine whether indices and the matlab clustering input
# needs to be re-created.
#
my $clustering_output_files_exist = $g_create_clustering_input->do_output_files_exist();
my $parse_requests_files_exist = $g_parse_requests->do_output_files_exist();

if($clustering_output_files_exist == 0 || 
   $parse_requests_files_exist == 0 ||
   $g_reconvert_reqs == 1) {
    
    print "Re-translating reqs: parse_requests: $parse_requests_files_exist\n" . 
        "clustering files exist: $clustering_output_files_exist\n";
    
    $g_parse_requests->parse_requests();
    $g_create_clustering_input->create_clustering_input();
}    

##
# Free memory occupied by the g_parse_requests
# and g_clustering_input module
##
undef $g_parse_requests;
undef $g_create_clustering_input;


##
# Actually cluster the requests
##
if ($g_pass_through) {
    my $pass_through_module = new PassThrough("$g_convert_reqs_output_dir/input_vector.dat",
                                              "$g_convert_reqs_output_dir/distance_matrix.dat",
                                              "$g_convert_reqs_output_dir");
    
    $pass_through_module->cluster();
} else {
    # Clustering not supported yet!
    assert(0);
}

# Get changed edges
#compare_edge_distributions("$g_convert_reqs_output_dir/s0_edge_based_indiv_latencies.dat",
#                           "$g_convert_reqs_output_dir/s1_edge_based_indiv_latencies.dat",
#                           "$g_convert_reqs_output_dir/global_req_edge_columns.dat",
#                           "$g_convert_reqs_output_dir/edge_distribution_comparisons.dat");
                           

my $g_print_requests = new PrintRequests("$g_convert_reqs_output_dir",
                                         $g_snapshot0_file,
                                         $g_snapshot1_file);


my $g_parse_clustering_results = new ParseClusteringResults($g_convert_reqs_output_dir,
                                                            $g_cluster_output_ranking,
                                                            $g_print_requests,
                                                            $g_output_dir);

print "Initializng parse clustering results\n";
$g_parse_clustering_results->print_clusters();

   

### Helper functions #######
#
# Parses command line options
#
sub parse_options {

	GetOptions("output_dir=s"   => \$g_output_dir,
			   "snapshot0=s"    => \$g_snapshot0_file,
			   "snapshot1:s"    => \$g_snapshot1_file,
			   "min_k=i"        => \$g_clustering_params{MIN_K},
			   "max_k=i"        => \$g_clustering_params{MAX_K},
			   "k_interval=i",  => \$g_clustering_params{K_INTERVAL},
			   "best_only+"     => \$g_clustering_params{BEST_ONLY},
			   "pass_through+"  => \$g_pass_through,
               "ranking=s"      => \$g_cluster_output_ranking,
			   "reconvert_reqs+" => \$g_reconvert_reqs);

    # These parameters must be specified by the user
    if (!defined $g_output_dir || !defined $g_snapshot0_file ||
       !defined $g_cluster_output_ranking) {
        print_usage();
        exit(-1);
    }

    # Make sure that user does not specify "best_only" and "pass_through"
    if (defined $g_clustering_params{BEST_ONLY} 
        && defined $g_pass_through) {
        print_usage();
        exit(-1);
    }

    # If the user does not specify best_only or pass_through, he must
 

    $g_convert_reqs_output_dir = "$g_output_dir/convert_data";
    system("mkdir -p $g_convert_reqs_output_dir");
}

#
# Prints usage for this perl script
#
sub print_usage {
    print "usage: spectroscope.pl --output_dir, --snapshot0, --snapshot1, --min_k\n" .
		"\t--max_k, --k_interval, --best_only --pass_through --dont_reconvert_reqs\n"; 
    print "\n";
    print "\t--output_dir: The directory in which output should be placed\n";
    print "\t--ranking: Must be specified as req_difference\n";
    print "\t--snapshot0: The name of the dot graph output containing requests from\n" .
        "\t the non-problem snapshot\n";
	print "\t--snapshot1: The name of the dot graph output containing requests from\n" . 
        "\t the problem snapshot (OPTIONAL)\n";
	print "\t--min_k: The minimum number of clusters to explore (OPTIONAL)\n";
	print "\t--max_k: The maximum number of clusters to explore (OPTIONAL)\n";
	print "\t--k_interval: The increment step between min_k and max_k (OPTIONAL)\n";
	print "\t--best_only: Optional parameter indicating whether the output should\n" .
        "\t contain only results for the 'best' clustering, or for all\n" .
        "\t clusters explored (OPTIONAL)\n";
    print "\t--reconvert_reqs: Re-indexes and reconverts requests for\n" .
          "\t fast access and MATLAB input (OPTIONAL)\n";
	print "\t--pass_through: Skips the clustering step (OPTIONAL)\n";


}















