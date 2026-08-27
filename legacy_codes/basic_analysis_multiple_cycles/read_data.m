%% Read plot: 
%This code reads the text file that contains the time and the intensities,
%stores it as a matrix, filter it and plot it. 
%% Open and load the file
% Copy your directory and the .txt (output from
% output2P_intensityVsTime_cellBodies, also write down which ROI is your
% background
close all
rootdir = '/Users/camilog/Downloads';
cd(rootdir);
filename = '20230510 R23E10 ASAP2S Ctrl_2-006_Cycle00001_Ch2__userDrawnMask__Intensities' ;
data = readmatrix(filename,'Delimiter',{','});
backgroundColumn = 2; 
%% Filter data and plot the original and the filtered version
% For this I used a mean windown, feel free to play around with it
filtered_data = smoothdata(data(:,[3:2:end]),'movmean',10); 

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
%% Substract background and plot
filtered_data = [data(:,1) filtered_data - filtered_data(:,backgroundColumn)];
figure(3)
plot(filtered_data(:,1),filtered_data(:,2))
title('Background susbtracted');
