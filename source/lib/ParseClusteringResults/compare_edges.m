%%
% This matlab script compares the edge latency distributions of the
% edge latencies passed into it and returns whether they are the same.  The
% output file returned is of the format
% <edge row_num> <accept null hypothesis?> <p-value> <avg. latency s0>
% <stddev s0> <avg. latency s1> <stddev s1>
%
% Note that this script will summarily decide to reject the null hypothesis
% if no edge latencies are present for the edge in s0 xor s1.  In this case
% the p-value returned is -1.
%
% If there is not enough data to a given edge edges using the chosen statistical
% test, the null hypothesis will be accepted and a p-value of -1 returned.
%
% If there is no data for the given edge, no information for the edge
% will be computed.
%
% @param s0_edge_latencies: Edge latencies from the zeroth
%        snapshot.  This is in MATLAB sparse file format.  Format is:
%        <row num> <col num> <edge latency>
% @param s1_edge_latencies: Edge latencies from the first
%        shapshot.  This is in MATLAB sparse file format.
% @param output_file.dat: Where the output of this script will be placed
%%
function [] = compare_edges(s0_file, s1_file, output_file)    

    s0_data = load(s0_file);

    if(~isempty(s0_data)),
       s0_data = spconvert(s0_data);
    end

    s1_data = load(s1_file);
    if(~isempty(s1_data)),
       s1_data = spconvert(s1_data);
    end
 
    max_rows = max(size(s0_data, 1), size(s1_data, 1));
    
    outfid = fopen(output_file, 'w');
        
    % Iterate through rows of the edge matrix, 
    for i = 1:max_rows,
        
        if( i <= size(s0_data, 1))
            s0_edge_latencies = s0_data(i, :);
            s0_edge_latencies = full(s0_edge_latencies);
            s0_edge_latencies = s0_edge_latencies(find(s0_edge_latencies ~= 0));
        else 
            s0_edge_latencies = [];
        end
        
        if (i <= size(s1_data, 1)),
            s1_edge_latencies = s1_data(i, :); 
            s1_edge_latencies = full(s1_edge_latencies);
            s1_edge_latencies = s1_edge_latencies(find(s1_edge_latencies ~= 0));
        else 
            s1_edge_latencies = [];
        end
        
        if(isempty(s0_edge_latencies) && isempty(s1_edge_latencies)),
           % This edge was not seen at all in both datasets; ignore it
           continue;
        end
        
        
        %%
        % This block of code checks to see if one of the edge latency
        % vectors for s0 or s1 are empty.  If so, it summarily outputs
        % a decision and does not apply the kstest.
        %%
        if(isempty(s0_edge_latencies)),
            % This edge was only seen in the s1 data
            fprintf(outfid, '%d %d %3.2f %3.2f %3.2f %3.2f %3.2f\n', ...
                    i, 1, -1, 0, 0, mean(s1_edge_latencies), std(s1_edge_latencies));
            continue;
        end
        
        if(isempty(s1_edge_latencies)),
            % This edge was only seen in the s0 data
            fprintf(outfid, '%d %d %3.2f %3.2f %3.2f %3.2f %3.2f\n', ...
                    i, 1, -2, mean(s0_edge_latencies), std(s0_edge_latencies), 0, 0);
            continue;
        end


        %% This block of code runs the kstest algorithm.
        s0_size = size(s0_edge_latencies, 2);
        s1_size = size(s1_edge_latencies, 2);

        % Matlab help suggests that kstest2 produces reasonable estimates
        % when the following condition is false.
        e = 0.0001;
        if(s0_size*s1_size/(s0_size + s1_size + e) < 4),
            fprintf(outfid, '%d %d %3.2f %3.2f %3.2f %3.2f %3.2f\n', ...
                i, 0, -3, mean(s0_edge_latencies), std(s0_edge_latencies), ...
                    mean(s1_edge_latencies), std(s1_edge_latencies));
            continue;
        end

        [h, p] = kstest2(s0_edge_latencies, s1_edge_latencies);
        
        fprintf(outfid, '%d %d %f %3.2f %3.2f %3.2f %3.2f\n', ...
                i, h, p, mean(s0_edge_latencies), std(s0_edge_latencies), ...
                    mean(s1_edge_latencies), std(s1_edge_latencies));
    end

end
