#! /usr/bin/perl -w

# cmuPDL: HypothesisTest.pm, v $

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
# This perl module object performs multiple statistical 'comparisons.'  Each
# comparison compares a set of null distributions against a set of test
# distributions and determine their are statistically significant differences.
# Two statistical tests are currently supported: the Kolomogrov-Smirnov test and
# the X^2 Goodness of Fit test.
#
# A comparison may represent a group of related distributions that are to be
# compared.  Adding a comparison requires specifying two input files, specified
# in MATLAB sparse data format.
#
# For categorical distributions, each row should represent a category, the first
# column the count, and the second a unique name.  Specifically, each row should
# look like: <count> <name>
#
# For continuous distributions, each row should represent a distribution, and
# each column a unique value.  Data must be specified in MATLAB sparse data
# format.  Rows are 1-indexed.  <row>, <col> <value>
#
# Once the hypothesis tests are performed, this function will return the results
# in for each comparison in a hash reference structured as follows.  name is
# either the row number, or a name assigned to the row number, which can be
# specified by the caller.
#
# hyp_test_results_hash{name} = { REJECT_NULL   => <value>,
#                                 P_VALUE       => <value>,
#                                 AVGS           => \@array
#                                 STDDEVS       => \@array }
#
# Note that The AVGS field and STDDEVS field contain references to an array.
# The first value is the average/standard deviation from the null distribution,
# whereas the second represents the average/standard deviation from the test
# distribution.
##

package HypothesisTest;

use strict;
use Cwd;
use Test::Harness::Assert;


#### Global constants ##############

# Import value of DEBUG if defined
no define DEBUG =>;


#### Private functions #############

##
# Creates a file that lists the filenames containing distribution data for each
# comparison that is to be run.  Also write lthe output filenames, into which
# results for each comparison will be written, to this file.
#
# @param self: The object container
##
my $_create_comparison_file = sub {
    assert(scalar(@_) == 1);
    my ($self) = @_;

    open (my $fh, ">$self->{COMPARISON_FILE}") or 
        die "Could not open $self->{COMPARISON_FILE} for writing: $!\n";
    
    foreach (@{$self->{COMPARISON_INFO}}) {
        my $comparison_hash = $_;

        printf $fh "%s %s %s %s\n", 
        $comparison_hash->{NULL_DISTRIB_FILE},
        $comparison_hash->{TEST_DISTRIB_FILE},
        $comparison_hash->{OUTPUT_FILE},
        $comparison_hash->{STATS_FILE};        
    }

    close($fh);
};
        

#### API functions #################

##
# Creates a new HypothesisTests class.
#
# @param output_dir: Output about the results of each comparison
# will be stored in this directory
# @param name: The name of this group of comparisons
## 
sub new {
    assert(scalar(@_) == 3);
    my($proto, $name, $output_dir) = @_;

    my $class = ref($proto) || $proto;
    my $self = {};

    $self->{HAVE_TESTS_BEEN_RUN} = 0;
    $self->{OUTPUT_DIR} = $output_dir;
    
    my $time = time();
    $self->{COMPARISON_FILE} = "$output_dir/hypothesis_test_comp_list_" . "$name" . ".dat";
    
    $self->{COMPARISON_INFO} = ();
    bless($self, $class);

    return $self;
}

##
# Returns the output directory
#
# @param self: The object container
##
sub get_output_dir {
    assert(scalar(@_) == 1);
    my ($self) = @_;

    return $self->{OUTPUT_DIR};
}


##
# Adds a new comparison between a set of null distributions and a set of test
# distributions.
#
# @param self: The object container
# @param null_distribution_file: File containing data from the null distribution  
# @param test_distribution_file: File containing data from the test distribution
# @param name: Name of this comparison
#
# @return an integer ID that identifies this comparison
## 
sub add_comparison {
    assert(scalar(@_) == 4);
    my ($self, $null_file, $test_file, $name) = @_;

    my %comparison_hash = (NULL_DISTRIB_FILE => $null_file,
                           TEST_DISTRIB_FILE => $test_file,
                           OUTPUT_FILE => "$self->{OUTPUT_DIR}/$name" . "_hypothesis_test_results.dat",
                           STATS_FILE => "$self->{OUTPUT_DIR}/$name" . "_stats.dat"
                           );

    push(@{$self->{COMPARISON_INFO}}, \%comparison_hash);
    
    return (scalar(@{$self->{COMPARISON_INFO}}) - 1);
}


