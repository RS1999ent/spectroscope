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
#
# @author: Raja Sambasivan
# 
# Extracts the N most expensive requests.
#
###

use strict;
use Getopt::Long;


## Global variables #####

my $graph_file;
my @expensive_reqs = ();
my $num_expensive_reqs;
my $print_help_and_exit = 0;


## Main

parse_options();
extract_most_expensive_reqs();
print_expensive_reqs();


## 
# Prints most expensive requests to STDOUT
##
sub print_expensive_reqs {

    my $old_seperator = $/;
    $/ = '}';
    
    for(my $i = 0; $i < $num_expensive_reqs; $i++) {
        if(defined $expensive_reqs[$i]) {
            print STDOUT $expensive_reqs[$i]->{REQUEST};
        }
        else {
            return;
        }
    }

    $/ = $old_seperator;
}


sub move_items_down {
    my $start = shift;
    my $temp;


    $temp = $expensive_reqs[$start];

    for(my $i = $start+1; $i < $num_expensive_reqs; $i++) {

        my $temp2 = $expensive_reqs[$i];
        $expensive_reqs[$i] = $temp;
        $temp = $temp2;
    }
}


##
# comparison function for sort
##
sub insertion_sort {
    my $req_latency = shift;
    my $req_string = shift;
    
    for (my $i = 0; $i < $num_expensive_reqs; $i++) {
        if(!defined $expensive_reqs[$i]) {
            $expensive_reqs[$i] = {LATENCY => $req_latency,
                                   REQUEST => $req_string};
            return;
        }
        
        if($req_latency >= $expensive_reqs[$i]->{LATENCY}) {
            move_items_down($i);
            $expensive_reqs[$i] = {LATENCY => $req_latency,
                                   REQUEST => $req_string};
            return;
        }
    }
}


##
# Iterates through graph file and extracts the most expensive ones
##
sub extract_most_expensive_reqs {
    
    my $old_seperator = $/;
    $/ = '}';

    my $i = 0;
    while(<STDIN>) {
        my $request_latency;
        my $request_id;

        if(/\# (\d+)  R: ([0-9\.]+)/) {
            # Found the start of a request
            $request_id = $1;
            $request_latency = $2;
        } else {
            next;
        }
        insertion_sort($request_latency, $_);
    }

    $/ = $old_seperator;
}


##
# Prints usage
##
sub print_usage {
    print "usage: extract_most_expensive_requests.pl";
    print "\t--n: Number of most expensive requests to extract\n";
    print "\t--h: (Optional) print help and exit\n";
}


##
# Collects user specified options
##
sub parse_options {

    GetOptions("n=i"     => \$num_expensive_reqs,
               "h+"     => \$print_help_and_exit);

    if(!defined \$num_expensive_reqs
       || $print_help_and_exit == 1) {
        print_usage();
        exit(-1);
    }
}







