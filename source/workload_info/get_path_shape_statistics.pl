#! /user/bin/perl -w

# $cmuPDL: get_path_shape_statistics.pl,v 1.1 2009/07/27 20:08:21 rajas Exp $

##
# @author Raja Sambasivan
#
# Returns statistics about the path-shapes induced by the request-types specified in
# the input config file.  The input config file should specify request-types and groupings
# follows: 
#
# @group_name = ["node name demarcating first request-type that belongs to this group",
#                 ...,
#                 "node name demarcating last request-type that belongs to this group"]
#
# Valid group names are: "data_ops," "directory_ops," and "metadata_ops."  All group names
# must be specified.
##

#### Package declarations ####################

use strict;
use warnings;
use diagnostics;
use Test::Harness::Assert;
use Getopt::Long;

use lib '../lib';
use define DEBUG => 0;

use PassThrough::PassThrough;
use SedClustering::CreateClusteringInput;
use ParseDot::ParseRequests;
use ParseDot::PrintRequests;
use ParseClusteringResults::ParseClusteringResults;
use ParseDot::DotHelper qw[find_dot_node];

use Data::Dumper;

#### Global variables ######################

# Directory in which temporary output will be placed
my $g_pass_through_output_dir = "/tmp/path_shape_statistics/";

# Reference to name of input files
my @g_graph_files_ref;

# Output directory location
my $g_temp_output_dir;

# Directory in which intermediate output fill be placed
my $g_convert_reqs_dir;

# Name of the config file
my $g_config_file;

# Hash of request-types to path shapes induced by them
my %g_request_type_hash;

# Hash of information about path shapes that belong to a group
my %g_group_hash;

##### Sub routines #######################

##
# Prints usage for this script
##
sub print_usage {
    print "get_shape_statistics.pl --graphs_file --config_file --output_temp_dir\n";
    print "\t--graphs_file: Names of up to 10 files containing request graphs\n";
    print "\t--config_file: The configuration file indicating which request-types\n" .
        "\t\tfor which to find path shapes and their grouping\n";
    print "\t--temp_output_dir: The directory in which to place temporary output\n" .
        "\t\tIf this dir exists, the data in it will be used and not re-computed.\n" .
        "\t\tThis directory is safe to delete after the program has finished\n";
}
        
        
##
# Parse input options and store them in global variables
##
sub parse_options {
    
    GetOptions("graphs_file=s{1,10}"  =>  \@g_graph_files_ref,
               "config_file=s"        =>  \$g_config_file,
               "temp_output_dir=s"    =>  \$g_temp_output_dir);

    if( !defined $g_temp_output_dir 
        || !defined $g_graph_files_ref[0]
        || !defined $g_temp_output_dir) {
        
        print_usage();
        exit(-1);
    }
    $g_convert_reqs_dir = "$g_temp_output_dir/convert_reqs";

    system("mkdir -p $g_temp_output_dir") == 0 
        or die("Could not create $g_temp_output_dir\n");
    system("mkdir -p $g_convert_reqs_dir") == 0 
        or die("Could not create $g_convert_reqs_dir");

}


##
# Evaluate the input configuration file and store config
# data in namespace "C"
##
sub eval_config_file {
    
    { 
        print "Evaluating configuration file\n";
        {
            package C;
            unless (do $g_config_file) {
                print "Could not evaluate $g_config_file -- ABORTING!\n";
                exit(-1);
            }
        }
        print "Done evaluating configuration file\n";
    }
}


##
# Performs work necessary to create a "parse_clustering_results" object
# using the "PassThrough" clustering algorithm.  Doing so, will allow
# querying of the pcr object to determine how many requests of each unique
# path exist
##
sub create_parse_clustering_results_obj {

    my $parse_requests = new ParseRequests(\@g_graph_files_ref, 
                                           $g_convert_reqs_dir);
    my $clustering_input = new CreateClusteringInput(\@g_graph_files_ref,
                                                 $g_convert_reqs_dir);
    my $pass_through = new PassThrough($g_convert_reqs_dir,
                                       $g_convert_reqs_dir);

    if ($parse_requests->do_output_files_exist() == 0 ||
        $clustering_input->do_output_files_exist() == 0 ||
        $pass_through->do_output_files_exist() == 0) {
        
        $parse_requests->parse_requests();
        $clustering_input->create_clustering_input();
        $pass_through->cluster();
    }

    undef $parse_requests;
    undef $clustering_input;
    undef $pass_through;
    
    my $print_requests = new PrintRequests($g_convert_reqs_dir,
                                           \@g_graph_files_ref);
    my $parse_clustering_results = new ParseClusteringResults($g_convert_reqs_dir,
                                                              $print_requests,
                                                              $g_temp_output_dir);
    undef $print_requests;
    
    return $parse_clustering_results;
}


