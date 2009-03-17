#! /usr/bin/perl -w

##
# This perl modules allows users to quickly extract DOT requests
# and their associated latencies.
##

package PrintRequests;

use strict;
use Test::Harness::Assert;

#### Private functions #########

##
# Loads: 
#  $self->{SNAPSHOT0_INDEX_HASH} from $self->{SNAPSHOT0_INDEX_FILE}
#  $self->{SNAPSHOT1_INDEX_HASH} from $self->{SNAPSHOT1_INDEX_FILE}
#  $self->{GLBOAL_ID_TO_LOCAL_ID_HASH} from $self->{GLOBAL_ID_TO_LOCAL_ID_FILE}
#  
# @param self: The object container
##
my $_load_input_files_into_hashes = sub {
    my $self = shift;

    # Load the snapshot0 index
    open(my $snapshot0_index_fh, "<$self->{SNAPSHOT0_INDEX_FILE}")
        or die("Could not open $self->{SNAPSHOT0_INDEX_FILE}");

    my %snapshot0_index_hash;
    while (<$snapshot0_index_fh>) {
        my @data = split(/ /, $_);
        chomp;
        $snapshot0_index_hash{$data[0]} = $data[1];
    }
    close($snapshot0_index_fh);
    $self->{SNAPSHOT0_INDEX_HASH} = \%snapshot0_index_hash;


    # If necessary, load the snapshot1 index
    if (defined $self->{SNAPSHOT1_INDEX_FILE}) {
        assert(defined $self->{SNAPSHOT1_FILE});
    
        open(my $snapshot1_index_fh, "<$self->{SNAPSHOT1_INDEX_FILE}")
            or die("Could not open $self->{SNAPSHOT1_INDEX_FILE}");
    
        my %snapshot1_index_hash;
        while (<$snapshot1_index_fh>) {
            chomp;
            my @data = split(/ /, $_);
            $snapshot1_index_hash{$data[0]} = $data[1];
        }
        close ($snapshot1_index_fh);
        $self->{SNAPSHOT1_INDEX_HASH} = \%snapshot1_index_hash;
    }

    # Load the global_id_to_local_id hash
    open(my $global_id_to_local_id_fh, "<$self->{GLOBAL_ID_TO_LOCAL_ID_FILE}")
        or die ("Could not open $self->{GLOBAL_ID_TO_LOCAL_ID_FILE}");
    
    my %global_id_to_local_id_hash;
    while(<$global_id_to_local_id_fh>) {
        chomp;
        my @data = split(/ /, $_);
        assert($#data == 2);

        $global_id_to_local_id_hash{$data[0]} = join(',', ($data[1], $data[2]));
    }
    close($global_id_to_local_id_fh);
    $self->{GLOBAL_ID_TO_LOCAL_ID_HASH} = \%global_id_to_local_id_hash;

    $self->{HASHES_LOADED} = 1;
};
    
    
#### API functions #############

##
# Class constructor.  Obtains locations of files needed
# for this class to work.
##
sub new {
    my $proto = shift;

    my $global_id_to_local_id_file = shift;
    my $global_req_edge_latencies_file = shift;
    my $snapshot0_file = shift;
    my $snapshot0_index = shift;

    my $snapshot1_file;
    my $snapshot1_index;
    if ($#_ == 1) {
        $snapshot1_file = shift;
        $snapshot1_index = shift;
    }
     
    # There should be no more input arguments
    assert($#_ == -1);
        
    my $class = ref($proto) || $proto;

    my $self = {};

    $self->{GLOBAL_ID_TO_LOCAL_ID_FILE} = $global_id_to_local_id_file;

    $self->{REQ_EDGE_LATENCIES_FILE} = $global_req_edge_latencies_file;

    $self->{SNAPSHOT0_FILE} = $snapshot0_file;
    $self->{SNAPSHOT0_INDEX_FILE} = $snapshot0_index;

    if (defined $snapshot1_file) {
        $self->{SNAPSHOT1_FILE} = $snapshot1_file;
        assert(defined $snapshot1_index);
        $self->{SNAPSHOT1_INDEX_FILE} = $snapshot1_index;
    }
    
    $self->{SNAPSHOT0_INDEX_HASH} = undef;
    $self->{SNAPSHOT1_INDEX_HASH} = undef;
    $self->{GLOBAL_ID_TO_LOCAL_ID_HASH} = undef;
    $self->{HASHES_LOADED} = 0;

    bless($self, $class);
    return $self;
}


##
# Prints the request with the local id and snapshot
# specified to the output filehandle specified
#
# @param self: The object container
# @param local_id: The local id of the request
# @param snapshot: The snapshot to which the req belongs
# @param output_fh: The output filehandle
##
sub print_local_id_indexed_request {
    my $self = shift;

    my $local_id = shift;
    my $snapshot = shift;
    my $output_fh = shift;

    # Input validation
    assert(defined $self &&
           defined $snapshot &&
           defined $output_fh);
    assert($#_ == -1);
    assert($snapshot == 0 || $snapshot == 1);

    if($self->{HASHES_LOADED} == 0) {
        $self->$_load_input_files_into_hashes();
    }

    my $snapshot_fh;
    if($snapshot == 0) {
        my $snapshot_index = $self->{SNAPSHOT0_INDEX_HASH};
        open($snapshot_fh, "<$self->{SNAPSHOT0_FILE}");
        seek($snapshot_fh, $snapshot_index->{$local_id}, 0); # SEEK_SET
    }
    
    if($snapshot == 1) {
        assert(defined $self->{SNAPSHOT1_FILE} &&
               defined $self->{SNAPSHOT1_INDEX_FILE});

        my $snapshot_index = $self->{SNAPSHOT1_INDEX_HASH};
        open($snapshot_fh, "<$self->{SNAPSHOT1_FILE}");
        seek($snapshot_fh, $snapshot_index->{$local_id}, 0); # SEEK_SET
    }

    # Print the request
    my $old_terminator = $/;
    $/ = '}';
    my $request = <$snapshot_fh>;
    print $output_fh "$request\n";
    $/ = $old_terminator;
}


##
# Prints the request with the global id specified to
# the output filehandle specified.
#
# @param self: The object container
# @param global_id: The request that should be printed
# @param output_fh: The filehandle to which to print the request
##
sub print_global_id_indexed_request {
    my $self = shift;
    
    my $global_id = shift;
    my $output_fh = shift;

    if ($self->{HASHES_LOADED} == 0) {
        $self->$_load_input_files_into_hashes();
    }

    # Get the local id and snapshot to which the
    # request belongs
    my $global_id_to_local_id_hash = $self->{GLOBAL_ID_TO_LOCAL_ID_HASH};
    my @local_info = split(/,/, $global_id_to_local_id_hash->{$global_id});
    $self->print_local_id_indexed_request($local_info[0], $local_info[1], $output_fh);
}

1;
