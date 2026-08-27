% --- Single-Channel (Ch3/GCaMP) Multi-ROI, Multi-Position, Multi-Cycle Analysis ---
% Handles experiments where multiple stage positions are revisited
% repeatedly across a long recording (e.g. positions 1-7 cycling in
% sequentially-numbered TSeries folders: ..._-898, ..._-899, ..., ..._-904,
% ..._-905 (back to position 1), etc.)
%
% Key differences from the single-folder version:
%   1. You process ONE stage position per run. All TSeries folders
%      belonging to that position (across the whole experiment) are
%      auto-located and concatenated at the FILE-LIST level only --
%      nothing is copied or merged on disk.
%   2. No real-time axis: everything is indexed by GlobalFrame (1, 2, 3...
%      across the whole concatenated position). Stimulation is marked by
%      the folder-suffix-number threshold you provide (e.g. "-940 onward
%      is stim") -- every frame from a folder past that number is flagged
%      StimPeriod = true in the CSV, and the first such GlobalFrame is
%      marked with a vertical line on the plots.
%   3. Before extracting the full trace, the script does a DRIFT SPOT-
%      CHECK: it draws your ROI(s) on the projection from the FIRST visit
%      to this position, then overlays those same ROI outlines on the
%      projection from the LAST visit. You decide whether to keep the
%      original ROI(s) for the whole position, or redraw ROI(s) on the
%      last-visit projection (in which case the script uses the early
%      mask for the first half of the visits and the late mask for the
%      second half -- a simple step-change correction, not continuous
%      registration; see notes at bottom of script for how to extend this
%      later to per-cycle registration if drift turns out to be gradual).
%   4. Corrupted/unreadable TIFF files do NOT stop the run. If a frame
%      can't be read, it's logged with a warning, its values are set to
%      NaN for that GlobalFrame, and extraction continues with the next
%      frame.
%
% ASSUMPTIONS YOU SHOULD VERIFY:
%   - Folder naming is "<anything>-<NUM>" where NUM is a sequential
%     integer suffix, one per acquisition, shared across all positions
%     (i.e. position assignment = position of NUM within the repeating
%     cycle of nPositions).


clear; clc; close all;

%% === Config: parent folder containing ALL TSeries folders for the experiment ===
% Use a guaranteed-valid starting folder for the dialog. pwd can fail here
% (e.g. in MATLAB Online, or if the current folder was deleted/unmounted),
% which throws "Initial file path must be... a valid path" from uigetdir.
startDir = pwd;
if isempty(startDir) || ~isfolder(startDir)
    startDir = userpath;
end
if isempty(startDir) || ~isfolder(startDir)
    startDir = tempdir;
end

parentFolder = uigetdir(startDir, 'Select the PARENT folder containing all TSeries folders');
if isequal(parentFolder, 0)
    error('No folder selected.');
end

%% === Config: numbering scheme ===
prompt = {
    'Folder suffix number of POSITION 1, FIRST cycle (e.g. 898):', ...
    'Number of stage positions per cycle (e.g. 7):', ...
    'Which position to process now (1-based):', ...
    'Folder suffix number of the LAST folder in the whole experiment:', ...
    'Folder suffix number where stimulation STARTED (inclusive -- e.g. 940 if -940 itself is the first stim folder):'
    };
dlgtitle = 'Multi-position experiment setup';
dims = [1 60];
definput = {'1255','10','1','1374','1315'};
answer = inputdlg(prompt, dlgtitle, dims, definput);
if isempty(answer)
    error('Setup cancelled.');
end

startNum   = str2double(answer{1});
nPositions = str2double(answer{2});
posToProc  = str2double(answer{3});
endNum     = str2double(answer{4});
stimStartFolderNum = str2double(answer{5});

%% === Resolve folder numbers belonging to this position, in chronological order ===
posNums = (startNum + (posToProc - 1)) : nPositions : endNum;
posNums = posNums(posNums <= endNum);

if isempty(posNums)
    error('No folder numbers computed for this position -- check startNum/nPositions/endNum.');
end

fprintf('Position %d appears in %d cycles: folder numbers %s\n', ...
    posToProc, numel(posNums), mat2str(posNums));

%% === Locate actual folder paths for each number ===
% Scan the parent folder ONCE and build a lookup from folder-suffix-number
% -> path. The old approach called dir(parentFolder) separately for every
% entry in posNums, which re-lists the entire parent folder each time --
% if the parent folder holds many TSeries folders (likely, across many
% positions and cycles) and/or lives on a network drive, that repeated
% full listing is almost certainly what was hanging before any of the
% per-folder progress messages had a chance to print.
fprintf('Scanning parent folder for TSeries subfolders...\n');
folderNumberMap = buildFolderNumberMap(parentFolder);
fprintf('Found %d TSeries folders in parent folder.\n', folderNumberMap.Count);

folderList = {};
foundNums = [];
for k = 1:numel(posNums)
    key = num2str(posNums(k));
    if ~isKey(folderNumberMap, key)
        warning('Could not find a folder ending in -%d, skipping.', posNums(k));
        continue;
    end
    folderList{end+1} = folderNumberMap(key); %#ok<SAGROW>
    foundNums(end+1) = posNums(k); %#ok<SAGROW>
end

nCycles = numel(folderList);
if nCycles == 0
    error('No matching folders found on disk.');
end
fprintf('Found %d of %d expected folders on disk.\n', nCycles, numel(posNums));

%% === Get per-folder file lists (Ch3 only -- single-channel experiment), frame counts ===
folderCh3Files = cell(nCycles,1);
nFramesPerFolder = zeros(nCycles,1);

for k = 1:nCycles
    names3 = sort(listFilesFast(folderList{k}, '*Ch3_*.ome.tif'));
    n = numel(names3);
    if n == 0
        error('Missing Ch3 files in folder: %s', folderList{k});
    end
    folderCh3Files{k} = names3;
    nFramesPerFolder(k) = n;
    fprintf('  Listed folder %d/%d (%s): %d frames\n', k, nCycles, folderList{k}, n);
end

nFramesTotal = sum(nFramesPerFolder);
fprintf('Total concatenated frames for this position: %d\n', nFramesTotal);

%% === Per-frame bookkeeping (no time axis -- GlobalFrame only) ===
cycleIdx = zeros(nFramesTotal,1);
frameInFolderIdx = zeros(nFramesTotal,1);
folderNumIdx = zeros(nFramesTotal,1);

ptr = 0;
for k = 1:nCycles
    n = nFramesPerFolder(k);
    idx = ptr + (1:n);
    cycleIdx(idx) = k;
    frameInFolderIdx(idx) = (1:n)';
    folderNumIdx(idx) = foundNums(k);
    ptr = ptr + n;
end

%% === Stimulation period, from the folder-number threshold ===
% Every frame belonging to a folder whose number is >= stimStartFolderNum
% (the entered folder number itself IS the first stim folder).
stimPeriod = folderNumIdx >= stimStartFolderNum;

stimCycle = find(foundNums >= stimStartFolderNum, 1, 'first');
if isempty(stimCycle)
    warning(['No folder in this position''s sequence has a number > %d -- ' ...
        'stimulation never starts within this position''s data. ' ...
        'Stim marker will not be plotted.'], stimStartFolderNum);
    stimStartGlobalFrame = NaN;
else
    stimStartGlobalFrame = find(cycleIdx == stimCycle, 1, 'first');
    fprintf('Stimulation starts at folder -%d (cycle %d of %d), GlobalFrame = %d\n', ...
        foundNums(stimCycle), stimCycle, nCycles, stimStartGlobalFrame);
end

%% === Projection from FIRST visit (Ch3) ===
projFirst = buildProjection(folderList{1}, folderCh3Files{1}, 5);

%% === Draw ROI(s) on first-visit projection ===
figure; imshow(projFirst);
title(sprintf('Position %d - FIRST visit. Draw ROI(s), ENTER when done', posToProc));
hold on;

roiMasksEarly = {};
roiCount = 0;
while true
    h = drawpolygon();
    if isempty(h)
        break;
    end
    wait(h);
    roiCount = roiCount + 1;
    roiMasksEarly{roiCount} = createMask(h);
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

%% === Background ROI (drawn once, on first-visit projection) ===
figure; imshow(projFirst);
title('Draw BACKGROUND ROI');
bkgMaskEarly = createMask(drawpolygon());
close all;

roiSizes = cellfun(@nnz, roiMasksEarly);
bkgSizeEarly = nnz(bkgMaskEarly);

%% === DRIFT SPOT-CHECK: overlay early ROI(s) on LAST visit projection ===
projLast = buildProjection(folderList{end}, folderCh3Files{end}, 5);

figure('Name','Drift spot-check','Position',[100 100 1200 600]);
subplot(1,2,1);
imshow(projFirst); hold on;
overlayRoiOutlines(roiMasksEarly, 'y');
title('FIRST visit (ROI drawn here)');

subplot(1,2,2);
imshow(projLast); hold on;
overlayRoiOutlines(roiMasksEarly, 'y');
title('LAST visit (early ROI overlaid)');

driftChoice = questdlg( ...
    'Do the ROI(s) still look aligned on the LAST visit, or is there visible drift?', ...
    'Drift check', 'Aligned - keep original ROI(s)', 'Drift - redraw on last visit', ...
    'Aligned - keep original ROI(s)');

useLateMask = false;
roiMasksLate = roiMasksEarly;
bkgMaskLate = bkgMaskEarly;
bkgSizeLate = bkgSizeEarly;

if strcmp(driftChoice, 'Drift - redraw on last visit')
    useLateMask = true;
    close all;

    figure; imshow(projLast);
    title(sprintf('Redraw the SAME %d ROI(s), in the SAME order, ENTER when done', roiCount));
    hold on;
    roiMasksLate = {};
    for r = 1:roiCount
        h = drawpolygon();
        wait(h);
        roiMasksLate{r} = createMask(h); %#ok<SAGROW>
        pos = mean(h.Position,1);
        text(pos(1), pos(2), sprintf('%d', r), ...
            'Color','yellow','FontSize',14,'FontWeight','bold');
    end

    figure; imshow(projLast);
    title('Draw BACKGROUND ROI for the late mask');
    bkgMaskLate = createMask(drawpolygon());
    bkgSizeLate = nnz(bkgMaskLate);
end
close all;

% Cutover point: folders 1..cutover use the early mask, cutover+1..end use
% the late mask. This is a simple step correction, not continuous
% registration -- see notes at the end of the script.
cutover = ceil(nCycles/2);

fprintf('Drift correction: %s\n', driftChoice);
if useLateMask
    fprintf('  Using EARLY mask for cycles 1-%d, LATE mask for cycles %d-%d.\n', ...
        cutover, cutover+1, nCycles);
end

%% === Initialize extraction arrays ===
roiCh3 = zeros(nFramesTotal, roiCount);
bkgCh3 = zeros(nFramesTotal, 1);
maskUsed = zeros(nFramesTotal, 1); % 1 = early, 2 = late

%% === Bounding boxes: read only the pixel region the masks actually cover ===
% imread supports 'PixelRegion' for TIFFs, which reads a sub-rectangle
% straight off disk instead of the full frame. Since every extracted value
% is a sum over a mask, cropping to the union of all ROI(s) + background
% mask before reading is exact (nothing outside the crop is ever used) and
% can substantially speed up the frame-by-frame loop below, especially for
% large frames with small ROIs. If the background ROI is placed far from
% the signal ROIs, the bounding box will be large and the speedup will be
% modest -- that's expected, not a bug.
bboxEarly = maskSetBoundingBox(roiMasksEarly, bkgMaskEarly);
if useLateMask
    bboxLate = maskSetBoundingBox(roiMasksLate, bkgMaskLate);
end

fprintf('Processing %d frames across %d folders...\n', nFramesTotal, nCycles);

%% === Loop over folders and frames ===
ptr = 0;
tExtractionStart = tic;
framesDoneSoFar = 0;
progressEvery = 100; % print an ETA every this many frames

for k = 1:nCycles
    n = nFramesPerFolder(k);

    if useLateMask && k > cutover
        theseRoiMasks = roiMasksLate;
        thisBkgMask = bkgMaskLate;
        thisMaskFlag = 2;
        bbox = bboxLate;
    else
        theseRoiMasks = roiMasksEarly;
        thisBkgMask = bkgMaskEarly;
        thisMaskFlag = 1;
        bbox = bboxEarly;
    end

    % Crop the masks once per folder (not once per frame) to match the
    % cropped region that will be read from each TIFF in this folder.
    rRange = bbox.rowRange(1):bbox.rowRange(2);
    cRange = bbox.colRange(1):bbox.colRange(2);
    theseRoiMasksCropped = cellfun(@(m) m(rRange, cRange), theseRoiMasks, 'UniformOutput', false);
    thisBkgMaskCropped = thisBkgMask(rRange, cRange);

    nBadFrames = 0;

    for i = 1:n
        idx = ptr + i;
        framePath = fullfile(folderList{k}, folderCh3Files{k}{i});

        try
            frame3 = double(imread(framePath, 'PixelRegion', {bbox.rowRange, bbox.colRange}));
        catch ME
            warning('Corrupted/unreadable frame, skipping (values set to NaN): %s (%s)', ...
                framePath, ME.message);
            bkgCh3(idx) = NaN;
            roiCh3(idx,:) = NaN;
            maskUsed(idx) = thisMaskFlag;
            nBadFrames = nBadFrames + 1;

            framesDoneSoFar = framesDoneSoFar + 1;
            continue;
        end

        bkgCh3(idx) = sum(frame3(thisBkgMaskCropped));

        for r = 1:roiCount
            roiCh3(idx,r) = sum(frame3(theseRoiMasksCropped{r}));
        end

        maskUsed(idx) = thisMaskFlag;

        framesDoneSoFar = framesDoneSoFar + 1;
        if mod(framesDoneSoFar, progressEvery) == 0 || framesDoneSoFar == nFramesTotal
            elapsedSec = toc(tExtractionStart);
            rate = framesDoneSoFar / elapsedSec; % frames/sec
            remainingSec = (nFramesTotal - framesDoneSoFar) / rate;
            fprintf('  %d/%d frames (%.1f%%) -- elapsed %.0fs, ETA %.0fs\n', ...
                framesDoneSoFar, nFramesTotal, 100*framesDoneSoFar/nFramesTotal, ...
                elapsedSec, remainingSec);
        end
    end

    if nBadFrames > 0
        fprintf('  Folder %d/%d: %d corrupted/unreadable frame(s) set to NaN.\n', ...
            k, nCycles, nBadFrames);
    end

    ptr = ptr + n;
end

%% === Scale background per ROI (mask-aware background size) ===
bkgCh3_scaled = zeros(nFramesTotal, roiCount);

earlyIdx = (maskUsed == 1);
lateIdx  = (maskUsed == 2);

for r = 1:roiCount
    scaleEarly = roiSizes(r) / bkgSizeEarly;
    bkgCh3_scaled(earlyIdx,r) = bkgCh3(earlyIdx) * scaleEarly;

    if any(lateIdx)
        scaleLate = roiSizes(r) / bkgSizeLate;
        bkgCh3_scaled(lateIdx,r) = bkgCh3(lateIdx) * scaleLate;
    end
end

%% === Corrected ===
corrCh3 = roiCh3 - bkgCh3_scaled;

%% === Save CSV ===
GlobalFrame = (1:nFramesTotal)';
Cycle = cycleIdx;
FolderNum = folderNumIdx;
FrameInFolder = frameInFolderIdx;
StimPeriod = stimPeriod;
MaskUsed = maskUsed;

T = table(GlobalFrame, Cycle, FolderNum, FrameInFolder, StimPeriod, MaskUsed);

for r = 1:roiCount
    T.(['Ch3_Raw_ROI' num2str(r)]) = roiCh3(:,r);
    T.(['Ch3_BkgScaled_ROI' num2str(r)]) = bkgCh3_scaled(:,r);
    T.(['Ch3_Corrected_ROI' num2str(r)]) = corrCh3(:,r);
end

outFile = fullfile(parentFolder, sprintf('Position%d_MultiCycle_FullTraces.csv', posToProc));
writetable(T, outFile);

%% === Plot PER ROI (GlobalFrame x-axis, stim onset marked) ===
for r = 1:roiCount

    figure;
    plot(GlobalFrame, roiCh3(:,r), '-g', 'LineWidth', 1.2); hold on;
    plot(GlobalFrame, bkgCh3_scaled(:,r), '--k', 'LineWidth', 1.2);
    plot(GlobalFrame, corrCh3(:,r), '-b', 'LineWidth', 1.5);
    if ~isnan(stimStartGlobalFrame)
        xline(stimStartGlobalFrame, '--m', 'Stim', 'LineWidth', 1.5);
    end
    xlabel('Global Frame'); ylabel('Intensity');
    title(sprintf('Position %d - Ch3 (GCaMP) - ROI %d', posToProc, r));
    legend('Raw ROI', 'Background (scaled)', 'Corrected');
    grid on;
end

fprintf('\n Done. Results saved to:\n%s\n', outFile);

%% =====================================================================
%% Local functions
%% =====================================================================

function names = listFilesFast(folderPath, pattern)
    % Fast alternative to dir() for folders containing huge numbers of
    % files (e.g. one TIFF per frame). MATLAB's dir() computes full
    % metadata -- including a datenum -- for every matched file, which
    % becomes very slow once a folder has thousands of files, and worse
    % again on a network/mapped drive. This calls the OS's own directory
    % listing command instead, which is much faster, and returns just the
    % file names (as a column cell array), unsorted -- sort separately.
    if ispc
        cmd = sprintf('dir /b "%s"', fullfile(folderPath, pattern));
    else
        cmd = sprintf('ls -1 "%s"/%s 2>/dev/null', folderPath, pattern);
    end

    [status, out] = system(cmd);

    if status ~= 0 || isempty(strtrim(out))
        names = {};
        return;
    end

    lines = strsplit(strtrim(out), newline);
    lines = strtrim(lines);
    lines = lines(~cellfun(@isempty, lines));

    if ~ispc
        % On Mac/Linux, ls with a full-path glob returns full paths --
        % strip back down to just the file name to match dir()'s output.
        lines = cellfun(@(p) regexprep(p, '.*[\\/]', ''), lines, 'UniformOutput', false);
    end

    names = lines(:);
end

function bbox = maskSetBoundingBox(roiMasks, bkgMask)
    % Bounding box (row/col range) enclosing every true pixel across all
    % ROI masks plus the background mask. Used to crop what gets read
    % from disk per frame.
    combined = bkgMask;
    for r = 1:numel(roiMasks)
        combined = combined | roiMasks{r};
    end
    [rows, cols] = find(combined);
    bbox.rowRange = [min(rows), max(rows)];
    bbox.colRange = [min(cols), max(cols)];
end

function folderMap = buildFolderNumberMap(parentFolder)
    % Single pass over parentFolder's subfolders, building a
    % containers.Map from trailing suffix number (as a string key) to
    % full folder path. Call this once, then do fast lookups, instead of
    % re-listing parentFolder for every folder number you need.
    d = dir(parentFolder);
    d = d([d.isdir]);
    folderMap = containers.Map('KeyType', 'char', 'ValueType', 'char');
    for i = 1:numel(d)
        if strcmp(d(i).name, '.') || strcmp(d(i).name, '..')
            continue;
        end
        tok = regexp(d(i).name, '-(\d+)$', 'tokens', 'once');
        if isempty(tok)
            continue;
        end
        folderMap(tok{1}) = fullfile(parentFolder, d(i).name);
    end
end

function projImg = buildProjection(folderPath, sortedFileNames, nProj)
    % Average projection of the first nProj *readable* frames in
    % sortedFileNames. Corrupted/unreadable files are skipped with a
    % warning rather than stopping the script; it keeps trying subsequent
    % files until it has nProj good frames or runs out of files.
    nWanted = min(nProj, numel(sortedFileNames));
    sumProjection = [];
    nGood = 0;
    i = 0;
    while nGood < nWanted && i < numel(sortedFileNames)
        i = i + 1;
        fpath = fullfile(folderPath, sortedFileNames{i});
        try
            frame = double(imread(fpath));
        catch ME
            warning('Skipping unreadable file for projection: %s (%s)', fpath, ME.message);
            continue;
        end
        if isempty(sumProjection)
            sumProjection = zeros(size(frame));
        end
        sumProjection = sumProjection + frame;
        nGood = nGood + 1;
    end
    if nGood == 0
        error('No readable frames found in %s to build a projection.', folderPath);
    end
    projRaw = sumProjection / nGood;
    lowHigh = prctile(projRaw(:), [1 99]);
    projImg = mat2gray(projRaw, lowHigh);
end

function overlayRoiOutlines(roiMasks, colorSpec)
    % Draw outlines of each mask in roiMasks on the current axes.
    for r = 1:numel(roiMasks)
        B = bwboundaries(roiMasks{r});
        for b = 1:numel(B)
            boundary = B{b};
            plot(boundary(:,2), boundary(:,1), colorSpec, 'LineWidth', 1.5);
        end
        c = regionprops(roiMasks{r}, 'Centroid');
        if ~isempty(c)
            text(c(1).Centroid(1), c(1).Centroid(2), sprintf('%d', r), ...
                'Color', colorSpec, 'FontSize', 12, 'FontWeight', 'bold');
        end
    end
end
