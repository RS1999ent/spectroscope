%%
% Given an input sparse matrix of edges latencies and a file
% mapping the rows of each sparse matrix to a edge name,
% this matlab script check to see if the latencies of 
% each edge are normally distributed.
%
% @param sparse_edge_matrix_file: A file of the format
%  row_num, col_num: non-zero edge_latency value.
% 
% @param edge_name_file: A file mapping row numbers to edge names
%   row_num edge name
% 
% @param outfile: The file in which the hypothesis test results
% will be placed
% 
% @param graph_output: A directory in which cdfplots for each edge will
% be placed
%
% @note: It is assumed that the first row contains request latencies
% and so is ommitted from this test
%%
function [] = are_edges_normal(sparse_edge_matrix_file, edge_name_file, outfile, graph_outdir)

    set(0, 'defaulttextinterpreter', 'none');
    
    data = load(sparse_edge_matrix_file);
    sparse_edges_mat = spconvert(data);
    
    [edge_num, edge_names] = textread(edge_name_file, '%d %s\n');
    
    outfid = fopen(outfile, 'w');
    % Iterate through rows of the edge matrix, 
    for i = 2:size(sparse_edges_mat, 1),
        edge_latencies = sparse_edges_mat(i, :);
        edge_latencies = full(edge_latencies);
        edge_latencies = edge_latencies(find(edge_latencies ~= 0));
        
        if(size(edge_latencies, 2) < 20),
            fprintf(outfid, '%d: skipping\n', i);
            continue;
        end
        
        % Get important parameters from 
        avg = mean(edge_latencies);
        stderr = sqrt(var(edge_latencies));
        min_val = min(edge_latencies);
        max_val = max(edge_latencies);
            
        % Create the hypothetical distrib
        G = [unique(edge_latencies)', normcdf(unique(edge_latencies), avg, stderr)'];
        [h, p] = kstest(edge_latencies, G, 0.05, 0);
        [h_lillie p_lillie] = lillietest(edge_latencies, .05);

        fprintf(outfid, '%d:num: %d\n\tavg: %3.2f\n\tstd: %3.2f\n\tH: %d\n\tP: %3.2f\n\tH_Lillie: %d\n\tP_Lillie: %3.2f\n\n', ...
            i, size(edge_latencies, 2), avg, stderr, h, p, h_lillie, p_lillie);
        
        figure;
        A = cdfplot(edge_latencies);
        hold on;
        B = plot(G(:, 1)', G(:, 2)', 'rx--');
        title(edge_names{i});
        Legend([A B], ...
            'Empirical', 'Normal');
        
        graph_name = sprintf('%s/%d_fig_cdfplot.eps', graph_outdir, i);
        exportfig(gcf, graph_name, 'Width', 6.4, 'Height', 4.2, 'Color', 'cmyk', 'Fontmode', 'fixed', 'Fontsize', 8);
    end
end
    
       