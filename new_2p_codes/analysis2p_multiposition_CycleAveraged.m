% --- Single-Channel (Ch3/GCaMP) Multi-ROI, Multi-Position, Multi-Cycle Analysis ---
% CYCLE-AVERAGED VARIANT: identical pipeline to analysis2p_multiposition.m
% (same ROI drawing, same per-cycle drift registration and ROI-shift
% correction) but the OUTPUT collapses every cycle's many frames down to
% ONE value per cycle (the mean across that cycle's frames), instead of
% keeping every frame as its own row.
%
% "Time" for each collapsed cycle is the GlobalFrame of that cycle's
% MIDDLE frame (ceil(nFramesInCycle/2)) -- i.e. where that cycle sits in
% the overall frame-ordered sequence, not a real elapsed-time value (no
% per-frame acquisition timestamps are read here). This keeps the same
% GlobalFrame numbering used throughout the per-frame version, so a
% cycle-averaged point and a per-frame point can still be compared on
% the same axis if needed.
%
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
%      is stim") -- every cycle whose folder number is past that
%      threshold is flagged StimPeriod = true in the CSV, and the first
%      such cycle's mid-frame GlobalFrame is marked with a vertical line
%      on the plots.
%   3. Drift correction is CONTINUOUS and PER-CYCLE. You draw the ROI(s)
%      + background ROI ONCE, on the first-visit projection. The script
%      then registers every OTHER cycle's projection against that same
%      first-visit reference (whole-frame template match -- the same
%      method validated in drift_check_all_positions.m) and translates
%      the ROI/background masks by that cycle's own measured pixel shift
%      before extracting.
%   4. Corrupted/unreadable TIFF files do NOT stop the run. If a frame
%      can't be read, it's excluded (NaN) from that cycle's average
%      rather than stopping extraction; NValidFrames per cycle records
%      how many frames actually went into each average.
%
% ASSUMPTIONS YOU SHOULD VERIFY:
%   - Folder naming is "<anything>-<NUM>" where NUM is a sequential
%     integer suffix, one per acquisition, shared across all positions
%     (i.e. position assignment = position of NUM within the repeating
%     cycle of nPositions).
%   - Drift is translational. If a position shows rotation, deformation,
%     or z-focus drift (check that position's output from
%     drift_check_all_positions.m -- confidence dropping while measured
%     shift stays flat/plateaus is the tell), a whole-frame translation
%     correction will not fully fix it and the extracted trace should be
%     treated with caution.
%   - Averaging within a cycle assumes the signal is roughly stationary
%     across that cycle's frames (e.g. a slow calcium signal relative to
%     the frame rate). If the signal changes meaningfully WITHIN a single
%     cycle's acquisition window, collapsing to one value per cycle
%     discards that within-cycle dynamic -- use the per-frame version
%     (analysis2p_multiposition.m) instead if that matters for your
%     analysis.


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
dlgtitle = 'Multi-position experiment setup (cycle-averaged)';
dims = [1 60];
definput = {'1736','10','1','1855','1796'};
answer = inputdlg(prompt, dlgtitle, dims, definput);
if isempty(answer)
    error('Setup cancelled.');
end

startNum   = str2double(answer{1});
nPositions = str2double(answer{2});
posToProc  = str2double(answer{3});
endNum     = str2double(answer{4});
stimStartFolderNum = str2double(answer{5});

%% === Config: drift-registration parameters ===
% Same method (and same rationale) as drift_check_all_positions.m: a
% centered crop of the reference (first-visit) projection is matched
% against each OTHER cycle's full projection via normxcorr2 template
% matching. Running normxcorr2 on two FULL, equal-size images instead
% (no crop) has a shrinking-overlap bias that underestimates real drift
% -- see that script's comments for the full explanation.
wholeFrameMarginFrac = 0.15;  % keep the central 70% of each dimension as the template
nProjFramesForReg = 20;       % frames averaged per cycle when building the projection used
                               % both for ROI drawing (cycle 1 only) and for registration
