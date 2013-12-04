spectroscope
============

Spectroscope is an implementation of request-flow comparison, a technique for diagnosing performance changes in distributed systems.  Please see the NSDI 2011 paper "Diagnosing performance changes by comparing request flows" for more information.

Overview of source code
============
Spectroscope is written as several perl modules that interface with each other and Matlab.  Running Spectroscope requires several perl modules (see the various source files) and Matlab.  

Naming conventions
============
In the NSDI'11 paper, categories are groups of requests with the same structure or topology.  In the Spectroscope source code, these are more generally called 'clusters.'  This is because the source code allows on to insert arbritrary clustering algorithms (cluster by structure is one such example).  

Similarly, in the NSDI'11 paper, categories that requests that have changed in structure during the problem period are called 'precursors.'  In this code, they may be called 'originators.'  

Running Spectroscope
============
To run Spectroscope, cd to 'spectroscope/source/spectroscope.' and run spectroscope.pl.  You can see the various command line parameter options by running spectroscope.pl w/o any options.  The options are further described below:

--output_dir: The directory in which output should be placed.

--snapshot0: The name(s) of the DOT graph files containing requests from the non-problem period.  Up to 10 non-problem snapshots can be specified.

--snapshot1: The name(s) of the DOT graph files containing requests from the problem period.  Up to 10 problem snapshots can be specified. (OPTIONAL).

--reconvert_reqs: Re-indexes and reconverts requests.  By default, spectroscope performs indexing and conversion of the input DOT files the first time it is run.  After the first time, it re-uses previous results.  This option forces indexing and conversion. (OPTIONAL).
	
--bypass_sed: Whether to bypass string-edit distance calculation.  Spectroscope uses string-edit distance as the metric for determining most likely precursors, but computing it for all necessary clusters (categories) can take a while.  This option allows the user to skip the calculation. (OPTIONAL).
	
--calc_all_distances: Whether all edit distances should be pre-computed or calculated on demand.  By default, String-edit distance is calculated only for cluters (categories) that can be precursor/mutation pairs.  This option forces string-edit distance to be calculated for all clusters (categories).  (OPTIONAL).

--mutation_threshold: Threshold for identifying a cluster as containing mutations or precursors.

Input file format.
============

The snapshot0 and snapshot1 files must contain request-flow graphs in DOT format. Each graph must be preceeded with a header that specifies an ID for the graph and its response time (R).  I currently don't remember what the 'RT' parameter in the header specifies.  Here is an example graph from a snapshot file.  The label indicates the node name. Edges must contain a label with a "R: <> us" value, indicating the latency of that edge in the request-flow graph.

# 1  R: 4.381460 usecs RT: 0.000000 usecs
Digraph G {
2586230574719640.2586230574720450 [label="e10__t3__NFS3_NULL_CALL_TYPE\nDEFAULT"]
2586230574719640.2586230574733590 [label="e10__t3__NFS3_NULL_REPLY_TYPE\nDEFAULT"]
2586230574719640.2586230574720450 -> 2586230574719640.2586230574733590 [label="R: 4.381460 us"]
}
