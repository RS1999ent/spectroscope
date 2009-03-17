#! /usr/bin/perl -w

##
# This Perl module implements routines for parsing the results
# of a clustering operation.  It takes in as input the 
# clustering results and a ranking scheme.  It then prints out
# two files
#  File 1: Ranked cluster info, which contains: 
#   <cluster num>, <num requests in s0>, <num requests in s1>, <avg. latency s0>
#   <avg. latency s1>.
#  File 2: Dot graphs of the cluster representatives, ranked according
#  to the scheme specified.
##

package ParseClusteringResults;

use strict;
use Test::Harness::Assert;

#### Private functions ############

##
# Loads information about each cluster into
# $self->{CLUSTER_INFO_HASH}.  For each cluster, an array is stored, 
# consisting of: (<number of requests in s0>, <number of requests in s1>,
# <avg. latency of requests in s0, avg. latency of requests in s1>
#
# @BUG: Right now, the array only contains: 
# <number of requests in s0>, <number of requests in s1>.
# This will have to be expanded later.
#
# @param self: The object-container
##
my $_load_cluster_info_hash = sub {
    my $self = shift;
    
    my $cluster_assignment_hash = $self->{CLUSTER_HASH};
    my $input_vector_hash = $self->{INPUT_VECTOR_HASH};
    
    my %cluster_info_hash;
    
    ##
    # Build a list of 
    # clusters -> <number of reqs in s0 number of reqs in s1>
    #
    # @bug: Eventually want to add avg. latency of cluster and
    # total latency of cluster to the CLUSTER_INFO_HASH as well.    
    ##
    foreach my $key (keys %$cluster_assignment_hash) {
        
        my @input_vec_ids = split(/,/, $cluster_assignment_hash->{$key});
        my @cluster_info = (0, 0, 0, 0);

        foreach(@input_vec_ids) {
            
            my @originating_snapshots = split(/,/, $input_vector_hash->{$_});
            $cluster_info[0] += $originating_snapshots[0];
            $cluster_info[1] += $originating_snapshots[1];
        }
        
        $cluster_info_hash{$key} = join(',', @cluster_info);
    }
    
    $self->{CLUSTER_INFO_HASH} = \%cluster_info_hash;
};   


##
# Loads the following input files into hashes for use by
# the other functions in this class: 
#    $self->{CLUSTERS_FILE} is loaded into $self->{CLUSTER_HASH}
#    $self->{INPUT_VECTOR_FILE} is loaded into #self->{INPUT_VECTOR_HASH}
#
# $self->{CLUSTERS_FILE} contains information about each cluster.  Each
# row represents a cluster and contains the row offsets into
# $self->{INPUT_VECTOR_FILE} of the assignments.
# 
# #self->{INPUT_VECTOR_FILE} contains the MATLAB vector representatio
# of each unique request.  Each row looks like:
#  <# of reqs in s0> <#of reqs in s1> <representation>.
#
# @param self: The object-container
##
my $_load_files_into_hashes = sub {
    my $self = shift;
    
    # Open input file
    open (my $clusters_fh, "<$self->{CLUSTERS_FILE}") 
        or die("Could not open $self->{CLUSTERS_FILE}\n");
    open (my $input_vector_fh, "<$self->{INPUT_VECTOR_FILE}")
        or die("Could not open $self->{INPUT_VECTOR_FILE}\n");
    open (my $input_vec_to_global_ids_fh, "<$self->{INPUT_VEC_TO_GLOBAL_IDS_FILE}")
        or die("Could not open $self->{INPUT_VEC_TO_GLOBAL_IDS_FILE}");
    
    # load $self->{CLUSTERS_FILE};
    my %cluster_hash;
    my $cluster_num = 1;
    while(<$clusters_fh>) {
        chomp;
        my @cluster_items = split(' ', $_);
        my $hash_item = join(',', @cluster_items);
        
        $cluster_hash{$cluster_num} = $hash_item;
        $cluster_num++;
    }
    close($clusters_fh);
    $self->{CLUSTER_HASH} = \%cluster_hash;
    
    # load $self->{INPUT_VECTOR_HASH}
    my %input_vector_hash;
    my $input_vector_num = 1;
    while(<$input_vector_fh>) {
        chomp;
        my @hash_item;
        ##
        # Each line in this file should be of the format
        # Number of requests in s0, number of requests in s1 <vector>
        ##
        if(/(\d+) (\d+)/) {
            @hash_item = ($1, $2);
        } else {
            assert(0);
        }
        
        $input_vector_hash{$input_vector_num} = join(',', @hash_item);
        $input_vector_num++;
    }
    close($input_vector_fh);
    $self->{INPUT_VECTOR_HASH} = \%input_vector_hash;
    
    # load $self->{INPUT_VEC_TO_GLOBAL_IDS_HASH}
    my %input_vec_to_global_ids_hash;
    my $input_vec_num = 1;
    while(<$input_vec_to_global_ids_fh>) {
        chomp;
        my @hash_item = split(/ /, $_);

        $input_vec_to_global_ids_hash{$input_vec_num} = join(',', @hash_item);
        $input_vec_num++;
    }
    close($input_vec_to_global_ids_fh);
    $self->{INPUT_VEC_TO_GLOBAL_IDS_HASH} = \%input_vec_to_global_ids_hash;
    
    
    $self->{INPUT_HASHES_LOADED} = 1;
};


