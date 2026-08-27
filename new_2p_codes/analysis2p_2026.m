% --- Dual Channel Multi-ROI (Per-ROI Full Trace Visualization) ---
clear; clc; close all;

%% === Select folder ===
baseFolder = uigetdir(pwd, 'Select the TSeries folder');
if baseFolder == 0
    error('No folder selected.');
end

%% === Get file lists ===
filesCh1 = dir(fullfile(baseFolder, '*Ch1_*.ome.tif'));
filesCh3 = dir(fullfile(baseFolder, '*Ch3_*.ome.tif'));

if isempty(filesCh1) || isempty(filesCh3)
    error('Missing Ch1 or Ch3 files.');
end

namesCh1 = sort({filesCh1.name}');
namesCh3 = sort({filesCh3.name}');

nFrames = min(numel(namesCh1), numel(namesCh3));
fprintf('Found %d frames (paired)\n', nFrames);

%% === Projection from Ch3 ===
Nproj = min(5, nFrames);
sumProjection = [];

for i = 1:Nproj
    frame = double(imread(fullfile(baseFolder, namesCh3{i})));
    if isempty(sumProjection)
        sumProjection = zeros(size(frame));
    end
    sumProjection = sumProjection + frame;
end

projImg = sumProjection / Nproj;
lowHigh = prctile(projImg(:), [1 99]);
projEnhanced = mat2gray(projImg, lowHigh);

%% === Draw MULTIPLE ROIs ===
figure; imshow(projEnhanced);
title('Draw ROI(s) (double-click each, press ENTER when done)');
hold on;

roiMasks = {};
roiCount = 0;

while true
    h = drawpolygon();
    if isempty(h)
        break;
    end
    
    wait(h);
    
    roiCount = roiCount + 1;
    roiMasks{roiCount} = createMask(h);
    
    pos = mean(h.Position,1);
    text(pos(1), pos(2), sprintf('%d', roiCount), ...
        'Color','yellow','FontSize',14,'FontWeight','bold');
    
    choice = questdlg('Add another ROI?', 'ROIs', 'Yes','No','Yes');
    if strcmp(choice,'No')
        break;
    end
end

if roiCount == 0
    error('No ROIs drawn.');
end

%% === Background ROI ===
figure; imshow(projEnhanced);
title('Draw BACKGROUND ROI');
bkgMask = createMask(drawpolygon());
close all;

roiSizes = cellfun(@nnz, roiMasks);
bkgSize = nnz(bkgMask);

%% === Initialize ===
roiCh1 = zeros(nFrames, roiCount);
roiCh3 = zeros(nFrames, roiCount);
bkgCh1 = zeros(nFrames,1);
bkgCh3 = zeros(nFrames,1);

fprintf('Processing frames...\n');

%% === Loop ===
for i = 1:nFrames
    
    frame1 = double(imread(fullfile(baseFolder, namesCh1{i})));
    frame3 = double(imread(fullfile(baseFolder, namesCh3{i})));
    
    % Background
    bkgCh1(i) = sum(frame1(bkgMask));
    bkgCh3(i) = sum(frame3(bkgMask));
    
    % Each ROI
    for r = 1:roiCount
        roiCh1(i,r) = sum(frame1(roiMasks{r}));
        roiCh3(i,r) = sum(frame3(roiMasks{r}));
    end
end

%% === Scale background per ROI ===
bkgCh1_scaled = zeros(nFrames, roiCount);
bkgCh3_scaled = zeros(nFrames, roiCount);

for r = 1:roiCount
    scaleFactor = roiSizes(r) / bkgSize;
    bkgCh1_scaled(:,r) = bkgCh1 * scaleFactor;
    bkgCh3_scaled(:,r) = bkgCh3 * scaleFactor;
end

%% === Corrected ===
corrCh1 = roiCh1 - bkgCh1_scaled;
corrCh3 = roiCh3 - bkgCh3_scaled;

%% === Save CSV (expanded format) ===
Frame = (1:nFrames)';

T = table(Frame);

for r = 1:roiCount
    T.(['Ch1_Raw_ROI' num2str(r)]) = roiCh1(:,r);
    T.(['Ch1_BkgScaled_ROI' num2str(r)]) = bkgCh1_scaled(:,r);
    T.(['Ch1_Corrected_ROI' num2str(r)]) = corrCh1(:,r);
    
    T.(['Ch3_Raw_ROI' num2str(r)]) = roiCh3(:,r);
    T.(['Ch3_BkgScaled_ROI' num2str(r)]) = bkgCh3_scaled(:,r);
    T.(['Ch3_Corrected_ROI' num2str(r)]) = corrCh3(:,r);
end

outFile = fullfile(baseFolder, 'MultiROI_FullTraces.csv');
writetable(T, outFile);

%% === Plot PER ROI ===
for r = 1:roiCount
    
    % --- Ch1 ---
    figure;
    plot(roiCh1(:,r), '-r', 'LineWidth', 1.2); hold on;
    plot(bkgCh1_scaled(:,r), '--k', 'LineWidth', 1.2);
    plot(corrCh1(:,r), '-b', 'LineWidth', 1.5);
    xlabel('Frame'); ylabel('Intensity');
    title(sprintf('Ch1 (tdTomato) - ROI %d', r));
    legend('Raw ROI', 'Background (scaled)', 'Corrected');
    grid on;
    
    % --- Ch3 ---
    figure;
    plot(roiCh3(:,r), '-g', 'LineWidth', 1.2); hold on;
    plot(bkgCh3_scaled(:,r), '--k', 'LineWidth', 1.2);
    plot(corrCh3(:,r), '-b', 'LineWidth', 1.5);
    xlabel('Frame'); ylabel('Intensity');
    title(sprintf('Ch3 (GCaMP) - ROI %d', r));
    legend('Raw ROI', 'Background (scaled)', 'Corrected');
    grid on;
    
        % --- Overlay corrected signals (Ch1 vs Ch3) ---
    figure;
    plot(corrCh1(:,r), '-r', 'LineWidth', 1.5); hold on;
    plot(corrCh3(:,r), '-g', 'LineWidth', 1.5);
    xlabel('Frame');
    ylabel('Corrected Intensity');
    title(sprintf('Corrected Signals Overlay - ROI %d', r));
    legend('Ch1 (tdTomato)', 'Ch3 (GCaMP)');
    grid on;
end

fprintf('\n✅ Done. Results saved to:\n%s\n', outFile);