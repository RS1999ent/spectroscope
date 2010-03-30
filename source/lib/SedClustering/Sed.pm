#!/usr/bin/perl -w

# $cmuPDL: Sed.pm,v 1.6 2010/03/29 22:47:27 rajas Exp $

##
# @author Raja Sambasivan
#
# Provides an interface for calculating and returning the string-edit distance
# between a set of strings.  This Perl Script assumes that the individual
# elements in each string are seperated by single spaces.  So, each string looks
# like:
#    c1 c2 c2....cn.
##

package Sed;

use strict;
use Test::Harness::Assert;
use List::Util qw(max min);
use Data::Dumper;


# Global variables ###############################


# Private routines ##############################

##
# Loads file specified in $self->{INPUT_FILE} into
# a hash and saves this hash in $self->{INPUT_ARRAY}
#
# $self->{INPUT_FILE} should contain lines of the form:
#   <number> <number> <string>
#
# The string should consist of space seperated numbers.
# For example: 1 1000 3 4
#
# @param self: The object container
##
my $_load_input_file = sub {

    assert(scalar(@_) == 1);
    my ($self) = @_;
    
    my @input_array;

    open (my $input_fh, "<$self->{INPUT_FILE}") or 
        die "Sed.pm: _load_input_file(): Could not load $self->{INPUT_FILE}.  $!\n";

    my $i = 0;
    while (<$input_fh>) {
        chomp;

        if(/(\d+) (\d+) ([\d\s]+)/) {

            $input_array[$i] = $3;
            $i++;
        } else {
            print("Sed.pm: _load_input_file(): Input format not correct\n");
            assert(0);
        }
    }
    $self->{INPUT_ARRAY} = \@input_array;

    close($input_fh);
};


##
# Calculates the distance between two strings
#
# @bug: This code is *really* slow.  It is deprecated and has been
# replaced w/a C-only implementation.
#
# @param item1: A reference to an array containing the first string.
# @param item2: A reference to an array containing the second string.
#
# @return: The normalized edit distance between the two items
##
my $_calculate_edit_distance_inner_loop = sub {
    
    assert(scalar(@_) == 3);
    my($self, $item1_array_ref, $item2_array_ref) = @_;
    
    my $item1_size = scalar(@{$item1_array_ref});
    my $item2_size = scalar(@{$item2_array_ref});

    return 1 if ($item1_size == 0);
    
    return 1 if ($item2_size == 0);
    
    my %mat;
    
    # Initialize the distance matrix
    for (my $i = 0; $i <= $item1_size; $i++) {        
        $mat{$i}{0} = $i;
    }
    for (my $j = 0; $j <= $item2_size; $j++) {
        $mat{0}{$j} = $j;
    }

    
    for (my $i = 1; $i <= $item1_size; $i++) {
        for (my $j = 1; $j <= $item2_size; $j++) {
            
            my $cost = ($item1_array_ref->[$i-1] eq $item2_array_ref->[$j-1]) ? 0: 1;
            
            # cell $mat{i}{$j} is the minimum of: 
            # - The cell immediately above plus 1
            # - The cell immediately to the left plus 1
            # - The cell diagonally above and to the left plus the cost
            #
            # Can either insert a new character, delete a character, or
            # substitute an existing character (with associated cost)
            $mat{$i}{$j} = min($mat{$i-1}{$j} +1,
                                $mat{$i}{$j-1} + 1,
                                $mat{$i-1}{$j-1} + $cost);
        }
    }
    
    # Finally, the string-edit distance is the rightmost bottom cell of the matrix
    # Normalize the edit distance by dividing by the larger string
    my $distance = $mat{$item1_size}{$item2_size}/max($item1_size, $item2_size);
    
    return $distance;
};


