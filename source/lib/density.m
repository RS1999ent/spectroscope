req_latency = load('global_ids_to_latencies.dat');

latency = req_latency(:,2);
sample_rate = 0.1;

[f, samples] = ksdensity(latency, 'npoints', sample_rate*size(latency, 1));

semilogx(samples, f);

xlabel('request latency');
ylabel('pdf');

% hide Y-axis value...
set(gca, 'YTickLabelMode', 'Manual')
set(gca, 'YTick', [])

grid on;

exportfig(gcf, 'ksdensity.eps', 'width', 3.2, 'FontMode', 'fixed', 'FontSize', 8, 'color', 'cmyk');
