#!/usr/bin/perl -w

# $cmuPDL: spectroscope.pl,v 1.14 2010/03/27 04:15:48 rajas Exp $

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
use define DEBUG => 0;

use SedClustering::CreateClusteringInput;
use ParseDot::ParseRequests;
use ParseDot::PrintRequests;
use PassThrough::PassThrough;
use ParseClusteringResults::ParseClusteringResults;
use CompareEdges::CompareIndivEdgeDistributions;

$ENV{'PATH'} = "$ENV{'PATH'}" . ":../lib/SedClustering/";

#### Global variables ############################

# The directory in which output should be placed
my $g_output_dir;

# The directory the output of hte ConvertRequests module should be placed
my $g_convert_reqs_output_dir;

# The file(s) containing DOT requests from the non-problem period(s)
my @g_snapshot0_files;

# The file(s) containing DOT requests from the problem period(s)
my @g_snapshot1_files;

# Allow user to skip re-converting the input DOT files to the
# format required for this program, if this has been done before.
my $g_reconvert_reqs = 0;

# The module for converting requests into MATLAB compatible format
# for use in the clustering algorithm
my $g_create_clustering_input;

# The module for parsing requests
my $g_parse_requests;

# Whether or not to bypass SeD calculation. If bypassed, 
# "fake" SeD values will be inserted and the (actual) SeD calculation
# will not be performed
my $g_bypass_sed = 0;


#### Main routine #########

# Get input arguments
parse_options();

if (defined $g_snapshot1_files[0]) {
    $g_create_clustering_input = new CreateClusteringInput(\@g_snapshot0_files,
                                                           \@g_snapshot1_files,
                                                           $g_convert_reqs_output_dir);

    $g_parse_requests = new ParseRequests(\@g_snapshot0_files,
                                          \@g_snapshot1_files,
                                          $g_convert_reqs_output_dir);
} else {
    $g_create_clustering_input = new CreateClusteringInput(\@g_snapshot0_files,
                                                           $g_convert_reqs_output_dir);

    $g_parse_requests = new ParseRequests(\@g_snapshot0_files,
                                          \@g_snapshot1_files,
                                          $g_convert_reqs_output_dir);
}

# Determine whether indices and the matlab clustering input
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
    $g_create_clustering_input->create_clustering_input($g_bypass_sed);
}    

##
# Free memory occupied by the g_parse_requests
# and g_clustering_input module
##
undef $g_parse_requests;
undef $g_create_clustering_input;



# Only "Pass through clustering" is currently supported
my $pass_through_module = new PassThrough($g_convert_reqs_output_dir, 
                                          $g_convert_reqs_output_dir);    
$pass_through_module->cluster();

my $g_print_requests = new PrintRequests($g_convert_reqs_output_dir,
                                         \@g_snapshot0_files,
                                         \@g_snapshot1_files);


my $g_parse_clustering_results = new ParseClusteringResults($g_convert_reqs_output_dir,
                                                            $g_print_requests,
                                                            $g_output_dir);


print "Initializng parse clustering results\n";
$g_parse_clustering_results->print_ranked_clusters();

   

### Helper functions #######
#
# Parses command line options
#
sub parse_options {

	GetOptions("output_dir=s"              => \$g_output_dir,
			   "snapshot0=s{1,10}"         => \@g_snapshot0_files,
			   "snapshot1:s{1,10}"         => \@g_snapshot1_files,
			   "reconvert_reqs+"           => \$g_reconvert_reqs,
               "bypass_sed+"               => \$g_bypass_sed);

    # These parameters must be specified by the user
    if (!defined $g_output_dir || !defined $g_snapshot0_files[0]) {
        print_usage();
        exit(-1);
    }

    $g_convert_reqs_output_dir = "$g_output_dir/convert_data";
    system("mkdir -p $g_convert_reqs_output_dir");
}

#
# Prints usage for this perl script
#
sub print_usage {
    print "usage: spectroscope.pl --output_dir, --snapshot0, --snapshot1\n" .
		"\t--dont_reconvert_reqs --bypass_sed\n"; 
    print "\n";
    print "\t--output_dir: The directory in which output should be placed\n";
    print "\t--snapshot0: The name(s) of the dot graph output containing requests from\n" .
        "\t the non-problem snapshot(s).  Up to 10 non-problem snapshots can be specified\n";
	print "\t--snapshot1: The name(s) of the dot graph output containing requests from\n" . 
        "\t the problem snapshot(s).  Up to 10 problem snapshots can be specified. (OPTIONAL)\n";
    print "\t--reconvert_reqs: Re-indexes and reconverts requests for\n" .
          "\t fast access and MATLAB input (OPTIONAL)\n";
    print "\t--bypass_sed: Whether to bypass SED calculation (OPTIONAL)\n";
}
















