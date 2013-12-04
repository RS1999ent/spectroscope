#! /usr/bin/perl -w

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

##
# $cmuPDL: get_cluster_representative.pl, v $
#
# @author Raja Sambasivan
# 
# @brief Extracts a DOT graph of the cluster representative of a given category
##

use strict;
use warnings;
use diagnostics;
use Test::Harness::Assert;
use Getopt::Long;

use lib '../lib';
use define DEBUG => 0;

use ParseDot::PrintRequests;
use ParseClusteringResults::ParseClusteringResults;


#### Global variables ####

# The directory containing the results of running Spectroscope.  
# Used to initialize the ParseDot::PrintRequests class.
my $g_spectroscope_results_dir;

# Directory where intermediate spectroscope output is stored
my $g_convert_reqs_dir;

# The Cluster IDs for which representatives should be extracted
my @g_cluster_ids;

# The name of the files containing request-flow graphs from snapshot0 
my @g_snapshot0_files;

# The name of the file containing request-flow graphs from snapshot1
my @g_snapshot1_files;

# The name of the output file to which the cluster representative will
# be printed
my $g_output_file;


#### Internal functions ####

##
# Print usage
##
sub print_usage {
    print "usage: get_cluster_representative.pdl --spectroscope_results_dir\n" .
        "\t--snapshot0 --snapshot1 --cluster_ids --output_files\n";
    print "\t--spectroscope_results_dir: Dir in which spectroscope results are stored\n";
    print "\t--snapshot0: Files containing DOT graphs from snapshot0\n";
    print "\t--snapshot1: Files containing DOT graphs from snapshot1\n";
    print "\t--cluster_ids: Representatives of these clusters will be printead\n";
    print "\t--output_file: Representatives will be printed to this file\n";
}


##
# Obtains command line parameters
##
sub parse_options {

    # @bug: If multiple snapshot0 or snapshot1 files are specified, they must
    #  be specified in the same order as they were when Spectroscope was initially run
    GetOptions("spectroscope_results_dir=s" => \$g_spectroscope_results_dir,
               "snapshot0=s{1,10}"         => \@g_snapshot0_files,
               "snapshot1:s{1,10}"         => \@g_snapshot1_files,
               "cluster_ids=s{1,10}"       => \@g_cluster_ids,
               "output_file=s"              =>\$g_output_file);


    if (!defined $g_snapshot0_files[0] || !defined $g_cluster_ids[0] || 
        !defined $g_spectroscope_results_dir || !defined $g_output_file) {
        print_usage();
        exit(-1);
    }    

    $g_convert_reqs_dir = "$g_spectroscope_results_dir/convert_data";
}


#### Main routine #####

parse_options();

my $request_info_obj = new PrintRequests($g_convert_reqs_dir,
                                         \@g_snapshot0_files,
                                         \@g_snapshot1_files);

my $clustering_results_obj = new ParseClusteringResults($g_convert_reqs_dir,
                                                        $request_info_obj,
                                                        $g_spectroscope_results_dir);                                                          


open(my $fh, ">$g_output_file") or die ("Could not open $g_output_file\n");
foreach(@g_cluster_ids) {                                         
    my $graph = $clustering_results_obj->get_cluster_representative($_);
    printf $fh "$graph\n";
}

close($fh);

    