##
# Initialize the hash of request-types -> information
# about the path shapes they induce
##
sub initialize_hashes {
    my ($group_array_ptr, $group_name) = @_;

    # Initialize the request-type hash
    foreach (@{$group_array_ptr}) {
        my $request_type = $_;

        my @shapes;
        $g_request_type_hash{$request_type} = { total_reqs => 0,
                                              num_shapes => 0,
                                              shapes     => \@shapes,
                                              group      => $group_name
                                          };
    }

    # Initialize the group hash
    my @group_shapes;
    $g_group_hash{$group_name} = { total_reqs => 0,
                                   num_shapes => 0,
                                   shapes => \@group_shapes,
                                   group => $group_name
                               };
}


##
# Fills in request_type_hash and group_hashby acting on the clustering results
# induced by utilizing the PassThrough clustering algorithm.  Each cluster
# represents a unique path shape.  This function walks through the unique
# path shapes and attributes requests of each path-shape to the appropriate
# request-type and group.
#
# @param pcr: A ParseClusteringResults object.  The clustering algorithm
# used to generate this object should have been "PassThrough"
##
sub fill_hashes {
    my ($pcr) = @_;

    # Walk through the representatives of each cluster; check to see
    # if a representative contains a node that demarcates a particular
    # request type.  If so, modify that request type's hash to reflect
    # this info.
    my $num_types = $pcr->get_num_clusters();

    # Clusters are 1-indexed!!!
    for(my $i = 1; $i <= $num_types; $i++) {
        my $cluster_rep = $pcr->get_cluster_representative($i);
        my $found = 0;
        my $num_cluster_reqs = $pcr->get_num_requests_in_cluster($i);
        
        foreach(keys %g_request_type_hash) {
            my $request_type = $_;

            if (DotHelper::find_dot_node($request_type, $cluster_rep)) {

                # Fill in information for the matching request-type
                my $request_type_info = $g_request_type_hash{$request_type};
                $request_type_info->{total_reqs} += $num_cluster_reqs;
                $request_type_info->{num_shapes}++;
                push(@{$request_type_info->{shapes}}, $num_cluster_reqs);

                # Fill in information for the matching group-type
                my $group_name = $request_type_info->{group};
                my $group_info = $g_group_hash{$group_name};
                $group_info->{total_reqs} += $num_cluster_reqs;
                $group_info->{num_shapes} ++;
                push(@{$group_info->{shapes}}, $num_cluster_reqs);
                
                # Indicate we've found what we're looking for
                $found = 1;
                last;
            }
        }
        if($found == 0) {
            print "Could not find request-type that matches path-shape.  Path-shape printed below\n";
            print "$cluster_rep\n";
            assert(0);
        }
    }
    if(DEBUG) {
        print Dumper(\%g_request_type_hash);
        print Dumper(\%g_group_hash);
    }
}


##
# Prints information about the group passed in and its constituent
# request-types
#
# @param request_types_ref: Reference to an array of request-types
#  associated with the current group
# @param group_name: A string stating the name of this group
##
sub print_group_info {
    
    assert(scalar(@_) == 2);
    my($request_types_ref, $group_name) = @_;

    # Print header
    printf "%-30s %-15s %-15s\n", "Type", "Total Reqs", "Shapes";

    # First print information about the request-types    
    foreach(@{$request_types_ref}) {
        my $request_type = $_;
        my $request_type_info = $g_request_type_hash{$request_type};
        printf "%-30s %-15d %-15d\n", $request_type, $request_type_info->{total_reqs}, $request_type_info->{num_shapes};
    }

    # Now print the group info
    my $group_info = $g_group_hash{$group_name};
    printf "%-30s %-15d %-15d\n", $group_name, $group_info->{total_reqs}, $group_info->{num_shapes};

    # Print a terminator
    print "--------------------------------------------------------\n";
}
    



##### Main routine #######################

parse_options();

# Evaluate config file under the "C" namespace
eval_config_file();

### Create hashes for the processed types
initialize_hashes(\@C::data_ops, "DATA_OPS");
initialize_hashes(\@C::directory_ops, "DIRECTORY_OPS");
initialize_hashes(\@C::metadata_ops, "METADATA_OPS");
initialize_hashes(\@C::dont_care_ops, "DONT_CARE_OPS");

##### Re-create PassThrough clusters and associated data if needed
my $pcr = create_parse_clustering_results_obj();

### Fill in the request-types hash w/the appropriate info
fill_hashes($pcr);

### Print out information about groups and request-types
print_group_info(\@C::data_ops, "DATA_OPS");
print_group_info(\@C::directory_ops, "DIRECTORY_OPS");
print_group_info(\@C::metadata_ops, "METADATA_OPS");
print_group_info(\@C::dont_care_ops, "DONT_CARE_OPS");


exit(0);












    









