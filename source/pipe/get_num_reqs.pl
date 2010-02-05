#! /usr/bin/perl -w

##
# Counts the number of requests in the input file
##

my $old_seperator = $/;
$/ = '}';

my $count = 0;
while (<STDIN>) {
    $count++;
}

my $num_req = $count -1;
print "There are $num_req requests in this trace\n";