minRegConfidence = 0.3;       % below this, don't trust this cycle's measured shift -- carry
                               % forward the last trustworthy cycle's shift instead of
                               % applying a noisy/wrong one

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
cycleStartPtr = zeros(nCycles,1); % GlobalFrame offset (0-based) where each cycle begins
for k = 1:nCycles
    n = nFramesPerFolder(k);
    cycleStartPtr(k) = ptr;
    idx = ptr + (1:n);
    cycleIdx(idx) = k;
    frameInFolderIdx(idx) = (1:n)';
    folderNumIdx(idx) = foundNums(k);
    ptr = ptr + n;
end

%% === Per-cycle frame-count "time" (kept for reference/cross-checking only) ===
% GlobalFrame just counts frames -- it silently assumes frames are
% packed back-to-back with no gap between cycles, which is false here:
% between one visit to this position and the next, the microscope has to
% cycle through every OTHER position first, a real gap of many seconds
% that a frame counter can't see. See the REAL time block below, which
% reads actual acquisition timestamps from each folder's XML instead.
midFrameInFolder = ceil(nFramesPerFolder / 2);
midGlobalFrame = cycleStartPtr + midFrameInFolder;

%% === Per-cycle REAL time: XML timestamp of the middle frame ===
% Each TSeries folder's .xml records a real wall-clock acquisition start
% (PVScan date + Sequence time) plus, per frame, a relativeTime (seconds
% since that start) and the exact Ch3 filename it belongs to. Combining
% those gives the true acquisition time of any frame -- unlike
% GlobalFrame, this correctly reflects the real gap caused by cycling
% through the other positions between revisits.
midFrameDatetime = NaT(nCycles, 1);
for k = 1:nCycles
    xmlFiles = dir(fullfile(folderList{k}, '*.xml'));
    if numel(xmlFiles) ~= 1
        error('Expected exactly one .xml file in %s, found %d.', folderList{k}, numel(xmlFiles));
    end
    xmlPath = fullfile(xmlFiles(1).folder, xmlFiles(1).name);
    midFilename = folderCh3Files{k}{midFrameInFolder(k)};
    [seqStart, relTime] = readFrameTimeFromXML(xmlPath, midFilename);
    midFrameDatetime(k) = seqStart + seconds(relTime);
end

% Anchor t=0 at the very first folder of the WHOLE experiment (position 1,
% cycle 1, folder -startNum) rather than this position's own cycle 1, so
% that different positions' cycle-averaged CSVs share a common absolute
% timeline -- positions are interleaved in real time, not run back to
% back, so this is what makes their timestamps comparable to each other.
% Falls back to this position's own cycle 1 if that folder can't be
% found/read (ElapsedTime_sec is then only meaningful within this CSV).
try
    expStartKey = num2str(startNum);
    if ~isKey(folderNumberMap, expStartKey)
        error('Folder -%d (experiment start, position 1 cycle 1) not found.', startNum);
    end
    expStartFolder = folderNumberMap(expStartKey);
    expStartXmlFiles = dir(fullfile(expStartFolder, '*.xml'));
    if numel(expStartXmlFiles) ~= 1
        error('Expected exactly one .xml file in %s, found %d.', expStartFolder, numel(expStartXmlFiles));
    end
    experimentStart = readSequenceStartTime(fullfile(expStartXmlFiles(1).folder, expStartXmlFiles(1).name));
catch ME
    warning(['Could not read the experiment''s absolute start time (%s) -- using this ' ...
        'position''s own cycle 1 as t=0 instead. ElapsedTime_sec will NOT be comparable ' ...
        'across different positions in that case.'], ME.message);
    experimentStart = midFrameDatetime(1);
end

