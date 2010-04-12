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


use strict; 
use Getopt::Long qw(:config no_auto_abbrev);
$| = 1;

my ($dot_file, $line, $out_file);
my $rv;


$rv = GetOptions(
                 'o|outfile=s'        => \$out_file,
#				 'd|dontmount'          => \$dontmnt,
				);

sub usage {
    print "\nusage: aggregate_components dot-file\n";
#	print "\noptions are:\n";
#	print "\t-b / --benchmark [script-name]  run the given benchmark script\n";
	exit(1);
}

# Perl trim function to remove whitespace from the start and end of the string
sub trim($)
{
	my $string = shift;
	$string =~ s/^\s+//;
	$string =~ s/\s+$//;
	return $string;
}

#if($rv != 1 || $#ARGV < 1) {
if($#ARGV != 0) {
    &usage();
} 

# input a dot file.  
$dot_file = $ARGV[0];
unless(open(DOTFILE, $dot_file)) {
    die "aggregate_components: Couldn't open dot file $dot_file!\n";
}

my %bc_map;
my %entity_map;
my %rpc_map;
my %sync_map;  # For nodes of type SSIO_END_TYPE_* ignore incoming edges

my $RPC_CALL = "RPC_CALL_TYPE";
my $RPC_REPLY = "RPC_REPLY_TYPE";
my $SSIO_END_TYPE = "SSIO_END_TYPE";

# Give label to '.'s
print "aggregate_componets: ";

#  Ignore a line that starts with '#' or Digraph G
#  For each label, if it starts with 'e' grab the bread crumb (first field)
#  Only care about time between components, so for each entry of the form
#    b1 -> b2, if b1 and b2 are not in the same component, ignore them.
#  If b1 and b2 are in the same component, add the "R: " field to the total
#    for component e.

my $counter = 0;

# Scan the dot file
while($line = <DOTFILE>) {

    # Indicate work being done
    my @animation = qw( \ | / - );
    print "$animation[$counter++]\b";
    $counter = 0 if $counter == scalar(@animation);

    #remove trailing whitespace
    chomp($line);

    # If line starts with # - ignore
    # If line is Digraph G { - ignore
    if($line =~ /^#/ or $line =~ /^Digraph G/) {
        next;
    }

    # If line looks like bread_crumb [label="en__tag"] - hash bread_crumb into 
    # en's bucket
    if($line =~ /\[label="e\d+/) {


        my ($bc,$label) = split(/\[/, $line);
        my @garbage = split(/"|_/,$label);
        my $entity = $garbage[1];

        $bc = trim($bc);
        $bc_map{$bc} = $entity;

        if(!defined $entity_map{$entity}) {
            $entity_map{$entity} = 0;
        }

        # Keep track of calls of type: RPC_CALL_TYPE -> RPC_REPLY_TYPE because
        # this is time spent waiting, not doing.
        if($line =~ /RPC_CALL_TYPE/) {
            $rpc_map{$bc} = $RPC_CALL;
        } elsif ($line =~ /RPC_REPLY_TYPE/) {
            $rpc_map{$bc} = $RPC_REPLY;
        } elsif ($line =~ /SSIO_END_TYPE/) {
            $sync_map{$bc} = $SSIO_END_TYPE;
        } else {}

    }

    # If line looks like bread_crumb1 -> bread_crumb2 [label="R: t us"] - if
    # bread_crumb1 and bread_crumb2 have the same value, en, add t to en's
    # bucket
    if($line =~ /->/) {
        my ($e1, $e2);
        my ($bc1, $bc2, $garbage) = split(/->|\[/, $line);
        my @labels = split(/s+|\[/, $garbage);
        my $weight = 0;
        my $tmp;
        foreach $tmp (@labels) {
            if($tmp =~ /\d+/) {
                $tmp =~ s/[^\d+\.\d+]*//;
                $weight = $tmp;
                last;
            }
        }

        $bc1 = trim($bc1);
        $bc2 = trim($bc2);

        if(!defined $bc_map{$bc1} || !defined $bc_map{$bc2}) {
            print "aggregate_components: No defined entity for bc:$bc1 or";
            print " $bc2. Skipping, but this is not good!\n";
            next;
        }
        
        $e1 = $bc_map{$bc1};
        $e2 = $bc_map{$bc2};
        
        if($e1 eq $e2) {

            # If this link is of type RPC_CALL -> RPC_REPLY then skip it
            if(defined $rpc_map{$bc1} && defined $rpc_map{$bc2}) {
                if(($rpc_map{$bc1} eq $RPC_CALL) 
                   && ($rpc_map{$bc2} eq $RPC_REPLY)) {
                    next;
                }
            } else {
                # Ignore edges into sync nodes
                if(defined $sync_map{$bc2}) {
                    next;
                }
            }

            $entity_map{$e1} += $weight;
        }
    }
}

#newline after the dashes
print "\n";

my ($key, $value);
# Output results
print "aggregate_components: Final results:\n";
print "aggregate_components:\t Total number of nodes \t" . keys(%bc_map) ."\n";
while (($key,$value) = each(%entity_map)) {
    print "aggregate_components:\t $key \t$value\n";
}
print "aggregate_components: Finished!\n";
