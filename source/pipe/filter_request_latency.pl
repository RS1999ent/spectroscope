#! /usr/bin/perl -w

# $cmuPDL: filter_request_latency.pl,v 1.5 2010/04/25 05:05:38 lianghon Exp $v

##
# This program calculates the cluster distribution within a specific request 
# latency range. Given the minimum and maximum request latency, it counts 
# the number of requests falling into this range for each cluster. The input 
# file is located in output_dir/convert_data/global_ids_to_cluster_ids, each 
# line of which is a mapping from global id to the cluster id it belongs to. 
#
# An output file cluster_distribution.dat is generated as input for the matlab
# program cluster_distribution.m, which plots the histogram of the cluster distribution. 
##

#### Package declarations ###############################

use strict;
use Test::Harness::Assert;
use Getopt::Long;

use lib '../lib';

$ENV{'PATH'} = "$ENV{'PATH'}" . ":../lib/";

##### Global variables ####

my $g_output_dir;
my $min_latency = 0;
my $max_latency = 100000;
my $input_file;
my $output_file;
my %cluster_hash = ();

##### Functions ########

##
# Prints usage options
##
sub print_usage {
    
    print "filter_request_latency.pl --output_dir --min --max\n";
    print "\t--output_dir: Spectroscope output directory\n";
    print "\t--min: minimum request latency\n";
    print "\t--max: maximum request latency\n";
}


##
# Collects command line parameters
##
sub parse_options {
    
    GetOptions("output_dir=s" => \$g_output_dir,
	       "min:f"        => \$min_latency,
	       "max:f"        => \$max_latency);
    
    if(!defined $g_output_dir) {
        print_usage();
        exit(-1);
    }
}


parse_options();

$input_file = "$g_output_dir/convert_data/global_ids_to_cluster_ids.dat";
$output_file = "cluster_distribution.dat";

open(my $input_fh, "<$input_file")
    or die("Could not open $input_file\n");
open(my $output_fh, ">$output_file")
    or die("Could not open $output_file\n");

while(<$input_fh>) {
    chomp;

    if(/(\d+) (\d+) ([0-9\.]+)/) {
	my $global_id = $1;
	my $cluster_id = $2;
	my $req_latency = $3;

	if($req_latency >= $min_latency &&
	   $req_latency <= $max_latency) {

	    if(!defined $cluster_hash{$cluster_id}) {
		$cluster_hash{$cluster_id} = 1;
	    } else {
		$cluster_hash{$cluster_id}++;
	    }
	}
    }
}

for my $key (sort {$a<=>$b} keys %cluster_hash) {
    printf $output_fh "$key $cluster_hash{$key}\n";
}

close($input_fh);
close($output_fh);
