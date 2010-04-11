#! /usr/bin/perl -w

# cmuPDL: eval_structural_mutation_identification.pl, v $

##
# @author Raja Sambasivan
#
# Given the Spectroscope results, a "mutated edge" and a "predecessor edge,"
# this perl script will evaluate the quality of the Spectroscope results for
# structural mutations.
#
# Note that the results output by Spectroscope include 'virtual categories.'  A
# single category can appear twice in the results.
#
# As output, this function will yield info about the following: 
#
#  Information about requests: 
#    * Number/fraction of virtual requests that are false-positives (false positive rate)
#    * Number/fraction of structural mutation virtual requests that are false-positives
#    * Number/fraction of response-time mutation virtual requests that are false-positives
#    * Number/fraction of requests with the mutated edge identified as structural mutations (1 - false negative rate)
#
# Information about categories
#   * Number/fraction of virtual categories identified that are false-positivessm
#   * Number/fraction of virtual structural mutation virtual categories that are false positives
#   * Number/fraction of response-time mutation virtual categories that are false positives
#   * Number/fraction of categories with the mutated edge identified as structural mutations (1 - false negative rate)
#
# Also computed is the nDCG value.  Also a bitmap indicating ranks of relevant
# results is also output.  A 1 in position N of this bitmap indicates a relevant
# result; a 0, a non-relevant result, and a -1, a non-relevant response-time
# mutation.
##

##### Main routine #####

get_options();
handle_requests($g_combined_ranked_results_file, $g_originators_file, 1);
handle_requests($