ElapsedTime_sec = seconds(midFrameDatetime - experimentStart);
fprintf('Cycle mid-frame real times (elapsed seconds since experiment start):\n');
for k = 1:nCycles
    fprintf('  Cycle %d (folder -%d): %s (%.1f s)\n', ...
        k, foundNums(k), string(midFrameDatetime(k), 'HH:mm:ss.SSS'), ElapsedTime_sec(k));
end

%% === Stimulation period, from the folder-number threshold ===
% A cycle counts as stim if its folder number is >= stimStartFolderNum
% (the entered folder number itself IS the first stim folder).
stimPeriodByCycle = foundNums(:) >= stimStartFolderNum;

stimCycle = find(stimPeriodByCycle, 1, 'first');
if isempty(stimCycle)
    warning(['No folder in this position''s sequence has a number > %d -- ' ...
        'stimulation never starts within this position''s data. ' ...
        'Stim marker will not be plotted.'], stimStartFolderNum);
    stimStartMidGlobalFrame = NaN;
    stimStartElapsedSec = NaN;
else
    stimStartMidGlobalFrame = midGlobalFrame(stimCycle);
    stimStartElapsedSec = ElapsedTime_sec(stimCycle);
    fprintf('Stimulation starts at folder -%d (cycle %d of %d), %.1f s elapsed.\n', ...
        foundNums(stimCycle), stimCycle, nCycles, stimStartElapsedSec);
end

%% === Build a projection for EVERY cycle ===
% Needed for both ROI drawing (cycle 1) and per-cycle registration.
fprintf('Building per-cycle projections for drift registration...\n');
projections = cell(nCycles, 1);
for k = 1:nCycles
    projections{k} = buildProjection(folderList{k}, folderCh3Files{k}, nProjFramesForReg);
end
projFirst = projections{1};

%% === Draw ROI(s) on first-visit projection ===
figure; imshow(projFirst);
title(sprintf('Position %d - FIRST visit. Draw ROI(s), ENTER when done', posToProc));
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

%% === Background ROI (drawn once, on first-visit projection) ===
figure; imshow(projFirst);
title('Draw BACKGROUND ROI');
bkgMask = createMask(drawpolygon());
close all;

% Also save the ROI masks for drift_check_all_positions.m to load next
% time (it displays this as an overlay for visual reference -- purely
% cosmetic there, unused for its own registration).
roiSaveFile = fullfile(parentFolder, sprintf('Position%d_ROI.mat', posToProc));
roiMasksEarly = roiMasks; % kept under its old field name for compatibility
save(roiSaveFile, 'roiMasksEarly');

%% === Per-cycle drift registration relative to cycle 1 ===
% Same template-matching approach as drift_check_all_positions.m: crop a
% centered template out of the reference (cycle 1) projection, then find
% where that template best matches inside each OTHER cycle's full
% projection via normalized cross-correlation. See that script's
% wholeFrameMarginFrac comment for why a crop (rather than correlating
% two full, equal-size images) is necessary to avoid underestimating
% real drift.
[imgH, imgW] = size(projFirst);
trimX = round(imgW * wholeFrameMarginFrac);
trimY = round(imgH * wholeFrameMarginFrac);
templateRect = [trimX + 1, trimY + 1, imgW - 2 * trimX, imgH - 2 * trimY];
tx0 = max(1, templateRect(1)); ty0 = max(1, templateRect(2));
tx1 = min(imgW, tx0 + templateRect(3)); ty1 = min(imgH, ty0 + templateRect(4));
templatePatch = projFirst(ty0:ty1, tx0:tx1);

[dx0, dy0, ~] = registerTranslationNCC(projFirst, templatePatch);

shiftX = zeros(nCycles, 1);
shiftY = zeros(nCycles, 1);
regConfidence = ones(nCycles, 1);
nCarriedForward = 0;

