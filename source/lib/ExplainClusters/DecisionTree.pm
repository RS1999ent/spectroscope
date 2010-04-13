#! /user/bin/perl -w

# $cmuPDL: DecisionTree.pm,v 1.6 2010/04/08 18:44:15 rajas Exp $
##
# @author Raja Sambasivan
#
# @brief Provides an API for using a decision tree
# to find the low-level data that best separates
# two clusters of request-flow graphs
##

package DecisionTree;

use strict;
use warnings;
use diagnostics;
use Test::Harness::Assert;
use DBI;
use Data::Dumper;

use ExplainClusters::MatchGraphs qw[match_graphs];
use ParseDot::StructuredGraph qw[get_req_structure];


#### Global constants ####################

no define DEBUG =>;

#### Global variables ####

# Data for these columns will not be included when
# constructing the data table and column headers
my $_exclude_list = "breadcrumb timestamp tid soid file_soid status pid optype";


### Static Callback methods for the match graphs module #########

sub add_to_matching_nodes_callback {
    assert(scalar(@_) == 4);
    my ($callback_args, $name, $breadcrumb, $timestamp)  = @_;

    my $array = $callback_args->{ARRAY};

    push(@{$array}, $name);
}               


sub create_data_table_entries_callback {

    assert(scalar(@_) == 4);
    my ($callback_args, $name, $breadcrumb, $timestamp) = @_;

    # Sanity check that the name matches what we expect
    my $match_list = $callback_args->{MATCHING_NODES};

    my $match_name = $match_list->[$callback_args->{IDX}];
    assert($match_name eq $name);
    
    # Format the query
    my $queries = $callback_args->{QUERIES};
    my $query = $queries->{$callback_args->{IDX}};
    if(!defined $query) {
        $callback_args->{IDX}++;
        return;

    }

    $query = "$query " . "WHERE breadcrumb=$breadcrumb and timestamp=$timestamp";

    #print "Issuing query: $query\n";

    # Prepare the query
    my $dbh = $callback_args->{DB_CONN};
    my $sth = $dbh->prepare($query);
    assert(defined $dbh);

    ### Execute the statement in the database
    $sth->execute
        or die "Can't execute SQL statement: $DBI::errstr\n";
    
    ### There should be only one row of output data.  Retrieve it.
    my $row_num = 0;
    my $outfid = $callback_args->{OUTFID};
    while (my @row = $sth->fetchrow_array()) {        
        my $row_data = join(', ', @row);
        print $outfid "$row_data, ";
        $row_num++;
    }
    assert($row_num == 1);
    warn "Data fetching terminated early by error: $DBI::errstr\n"
        if $DBI::err;

    $callback_args->{IDX}++;
}


#### Private functions ###########################################

# Constructs a hash-table that represents the names of the columns for the
# regression tree input table.  The format of hash-table is as follows: #
#
# column_header_hash->{column_id} = 
#    {NAME => string representing column name,
#     IDX => array index into node_array_ptr of the
#            node (table) this column belongs to
#
# This function also constructs the queries needed to get the data for these
# columns from each of the tables.  The queries are returned in a hash as
# follows:
#
# queries->{idx} = string representing the query.
#
# @param self: The object container
# @param node_list: A pointer to an array of nodes.  These nodes represent
# tables in the underlying database.
#
# @return: a pointer to a hash-table with two elements: 
#     { COLUMN_HEADERS => \%column_header_hash,
#       QUERIES => \%queries }
##
my $_build_column_names_and_queries = sub {
    assert(scalar(@_) == 2);

    my $self = shift;
    my $node_array_ptr = shift;
    
    my %column_header_hash;
    my %queries;

    my $db0_conn = $self->{S0_DB_CONN};

    my $column_id_counter = 1;
    my $node_idx = 0;

    foreach (@$node_array_ptr) {        
        # Get one row of results from each table; the
        # handle to the statement will be populated
        # w/the table schema once the query is executed
        my $table_name = $_;
        my $statement = "SELECT * FROM $table_name limit 1";
        
        my $sth = $db0_conn->prepare($statement) || 
            die("Could not prepare statement\n");
        
        $sth->execute;
        my @row = $sth->fetchrow_array;
        
        my $column_names = "";
        my $found_non_excluded_attrib = 0;
        foreach (@{$sth->{NAME_lc}}) {

            if ($_exclude_list =~ /$_/) {
                next;
            }
            $found_non_excluded_attrib = 1;
            $column_header_hash{$column_id_counter} = { TABLE_NAME => $table_name,
                                                        ATTRIBUTE_NAME => $_,
                                                        IDX => $node_idx };
            $column_names  = $column_names . "$_" . ", ";
            $column_id_counter++;
        }
        
        # Remove last space and last ','
        chop($column_names);
        chop($column_names);

        if($found_non_excluded_attrib) {
            $queries{$node_idx} = "SELECT $column_names FROM $table_name";
        } else {
            $queries{$node_idx} = undef;
        }
        $node_idx++;
    }

    return ({COLUMN_HEADER => \%column_header_hash,
             QUERIES => \%queries});
};