##
# Runs the Kolomov-Smirgnov test to compare corresponding data distributions in each
# comparison.  The standard significance level of alpha=0.05 is used.
#
# Each data file should contain data in the format
#    <row>, <col>, <datapoint>.  
# Corresponding rows in the null and test distribution for each comparison are
# evaluated by the hypothesis test.
#
# For each comparison, an output file is created in $self->{OUTPUT_DIRECTORY}.  It
# is formated as follows: 
#   row_number, reject null?, p_value, avgs, stddevs
#
# @param self: The object container
##
sub run_kstest2 {
    
    assert(scalar(@_) == 1);
    my ($self) = @_;

    # First create file stating files involved in each of the comparisons
    $self->$_create_comparison_file();

    my $curr_dir = getcwd();

    chdir '../lib/StatisticalTests';

    system("matlab -nojvm -nosplash -nodisplay -r \"run_hypothesis_tests(\'$self->{COMPARISON_FILE}\', \'compare_edges\'); quit\"".
           "|| matlab -nodisply -r \"run_hypothesis_tests(\'$self->{COMPARISON_FILE}\', \'compare_edges\'); quite\"") == 0
           or die("Could not run Matlab kstest2");
    
    chdir $curr_dir;
    $self->{HAVE_TESTS_BEEN_RUN} = 1;
}


##
# Runs the X^2 test.  All comparisons should be categorical and each file should contain
# data in the following format: 
#   <id> <count> <name>
# id is the id of the category; count is the number of elements contained; name
# is a field that is used to combine multiple categories if each does not
# contain enough elements.
#
# For each comparison, an output file is created in $self->{OUTPUT_DIR}.  It is formated
# as follows
#  1 reject null? p_value, 0, 0
#
# @param self: The object container
# @param sed_file: A matrix specifying similarities values between categories
##
sub run_chi_squared {

    assert(scalar(@_) == 2);
    my ($self, $sed_file) = @_;

    # First create file stating the files involved in each of the comparisons
    $self->$_create_comparison_file();

    my $curr_dir = getcwd();

    chdir '../lib/StatisticalTests';

    system("matlab -nojvm -nosplash -nodisplay -r \"run_hypothesis_tests(\'$self->{COMPARISON_FILE}\', \'compare_categories\', $self->{SED_FILE}\'); quit\"".
           "|| matlab -nodisplay -r \"run_hypothesis_tests(\'$self->{COMPARISON_FILE}\', \'compare_categories\', $self->{SED_FILE}\'); quit\"") == 0
           or die("could not run Matlab to compare categories");

    chdir $curr_dir;
    $self->{HAVE_TESTS_BEEN_RUN} = 1;
}


##
# Returns results of running the selected hypothesis test.
#
# @param self: The object container
# @param ID: The comparison ID for which hypothesis test results are to be returned
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

    assert(scalar(@_) == 2 || scalar(@_) == 3);
    my ($self, $id, $row_nums_to_names);

    if(scalar(@_) == 2) {
        ($self, $id) = @_;
    } else {
        ($self, $id, $row_nums_to_names) = @_;
    }

    my $comparison_hash = $self->{COMPARISON_INFO}->[$id];
    
    open(my $hyp_test_results_fh, "<$comparison_hash->{OUTPUT_FILE}")
        or die ("Could not open $self->{OUTPUT_FILE}: $!\n");

    my $uncomparable = 0;
    my $rows = 0;
    my %hyp_test_results_hash;

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

            if($p_value  < 0) {
                $uncomparable++;
            }
            $rows++;

            $hyp_test_results_hash{$row_name} = { REJECT_NULL => $reject_null,
                                               P_VALUE        => $p_value,
                                               AVGS           => \@avg_latencies,
                                               STDDEVS        => \@stddevs };
        } else {
            print "get_hypothesis_test_results(): Cannot parse line in" .
                " $comparison_hash->{OUTPUT_FILE}\n $_";
            assert(0);
        }
    }
    
    close($hyp_test_results_fh);
    
    return \%hyp_test_results_hash;
}


1;




    
  