for k = 2:nCycles
    try
        [dxk, dyk, ck] = registerTranslationNCC(projections{k}, templatePatch);
        regConfidence(k) = ck;
        if ck >= minRegConfidence
            shiftX(k) = dxk - dx0;
            shiftY(k) = dyk - dy0;
        else
            % Untrustworthy registration for this cycle -- carry forward
            % the last trustworthy shift rather than applying a noisy or
            % wrong correction.
            shiftX(k) = shiftX(k-1);
            shiftY(k) = shiftY(k-1);
            nCarriedForward = nCarriedForward + 1;
            warning(['Position %d, cycle %d: registration confidence %.2f below ' ...
                'threshold %.2f -- carrying forward previous cycle''s shift ' ...
                '(%.0f, %.0f) px.'], posToProc, k, ck, minRegConfidence, shiftX(k), shiftY(k));
        end
    catch ME
        shiftX(k) = shiftX(k-1);
        shiftY(k) = shiftY(k-1);
        regConfidence(k) = 0;
        nCarriedForward = nCarriedForward + 1;
        warning('Position %d, cycle %d: registration failed (%s) -- carrying forward previous shift.', ...
            posToProc, k, ME.message);
    end
end
shiftX = round(shiftX);
shiftY = round(shiftY);

fprintf('Per-cycle drift shift relative to cycle 1 (px):\n');
for k = 1:nCycles
    fprintf('  Cycle %d (folder -%d): dx=%d dy=%d conf=%.2f\n', ...
        k, foundNums(k), shiftX(k), shiftY(k), regConfidence(k));
end
if nCarriedForward > 0
    fprintf('%d/%d cycles had untrustworthy registration; shift carried forward for those.\n', ...
        nCarriedForward, nCycles);
end

%% === Build per-cycle shifted ROI + background masks ===
roiMasksByCycle = cell(nCycles, roiCount);
bkgMaskByCycle = cell(nCycles, 1);
for k = 1:nCycles
    for r = 1:roiCount
        roiMasksByCycle{k, r} = shiftMask(roiMasks{r}, shiftX(k), shiftY(k));
    end
    bkgMaskByCycle{k} = shiftMask(bkgMask, shiftX(k), shiftY(k));
end

%% === Plot: BEFORE vs. AFTER correction, first visit vs. last visit ===
% "Before" fuses the two projections as-is (magenta = cycle 1, green =
% last cycle) -- any drift shows up as a colored fringe at the mismatch,
% same visual language as drift_check_all_positions.m. "After" undoes
% the measured drift by translating the LAST cycle's projection back
% into cycle 1's frame (the same shift applied to the masks, just
% applied to the image instead, and in the opposite direction) -- if the
% correction is right, the fringe should mostly disappear into gray/
% white. The original (cycle-1) ROI outline is drawn on top of the
% "after" panel specifically to show that the untranslated ROI now sits
% correctly on the realigned structure.
lastImg = projections{end};
alignedLastImg = imtranslate(lastImg, [-shiftX(end), -shiftY(end)]);

figCorrection = figure('Name','Drift correction spot-check','Position',[100 100 1500 500]);
subplot(1,3,1);
imshow(projFirst); hold on;
overlayRoiOutlines(roiMasks, 'y');
title('FIRST visit (ROI drawn here)');

subplot(1,3,2);
fusedBefore = imfuse(projFirst, lastImg, 'falsecolor', 'Scaling', 'joint', 'ColorChannels', [1 2 1]);
imshow(fusedBefore); hold on;
overlayRoiOutlines(roiMasks, 'y');
title(sprintf('BEFORE correction (drift = %d, %d px)', shiftX(end), shiftY(end)));

subplot(1,3,3);
fusedAfter = imfuse(projFirst, alignedLastImg, 'falsecolor', 'Scaling', 'joint', 'ColorChannels', [1 2 1]);
imshow(fusedAfter); hold on;
overlayRoiOutlines(roiMasks, 'g');
title('AFTER correction (should look gray/white if translation-only)');

sgtitle(sprintf(['Position %d: magenta = cycle 1, green = last cycle -- ' ...
    'gray/white = aligned, colored fringe = mismatch'], posToProc));

