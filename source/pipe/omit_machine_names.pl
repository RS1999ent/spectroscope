#! /usr/bin/perl -w

use strict;
use warnings;

while (<STDIN>) {
    $_=~ s/SS.+?_//g;
    print $_;
}