##
# Wrapper function for calculating edit-distance between
# the strings stored in $self->{INPUT_ARRAY}.  Distance between
# strings is stored in $self->{DISTANCE_HASH};
#
# @param self: The object container
##
my $_calculate_edit_distance_internal = sub {

    assert(scalar(@_) == 1);
    my ($self) = @_;
    
    assert(defined $self->{INPUT_ARRAY});
    my $input_array_ref = $self->{INPUT_ARRAY};

    my %distance_hash;

    my $num_items = scalar(@{$input_array_ref});
    for (my $i = 0; $i < $num_items; $i++) {        

        printf "SeD Calculator: Processing %d of %d\n", $i+1, $num_items;

        my @item1 = split(' ', $input_array_ref->[$i]);
        for (my $j = $i; $j < scalar(@{$input_array_ref}); $j++) {

            if ($self->{BYPASS_SED} == 1) {
                # Don't go through trouble of calculating SeD.  Just insert fake
                # placeholder values, as SeD will not be used for anything useful
                $distance_hash{$i+1}{$j+1} = 1;
                next;
            }

            if($j == $i) {
                $distance_hash{$i+1}{$j+1} = 0;
                next;
            }
            
            my @item2 = split(' ', $input_array_ref->[$j]);

            open(SED_PIPE, "echo $input_array_ref->[$i] -1 $input_array_ref->[$j] | calculate_sed_inner_loop |");
            
            my $distance = <SED_PIPE>;
            close(SED_PIPE);

            # Distance array is 1-indexed.
            $distance_hash{$i+1}{$j+1} = $distance/max(scalar(@item1), scalar(@item2));
            #$distance_hash{$i+1}{$j+1} = $self->$_calculate_edit_distance_inner_loop(\@item1, \@item2);
        }
    }
    
    $self->{DISTANCE_HASH} = \%distance_hash;
};


##
# Prints the hash in $self->{DISTANCE_HASH} to $self->{DISTANCE_FILE}.  
# The file is printed in Matlab sparse matrix format.
#
# @param self: The object container
##
my $_print_edit_distance = sub {
    assert(scalar(@_) == 1);
    my ($self) = @_;
    
    assert(defined $self->{DISTANCE_HASH});
    my $distance_hash_ref = $self->{DISTANCE_HASH};

    open(my $distance_fh, ">$self->{DISTANCE_FILE}");
    
    foreach my $i (sort {$a <=> $b} keys %{$distance_hash_ref}) {
        my $distance_hash_row = $distance_hash_ref->{$i};
        foreach my $j (sort {$a <=> $b} keys %{$distance_hash_row}) {
            print $distance_fh "$i $j $distance_hash_row->{$j}\n";
        }
    }

    close($distance_fh);
};


##
# Loads the data in $self->{DISTANCE_FILE} into a hash
# and stores this hash in $self->{DISTANCE_HASH}
#
# @param self: The object container
##
my $_load_distance_file = sub {
    assert(scalar(@_) == 1);
    my ($self) = @_;
    
    open(my $distance_fh, "<$self->{DISTANCE_FILE}") or 
        die("Sed.pm: Could not open file containing the distance matrix\n");
    
    my %distance_hash;
    
    while (<$distance_fh>) {
        if(/(\d+) (\d+) ([0-9\.]+)/) {
            my $i = $1;
            my $j = $2;
            my $distance = $3;
            $distance_hash{$i}{$j} = $distance;
        } else {
            print "Sed.pm: _load_distance_file(): $self->{DISTANCE_FILE} " .
                "Has the wrong format\n";
        }
    }
    $self->{DISTANCE_HASH} = \%distance_hash;
        
    close($distance_fh);
};
    
    
################# Public static functions ###############################
    
##
# Creates an object for calculating the edit distance between the strings
# specified in the input file.
#
# @param input_file: Each line of the input file is a string.  Individual
# elements of the string must be seperated by spaces.
# @param distance_file: The distance between different strings is written to this
# file.  This file is formated in matlab sparse matrix format.
# @param bypass_sed: > 0 if 'mock values' should be inserted instead of 
# edit distances
##
sub new {
    assert(scalar(@_) == 4);    

    my ($proto, $input_file, $distance_file, $bypass_sed) = @_;

    my $class = ref($proto) || $proto;
    
    my $self = {};

    $self->{INPUT_FILE} = $input_file;    
    $self->{DISTANCE_FILE} = $distance_file;

    $self->{DISTANCE_HASH} = undef;
    $self->{INPUT_ARRAY} = undef;

    $self->{BYPASS_SED} = $bypass_sed;
    
    bless($self, $class);
    return $self;
}