##
# A sorting routine for printing clusters ranked by difference.
# Given two clusters, they are ranked by the following logic
#     * For each cluster calculate ki = (#reqs in s1 - #reqs in s0)/total reqs
#     * if k0 > k1, return 1;
#     * if k0 < k1, return 0;
#     * if k0 == k1 return 1;
#
# @param a: Key of first cluster
# @param b: Key of second cluster
##
my  $_sort_by_difference_in_number_of_reqs = sub {
    my $self = shift;

    my $cluster_info_hash = get_cluster_info_hash();

    my @a_array = split(/,/, $cluster_info_hash->{1});
    my @b_array = split(/,/, $cluster_info_hash->{1});
    
    my $a_s0_reqs = $a_array[0];
    my $a_s1_reqs = $a_array[1];
    my $a_rank = ($a_s1_reqs - $a_s0_reqs)/($a_s0_reqs + $a_s1_reqs);
    
    my $b_s0_reqs = $b_array[0];
    my $b_s1_reqs = $b_array[1];
    my $b_rank = ($b_s1_reqs - $b_s0_reqs)/($b_s0_reqs + $b_s1_reqs);
    
    if($a_rank > $b_rank) {
        return 1;
    }
    if($a_rank < $b_rank) {
        return -1;
    }
    return 0;
};


##
# Prints the cluster representative of the cluster specified
#
# @param self: The object-container
# @param cluster_id: The cluster to print
# @param out_fh: The filehandle to which the graph should be printed
##

my $_print_graph = sub {
    my $self = shift;

    my $cluster_id = shift;
    my $out_fh = shift;

    my $print_graphs_class = $self->{PRINT_GRAPHS_CLASS};

    my $cluster_hash = $self->{CLUSTER_HASH};
    my $input_vec_to_global_ids_hash = $self->{INPUT_VEC_TO_GLOBAL_IDS_HASH};

    my @input_vecs = split(/,/, $cluster_hash->{$cluster_id});

    my @global_ids = split(/,/, $input_vec_to_global_ids_hash->{$input_vecs[0]});
    $print_graphs_class->print_global_id_indexed_request($global_ids[0], $out_fh);
};


#### API functions ################

##
# Constructor for the ParseClusteringResults class
#
# @param proto: The class identifier
#
# @param clusters_file: File containing cluster assignments
# 
# @param input_vector_file: File containing MATLAB compatible
# representations of requests and how many requests from
# each snapshot map to each representation.  Each row
# of this file looks like:
#  <# of s0 reqs> <# of s1 reqs> <MATLAB compatible rep>
# 
# @param rank_format: One of "req_difference,"
# "avg_latency_difference," or "total_latency_difference"
#
# @param output_dir: The directory in which the output files 
# should be placed
#
# @param snapshot0_file: The file containing requests
# from snapshot0.
# 
# @param snapshot0_index: The index on the snapshot0_file
#
# @param snapshot1_file: (OPTIONAL) The file containing requests
# from snapshot1
#
# @param snapshot1_index: (OPTIONAL) The index on snapshot1
##
sub new {
    my $proto = shift;

    my $clusters_file = shift;
    my $input_vector_file = shift;
    my $input_vec_to_global_ids_file = shift;

    my $rank_format = shift;
    my $print_graphs_class = shift;
    my $output_dir = shift;

    assert ($rank_format =~ m/req_difference/);
    # Will add in the following later.
    #        $rank_format eq "avg_latency_difference" ||
    #        $rank_foramt eq "total_latency_difference");

    my $class = ref($proto) || $proto;
    my $self = {};

    $self->{CLUSTERS_FILE} = $clusters_file;
    $self->{INPUT_VECTOR_FILE} = $input_vector_file;
    $self->{INPUT_VEC_TO_GLOBAL_IDS_FILE} = $input_vec_to_global_ids_file;
    $self->{RANK_FORMAT} = $rank_format;
    $self->{OUTPUT_DIR} = $output_dir;
    $self->{PRINT_GRAPHS_CLASS} = $print_graphs_class;
    
    # Hashes that will be maintained.  These hashes
    # are loaded from text files.
    $self->{INPUT_VECTOR_HASH} = undef;
    $self->{CLUSTER_HASH} = undef;
    $self->{INPUT_VEC_TO_GLOBAL_IDS_HASH} = undef;
    $self->{INPUT_HASHES_LOADED} = 0;
    
    # This hash is built by this class.
    $self->{CLUSTER_INFO_HASH} = undef;
    
    bless($self, $class);
    
    return $self;
}


