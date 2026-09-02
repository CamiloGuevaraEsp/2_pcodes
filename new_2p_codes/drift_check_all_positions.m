% --- Automated Drift Check, ALL Positions ---
% Quick, unattended screening tool: for every stage position in a
% multi-position, multi-cycle 2p experiment, this builds a projection for
% every revisit and measures translational drift relative to that
% position's own first visit -- with NO manual ROI drawing required,
% since drift here is measured on the whole field of view, not a
% specific ROI.
%
% Use this BEFORE running the full per-position extraction script, to
% quickly see which (if any) positions have real drift worth worrying
% about, and roughly when it starts, before committing to drawing ROIs
% and doing full extraction on each one.
%
% Output: one figure with a shift-vs-cycle subplot per position, a
% companion confidence figure, and a summary table printed to the
% console (and optionally saved as CSV).

clear; clc; close all;

%% === Config: parent folder ===
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
    'Folder suffix number of the LAST folder in the whole experiment:', ...
    'Optional: folder suffix number where stimulation started (leave blank to skip marking it):'
    };
dlgtitle = 'Drift check -- all positions';
dims = [1 60];
definput = {'1736','10','1855','1796'};
answer = inputdlg(prompt, dlgtitle, dims, definput);
if isempty(answer)
    error('Setup cancelled.');
end

startNum   = str2double(answer{1});
nPositions = str2double(answer{2});
endNum     = str2double(answer{3});
stimStartFolderNum = str2double(answer{4}); % NaN if left blank

%% === Registration mode ===
% Whole-frame: measures drift of the entire field of view, ignoring your
% specific signal region. Fast, fully automated, no drawing.
% ROI region: draws one rectangle per position (on that position's first
% cycle only) and tracks drift of JUST that local patch via template
% matching. Slower to set up (one quick draw per position) but tells you
% specifically whether the region you actually care about has drifted,
% independent of unrelated movement elsewhere in the frame.
modeChoice = questdlg( ...
    ['Register using the WHOLE FRAME (fully automated), or a specific ' ...
    'ROI REGION (draw one rectangle per position)?'], ...
    'Registration mode', 'Whole frame', 'ROI region', 'Whole frame');
if isempty(modeChoice)
    error('Setup cancelled.');
end
useROIMode = strcmp(modeChoice, 'ROI region');

marginPx = 15; % default margin around a saved ROI's bounding box, in pixels
if useROIMode
    marginAnswer = inputdlg( ...
        {'Margin (pixels) to add around the saved ROI''s bounding box:'}, ...
        'ROI tracking margin', [1 60], {'15'});
    if ~isempty(marginAnswer)
        marginPx = str2double(marginAnswer{1});
    end
end

%% === Scan parent folder ONCE, build folder-number -> path lookup ===
fprintf('Scanning parent folder for TSeries subfolders...\n');
folderNumberMap = buildFolderNumberMap(parentFolder);
fprintf('Found %d TSeries folders in parent folder.\n', folderNumberMap.Count);

%% === Process each position ===
results = struct('position', {}, 'folderNums', {}, 'shiftX', {}, 'shiftY', {}, ...
    'confidence', {}, 'nCycles', {}, 'projections', {}, 'roiRect', {});

