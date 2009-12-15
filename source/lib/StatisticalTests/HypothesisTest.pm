#! /usr/bin/perl -w

# cmuPDL: HypothesisTest.pm, v $

##
# This perl module expects as input two matlab sparse matrix files, where each
# row represents a distribution of data that should be compared to the
# corresponding row in the other file using a hypothesis test.  Note that rows
# of the input file MUST be one indexed.  Once the hypothesis test is performed,
# this function can return the results in a hash reference, which is structured
# as follows:
# hyp_test_results_hash{name} = { REJECT_NULL   => <value>,
#                                 P_VALUE       => <value>,
#                                 AVGS           => \@array
#                                 STDDEVS       => \@array }
#
# Each value in the hash reference presents the results from one row of the
# input files.  The name parameter is either the row number, or a "name."  The
# row number is 1-indexed.  The name is obtained from an input hash that maps
# row numbers to names.  Note that The AVG field and STDDEVS field contain
# references to an array.  The first value is the average/standard deviation
# from the first file, whereas the second represents the average/standard
# deviation from the second file.  
##

package HypothesisTest;

use strict;
use Cwd;
use Test::Harness::Assert;


#### Global constants ##############

# Import value of DEBUG if defined
no define DEBUG =>;

#### API functions #################

##
# Creates a new HypothesisTests class.
#
# @param file1: Each row contains samples that should be compared to the
# corresponding row in file 2 in MATLAB sparse matrix format
# @param file2: Each row contains samples that should be compared to the
# corresponding row in file 1 in MATLAB sparse matrix format
# @name: A unique name for these set of tests
# @param output_dir: Output about the results of each hypothesis tests 
# will be stored in this directory
## 
sub new {

    assert(scalar(@_) == 5);
    my($proto, $ref_file, $test_file, $name, $output_dir) = @_;

    my $class = ref($proto) || $proto;
    my $self = {};

    $self->{REF_DISTRIB_FILE} = $ref_file;
    $self->{TEST_DISTRIB_FILE} = $test_file;
    $self->{OUTPUT_FILE} = "$output_dir/$name" . "_hypothesis_test_results.dat";
    $self->{REF_GRAPH_FILE} = "$output_dir/$name" . "_ref_distrib_graph.eps";
    $self->{TEST_GRAPH_FILE} = "$output_dir/$name" . "_test_distribu_graph.eps";
    $self->{HAVE_TESTS_BEEN_RUN} = 0;

    bless($self, $class);

    return $self;
}


## 
# Runs the Kolomov-Smirgnov test to compare corresponding data distributions in
# each row of the input files.  The standard significance level of alpha=0.05 is
# used.
#
# The output of the hypothesis tests run is placed in $self->{OUTPUT_FILE}.
# Each row of the output file corresponds to the test run for the corresponding
# rows in the reference and test distribution files.  Each hypothesis test
# results row is formated as follows: 
#   edge_row_number, reject null?, p_value, avgs, stddevs
#
# @param self: The object container
#
##
sub run_kstest2 {
    
    assert(scalar(@_) == 1);
    my ($self) = @_;

    my $curr_dir = getcwd();
    chdir '../lib/StatisticalTests';
    
    system("matlab -nojvm -nosplash -nodisplay -r \"compare_edges(\'$self->{REF_DISTRIB_FILE}\', \'$self->{TEST_DISTRIB_FILE}\', \'$self->{OUTPUT_FILE}\'); quit\"".
           "|| matlab -nodisplay -r \"compare_edges(\'$self->{REF_DISTRIB_FILE}\', \'$self->{TEST_DISTRIB_FILE}\', \'$self->{OUTPUT_FILE}\'); quit\"") == 0
           or die ("Could not run Matlab compare_edges script\n");

    chdir $curr_dir;

    $self->{HAVE_TESTS_BEEN_RUN} = 1;
}


##
# Runs the X^2 test.  Input data should be categorical and in each row of the input
# files should be in the following format.
#   id count name
# id is the id of the category; count is the number of elements contained; name is
# a field that is used to combine multiple categories if each does not contain enough elements.
# Categories with the same name are assumed to be comparable.
##
sub run_chi_squared {
    assert(scalar(@_) == 1);
    my ($self) = @_;

    my $curr_dir = getcwd();
    chdir '../lib/StatisticalTests';

    system("matlab -nojvm -nosplash -nodisplay -r \"compare_categories(\'$self->{REF_DISTRIB_FILE}\', \'$self->{TEST_DISTRIB_FILE}\', \'$self->{OUTPUT_FILE}\', \'$self->{REF_GRAPH_FILE}\', \'$self->{TEST_GRAPH_FILE}\'); quit\"".
           "|| matlab -nodisplay -r \"compare_categories(\'$self->{REF_DISTRIB_FILE}\', \'$self->{TEST_DISTRIB_FILE}\', \'$self->{OUTPUT_FILE}\', \'$self->{REF_GRAPH_FILE}\', \'$self->{TEST_GRAPH_FILE}\'); quit\"") == 0
           or die("Could not run Matlab compare_categories script\n");
    
    chdir $curr_dir;

    $self->{HAVE_TESTS_BEEN_RUN} = 1;
}


##
# Returns results of running the selected hypothesis test.
#
# @param self: The object container
# @param row_nums_to_names: A hash reference mapping row numbers to "names"
# (optional)
#
# @returns: A hash reference where each item is: 
#    hyp_test_results_hash{name} = { REJECT_NULL => value,
#                                    P_VALUE => <value>,
#                                    AVGS => \@array,
#                                    STDDEVS => \@array}
#
# If the $row_num_to_names hash reference is not specified, row numbers are
# returned as the hash keys.  Such row numbers are one indexed.  The AVGS and
# STDDEVS elements contain references to two element arrays.  The 0th element is
# the avg or standard deviation in the reference distribution and the 1st
# element is the average or standard deviation in the test distribution.  
## 
sub get_hypothesis_test_results {

    assert(scalar(@_) == 1 || scalar(@_) == 2);
    my ($self, $row_nums_to_names);

    if(scalar(@_) == 1) {
        ($self) = @_;
    } else {
        ($self, $row_nums_to_names) = @_;
    }

    my %hyp_test_results_hash;
    
    open(my $hyp_test_results_fh, "<$self->{OUTPUT_FILE}")
        or die ("Could not open $self->{OUTPUT_FILE}: $!\n");

    while (<$hyp_test_results_fh>) {
        # This regexp must match the output specified by _run_hypothesis_test()
        if(/(\d+) (\d+) ([\-0-9\.]+) ([0-9\.-]+) ([0-9\.-]+) ([0-9\.-]+) ([0-9\.-]+)/) {
            my $edge_row_num = $1;
            my $reject_null = $2;
            my $p_value = $3;
            my @avg_latencies = ($4, $6);
            my @stddevs = ($5, $7);
            
            my $row_name;
            if (defined $row_nums_to_names) {
                $row_name = $row_nums_to_names->{$edge_row_num};
            }
            else {
                $row_name = $edge_row_num;
            }
            assert(defined $row_name);

            $hyp_test_results_hash{$row_name} = { REJECT_NULL => $reject_null,
                                               P_VALUE        => $p_value,
                                               AVGS           => \@avg_latencies,
                                               STDDEVS        => \@stddevs };
        } else {
            print "get_hypothesis_test_results(): Cannot parse line in" .
                " $self->{OUTPUT_FILE}\n $_";
            assert(0);
        }
    }
    
    close($hyp_test_results_fh);
    
    return \%hyp_test_results_hash;
}


1;




    
  
