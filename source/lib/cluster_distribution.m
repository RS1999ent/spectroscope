cluster = load('../pipe/cluster_distribution.dat');

bar(cluster(:,1), cluster(:,2));

xlabel('cluster ID');
ylabel('requests count');

grid on;

exportfig(gcf, '../pipe/cluster_distribution.eps', 'width', 3.2, 'FontMode', 'fixed', 'FontSize', 8, 'color', 'cmyk');
