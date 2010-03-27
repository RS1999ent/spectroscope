#!/usr/bin/perl -w

# $cmuPDL: Sed.pm,v 1.1 2009/08/06 17:33:20 rajas Exp $

##
# @author Raja Sambasivna
#
# This class tests the functionality of the string-edit distance class
##

package Test::Sed;

use strict;
use Test::Harness::Assert;
use base qw(Test::Class);
use Test::More;
use Test::Deep;

use lib 'lib';
use SedClustering::Sed;

delete @ENV{qw(IFS CDPATH ENV BASH_ENV)};
$ENV{'PATH'} = '/h/rajas/research/cvs_controlled/temp/perf_diagnosis/source/lib/SedClustering/';



#### Global variables #######

my @strings = ("0 1",
               "1 0",
               "1 0 2",
               "1 20 30 2");

my %expected_hash_row1 = ( 1 => 0,
                           2 => 1,    # substitution
                           3 => 2/3,     # deletion/additon or substitution/additon
                           4 => 1);    # deletion/addition

my %expected_hash_row2 = ( 2 => 0,
                           3 => 1/3,    # additoin
                           4 => .75 );  # deletion/addition

my %expected_hash_row3 = ( 3 => 0,
                           4 => .5);    # deltion/addition

my %expected_hash_row4 = ( 4 => 0);

my %expected_hash = ( 1 => \%expected_hash_row1,
                      2 => \%expected_hash_row2,
                      3 => \%expected_hash_row3,
                      4 => \%expected_hash_row4);

my $input_file = "/tmp/sed_test_input_vector.dat";
my $distance_file = "/tmp/sed_test_distance_matrix.dat";


##### Public functions ########

##
#  Create a test input file and calculate edit distance.
#  Verify that that do_output_files_exist() returns 0 before edit dist calc
#  Verify that $sed->{DISTANCE_HASH} is populated correctly
#  Verify that do_output_files_exist() returns 1 after edit dist calc
##
sub create_input_file_and_calculate_edit_distance: Tests(startup => 3) {

    open(my $input_fh, ">$input_file");
    
    foreach(@strings) {
        my $str = $_;
        printf $input_fh "1 1 $str\n";
    }
    close($input_fh);

    my $sed = new Sed($input_file, $distance_file);
    is($sed->do_output_files_exist(), 0, "Check that output file(s) do not exist");

    $sed->calculate_edit_distance(0);

    cmp_deeply($sed->{DISTANCE_HASH}, \%expected_hash, "Check Distance Hash contains the correct data");
    is($sed->do_output_files_exist(), 1, "Check that output file(s) do exist");

}


## 
# After tests are complete, remove the test input file and distnce_file
##
sub delete_files: Tests(shutdown) {
    
    $ENV{'PATH'} =~ /(.*)/; $ENV{'PATH'} = $1;
    system("rm -rf $input_file");
    system("rm -rf $distance_file");
}


## 
# Test that the name of the distance_matrix_file and input_file are saved
##
sub test_new: Test(2) {

    my $sed = new Sed($input_file, $distance_file);

    is ($sed->{INPUT_FILE}, $input_file, "Check that the input file is saved by the object");
    is ($sed->{DISTANCE_FILE}, $distance_file, "Check that the distance matrix is saved");
}


## 
# Test that we can retrieve the edit distance of strings correctly
##
sub test_get_sed: Test(16) {

    my $sed = new Sed($input_file, $distance_file);

    for my $i (sort {$a <=> $b} keys %expected_hash) {
        for my $j (sort {$a <=> $b} keys %expected_hash) {
            my $distance = $sed->get_sed($i, $j);
            my $test_distance = (defined $expected_hash{$i}{$j})? $expected_hash{$i}{$j} : $expected_hash{$j}{$i};
            is($distance, $test_distance, "distance between $i and $j should be $test_distance, but is $distance\n");
        }
    }
}
    
