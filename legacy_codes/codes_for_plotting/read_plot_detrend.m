%% Loading the cell data
% Copy your directory and the .txt (output from
% output2P_intensityVsTime_cellBodies
close all
clear all
rootdir = '/Users/camilog/Downloads/2precordings/R23E10Gal4_UAS_ASAP2S';
cd(rootdir);
%For cases in which I had to run the script more than once because
%different cells were in different thresholds uncooment lines 10,18,19

%filename1 = 'TSeries-11302022-1539-1048_Cycle00001_Ch2__maskReg1 3_Cycle00001_Intensities';
filename = '20230607_recombinantdfsb_1_zt0_Tseries-004_Cycle00001_Ch2__userDrawnMask__Intensities' ;
outname = [filename '_signal.mat']

ZTInitial = 0; 
backgroundColumn = 1; 
%Load the data and create a filtered version of it, you can play around
%with the filtering parameters
data = readmatrix(filename,'Delimiter',{','});

%data1 = readmatrix(filename1,'Delimiter',{','});
%fulldata = [data data1(:,2:end)]; 
%data = fulldata;
filtered_data = smoothdata(data(:,[3:2:end]),'movmean', 30); 
time = data(:,1);
ZTfinal = time(end)/3600;
%ZTTimes = ZtInitial: ZTfinal: 

%Define relevant variables to determine superplot size
x = size(data);
numRegions = (x(2)-1)/2;


sp_numrows = floor(sqrt(numRegions));
sp_numcols = ceil(numRegions/sp_numrows);

%Plot the raw and the filtered data, each one in a different figure
figure(1)
for i = 1: numRegions
   subplot(sp_numrows,sp_numcols, i)
   plot(data(:,1), (data(:,(i-1)*2+3)));
end
sgtitle('Raw data')

figure(2)

for i = 1: numRegions
   subplot(sp_numrows,sp_numcols, i)
   plot(data(:,1), filtered_data(:,i));
   title('', i)
   %xlim([0,5400]);
end
sgtitle('Filtered data')

%% substract background
%What column is your background



%filtered_data = [data(:,1) filtered_data - filtered_data(:,backgroundColumn)];

filtered_data = [filtered_data - filtered_data(:,backgroundColumn)];
filtered_data = -1 .* filtered_data;
%filtered_data = -1 .* filtered_data(:,3);
figure(3)
%subplot(1,2,1)
plot(time,filtered_data(:,2));
legend('Negative signal')
%plot(time,filtered_data(:,2));

%figure (4)
%plot(filtered_data(:,1),filtered_data(:,4))

%% Detrend

detrendData = [detrend(filtered_data)]; 
%plot(time, detrendData(:,1))
%subplot(1,2,1)
figure(4)
plot(time,detrendData(:,2));
legend('Detrend signal')
%signal = [time detrendData]; 
signal = [time filtered_data];
save(outname,'signal');


%subplot(1,2,2)
%plot(time, detrendData(:,2)); 

% %% Superimposed plots in different time ranges (after detrend)
% 
% %Write down what cells do you want to analyze and the time ranges you want
% %to look at
% 
% cells_to_analyze = [2 3];
% plot_ranges = [0 500;2000 2500; 2500 3000; 4500 5000];
% sp_numrows = 2;
% sp_numcols = 2;
% % sp_numrows = floor(sqrt(size(plot_ranges,1)));
% % sp_numcols = ceil(numRegions/sp_numrows);
% %colors = ["r" "g" "b" "c" "m" "y" "k"]
% figure
% sgtitle('Plots of selected time ranges')
% for j = 1: length(plot_ranges)
%     subplot(sp_numrows,sp_numcols,j)
%     for i = cells_to_analyze
%         %plot(data(:,1), (data(:,(i-1)*2+3)));
%        plot(data(:,1), detrendData(:,i));
%         xlim(plot_ranges(j,:))
%         hold on 
%     end
%     legend('1','3')
% 
% end
% %%
% %Normalize data by the mean of each cell
% 
% means = mean(detrendData); 
% mean_data = (detrendData- mean(detrendData))./mean(detrendData); 
% sp_numrows = floor(sqrt(numRegions));
% sp_numcols = ceil(numRegions/sp_numrows);
% figure
% for i = 1: numRegions
%    subplot(sp_numrows,sp_numcols, i)
%    plot(data(:,1), mean_data(:,i));
%    title('', i)
%    xlim([0,5400]);
% end
% sgtitle('Plot of normalized data')

% %% Correlation in time frames
% 
% cells_to_test = [2 3];
% time_ranges = [0 500;2000 2500; 2500 3000; 4500 5000];
% sp_numrows = 2;
% sp_numcols = 2;
% 
% 
% if find(time_ranges == 0)
%     figure
%     subplot(sp_numrows,sp_numcols,1)
%     lower = 1; 
%     upper = round((time_ranges(1,2) * length(detrendData))/data(end,1));
%     [c,lags] = xcorr(detrendData(lower:upper,cells_to_test(1)), detrendData(lower:upper, cells_to_test(2)), 'normalized');
%     plot(lags,c)
%     for i = 2: length(time_ranges)
%          subplot(sp_numrows,sp_numcols,i)
%          lower = round((time_ranges(i,1) * length(detrendData))/data(end,1));
%          upper =  round((time_ranges(i,2) * length(detrendData))/data(end,1));
%          [c,lags] = xcorr(detrendData(lower:upper,cells_to_test(1)), detrendData(lower:upper, cells_to_test(2)), 'normalized');
%           plot(lags,c)
%          %sgtitle ( fprintf(' %i vs %i', cells_to_test(1), cells_to_test(2)));
%     end
%     sgtitle ( sprintf(' %i vs %i', cells_to_test(1), cells_to_test(2)));
% else
%     for i = 1: length(time_ranges)
%          subplot(sp_numrows,sp_numcols,i)
%          lower = round((time_ranges(i,1) * length(detrendData))/data(end,1));
%          upper =  round((time_ranges(i,2) * length(detrendData))/data(end,1));
%          [c,lags] = xcorr(detrendData(lower:upper,cells_to_test(1)), detrendData(lower:upper, cells_to_test(2)), 'normalized');
%           plot(lags,c)
%           hold on
%           xline(0,'--');
%           hold off
% 
%     end
%     sgtitle ( sprintf(' %i vs %i', cells_to_test(1), cells_to_test(2)));
% end
