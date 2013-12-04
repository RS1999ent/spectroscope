#! /usr/bin/env perl

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

# @author: Spencer Whitman
#
# Do simple parsing to output simple statistics about a dot graph.
#

use strict; 
use Getopt::Long qw(:config no_auto_abbrev);

# Load statistics library
use lib "/h/ss/lib";
use Statistics::Descriptive;

$| = 1;

my ($dot_file, $line, $category, $quiet);
my $rv;
my %graph_stats;
my $nodes = 0;

my $stat;

my $counter = 0;
my @animation = qw( \ | / - );

$rv = GetOptions(
    'q|quiet'            => \$quiet,
    'c|category'         => \$category,
    );

sub usage {
    print "\nusage: $0 dot-file\n";
    print "Options:\n";
    print "-q\--quiet     suppress waiting ticker\n";
    print "-c\--category  Graphs are categories (subtract 1 from node count)\n";
	exit(1);
}

sub average_graph_size {
    my $stats = shift(@_);
    my ($nodes, $num_graphs);
    my $sum = 0;
    my $count = 0;

    die "ERROR: $0: average_graph_size: Bad input, not pointer to hash!" 
        if (ref($stats) ne 'HASH');

    while (($nodes,$num_graphs) = each(%$stats)) {
        $sum += $nodes * $num_graphs;
        $count += $num_graphs;
    }

    die "ERROR: $0: average_graph_size: No graphs found!" if ($count < 1);

    return ($sum / $count);
}

if($#ARGV != 0) {
    &usage();
} 

# input a dot file.  
$dot_file = $ARGV[0];
unless(open(DOTFILE, $dot_file)) {
    die "$0: Couldn't open dot file $dot_file!\n";
}

print "$0: Working...: ";

$stat = Statistics::Descriptive::Full->new();

# Scan the dot file
while($line = <DOTFILE>) {

    # Indicate work being done
    if(!$quiet) {
        print "$animation[$counter++]\b";
        $counter = 0 if $counter == scalar(@animation);
    }

    #remove trailing whitespace
    chomp($line);

    # If line starts with # - ignore
    # If line is a link (contains ->) - ignore
    if($line =~ /^#/ or $line =~ /->/) {
        next;
    }

    # New graph, reset node count
    if($line =~ /^Digraph G/) {
        $nodes = 0;
    }

    # Line is a node declaration contains [label= (no ->)
    if($line =~ /\[label=/) {
        $nodes++;
    }
    
    # End of a graph
    if($line =~ /}/) { 
        $nodes-- if(defined($category));

        $stat->add_data($nodes);
        $graph_stats{$nodes}++;
    }
}

print "\n";
my ($key, $value);
my $total = 0;
# Output results
print "$0: Final results:\n";
while (($key,$value) = each(%graph_stats)) {
    print "$0:\t$value Graphs had $key nodes\n";
    $total += $value;
}

#print "$0:\tTotal number of graphs: \t" . $total ."\n";
#print "$0:\tAverage graph size: \t" . average_graph_size(\%graph_stats) ."\n";

print "$0:\tStats:\n";
printf("$0:\t# of graphs: %d\t\n",$stat->count());
printf("$0:\tAverage graph size: %d\t\n",$stat->mean());
printf("$0:\tVariance of graph size: %d\t\n",$stat->variance());
printf("$0:\tMedian graph size: %d\t\n",$stat->median());

print "$0: Finished!\n";
