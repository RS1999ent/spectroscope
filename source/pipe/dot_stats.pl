#! /usr/bin/env perl

#
# The Self-* Storage System Project
# Copyright (c) 2008, Carnegie Mellon University.
# All rights reserved.
# http://www.pdl.cmu.edu/  (Parallel Data Lab at Carnegie Mellon)
#
# This software is being provided by the copyright holders under the
# following license. By obtaining, using and/or copying this software,
# you agree that you have read, understood, and will comply with the
# following terms and conditions:
#
# Permission to reproduce, use, and prepare derivative works of this
# software is granted provided the copyright and "No Warranty" statements
# are included with all reproductions and derivative works and associated
# documentation. This software may also be redistributed without charge
# provided that the copyright and "No Warranty" statements are included
# in all redistributions.
#
# NO WARRANTY. THIS SOFTWARE IS FURNISHED ON AN "AS IS" BASIS.
# CARNEGIE MELLON UNIVERSITY MAKES NO WARRANTIES OF ANY KIND, EITHER
# EXPRESSED OR IMPLIED AS TO THE MATTER INCLUDING, BUT NOT LIMITED
# TO: WARRANTY OF FITNESS FOR PURPOSE OR MERCHANTABILITY, EXCLUSIVITY
# OF RESULTS OR RESULTS OBTAINED FROM USE OF THIS SOFTWARE. CARNEGIE
# MELLON UNIVERSITY DOES NOT MAKE ANY WARRANTY OF ANY KIND WITH RESPECT
# TO FREEDOM FROM PATENT, TRADEMARK, OR COPYRIGHT INFRINGEMENT.
# COPYRIGHT HOLDERS WILL BEAR NO LIABILITY FOR ANY USE OF THIS SOFTWARE
# OR DOCUMENTATION.

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
printf("$0:\tAverage graph size: %f\t\n",$stat->mean());
printf("$0:\tstddev of graph size: %f\t\n", sqrt($stat->variance()));
printf("$0:\tMedian graph size: %f\t\n",$stat->median());

print "$0: Finished!\n";
