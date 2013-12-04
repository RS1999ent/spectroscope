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

# $cmuPDL: get_request_by_global_id.pl,v 1.2 2009/05/19 06:32:28 source Exp $

##
# @author Raja Sambasivan
#
# Writes a request to STDOUT given its global ID.
# Type perl get_request_by_global_id.pl -h for help
##

use strict;
use warnings;
use diagnostics;
use Test::Harness::Assert;

use Getopt::Long;

use lib '../lib';
use ParseDot::PrintRequests;
use ParseDot::ParseRequests;

#### Global variables ######################

# The spectroscope output directory
my $g_spectroscope_output_dir;

# The location of the snapshot0 requests file
my $g_snapshot0_file;

# The location of the snapshot1 requests file
my $g_snapshot1_file;

# The directory in which the output form ParseRequests is kept
my $g_parse_requests_output_dir;

# The global ID to retrieve
my $g_global_id;


#### Functions ############################


##
# Prints usage to the screen
##
sub print_usage {
    
    print "usage: get_request_by_global_id.pl --snapshot0_file --snapshot1_file\n" .
        "(--parse_requests_output_dir or --spectroscope_output_dir) --global_id\n";
    print "\n";
    print "\t--snapshot0: The file containing requests from snapshot0\n";
    print "\t--snapshot1: (OPTIONAL) The file containing requests from snapshot1\n";
    print "\t--spectroscope_output_dir: (OPTIONAL) The directory in which Spectroscope's\n" . 
        "\t results exist\n";
    print "\t--parse_requests_output_dir: (OPTIONAL) The directory in which the indices\n" .
        "\t created by the ParseRequests module exist\n";
    print "\n";
    print "Note that only only --spectroscope_output_dir xor\n" . 
        "--parse_requests_output_dir should be specified\n";
}


##
# Retrieves user options from the command line
##
sub parse_options {
    
    GetOptions("global_id=i"                 => \$g_global_id,
               "parse_reqs_output_dir:s"     => \$g_parse_requests_output_dir,
               "spectroscope_output_dir:s"   => \$g_spectroscope_output_dir,
               "snapshot0=s"                 => \$g_snapshot0_file,
               "snapshot1=s"                  => \$g_snapshot1_file);

    if(defined $g_spectroscope_output_dir && defined $g_parse_requests_output_dir) {
        print_usage();
        exit(-1);
    }

    if(!defined $g_global_id || !defined $g_snapshot0_file || 
       (!defined $g_parse_requests_output_dir && !defined $g_spectroscope_output_dir)) {
        print_usage();
        exit(-1);
    }

    if(defined $g_spectroscope_output_dir) {
        $g_parse_requests_output_dir = "$g_spectroscope_output_dir/convert_data";
    }
}


#### Main routine #########################

parse_options();

my $parse_requests_obj;
my $print_request_info_obj;

if (defined $g_snapshot1_file) {
    $parse_requests_obj = new ParseRequests($g_snapshot0_file,
                                           $g_snapshot1_file,
                                           $g_parse_requests_output_dir);

    $print_request_info_obj = new PrintRequests($g_parse_requests_output_dir,
                                                $g_snapshot0_file,
                                                $g_snapshot1_file);
} else {
    $parse_requests_obj = new ParseRequests($g_snapshot0_file,
                                           $g_parse_requests_output_dir);
    
    $print_request_info_obj = new PrintRequests($g_parse_requests_output_dir,
                                                $g_snapshot0_file);
}                                               

if ($parse_requests_obj->do_output_files_exist() == 0) {
    $parse_requests_obj->parse_requests();
}

$print_request_info_obj->print_global_id_indexed_request($g_global_id, \*STDOUT);





