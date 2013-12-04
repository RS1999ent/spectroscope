% $cmuPDL: run_hypothesis_tests.m,v 1.1 2010/04/03 05:50:23 rajas Exp $

%
% Copyright (c) 2013, Carnegie Mellon University.
% All rights reserved.
%
% Redistribution and use in source and binary forms, with or without
% modification, are permitted provided that the following conditions
% are met:
% 1. Redistributions of source code must retain the above copyright
%    notice, this list of conditions and the following disclaimer.
% 2. Redistributions in binary form must reproduce the above copyright
%    notice, this list of conditions and the following disclaimer in the
%    documentation and/or other materials provided with the distribution.
% 3. Neither the name of the University nor the names of its contributors
%    may be used to endorse or promote products derived from this software
%    without specific prior written permission.
%
% THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
% ``AS IS'' AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
% LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
% A PARTICULAR PURPOSE ARE DISCLAIMED.  IN NO EVENT SHALL THE COPYRIGHT
% HOLDERS OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
% INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING,
% BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS
% OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED
% AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
% LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY
% WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
% POSSIBILITY OF SUCH DAMAGE.
%

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
function [] = run_hypothesis_tests( comparison_file, hyp_test)

     [null_file, test_file, output_file, stats_file] = textread(comparison_file, '%s %s %s %s\n');
     
     for i=1:size(null_file, 1),
        feval(hyp_test, null_file{i}, test_file{i}, output_file{i}, stats_file{i});
     end
end

