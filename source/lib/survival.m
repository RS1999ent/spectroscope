req_latency = load('global_ids_to_latencies.dat');

[f, x] = ecdf(req_latency(:,2), 'function', 'survivor');

semilogx(x, f);

xlabel('request latency');
ylabel('survivor');

grid on;

exportfig(gcf, 'survival.eps', 'width', 3.2, 'FontMode', 'fixed', 'FontSize', 8, 'color', 'cmyk');
