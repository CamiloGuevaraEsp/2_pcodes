largest_time = max([size(data1,1) size(data2,1) size(data3,1) size(data4,1)]);
t1 = linspace(0, 60, size(data1,1))';
t2 = linspace(0, 60, size(data2,1))';
t3 = linspace(0, 60, size(data3,1))';
t4 = linspace(0, 60, size(data4,1))';
t_common = linspace(0, 60, largest_time);
group1_interp = interp1(t1, data1, t_common, 'linear');
group2_interp = interp1(t2, data2, t_common, 'linear'); 
group3_interp = interp1(t3, data3, t_common, 'linear');
group4_interp = interp1(t4, data4, t_common, 'linear'); % identity if t2 == t_common