correctionFigFile = fullfile(parentFolder, sprintf('Position%d_DriftCorrection.png', posToProc));
exportgraphics(figCorrection, correctionFigFile, 'Resolution', 150);
fprintf('Drift correction figure saved to:\n%s\n', correctionFigFile);

proceedChoice = questdlg( ...
    ['Does the AFTER panel look aligned (gray/white)? If it still shows a colored ' ...
    'fringe, this position likely has non-translational drift that this correction ' ...
    'cannot fully fix.'], ...
    'Drift correction check', 'Yes - proceed with extraction', 'No - abort', ...
    'Yes - proceed with extraction');
close all;
if isempty(proceedChoice) || strcmp(proceedChoice, 'No - abort')
    error(['Aborted at user request. If the AFTER panel still looked wrong, this ' ...
        'position likely has non-translational drift (rotation/deformation/z-focus) ' ...
        'that whole-frame translation correction cannot fix -- inspect it with ' ...
        'drift_check_all_positions.m before deciding how to proceed.']);
end

roiSizesByCycle = cellfun(@nnz, roiMasksByCycle);
bkgSizeByCycle = cellfun(@nnz, bkgMaskByCycle);

%% === Initialize extraction arrays (still per-frame -- averaged after) ===
roiCh3 = zeros(nFramesTotal, roiCount);
bkgCh3 = zeros(nFramesTotal, 1);

fprintf('Processing %d frames across %d folders...\n', nFramesTotal, nCycles);