## 
# Returns true if the output file specified in the constructor already exists
#
# @param self: The object container
#
# @return 1 if output files exist, 0 otherwise
##
sub do_output_files_exist {

    assert(scalar(@_) == 1);
    my ($self) = @_;

    if (-e($self->{DISTANCE_FILE})) {
        return 1;
    }

    return 0;
}


##
# Returns a file containing the distance matrix
# 
# @param self: The object container
# 
# @return The file containing the distance matrix
#
sub get_distance_matrix_file {

    assert(scalar(@_ ) == 1);
    my ($self) = @_;

    return $self->{DISTANCE_FILE};
}


##
# Calculates the edit distance between the strings specified in the input file
# and writes the results out to the distance_matrix_file specified in the object
# constructor.
#
# @param self: The object container
#
# @param self: The object contaienr
##
sub calculate_all_edit_distances {
    
    assert(scalar(@_) == 1);
    my ($self) = @_;

    $self->$_load_input_file();
    $self->$_calculate_edit_distance_internal();
    $self->$_print_edit_distance();

    # This hash is no longer needed, since all edit distances
    # have been computed and are stored in $self->{DISTANCE_HASH}
    $self->{INPUT_ARRAY} = undef;
}


##
# Returns the edit distance between two strings.  
#
# Two modes of operation are supported.  
#
#   1)If edit distances for all items have already been calcualted, this
#   function loads the distance file containign them from disk, if necessary,
#   and returns the pre-computed distance.  The distance file is kept in memory
#   until this object is destroyed.
#
#   2)If edit distances have not been calculated, this functions calculates the
#   distance 'on demand' by loading the data in $self->{INPUT_FILE} into memory
#   and using the strings it contains.  $self->{INPUT_FILE} is retained in
#   memory until "calculate_all_edit_distances()" is called, or this object is
#   destroyed.
#
# @param s1_index: The index of the first string in the input file
# @param s2_index: The index of the 2nd string in the input file
#
# @return: The distance between the two strings
#
# @note The indices are numbered starting at 1.
##
sub get_sed {
 
   assert(scalar(@_) == 3);
    my ($self, $s1_index, $s2_index) = @_;

   # assert that s1_index and s2_index are 1-indexed
   assert($s1_index > 0 && $s2_index > 0);

   # Might have already computed all of the edit distances, but just not loaded
   # the file into $self->{DISTANCE_HASH}
    if (!defined $self->{DISTANCE_HASH} && -e $self->{DISTANCE_FILE}) {
        $self->$_load_distance_file();
    }

   # Case where all of the edit distances have already been computed
   if (defined $self->{DISTANCE_HASH}) {
       my $retval = (defined $self->{DISTANCE_HASH}->{$s1_index}{$s2_index})?
           $self->{DISTANCE_HASH}->{$s1_index}{$s2_index}: 
           $self->{DISTANCE_HASH}->{$s2_index}{$s1_index};
       
       assert(defined $retval);
       return $retval;
   } 

   # Case where all of the edit distances have not been pre-calculated.
   # User wishes to calculate edit distance "on demand."
   if (!defined $self->{INPUT_ARRAY}) { 
       $self->$_load_input_file();
   }

   my @item1 = split(' ', $self->{INPUT_ARRAY}->[$s1_index - 1]);
   my @item2 = split(' ', $self->{INPUT_ARRAY}->[$s2_index - 1]);
   print "Performing on-demand SeD calculation for offsets: ($s1_index, $s2_index)\n";
   my $retval = $self->$_calculate_edit_distance_inner_loop(\@item1, \@item2);
   assert(defined $retval);
   return $retval;
}

1;       
