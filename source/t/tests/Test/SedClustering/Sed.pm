#!/usr/bin/perl -w

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

# $cmuPDL: Sed.pm,v 1.2 2010/03/27 04:15:48 rajas Exp $

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
sub create_input_file: Tests(startup) {

    open(my $input_fh, ">$input_file");
    
    foreach(@strings) {
        my $str = $_;
        printf $input_fh "1 1 $str\n";
    }
    close($input_fh);
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
sub a_test_new: Test(2) {

    my $sed = new Sed($input_file, $distance_file, 0);

    is ($sed->{INPUT_FILE}, $input_file, "Check that the input file is saved by the object");
    is ($sed->{DISTANCE_FILE}, $distance_file, "Check that the distance matrix is saved");
}


##
# Test get_sed() functianlit when edit distances are not pre-computed
##
sub b_test_get_sed: Test(17) {
     
    my $sed = new Sed($input_file, $distance_file, 0);
    for my $i (sort {$a <=> $b} keys %expected_hash) {
        for my $j (sort {$a <=> $b} keys %expected_hash) {
            my $distance = $sed->get_sed($i, $j);
            my $test_distance = (defined $expected_hash{$i}{$j})? $expected_hash{$i}{$j} : $expected_hash{$j}{$i};
            is($distance, $test_distance, "distance between $i and $j should be $test_distance, but is $distance\n");
        }
    }
    if (defined $sed->{DISTANCE_HASH}) {
        is(0, 1, "Distance hash should be undef, but is defined!");
    }
}


##
# Test Compute_all_edit_distances().  
# Verify that the distance hash is written to disk properly.
##
sub c_test_compute_all_edit_distances: Test(3) {

    my $sed = new Sed($input_file, $distance_file, 0);
    is($sed->do_output_files_exist(), 0, "Check that output file(s) do not exist");

    $sed->calculate_all_edit_distances();

    cmp_deeply($sed->{DISTANCE_HASH}, \%expected_hash, "Check Distance Hash contains the correct data");
    is($sed->do_output_files_exist(), 1, "Check that output file(s) do exist");
}


## 
# Test get_sed() functionality when edit distances are pre-computed.
##
sub d_test_get_sed_pre_computed: Test(17) {

    my $sed = new Sed($input_file, $distance_file, 0);
    for my $i (sort {$a <=> $b} keys %expected_hash) {
        for my $j (sort {$a <=> $b} keys %expected_hash) {
            my $distance = $sed->get_sed($i, $j);
            my $test_distance = (defined $expected_hash{$i}{$j})? $expected_hash{$i}{$j} : $expected_hash{$j}{$i};
            is($distance, $test_distance, "distance between $i and $j should be $test_distance, but is $distance\n");
        }
    }
    cmp_deeply($sed->{DISTANCE_HASH}, \%expected_hash, "Check distance hash is populated");
}




    
