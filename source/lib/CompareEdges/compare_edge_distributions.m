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

% $cmuPDL: compare_edge_distributions.m,v 1.2 2009/04/26 23:48:44 source Exp $
%%
% This matlab script compares the edge latency distributions of the
% edges passed into it and returns whether they are the same.  The
% output file returned is of the format
% <edge name> <accept null hypothesis?> <p-value>
%
% @param /tmp/s0_edge_latencies.dat: Edge latencies from the zeroth
%        snapshot.  This is in MATLAB sparse file format.  Format is:
%        <row num> <col num> <edge latency>
% @param /tmp/s1_edge_latencies.dat: Edge latencies from the first
%        shapshot.  This is in MATLAB sparse file format.
% @param /tmp/edge_names.dat: Names of each edge and their corresponding
%        row number.  Format is:
%         <row number> <edge name>.
%        This file is sorted by row number in ascenting order
% @param output_file.dat: Where the output of this script will be placed
%%
    
    s0_data = load('/tmp/s0_edge_latencies.dat');
    s0_data = spconvert(s0_data);
    s1_data = load('/tmp/s1_edge_latencies.dat');
    s1_data = spconvert(s1_data);
    
    [edge_num, edge_names] = textread('/tmp/edge_names.dat', '%d %s\n');
    
    outfid = fopen('/tmp/output_file.dat', 'w');
    % Iterate through rows of the edge matrix, 
    for i = min(edge_num):max(edge_num),
        
        if( i <= size(s0_data, 1))
            s0_edge_latencies = s0_data(i, :);
            s0_edge_latencies = full(s0_edge_latencies);
            s0_edge_latencies = s0_edge_latencies(find(s0_edge_latencies ~= 0));
        else
            fprintf(outfid, '-%30s %d %3.5f\n', edge_names{i-1}, -1, 0);
            continue;
        end
          
        if (i <= size(s1_data, 1)),
            s1_edge_latencies = s1_data(i, :); 
            s1_edge_latencies = full(s1_edge_latencies);
            s1_edge_latencies = s1_edge_latencies(find(s1_edge_latencies ~= 0));
        else 
            fprintf(outfid, '-%30s %d %3.5f\n', edge_names{i-1}, -1, 0);
            continue;
        end
        
        s0_size = size(s0_edge_latencies, 2);
        s1_size = size(s1_edge_latencies, 2);

        % Matlab help suggests that kstest2 produces reasonable estimates
        % when the following condition is false.
        e = 0.0001;
        if(s0_size*s1_size/(s0_size + s1_size + e) < 4) 
     %continue;
        end

        [h, p] = kstest2(s0_edge_latencies, s1_edge_latencies);
        
        fprintf(outfid, '-%30s %d %3.5f\n', ...
                edge_names{i-1}, h, p);

    end
    
       
