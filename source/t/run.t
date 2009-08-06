#! perl -T

# $cmuPDL: Sed.pm, v$


##
# @author Raja Sambasivan
# 
# Wrapper code for running unit tests
##


use strict;
use warnings;

use Test::Class;

use lib 't/tests';
use Test::SedClustering::Sed;

Test::Class->runtests;