%% === Loop over folders and frames ===
% Bounding box (and therefore the on-disk PixelRegion crop) is recomputed
% PER CYCLE now, since the shifted mask position moves cycle to cycle --
% see maskSetBoundingBox below. Extraction still happens frame-by-frame
% (there's no way to average without first reading every frame); the
% collapse to one value per cycle happens afterward.
ptr = 0;
tExtractionStart = tic;
framesDoneSoFar = 0;
progressEvery = 100; % print an ETA every this many frames

for k = 1:nCycles
    n = nFramesPerFolder(k);

    theseRoiMasks = roiMasksByCycle(k,:);
    thisBkgMask = bkgMaskByCycle{k};
    bbox = maskSetBoundingBox(theseRoiMasks, thisBkgMask);

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
            nBadFrames = nBadFrames + 1;

            framesDoneSoFar = framesDoneSoFar + 1;
            continue;
        end

        bkgCh3(idx) = sum(frame3(thisBkgMaskCropped));

        for r = 1:roiCount
            roiCh3(idx,r) = sum(frame3(theseRoiMasksCropped{r}));
        end

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

%% === Scale background per ROI, per cycle (mask-aware background size) ===
% Mask sizes can vary slightly cycle to cycle now: a shifted mask that
% partially leaves the frame gets clipped by shiftMask, which shrinks its
% pixel count. Scaling per-cycle (rather than a single early/late value)
% keeps the background subtraction correct even when that happens.
bkgCh3_scaled = zeros(nFramesTotal, roiCount);
for k = 1:nCycles
    inCycle = (cycleIdx == k);
    for r = 1:roiCount
        scaleFactor = roiSizesByCycle(k,r) / bkgSizeByCycle(k);
        bkgCh3_scaled(inCycle, r) = bkgCh3(inCycle) * scaleFactor;
    end
end

%% === Corrected (still per-frame) ===
corrCh3 = roiCh3 - bkgCh3_scaled;

%% === Collapse each cycle's frames down to ONE averaged value ===
% mean(..., 'omitnan') so corrupted/unreadable frames (NaN) don't pull
% down the average; NValidFrames records how many frames actually
% contributed, in case a cycle lost a large fraction of its frames.
roiCh3_cycleMean = nan(nCycles, roiCount);
bkgCh3_scaled_cycleMean = nan(nCycles, roiCount);
corrCh3_cycleMean = nan(nCycles, roiCount);
nValidFrames = zeros(nCycles, roiCount);

for k = 1:nCycles
    inCycle = (cycleIdx == k);
    for r = 1:roiCount
        roiCh3_cycleMean(k,r) = mean(roiCh3(inCycle,r), 'omitnan');
        bkgCh3_scaled_cycleMean(k,r) = mean(bkgCh3_scaled(inCycle,r), 'omitnan');
        corrCh3_cycleMean(k,r) = mean(corrCh3(inCycle,r), 'omitnan');
        nValidFrames(k,r) = nnz(~isnan(corrCh3(inCycle,r)));
    end
end

%% === Save CSV (one row per CYCLE) ===
Cycle = (1:nCycles)';
FolderNum = foundNums(:);
NFramesInCycle = nFramesPerFolder;
MidFrameInFolder = midFrameInFolder;
MidGlobalFrame = midGlobalFrame; % frame-count reference only -- see ElapsedTime_sec for real time
MidFrameDatetime = midFrameDatetime; % real acquisition time (from XML) of each cycle's mid frame
StimPeriod = stimPeriodByCycle;
ShiftX = shiftX;
ShiftY = shiftY;
RegConfidence = regConfidence;

T = table(Cycle, FolderNum, NFramesInCycle, MidFrameInFolder, MidGlobalFrame, ...
    MidFrameDatetime, ElapsedTime_sec, StimPeriod, ShiftX, ShiftY, RegConfidence);

for r = 1:roiCount
    T.(['Ch3_Raw_ROI' num2str(r) '_Mean']) = roiCh3_cycleMean(:,r);
    T.(['Ch3_BkgScaled_ROI' num2str(r) '_Mean']) = bkgCh3_scaled_cycleMean(:,r);
    T.(['Ch3_Corrected_ROI' num2str(r) '_Mean']) = corrCh3_cycleMean(:,r);
    T.(['NValidFrames_ROI' num2str(r)]) = nValidFrames(:,r);
end

outFile = fullfile(parentFolder, sprintf('Position%d_MultiCycle_CycleAveraged.csv', posToProc));
writetable(T, outFile);

%% === Plot PER ROI (real elapsed time x-axis, one point per cycle) ===
for r = 1:roiCount

    figure;
    plot(ElapsedTime_sec, roiCh3_cycleMean(:,r), '-og', 'LineWidth', 1.2); hold on;
    plot(ElapsedTime_sec, bkgCh3_scaled_cycleMean(:,r), '--k', 'LineWidth', 1.2);
    plot(ElapsedTime_sec, corrCh3_cycleMean(:,r), '-ob', 'LineWidth', 1.5);
    if ~isnan(stimStartElapsedSec)
        xline(stimStartElapsedSec, '--m', 'Stim', 'LineWidth', 1.5);
    end
    xlabel('Elapsed time (s, since experiment start -- from XML timestamps)'); ylabel('Mean intensity');
    title(sprintf('Position %d - Ch3 (GCaMP) - ROI %d (cycle-averaged)', posToProc, r));
    legend('Raw ROI', 'Background (scaled)', 'Corrected');
    grid on;
end

fprintf('\n Done. Cycle-averaged results saved to:\n%s\n', outFile);

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
    if isempty(rows) || isempty(cols)
        error(['A shifted ROI or background mask has no pixels left inside the frame -- ' ...
            'drift has carried it entirely out of view. Inspect this position''s drift ' ...
            'with drift_check_all_positions.m; whole-frame translation correction cannot ' ...
            'recover from drift this large.']);
    end
    bbox.rowRange = [min(rows), max(rows)];
    bbox.colRange = [min(cols), max(cols)];
end

function seqStart = readSequenceStartTime(xmlPath)
    % Real wall-clock start time of a TSeries folder's acquisition,
    % combining the PVScan tag's calendar date with the Sequence tag's
    % more precise (sub-second) time-of-day -- both describe the same
    % moment, but PVScan's date attribute rounds to whole seconds.
    xmlText = fileread(xmlPath);

    dateTok = regexp(xmlText, '<PVScan[^>]*\sdate="([^"]+)"', 'tokens', 'once');
    if isempty(dateTok)
        error('Could not find a PVScan date attribute in %s', xmlPath);
    end
    pvScanDate = datetime(dateTok{1}, 'InputFormat', 'M/d/yyyy h:mm:ss a');

    timeTok = regexp(xmlText, '<Sequence[^>]*\stime="([^"]+)"', 'tokens', 'once');
    if isempty(timeTok)
        error('Could not find a Sequence time attribute in %s', xmlPath);
    end
    seqTimeOfDay = duration(timeTok{1}, 'InputFormat', 'hh:mm:ss.SSSSSSS');

    seqStart = dateshift(pvScanDate, 'start', 'day') + seqTimeOfDay;
end

function [seqStart, relTime] = readFrameTimeFromXML(xmlPath, targetFilename)
    % seqStart: real wall-clock start time of this folder's acquisition.
    % relTime: seconds elapsed from seqStart to the specific frame whose
    % Ch3 filename is targetFilename (matched by filename, not by
    % assuming XML Frame order matches the sorted file list -- exact and
    % robust to either list being reordered).
    seqStart = readSequenceStartTime(xmlPath);
    xmlText = fileread(xmlPath);

    escapedName = regexptranslate('escape', targetFilename);
    pattern = ['<Frame relativeTime="([^"]+)"[^>]*>\s*<File[^>]*filename="' escapedName '"'];
    relTok = regexp(xmlText, pattern, 'tokens', 'once');
    if isempty(relTok)
        error('Could not find a frame timestamp for %s in %s', targetFilename, xmlPath);
    end
    relTime = str2double(relTok{1});
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

function [dx, dy, peakCorr] = registerTranslationNCC(fixedImg, movingImg)
    % Same whole-frame template-matching registration used and validated
    % in drift_check_all_positions.m: cross-correlate a (smaller)
    % template against a (larger or equal) search image and report the
    % integer-pixel peak location as a translation.
    c = normxcorr2(movingImg, fixedImg);
    [peakCorr, linIdx] = max(c(:));
    [ypeak, xpeak] = ind2sub(size(c), linIdx);
    dy = ypeak - size(movingImg, 1);
    dx = xpeak - size(movingImg, 2);
end

function shifted = shiftMask(mask, dx, dy)
    % Integer-pixel translation of a logical mask by (dx, dy) -- positive
    % dx moves content right, positive dy moves content down -- matching
    % the sign convention of shiftX/shiftY from registerTranslationNCC:
    % a positive shift means the tracked structure now appears further
    % right/down in the CURRENT cycle's frame than it did in cycle 1, so
    % the ROI must move by the same amount to keep following it. Pixels
    % shifted in from outside the original frame are zero-padded (there's
    % no data there to fill them with); pixels shifted out are dropped,
    % which is why roiSizesByCycle/bkgSizeByCycle are recomputed per
    % cycle rather than assumed constant.
    [h, w] = size(mask);
    shifted = false(h, w);

    srcColStart = max(1, 1 - dx); srcColEnd = min(w, w - dx);
    srcRowStart = max(1, 1 - dy); srcRowEnd = min(h, h - dy);
    if srcColStart > srcColEnd || srcRowStart > srcRowEnd
        return; % shift is larger than the whole frame -- nothing survives
    end

    dstColStart = srcColStart + dx; dstColEnd = srcColEnd + dx;
    dstRowStart = srcRowStart + dy; dstRowEnd = srcRowEnd + dy;
    shifted(dstRowStart:dstRowEnd, dstColStart:dstColEnd) = ...
        mask(srcRowStart:srcRowEnd, srcColStart:srcColEnd);
end