for posIdx = 1:nPositions
    posNums = (startNum + (posIdx - 1)) : nPositions : endNum;
    posNums = posNums(posNums <= endNum);

    folderList = {};
    foundNums = [];
    for kk = 1:numel(posNums)
        key = num2str(posNums(kk));
        if isKey(folderNumberMap, key)
            folderList{end+1} = folderNumberMap(key); %#ok<SAGROW>
            foundNums(end+1) = posNums(kk); %#ok<SAGROW>
        end
    end

    nCycles = numel(folderList);
    if nCycles == 0
        warning('Position %d: no folders found on disk, skipping.', posIdx);
        continue;
    end

    fprintf('\nPosition %d: %d cycles found (folders %s)\n', ...
        posIdx, nCycles, mat2str(foundNums));

    % Build a projection per cycle (Ch3 only), tolerating corrupted files.
    allProjections = cell(nCycles, 1);
    for k = 1:nCycles
        names3 = sort(listFilesFast(folderList{k}, '*Ch3_*.ome.tif'));
        if isempty(names3)
            warning('Position %d, cycle %d (folder %s): no Ch3 files found, skipping this cycle.', ...
                posIdx, k, folderList{k});
            allProjections{k} = [];
            continue;
        end
        allProjections{k} = buildProjection(folderList{k}, names3, 20);
        fprintf('  Built projection for cycle %d/%d (folder -%d)\n', k, nCycles, foundNums(k));
    end

    % Drop any cycles where no projection could be built at all.
    validCycles = ~cellfun(@isempty, allProjections);
    if ~any(validCycles)
        warning('Position %d: no valid projections could be built, skipping.', posIdx);
        continue;
    end
    allProjections = allProjections(validCycles);
    foundNums = foundNums(validCycles);
    nCycles = numel(allProjections);

    % Register every cycle's projection against THIS position's own first
    % valid cycle -- either whole-frame, or a specific ROI region.
    shiftX = nan(nCycles, 1);
    shiftY = nan(nCycles, 1);
    confidence = nan(nCycles, 1);
    refImg = allProjections{1};
    [imgH, imgW] = size(refImg);
    roiRect = [];

    % Always TRY to load a saved ROI for this position, purely for display
    % on the montage -- independent of which registration mode is active.
    % Whole-frame mode never needs this to compute anything, but seeing
    % the region you actually care about outlined makes visual drift
    % inspection much easier either way.
    roiSaveFile = fullfile(parentFolder, sprintf('Position%d_ROI.mat', posIdx));
    if isfile(roiSaveFile)
        loaded = load(roiSaveFile, 'roiMasksEarly');
        roiRect = roiUnionBoundingBox(loaded.roiMasksEarly, marginPx, [imgH, imgW]);
    end

    if useROIMode
        if isempty(roiRect)
            warning(['Position %d: no saved ROI found at %s -- falling back to a manually ' ...
                'drawn rectangle. Run the main extraction script for this position first ' ...
                'to auto-populate this in future runs.'], posIdx, roiSaveFile);
            figure; imshow(refImg);
            title(sprintf(['Position %d: draw a RECTANGLE around the region to track ' ...
                '(double-click to confirm)'], posIdx));
            rectH = drawrectangle();
            wait(rectH);
            roiRect = round(rectH.Position); % [x y w h]
            close all;
        else
            fprintf('Position %d: using saved polygon ROI from %s (bounding box + %d px margin).\n', ...
                posIdx, roiSaveFile, marginPx);
        end

        % Clamp to image bounds just in case.
        x0 = max(1, roiRect(1)); y0 = max(1, roiRect(2));
        x1 = min(imgW, x0 + roiRect(3)); y1 = min(imgH, y0 + roiRect(4));
        templatePatch = refImg(y0:y1, x0:x1);

        % Baseline: match the template against its OWN source image. This
        % calibrates out normxcorr2's fixed indexing offset so that what
        % we report is purely the CHANGE in position across cycles, not
        % an absolute pixel coordinate.
        [dx0, dy0, ~] = registerTranslationNCC(refImg, templatePatch);

        for k = 1:nCycles
            try
                [dxk, dyk, ck] = registerTranslationNCC(allProjections{k}, templatePatch);
                shiftX(k) = dxk - dx0;
                shiftY(k) = dyk - dy0;
                confidence(k) = ck;
            catch ME
                warning('Position %d, cycle %d: ROI registration failed (%s).', posIdx, k, ME.message);
            end
        end
    else
        for k = 1:nCycles
            try
                [shiftX(k), shiftY(k), confidence(k)] = registerTranslationNCC(refImg, allProjections{k});
            catch ME
                warning('Position %d, cycle %d: registration failed (%s).', posIdx, k, ME.message);
            end
        end
    end

    results(end+1) = struct('position', posIdx, 'folderNums', foundNums, ...
        'shiftX', shiftX, 'shiftY', shiftY, 'confidence', confidence, 'nCycles', nCycles, ...
        'projections', {allProjections}, 'roiRect', roiRect); %#ok<SAGROW>
end

if isempty(results)
    error('No positions could be processed -- check your numbering scheme and parent folder.');
end

%% === Plot: shift curves, one subplot per position ===
nPos = numel(results);
nCols = ceil(sqrt(nPos));
nRows = ceil(nPos / nCols);