##
# Builds the data table, which serves as the input to the regression
# tree algorithm.  Each row of the data-table corresponds to a request
# assigned to the input cluster.  The columns for each row are
# created by issuing the queries passed in for each of the matching
# nodes.  The label assigned to each row is the $label parameter passed in.
#
# @param self: The object container
# @param cluster_id: The ID of the cluster containing the requests
# whose low-level data is to be extracted
# @param matching_nodes_array_ptr: Pointer to the array of matching
# nodes between the mutated cluster and the original cluster
# @param queries_hash_ptr: A pointer to a hash table, where the keys
# are indexes into the matching_nodes_array_ptr and the values are
# strings that reprsent the SQL query to be issues to retrieve the
# columns
# @param outfid: filehandle to which the datatable should be written.
# This file will be appended.
# @param label: The label that will be applied to each row
##
my $_build_and_print_data_table = sub {

    assert(scalar(@_) == 7);
    my($self, $cluster_id, $template_container_ptr,
       $matching_node_array_ptr, $queries_hash_ptr,
       $outfid, $label) = @_;

    my $cluster_info_obj = $self->{PARSE_CLUSTERING_RESULTS_OBJ};
    my $request_info_obj =$self->{REQUEST_INFO_OBJ};
    
    my $cookie = 0;
    my $callback_args = {OUTFID => $outfid, 
                         MATCHING_NODES => $matching_node_array_ptr,
                         QUERIES => $queries_hash_ptr, 
                         IDX => 0};

    while (-1 != (my $global_id = $cluster_info_obj->get_cluster_requests($cluster_id, \$cookie))) {

        my $req_string = $request_info_obj->get_global_id_indexed_request($global_id);
        my $req_container = StructuredGraph::build_graph_structure($req_string);
        my $snapshot = $request_info_obj->get_snapshots_given_global_ids([$global_id]);
        
        if ($snapshot->[0] == 0) {
            $callback_args->{DB_CONN} = $self->{S0_DB_CONN};
        } else {
            assert($snapshot->[0] == 1);
            $callback_args->{DB_CONN} = $self->{S1_DB_CONN};
        }

        $callback_args->{IDX} = 0;
        
        MatchGraphs::match_graphs($req_container, $template_container_ptr, 
                                  \&DecisionTree::create_data_table_entries_callback,
                                  $callback_args);

        # The callback is called for every node that matches between the graphs;
        # The number of nodes that match should be equal to the size of the 
        # matching_node_array_ptr; since the callback fn increments
        # $callback_args->{IDX}, the following is an invariant:
        assert($callback_args->{IDX} == scalar(@$matching_node_array_ptr));
        
        printf $outfid "$label\n";
    }
};

##
# Creates the C4.5 name file in the filehandle specified.  
# This file is formatted as follows: 
# 
# <class label 1, class label 2, ..., class label k>.#
# <attribute 1>: <continuous, discrete (#num values)>
# ...
# <attribute M>: <continuous, discrete (#num values)>
#
# For now, we model all variables as continuous.  
#
# @param names_hash_ptr: A pointer to a hash specifiying the
# names of each attribute (column).  The attributes
# will be printed in the order specified by the array
#
# @param $class_labels_ptr: A pointer to an array of lables
#
# @param outfid: The filehandle to which the name file should
# be printed
##
my $_create_attribute_list = sub {

    assert(scalar(@_) == 4);

    (my $self, my $names_hash_ptr, my $class_labels_ptr, my $outfid) = @_;

    # First print the class labels
    my $class_labels = join(', ', @$class_labels_ptr) . "\.";
    print $outfid "$class_labels\n";

    # Now print the attributes
    for my $key (sort {$a <=> $b} keys %$names_hash_ptr) {
        my $hash_val = $names_hash_ptr->{$key};
        my $name = "$hash_val->{TABLE_NAME}" . "_" . "$hash_val->{ATTRIBUTE_NAME}" . 
            "_" . "$hash_val->{IDX}";
        
        print $outfid "$name: continuous\.\n";
    }
};

    
### Public functions ###########################################

       
##
# The object constructor
#
# @param proto: Passed in automatically
# @param request_info_obj: A instantiation of the PrintGraphs class
# that defines how to print and obtain information about requests in
# the input datasets
# @param parse_clustering_results_obj: A instantiation of the 
# ParseClusteringResults class that can be used to obtain info about
# the request clusters
# @param output_dir: The directory in which output should be placed
# @param s0_database_file: Database containing low-level information
# about requests in snapshot0
# @param s1_database_file: Database containing low-level information
# about requests in snapshot1
#
# @return An object of class DecisionTree
##
sub new {

    assert(scalar(@_) == 5 ||
           scalar(@_) == 6);

    my $proto = shift;
    my $request_info_obj = shift;
    my $parse_clustering_results_obj = shift;
    my $output_dir = shift;
    my $s0_database_file = shift;
    my $s1_database_file;
    if(scalar(@_) == 1) {
        $s1_database_file = shift;
    }

    # Make sure all input was specified
    assert(defined $proto && defined $request_info_obj
           && defined $parse_clustering_results_obj 
           && defined $s0_database_file
           && defined $output_dir);

    my $class = ref($proto) || $proto;

    # Fill in $self structure
    my $self = {};
    $self->{S0_DB_CONN} = DBI->connect( "dbi:SQLite:$s0_database_file", "", "" ) ||
        die("Could not connect to $s0_database_file: $DBI::errstr\n");
    $self->{S0_DB_CONN}->{AutoCommit} = 0;
    if (defined $s1_database_file) {
        $self->{S1_DB_CONN} = DBI->connect( "dbi:SQLite:$s1_database_file", "", "" ) ||
            die("Could not connect to $s1_database_file: $DBI::errstr\n");
        $self->{S1_DB_CONN}->{AutoCommit} = 0;
    }
    else {
        $self->{S1_DB_CONN} = undef;
    }

    $self->{REQUEST_INFO_OBJ} = $request_info_obj;
    $self->{PARSE_CLUSTERING_RESULTS_OBJ} = $parse_clustering_results_obj;

    bless($self, $class);
}
 

