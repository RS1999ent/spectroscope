#! /usr/bin/perl -w

my $old_seperator = $/;
$/ = '}'    ;


my $num_reqs = 0;
my $response_times = 0;

while(<STDIN>) {
    
    if(/\# (\d+)  R: ([0-9\.]+)/) {
        # Found the start of a request
        $num_reqs ++;
        $response_times += $2;
    } else {
        next;
    }
}

printf "Avg. response-time: %3.2f\n", $response_times/$num_reqs;