figure('Name', 'Drift check -- all positions (shift)', 'Position', [50 50 1600 900]);
for p = 1:nPos
    subplot(nRows, nCols, p);
    r = results(p);
    plot(1:r.nCycles, r.shiftX, '-o', 'LineWidth', 1.1); hold on;
    plot(1:r.nCycles, r.shiftY, '-o', 'LineWidth', 1.1);

    if ~isnan(stimStartFolderNum)
        stimCyc = find(r.folderNums >= stimStartFolderNum, 1, 'first');
        if ~isempty(stimCyc)
            xline(stimCyc, '--m', 'Stim', 'LineWidth', 1.2);
        end
    end

    xlabel('Cycle'); ylabel('Shift (px)');
    title(sprintf('Position %d', r.position));
    if p == 1
        legend('X shift', 'Y shift', 'Location', 'best');
    end
    grid on;
end
sgtitle(sprintf('Per-position translational drift relative to each position''s own first visit (%s)', modeChoice));

%% === Plot: confidence curves, one subplot per position ===
figure('Name', 'Drift check -- all positions (confidence)', 'Position', [50 50 1600 900]);
for p = 1:nPos
    subplot(nRows, nCols, p);
    r = results(p);
    plot(1:r.nCycles, r.confidence, '-o', 'LineWidth', 1.1, 'Color', [0.4 0.4 0.4]);

    if ~isnan(stimStartFolderNum)
        stimCyc = find(r.folderNums >= stimStartFolderNum, 1, 'first');
        if ~isempty(stimCyc)
            xline(stimCyc, '--m', 'Stim', 'LineWidth', 1.2);
        end
    end

    xlabel('Cycle'); ylabel('Peak NCC');
    title(sprintf('Position %d', r.position));
    ylim([0 1]);
    grid on;
end
sgtitle(sprintf('Registration confidence per position (%s; lower = less reliable shift estimate)', modeChoice));

%% === Summary table ===
Position = zeros(nPos,1);
NCycles = zeros(nPos,1);
MaxAbsShiftX = zeros(nPos,1);
MaxAbsShiftY = zeros(nPos,1);
MinConfidence = zeros(nPos,1);

for p = 1:nPos
    r = results(p);
    Position(p) = r.position;
    NCycles(p) = r.nCycles;
    MaxAbsShiftX(p) = max(abs(r.shiftX), [], 'omitnan');
    MaxAbsShiftY(p) = max(abs(r.shiftY), [], 'omitnan');
    MinConfidence(p) = min(r.confidence, [], 'omitnan');
end

summaryT = table(Position, NCycles, MaxAbsShiftX, MaxAbsShiftY, MinConfidence);
disp('Drift summary across positions:');
disp(summaryT);

outFile = fullfile(parentFolder, 'DriftCheck_AllPositions_Summary.csv');
writetable(summaryT, outFile);
fprintf('\nSummary saved to:\n%s\n', outFile);

%% === Visual confirmation: one projection montage per position ===
% Same idea as the montage in the main extraction script, but here there's
% no ROI to overlay (this script never draws one) -- instead, each tile
% shows the raw projection for that cycle, and cycles the numbers already
% flagged as suspicious are highlighted so you can visually cross-check
% the shift/confidence curves against what the images actually look like.
%
% "Suspicious" here just means: |shift| beyond outlierShiftPx, or
% confidence below outlierConfidence. These are simple, adjustable
% thresholds, not a statistical test -- treat them as a spotlight on
% where to look, not a verdict.
outlierShiftPx = 5;      % pixels
outlierConfidence = 0.5; % peak NCC

maxTiles = 24;

for p = 1:nPos
    r = results(p);
    nCycles = r.nCycles;

    if nCycles <= maxTiles
        tileIdx = 1:nCycles;
    else
        tileIdx = unique(round(linspace(1, nCycles, maxTiles)));
    end
    nTiles = numel(tileIdx);
    nCols = ceil(sqrt(nTiles));
    nRows = ceil(nTiles / nCols);

    figure('Name', sprintf('Position %d projections', r.position), 'Position', [50 50 1600 900]);
    for t = 1:nTiles
        k = tileIdx(t);
        subplot(nRows, nCols, t);
        imshow(r.projections{k}); hold on;
        if ~isempty(r.roiRect)
            rectangle('Position', r.roiRect, 'EdgeColor', 'y', 'LineWidth', 1.2);
        end

        isOutlier = (abs(r.shiftX(k)) > outlierShiftPx) || (abs(r.shiftY(k)) > outlierShiftPx) || ...
            (r.confidence(k) < outlierConfidence);

        titleStr = sprintf('Cyc %d (-%d)\n\\Delta=(%.1f,%.1f) c=%.2f', ...
            k, r.folderNums(k), r.shiftX(k), r.shiftY(k), r.confidence(k));

        if isOutlier
            title(titleStr, 'FontSize', 7, 'Color', 'r', 'FontWeight', 'bold');
        else
            title(titleStr, 'FontSize', 7);
        end
    end
    sgtitle(sprintf('Position %d: projections per cycle (red title = flagged as drift/low-confidence outlier)', ...
        r.position));
