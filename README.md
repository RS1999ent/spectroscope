Spectroscope
============
Spectroscope is an implementation of request-flow comparison, a
technique for diagnosing performance changes in distributed systems.
Please see the NSDI 2011 paper <a href="http://www.pdl.cmu.edu/PDL-FTP/SelfStar/NDSI11_abs.shtml">"Diagnosing performance changes by comparing request flows"</a> for more information.

Overview of source code
============
Spectroscope is written as several perl modules that interface with
each other and Matlab.  Running Spectroscope requires several perl
modules, listed below, Matlab.  To use portion of Spectroscope that
identifies low-level differences between mutations and precursors
(explain_clusters.pl), the C4.5 regression tree program must be
installed.

Required Perl packages:
Test::Harness::Straps
define
Statistics::Descriptive

Naming conventions
============
In the NSDI'11 paper, categories are groups of requests with the same
structure or topology.  In the Spectroscope source code, these are
more generally called 'clusters.'  This is because the source code
allows on to insert arbritrary clustering algorithms (cluster by
structure is one such example).

Similarly, in the NSDI'11 paper, categories that requests that have
changed in structure during the problem period are called
'precursors.'  In this code, they may be called 'originators.'

Running Spectroscope
============
To run Spectroscope, cd to 'spectroscope/source/spectroscope.' and run
spectroscope.pl.  You can see the various command line parameter
options by running spectroscope.pl w/o any options.  The options are
further described below:

--output_dir: The directory in which output should be placed.

--snapshot0: The name(s) of the DOT graph files containing requests
  from the non-problem period.  Up to 10 non-problem snapshots can be
  specified.

--snapshot1: The name(s) of the DOT graph files containing requests
  from the problem period.  Up to 10 problem snapshots can be
  specified. (OPTIONAL).

--reconvert_reqs: Re-indexes and reconverts requests.  By default,
  spectroscope performs indexing and conversion of the input DOT files
  the first time it is run.  After the first time, it re-uses previous
  results.  This option forces indexing and conversion. (OPTIONAL).
	
--bypass_sed: Whether to bypass string-edit distance calculation.
  Spectroscope uses string-edit distance as the metric for determining
  most likely precursors, but computing it for all necessary clusters
  (categories) can take a while.  This option allows the user to skip
  the calculation. (OPTIONAL).
	
--calc_all_distances: Whether all edit distances should be
  pre-computed or calculated on demand.  By default, String-edit
  distance is calculated only for cluters (categories) that can be
  precursor/mutation pairs.  This option forces string-edit distance
  to be calculated for all clusters (categories).  (OPTIONAL).

--mutation_threshold: Threshold for identifying a cluster as
  containing mutations or precursors.

Input file format
============
The snapshot0 and snapshot1 files must contain request-flow graphs in
DOT format. Each graph must be preceeded with a header that specifies
an ID for the graph and its response time (R).  I currently don't
remember what the 'RT' parameter in the header specifies.  Here is an
example graph from a snapshot file.  The label indicates the node
name. Edges must contain a label with a "R: <> us" value, indicating
the latency of that edge in the request-flow graph.

'# 1  R: 4.381460 usecs RT: 0.000000 usecs
Digraph G {
2586230574719640.2586230574720450 [label="e10__t3__NFS3_NULL_CALL_TYPE\nDEFAULT"]
2586230574719640.2586230574733590 [label="e10__t3__NFS3_NULL_REPLY_TYPE\nDEFAULT"]
2586230574719640.2586230574720450 -> 2586230574719640.2586230574733590 [label="R: 4.381460 us"]
}'

Output files
============
In the output directory specified, Spectroscope creates several files
and directories, described below.

interim_cluster_data: Intermediate files created in order to run the
statistical tests used to identify response-time mutations and the
edges responsible for them.  If this directory exists in the output
directory, its contents aren't re-created unless '--reconvert_reqs' is
specified.

To view a DOT graph of a category, I suggest copying the entire graph
to a seperate file and using the DOT program (of graphviz) to
visualize it.  You must visualize structural-mutation categories and
precursor categories side-by-side and manually identify changed
substructures.  We also worked on better visualizations for
Spectroscope (see our InfoVis'13 paper: 'Visualizing request-flow
comparison to aid performance diagnosis in distributed systems).  I
might make the source code for these better visualizations available
in the future.

convert_data: Indices created for the snapshot0 and snapshot1 inputs.
If this directory exists in the output directory, its contents aren't
re-created unless '--reconvert_reqs' is specified.

weighted_combined_ranked_graphs.dot: This is Spectroscope's main
output.  It contains DOT graphs of categories containing mutations.
Since all requests assigned to a given category have the same
structure, a single graph, annotated with aggregate informaton is
sufficient to represent all of them.  The first node of each dot graph
specifies aggregate information about the category, including the type
of mutation it contains (structural or response time) and performance
cost.  For structural mutations, the node lists the possible precursor
categories for the mutation (called candidate originating clusters).
The list is ranked by structural similarity to the structural mutation.

Edges show average latencies and standard deviations.  For
response-time mutations, edges responsible for the overall timing
change have a color=RED attribute attached to them.

unweighted_combined_ranked_graphs.dot: This file also contains all of
the categories identifeid by Spectroscope as containing mutations.
But, the categories in this file are ranked w/o weighting possible
precursors based on structural similarity.

originating_clusters.dot: This file contains all precursor categories
of the strucural-mutations categories identified by Spectroscope.

cluster_info.dat: A list of cateories identified by Spectroscope as
containing mutations in table format.
