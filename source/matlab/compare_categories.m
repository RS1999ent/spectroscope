%
% Performs a chi^2 test on the input data
%
% s0_counts_file: File containing expected counts for the categories
% s1_counts_file: File containing observed counts for the categories
% sed_file: A MATLAB sparse matrix specifying the normalized SeD
% output_file: File to which hypothesis test result should be written
% stats_file: Information about the raw category counts and counts after
% merging will be written here
% s0_cdf_file: A graph of the CDF of category counts for the s0 dataset
% s1_cdf_file: A grph of the CDF of category counts for the s1 dataset
%%
function [] = compare_categories(s0_counts_file, s1_counts_file, sed_file, output_file, stats_file, s0_cdf_file, s1_cdf_file)

    [s0_ids, s0_counts, names] = textread(s0_counts_file, '%d %d %s');
    [s1_ids, s1_counts, names] = textread(s1_counts_file, '%d %d %s');
    [sed_matrix] = load(sed_file);
    sed_matrix = full(spconvert(sed_matrix));
    
    %P=path;
    %path(P,'../../matlab')
    
    %% Create graphs of the unmodified counts
    % Create graphs of the s0 CDF
    gcf0 = figure; 
    gca0 = cdfplot(s0_counts);

    % Create graphs of the s1 CDF
    gcf1 = figure;
    gca1 = cdfplot(s1_counts);

    % Find the number of categories that have count less than five
    ref_small_categories = size(find(s0_counts < 5), 1)/size(s0_counts, 1);
    test_small_categories = size(find(s1_counts < 5), 1)/size(s1_counts, 1);
    
    
    %% 
    % X^2 test will not work properly if the s0 (expected) category counts
    % are less than five. In this code block, such low frequency categories
    % are merged.  The choice of which low frequency categories to merge together 
    % is based on the normalized SeD between them.
    %
    large_count_idxs = find(s0_counts > 10);
    
    idxs = find(s0_counts <= 10);
    merged_idxs = [];
    
    while(size(idxs, 1) > 0),
        size(idxs, 1)
        % Pick a low frequency category: 
        i = idxs(1);
        
        expected_id = s0_ids(i);
        expected_id_name = names(i);
        [Y, sorted_sed_ids] = sort(sed_matrix(expected_id, :));
                
        for j = [sorted_sed_ids],
                        
            if ((strcmp(names(j), expected_id_name)) & (j ~= i) & ...
                (~isempty(find(s0_ids(idxs) == j)))),
                                        
                    s0_counts(i) = s0_counts(i) + s0_counts(j);
                    s0_counts(j) = 0;
                    
                    s1_counts(i) = s1_counts(i) + s1_counts(j);
                    s1_counts(j) = 0;
                    
                    idxs = setdiff(idxs, find(s0_ids == j));
                end
            
            if(s0_counts(i) > 5),                  
                break;
            end
        end
        idxs = setdiff(idxs, i);
        merged_idxs = [merged_idxs i];
    end
    
    % Prune empty categories        
    s0_ids = [s0_ids(large_count_idxs); s0_ids(merged_idxs)];
    s0_counts = [s0_counts(large_count_idxs); s0_counts(merged_idxs)];
    
    s1_ids = [s1_ids(large_count_idxs); s1_ids(merged_idxs)];
    s1_counts = [s1_counts(large_count_idxs); s1_counts(merged_idxs)];
    
    names = [names(large_count_idxs); names(merged_idxs)];
    
    
    %% Plot CDFs of the merged categories
    figure(gcf0);
    hold on;
    cdfplot(s0_counts);
    hold off;
    
    figure(gcf1);
    hold on;
    cdfplot(s1_counts);
    hold off;
    
    %% Calculate number of categories w/count less than 5 now.
    ref_merged_small_categories = size(find(s0_counts < 5), 1)/size(s0_counts, 1);
    test_merged_small_categories = size(find(s1_counts < 5), 1)/size(s1_counts, 1);
    
    
    %%
    % Run the hypothesis test
    chi_squared_stat = sum( (s1_counts - s0_counts).^2./(s0_counts));
    p = 1 - chi2cdf(chi_squared_stat, size(s0_counts, 1) - 1);
    h = 0;
    if (p < 0.05) 
        h = 1,
    end

     % Print out the hypothesis test results
     outfid = fopen(output_file, 'w');
     fprintf(outfid, '%d %d %f %3.2f %3.2f %3.2f %3.2f\n', ...
                1, h, p, -1, -1, -1, -1);
     fclose(outfid);
     
     %%
     % Print out the statistics
     outfid = fopen(stats_file, 'w');
     fprintf(outfid, 'Number of categories w/less than five items originally: %d %d\n', ...
         ref_small_categories, test_small_categories);
     fprintf(outfid, 'Number of categories w/less than five item safter merge: %d %d\n', ...
         ref_merged_small_categories, test_merged_small_categories);
     close(outfid);
     
     %% Print the graphs to the right directory
    %exportfig(gcf0, s0_histogram_file, 'width', 3.2, 'FontMode', 'fixed', 'FontSize', 8);
    %exportfig(gcf1, s1_histogram_file, 'width', 3.2, 'FontMode', 'fixed', 'FontSize', 8);

     
     
