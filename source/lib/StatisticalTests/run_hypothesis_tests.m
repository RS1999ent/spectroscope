% $cmuPDL: run_hypothesis_tests., v$

%%
% This matlab script is a wrapper for running hypothesis tests on several
% comparisons.  It loads a "meta file" (comparisons_file) that describes the input and 
% output files for each comparison, and then calls the appropriate hypothesis test.
%
% The "meta file" it loads should be of the format: 
%   <null distribution file name> <test distribution file name> <output file name> <stats file name>
%
% @param comparisons_file: "meta file" containing names of input, output, and stats file for each
%  comparison
% @param hyp_test: Name of the matlab script that will actually perform the hypothesis test
%%
function [] = run_hypothesis_tests( comparisons_file, hyp_test)

     [null_file, test_file, output_file, stats_file] = textread(comparisons_file, "%s %s %s %s\n");
     

     for i=[1:size(null_file, 1)],
        hyp_test(null_file{i}, test_file{i}, output_file{i}, stats_file{i});
     end
end

