#! /usr/bin/perl -w

# $cmuPDL: explain_clusters.pl,v 1.3 2009/07/23 01:15:58 rajas Exp $

##
# @author Raja Sambasivan
# 
# @brief "Explains" why two clusters differ by inducing
# a decision tree to analyze their low-level data.  Assumes 
# that the C4.5 package is installed and available for use
##

use strict;
use warnings;
use diagnostics;
use Test::Harness::Assert;
use Getopt::Long;

use lib '../lib';
use define DEBUG => 0;

use ParseDot::PrintRequests;
use SedClustering::Sed;
use ParseClusteringResults::ParseClusteringResults;
use ExplainClusters::DecisionTree;

$ENV{'PATH'} = "$ENV{'PATH'}" . ":../lib/SedClustering/";


#### Global variables #####

# The directory containing the results of running Spectroscope.  Used to
# initialize the ParseClusteringResults class and the ParseDot class.
my $g_spectroscope_results_dir;

# The ID of the mutated cluster
my $g_mutated_cluster_id;

# The ID of the original cluster
my $g_original_cluster_id;

# The name of the SQLite database in which snapshot0's low-level
# data is stored
my $g_s0_database_name;

# The name of the SQLite database in which snapshot1's low-level
# data is stored
my $g_s1_database_name;

# The name of the file containing request-flow graphs from snapshot0
my $g_snapshot0_graphs;

# The name of the file containing request-flow graphs from snapshot1
my $g_snapshot1_graphs;

# The location of the converted input request-flow graphs
my $g_convert_reqs_dir;


#### Private functions

##
# Prints usage information
##
sub print_usage {
    print "usage: explain_clusters.pl --spectroscope_results_dir --mutated_cluster_id\n" .
        "\t--original_cluster_id --s0_database --s1_database --s0_graphs --s1_graphs\n";
    print "\n";
    print "\t--spectroscope_results_dir: Location of the Spectroscope results\n";
    print "\t--mutated_cluster_id: ID of the mutated cluster\n";
    print "\t--original_cluster_id: The ID of the original cluster\n";
    print "\t--s0_database: The db in which s0's low-level data resides\n";
    print "\t--s1_database: (OPT) The db in which s1's low-level data resides\n";
    print "\t--s0_graphs: Graphs file from snapshot 0\n";
    print "\t--s1_graphs: Graphs file from snapshot 1\n";
}


##
# Gets input options from the user
#
sub parse_options {
    
    GetOptions("spectroscope_results_dir=s" => \$g_spectroscope_results_dir,
               "mutated_cluster_id=s" => \$g_mutated_cluster_id,
               "original_cluster_id=s" => \$g_original_cluster_id,
               "s0_database=s" => \$g_s0_database_name,
               "s1_database:s" => \$g_s1_database_name,
               "s0_graphs=s"   => \$g_snapshot0_graphs,
               "s1_graphs:s"   => \$g_snapshot1_graphs);
   

    # Check input options
    if (!defined $g_mutated_cluster_id || $g_mutated_cluster_id < 1 ||
        !defined $g_original_cluster_id || $g_original_cluster_id < 1 ||
        !defined $g_spectroscope_results_dir || !defined $g_snapshot0_graphs) {

        print_usage();
        exit(-1);
    }

    $g_convert_reqs_dir = "$g_spectroscope_results_dir/convert_data";
}


#### Main routine #########

parse_options();

my @s0_graphs = ($g_snapshot0_graphs);
my @s1_graphs = ($g_snapshot1_graphs);

my $request_info_obj = new PrintRequests($g_convert_reqs_dir,
                                         \@s0_graphs, \@s1_graphs);

# String-edit distance might already have been computed as part of running Spectroscope
my $g_sed = new Sed("$g_convert_reqs_dir/input_vector.dat",
                    "$g_convert_reqs_dir/cluster_distance_matrix.dat",
                    0);

my $clustering_results_obj = new ParseClusteringResults($g_convert_reqs_dir,
                                                        $request_info_obj,
                                                        $g_sed,
                                                        $g_spectroscope_results_dir);

my $decision_tree_obj = new DecisionTree($request_info_obj,
                                        $clustering_results_obj,
                                        $g_spectroscope_results_dir,
                                        $g_s0_database_name,
                                        $g_s1_database_name);

$decision_tree_obj->explain_clusters($g_original_cluster_id, $g_mutated_cluster_id,
                                     $g_spectroscope_results_dir);