##
# Given the ID of a mutated cluster and the original cluster,
# this function generates a regression tree that attempts to 
# separate the two clusters using the low-level data referred
# to by the constituent requests.  When this function returns,
# output_dir will be populated by the decision rules and tree
# generated by the C4.5 classifier.
#
# @param original_cluster_id: ID of requests in the original cluster
# @param mutated_cluster_id: ID of requests in the mutated cluster
# @param output_dir: Location in which the output regression tree
#  rules should be placed
# 
sub explain_clusters {
    assert(scalar(@_) == 4);
    my($self, $original_cluster_id, 
       $mutated_cluster_id, $output_dir) = @_;

    my $request_info_obj = $self->{REQUEST_INFO_OBJ};
    my $clustering_results_obj = $self->{PARSE_CLUSTERING_RESULTS_OBJ};

    my $original_request_id = 
        $clustering_results_obj->get_global_id_of_cluster_rep($original_cluster_id);
    my $mutated_request_id = 
        $clustering_results_obj->get_global_id_of_cluster_rep($mutated_cluster_id);

    my $req_string = $request_info_obj->get_global_id_indexed_request($original_request_id);
    my $original_req_container = StructuredGraph::build_graph_structure($req_string);

    $req_string = $request_info_obj->get_global_id_indexed_request($mutated_request_id);
    my $mutated_req_container = StructuredGraph::build_graph_structure($req_string);

    # Get list of nodes that match between the two graphs
    my @matching_nodes_list;
    my $callback_args = { ARRAY => \@matching_nodes_list };
    MatchGraphs::match_graphs($original_req_container,
                              $mutated_req_container,
                              \&DecisionTree::add_to_matching_nodes_callback,
                              $callback_args);
    print Dumper @matching_nodes_list;

    # Build up column headers and queries for extracting the low-level data
    my $queries_column_names = $self->$_build_column_names_and_queries(\@matching_nodes_list);

    # Get names of the data table and header for C45
    my $filestem = "C45" . "_cluster" . "$original_cluster_id" . "_cluster" . "$mutated_cluster_id";

    # Build up the data table.  Classify rows corresponding to the low-level
    # data of requests from the original cluster as '0.'  Classify rows
    # corresponding to the low-level data from the mutated cluster as '1'.
    my $datatable_file = "$output_dir/$filestem.data";
    open(my $datatable_fid, ">$datatable_file");

    $self->$_build_and_print_data_table($original_cluster_id, 
                                        $mutated_req_container,
                                        \@matching_nodes_list,
                                        $queries_column_names->{QUERIES}, 
                                        $datatable_fid,
                                        "Non_problem");
    $self->$_build_and_print_data_table($mutated_cluster_id,
                                        $original_req_container,
                                        \@matching_nodes_list,
                                        $queries_column_names->{QUERIES},
                                        $datatable_fid,
                                        "Problem");
    close($datatable_fid);


    # Print the header table.
    my $header_file = "$output_dir/$filestem.names";
    open(my $header_fid, ">$header_file");
    
    $self->$_create_attribute_list($queries_column_names->{COLUMN_HEADER},
                                   ["Problem", "Non_problem"],
                                   $header_fid);
    close($header_fid);
}


1;
    
    
