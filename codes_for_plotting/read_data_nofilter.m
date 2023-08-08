%% Read plot: 
%This code reads the text file that contains the time and the intensities,
%stores it as a matrix, filter it and plot it. 
%% Open and load the file
% Copy your directory and the .txt (output from
% output2P_intensityVsTime_cellBodies, also write down which ROI is your
% background
close all
rootdir = '/Users/camilog/Downloads/Vishnu_meeting';
cd(rootdir);
filename = '20230607_recombinantdfsb_1_zt0_Tseries-004_Cycle00001_Ch2__userDrawnMask__Intensities' ;
data = readmatrix(filename,'Delimiter',{','});
time = data(:,1);
signal = data(:,[3:2:end]);
backgroundColumn = 2;
signalColumn = 1; 
%% Filter data and plot the original and the filtered version
% For this I used a mean windown, feel free to play around with it
%filtered_data = smoothdata(data(:,[3:2:end]),'movmean',10); 

%Define relevant variables to determine superplot size
x = size(data);
numRegions = (x(2)-1)/2;
sp_numrows = floor(sqrt(numRegions));
sp_numcols = ceil(numRegions/sp_numrows);

%Plot the raw data
figure(1)
for i = 1: numRegions
   subplot(sp_numrows,sp_numcols, i)
   plot(time, (data(:,(i-1)*2+3)));
end
sgtitle('Raw data')

%% Substract background and plot
substracted_data = [signal - signal(:,backgroundColumn)];
figure(3)
plot(time,substracted_data(:,signalColumn))
title('Background susbtracted');
