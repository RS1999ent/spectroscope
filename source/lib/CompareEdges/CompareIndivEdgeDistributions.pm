#! /usr/bin/perl -w

# cmuPDL: CompareIndivEdgeDistributions.pm

##
# This perl module serves as a wrapper for a matlab script
# that compares the latency distributions of various edge.
#
# The input to this module are the locations of two data files,
# which specify the edge latency of the request in MATLAB sparse
# file format.  That is: 
#  <row number> <column number> <non-zero edge latency value>
#
# Each row corresponds to an unique edge.  The edge it corresponds
# to is specified in the third input file, which must be of the format
# <row number> <edge num>
#
# The final parameter to this module is the location in which to produce
# results.  The results are of the form: 
# 
# <EDGE NAME> <Reject null hypothesis> <p-value>.
##

use strict;
use Exporter;
use Test::Harness::Assert;

@CompareIndivEdgeDistributions::ISA = qw(Exporter);
@CompareIndivEdgeDistributions::EXPORT = qw(compare_edge_distributions);


#### Module function ########

sub remove_existing_symlinks {

    system ("rm -f /tmp/s0_edge_latencies.dat");
    system ("rm -f /tmp/s1_edge_latencies.dat");
    system ("rm -f /tmp/edge_names.dat");
    system ("rm -f /tmp/output_file.dat");
}


sub compare_edge_distributions {

    if ($#_ != 3) {
        print("Invalid number of parameters to this function\n");
        assert(0);
    }

    my $s0_edge_latencies_file = shift;
    my $s1_edge_latencies_file = shift;
    my $edge_names_file = shift;
    my $output_file = shift;

    remove_existing_symlinks();

    system("ln -s $s0_edge_latencies_file /tmp/s0_edge_latencies.dat") == 0
        or die("Could not create symlink\n");
    system("ln -s $s1_edge_latencies_file /tmp/s1_edge_latencies.dat") == 0
        or die("Could not create symlink\n");
    system("ln -s $edge_names_file /tmp/edge_names.dat")  == 0 
        or die("Could not create symlink\n");
    system("touch $output_file") == 0
        or die("Could not create output file\n");
    system("ln -s $output_file /tmp/output_file.dat");

    chdir "../lib/CompareEdges";

    system("matlab -nojvm -nosplash -r \"compare_edge_distributions; quit\"" .
		   "|| matlab -nodisplay -r \"compare_edge_distributions; quit\"") == 0
		   or die ("could not run Matlab compare_avg_edge_latencies script\n");

    chdir "../../spectroscope";

    remove_existing_symlinks();

}




    
    
    
    
