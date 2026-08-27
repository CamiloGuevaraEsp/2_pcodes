% --- Volumetric Dual Channel Multi-ROI Analysis ---
clear; clc; close all;

%% === Select folder ===
baseFolder = uigetdir(pwd, 'Select TSeries folder');

if baseFolder == 0
    error('No folder selected.');
end

%% === Get file lists ===
filesCh1 = dir(fullfile(baseFolder, '*Ch1_*.ome.tif'));
filesCh3 = dir(fullfile(baseFolder, '*Ch3_*.ome.tif'));

if isempty(filesCh1) || isempty(filesCh3)
    error('Missing Ch1 or Ch3 files.');
end

namesCh1 = {filesCh1.name}';
namesCh3 = {filesCh3.name}';

%% === Extract cycle numbers ===
cycleNums = [];

for i = 1:length(namesCh3)

    token = regexp(namesCh3{i}, 'Cycle(\d+)', 'tokens');

    if isempty(token)
        error('Could not parse cycle number.');
    end

    cycleNums(i) = str2double(token{1}{1});
end

uniqueCycles = unique(cycleNums);
nCycles = length(uniqueCycles);

fprintf('Found %d cycles\n', nCycles);

%% =========================================================
%% === Build reference projection from FIRST 5 CYCLES ======
%% =========================================================

NprojCycles = min(5, nCycles);

referenceSum = [];

fprintf('Building reference projection...\n');

for c = 1:NprojCycles

    cycleID = uniqueCycles(c);

    idx = cycleNums == cycleID;

    cycleFiles = namesCh3(idx);

    cycleProjection = [];

    for s = 1:length(cycleFiles)

        img = double(imread(fullfile(baseFolder, cycleFiles{s})));

        if isempty(cycleProjection)
            cycleProjection = zeros(size(img));
        end

        cycleProjection = cycleProjection + img;
    end

    if isempty(referenceSum)
        referenceSum = zeros(size(cycleProjection));
    end

    referenceSum = referenceSum + cycleProjection;
end

projImg = referenceSum / NprojCycles;

lowHigh = prctile(projImg(:), [1 99]);
projEnhanced = mat2gray(projImg, lowHigh);

%% === Draw MULTIPLE ROIs ===
figure;
imshow(projEnhanced);
title('Draw ROI(s) (double-click each, ENTER when done)');
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
        'Color','yellow', ...
        'FontSize',14, ...
        'FontWeight','bold');

    choice = questdlg('Add another ROI?', ...
        'ROIs', ...
        'Yes','No','Yes');

    if strcmp(choice,'No')
        break;
    end
end

if roiCount == 0
    error('No ROIs drawn.');
end

%% === Background ROI ===
figure;
imshow(projEnhanced);
title('Draw BACKGROUND ROI');

bkgMask = createMask(drawpolygon());

close all;

%% === ROI sizes ===
roiSizes = cellfun(@nnz, roiMasks);
bkgSize = nnz(bkgMask);

%% === Initialize ===
roiCh1 = zeros(nCycles, roiCount);
roiCh3 = zeros(nCycles, roiCount);

bkgCh1 = zeros(nCycles,1);
bkgCh3 = zeros(nCycles,1);

fprintf('Processing cycles...\n');

%% =========================================================
%% === LOOP THROUGH CYCLES ================================
%% =========================================================

for c = 1:nCycles

    cycleID = uniqueCycles(c);

    fprintf('Cycle %d / %d\n', c, nCycles);

    %% --- Find slices for this cycle ---
    idx1 = cycleNums == cycleID;
    idx3 = cycleNums == cycleID;

    cycleFilesCh1 = namesCh1(idx1);
    cycleFilesCh3 = namesCh3(idx3);

    %% --- Sum projection for THIS cycle ---
    projCh1 = [];
    projCh3 = [];

    for s = 1:length(cycleFilesCh1)

        img1 = double(imread(fullfile(baseFolder, cycleFilesCh1{s})));
        img3 = double(imread(fullfile(baseFolder, cycleFilesCh3{s})));

        if isempty(projCh1)

            projCh1 = zeros(size(img1));
            projCh3 = zeros(size(img3));
        end

        projCh1 = projCh1 + img1;
        projCh3 = projCh3 + img3;
    end

    %% --- Background ---
    bkgCh1(c) = sum(projCh1(bkgMask));
    bkgCh3(c) = sum(projCh3(bkgMask));

    %% --- ROI extraction ---
    for r = 1:roiCount

        roiCh1(c,r) = sum(projCh1(roiMasks{r}));
        roiCh3(c,r) = sum(projCh3(roiMasks{r}));
    end
end

%% === Scale background ===
bkgCh1_scaled = zeros(nCycles, roiCount);
bkgCh3_scaled = zeros(nCycles, roiCount);

for r = 1:roiCount

    scaleFactor = roiSizes(r) / bkgSize;

    bkgCh1_scaled(:,r) = bkgCh1 * scaleFactor;
    bkgCh3_scaled(:,r) = bkgCh3 * scaleFactor;
end

%% === Background corrected ===
corrCh1 = roiCh1 - bkgCh1_scaled;
corrCh3 = roiCh3 - bkgCh3_scaled;

%% === Save CSV ===
Cycle = uniqueCycles';

T = table(Cycle);

for r = 1:roiCount

    T.(['Ch1_Raw_ROI' num2str(r)]) = roiCh1(:,r);
    T.(['Ch1_BkgScaled_ROI' num2str(r)]) = bkgCh1_scaled(:,r);
    T.(['Ch1_Corrected_ROI' num2str(r)]) = corrCh1(:,r);

    T.(['Ch3_Raw_ROI' num2str(r)]) = roiCh3(:,r);
    T.(['Ch3_BkgScaled_ROI' num2str(r)]) = bkgCh3_scaled(:,r);
    T.(['Ch3_Corrected_ROI' num2str(r)]) = corrCh3(:,r);
end

outFile = fullfile(baseFolder, 'Volumetric_MultiROI.csv');

writetable(T, outFile);

%% === Plot corrected signals ===
for r = 1:roiCount

    figure;

    plot(corrCh1(:,r), '-r', 'LineWidth', 1.5);
    hold on;

    plot(corrCh3(:,r), '-g', 'LineWidth', 1.5);

    xlabel('Cycle');
    ylabel('Corrected Intensity');

    title(sprintf('ROI %d', r));

    legend('Ch1', 'Ch3');

    grid on;
end

fprintf('\n✅ Done.\nSaved to:\n%s\n', outFile);