end

%% === Visual confirmation 2: false-color overlay of each cycle onto cycle 1 ===
% imfuse() overlays two images in false color: the reference (cycle 1) in
% magenta, the current cycle in green. Where they line up, you get gray/
% white; where they don't, you get a magenta/green fringe right at the
% mismatch -- a much more sensitive way to SEE sub-pixel-to-few-pixel
% misalignment than flipping between two separate grayscale images.
for p = 1:nPos
    r = results(p);
    nCycles = r.nCycles;
    refImg = r.projections{1};

    if nCycles <= maxTiles
        tileIdx = 1:nCycles;
    else
        tileIdx = unique(round(linspace(1, nCycles, maxTiles)));
    end
    nTiles = numel(tileIdx);
    nCols = ceil(sqrt(nTiles));
    nRows = ceil(nTiles / nCols);

    figure('Name', sprintf('Position %d overlay to cycle 1', r.position), 'Position', [50 50 1600 900]);
    for t = 1:nTiles
        k = tileIdx(t);
        subplot(nRows, nCols, t);

        fused = imfuse(refImg, r.projections{k}, 'falsecolor', 'Scaling', 'joint', ...
            'ColorChannels', [1 2 1]); % reference=magenta(R+B), this cycle=green
        imshow(fused); hold on;
        if ~isempty(r.roiRect)
            rectangle('Position', r.roiRect, 'EdgeColor', 'y', 'LineWidth', 1.2);
        end

        isOutlier = (abs(r.shiftX(k)) > outlierShiftPx) || (abs(r.shiftY(k)) > outlierShiftPx) || ...
            (r.confidence(k) < outlierConfidence);
        titleStr = sprintf('Cyc %d (-%d) c=%.2f', k, r.folderNums(k), r.confidence(k));
        if isOutlier
            title(titleStr, 'FontSize', 7, 'Color', 'r', 'FontWeight', 'bold');
        else
            title(titleStr, 'FontSize', 7);
        end
    end
    sgtitle(sprintf(['Position %d: magenta = cycle 1 (reference), green = this cycle -- ' ...
        'gray/white = aligned, colored fringe = mismatch'], r.position));
end

%% =====================================================================
%% Local functions (shared logic with the main extraction script)
%% =====================================================================

function rect = roiUnionBoundingBox(roiMasks, marginPx, imgSize)
    % Bounding box (as [x y w h], matching drawrectangle's Position format)
    % around the union of all ROI masks, padded by marginPx on every side
    % and clamped to the image bounds.
    combined = false(imgSize);
    for r = 1:numel(roiMasks)
        combined = combined | roiMasks{r};
    end
    [rows, cols] = find(combined);
    y0 = max(1, min(rows) - marginPx);
    y1 = min(imgSize(1), max(rows) + marginPx);
    x0 = max(1, min(cols) - marginPx);
    x1 = min(imgSize(2), max(cols) + marginPx);
    rect = [x0, y0, x1 - x0, y1 - y0];
end

function folderMap = buildFolderNumberMap(parentFolder)
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

function names = listFilesFast(folderPath, pattern)
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
        lines = cellfun(@(p) regexprep(p, '.*[\\/]', ''), lines, 'UniformOutput', false);
    end

    names = lines(:);
end

function projImg = buildProjection(folderPath, sortedFileNames, nProj)
    % MEAN projection (see analysis2p_multiposition.m for rationale --
    % median was tried and didn't help; mean is the right call for
    % photon-limited, single-channel GCaMP data).
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

function [dx, dy, peakCorr] = registerTranslationNCC(fixedImg, movingImg)
    c = normxcorr2(movingImg, fixedImg);
    [peakCorr, linIdx] = max(c(:));
    [ypeak, xpeak] = ind2sub(size(c), linIdx);
    dy = ypeak - size(movingImg, 1);
    dx = xpeak - size(movingImg, 2);
end