##
# Prints ranked cluster information.  Two files are printed.
# The ranked_clusters_by_<metric>.dat, will contain information
# about each cluster.  The first ranked cluster is printed first
# on the first line and so on.  The second file contains
# DOT graphs of the cluster representatives of each cluster
# ranked appropriately.
#
# @param self: The object-container
##
sub print_clusters {
    my $self = shift;
    
    my $ranked_cluster_info_file;
    my $ranked_cluster_dot_file;
    
    # If the necessary input files have yet been
    # loaded in, do so now
    #
    if($self->{INPUT_HASHES_LOADED} == 0) {
       $self->$_load_files_into_hashes();
   }
    
    # If necessary information about each cluster has
    # not yet been obtained, do so now
    if (!defined $self->{CLUSTER_INFO_HASH}) {
        $self->$_load_cluster_info_hash();
    }
    
    # Prep for printing clusters
    my $cluster_info_hash = $self->{CLUSTER_INFO_HASH};
    
    open(my $ranked_clusters_fh, 
         ">$self->{OUTPUT_DIR}/ranked_clusters_by_$self->{RANK_FORMAT}.dat") 
        or die ("Could not open ranked clusters file\n");
    
    open(my $ranked_clusters_dot_fh,
        ">$self->{OUTPUT_DIR}/ranked_graphs_by_$self->{RANK_FORMAT}.dot");
    
    my $sort_routine;
    if($self->{RANK_FORMAT} =~ /req_difference/) {
        $sort_routine = $_sort_by_difference_in_number_of_reqs;
    }
    
    # Print out cluster information
    my $rank = 1;
    for my $key (sort {    
        my @a_array = split(/,/, $cluster_info_hash->{$a});
        my @b_array = split(/,/, $cluster_info_hash->{$b});
        
        my $a_s0_reqs = $a_array[0];
        my $a_s1_reqs = $a_array[1];
        my $a_rank = ($a_s1_reqs - $a_s0_reqs)/($a_s0_reqs + $a_s1_reqs);
        
        my $b_s0_reqs = $b_array[0];
        my $b_s1_reqs = $b_array[1];
        my $b_rank = ($b_s1_reqs - $b_s0_reqs)/($b_s0_reqs + $b_s1_reqs);
    
        if($a_rank > $b_rank) {
            return -1;
        }
        if($a_rank < $b_rank) {
            return 1;
        }

        # If the ranks are equal, order based on
        # number of requests from snapshot 1
        if($a_s1_reqs > $b_s1_reqs) {
            return -1;
        }
        if($a_s1_reqs < $b_s1_reqs) {
            return 1;
        }

        return 0;
    } keys %$cluster_info_hash) {

        # Print information about the cluster
        my @cluster_info = split(/,/, $cluster_info_hash->{$key});
        printf $ranked_clusters_fh "%5d %5d ", $rank, $key;
        printf $ranked_clusters_fh "%5d %5d %3.2f %3.2f\n", @cluster_info;
        $rank++;
        
        # Print a dot graph representing this cluster
        $self->$_print_graph($key, $ranked_clusters_dot_fh);
    }

    close($ranked_clusters_fh);
    close($ranked_clusters_dot_fh);
}


1;




                                    

                                    
    

    
    
    
    
    


    


            
    
