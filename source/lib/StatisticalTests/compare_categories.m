%
% Performs a chi^2 test on the input data
%
function [] = compare_categories(s0_counts_file, s1_counts_file, output_file, s0_histogram_file, s1_histogram_file)

    [s0_ids, s0_counts, s0_names] = textread(s0_counts_file, '%d %d %s');
    [s1_ids, s1_counts, s0_names] = textread(s1_counts_file, '%d %d %s');

    P=path;
    path(P,'../../matlab')
    
    gcf0 = figure;
    
    % Create graphs of the s0 histogram
    gca0 = plot(s0_ids, s0_counts);
    xlabel('Category IDs');
    ylabel('Counts');
    
    % Create graphs of the s1 histogram
    gcf1 = figure;

    gca1 = plot(s1_ids, s1_counts);
    xlabel('Category IDs');
    ylabel('Counts');
    
    % Print the graphs to the right directory
    exportfig(gcf0, s0_histogram_file, 'width', 3.2, 'FontMode', 'fixed', 'FontSize', 8);
    exportfig(gcf1, s1_histogram_file, 'width', 3.2, 'FontMode', 'fixed', 'FontSize', 8);
    
    % Run the hypothesis tests
    [h, p, st] = chi2gof(s0_ids, 'ctrs', s0_ids, 'frequency', s1_counts, ...
                            'expected', s0_counts);

     % Print out the hypothesis test results
     outfid = fopen(output_file, 'w');
     fprintf(outfid, '%d %d %f %3.2f %3.2f %3.2f %3.2f\n', ...
                1, h, p, -1, -1, -1, -1);
     fclose(outfid);
