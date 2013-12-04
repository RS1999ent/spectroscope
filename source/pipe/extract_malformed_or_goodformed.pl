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

##
# Simple script that iterates through all input DOT graphs and makes sure that
# all intra-component CALL nodes have a matching REPLY node.
##

use strict;
use Test::More;
use Test::Deep::NoTest;
use Getopt::Long;


#### Global variables #######

my $extract_malformed = 0;


##### Functions #######

sub parse_options {
    GetOptions("malformed+", => \$extract_malformed);
}


##### Main routine ######

parse_options();
my $old_seperator = $/;
$/ = '}';

while(<STDIN>) {

    my %call_type_entities;
    my %reply_type_entities;
    my $request = $_;

    # Get all call type nodes
    while($request =~ /e(\d+)__(.*)CALL_TYPE/g) {
        $call_type_entities{$1}++;
    }

    while($request =~ /e(\d+)__(.*)REPLY_TYPE/g) {
        $reply_type_entities{$1}++;
    }

    if (scalar %call_type_entities || scalar %reply_type_entities) {
        if (eq_deeply(\%call_type_entities, \%reply_type_entities) == 0) {        
            if ($extract_malformed) {
                print "$request\n";            
            }
        } elsif ($extract_malformed == 0) {
            print "$request\n";
        }
    }
}


