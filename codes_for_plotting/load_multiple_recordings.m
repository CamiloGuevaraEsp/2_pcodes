close all
clear all
rootdir = '/Users/camilog/Downloads/2precordings/R23E10Gal4_UAS_ASAP2S';
cd(rootdir)
%Input the name of the signals

recordings_array =  {'20230404_Tseries_dfb_zt0_150pockels_600PMT_bias012-001_Cycle00001_Ch2__userDrawnMask_Cycle00001_Intensities_signal.mat';
 '20230413_TSeries_dfb_zt0_150pockels_600PMT_bias012-006_Cycle00001_Ch2__userDrawnMask__Intensities_signal.mat';
 '20230607_recombinantdfsb_1_zt0_Tseries-004_Cycle00001_Ch2__userDrawnMask__Intensities_signal.mat';
}

for i = 1: length(recordings_array)
    A{i,1} = load(recordings_array{i,1});
    %A{i,1} = nonzeros(A{i,1}.signal)
    %Store the name and the size
    A{i,1}.name = recordings_array(i); 
    A{i,2} = size(A{i,1}.signal,1);
    %From previous analysis the array resulted in a column full of zeros,
    %this part get rid of them
    nonzero_columns = any(A{i,1}.signal,1);
    A{i,1}.signal = A{i,1}.signal(:,nonzero_columns);
    arrayLenght(i,1) = size(A{i,1}.signal,1);
    min_size = min(arrayLenght);
end

for i = 1: length(recordings_array)
    if size(A{i,1}.signal,1) ~= min_size 
          A{i,1}.signal_interp(:,1) = A{2,1}.signal(:,1);  
          A{i,1}.signal_interp(:,2) = interp1(A{i,1}.signal(:,1), A{i,1}.signal(:,2), A{2,1}.signal(:,1));
          A{i,1}.signal = A{i,1}.signal_interp;
          time(:,i) = A{i,1}.signal(:,1);
          matrix_signal(:,i) = A{i,1}.signal(:,2);
    else  
         time(:,i) = A{i,1}.signal(:,1);  
         matrix_signal (:,i) = A{i,1}.signal(:,2);
    end
    %values_array(:,i) = A{i,1}.signal(:,2); 
end
time = mean(time,2);
matrix_signal(:,end+1) = median(matrix_signal,2);

plot(time,matrix_signal(:,1:end-1), 'LineWidth', 0.5, 'Color', [0 0.4470 0.7410 0.6])
hold on
plot(time,matrix_signal(:,end), 'LineWidth',2, 'Color', [1 0 0 1]);




%load("20230404_Tseries_dfb_zt0_150pockels_600PMT_bias012-001_Cycle00001_Ch2__userDrawnMask_Cycle00001_Intensities_signal.mat")

%This is how you change array size to make it equal to other

%y = interp1(A{1,1}.signal(:,1), A{1,1}.signal(:,2), A{2,1}.signal(:,1));



%%
% Example data
x = 1:10;
y = sin(x);

% Plot with adjusted opacity
plot(x, y, 'LineWidth', 2, 'Color', [0, 0.5, 1, 1]); % Set alpha value to 0.5

% Axis labels
xlabel('X');
ylabel('Y');
