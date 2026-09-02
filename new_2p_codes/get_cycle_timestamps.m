% --- Cycle Timestamps (XML-derived, real time) ---
% Standalone utility: for ONE stage position in a multi-position,
% multi-cycle 2p experiment, returns one REAL timestamp per cycle (the
% wall-clock time of that cycle's MIDDLE frame), read from each TSeries
% folder's own .xml metadata -- not a frame-count proxy.
%
% Why not just count frames: GlobalFrame-style frame counting silently
% assumes cycles are back-to-back with no gap, which is false here --
% between one visit to this position and the next, the microscope has to
% cycle through every OTHER position first, a real gap of many seconds
% (often ~50-130+ s) that a frame counter can't see. Each folder's .xml
% records a real acquisition start time (PVScan date + Sequence time) and
% a per-frame relativeTime plus its exact Ch3 filename, which together
% give the true acquisition time of any frame.
%
% Output: one row per cycle (e.g. 12 cycles -> 12 timestamps), printed to
% the console and saved as Position{N}_CycleTimestamps.csv.

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
    'Folder suffix number of POSITION 1, FIRST cycle (e.g. 1496):', ...
    'Number of stage positions per cycle (e.g. 10):', ...
    'Which position to process now (1-based):', ...
    'Folder suffix number of the LAST folder in the whole experiment:', ...
    'Folder suffix number where stimulation STARTED (inclusive -- leave blank to skip marking it):'
    };
dlgtitle = 'Cycle timestamps -- setup';
dims = [1 60];
definput = {'1496','10','3','1615','1556'};
answer = inputdlg(prompt, dlgtitle, dims, definput);
if isempty(answer)
    error('Setup cancelled.');
end

startNum   = str2double(answer{1});
nPositions = str2double(answer{2});
posToProc  = str2double(answer{3});
endNum     = str2double(answer{4});
stimStartFolderNum = str2double(answer{5}); % NaN if left blank

%% === Resolve folder numbers belonging to this position, in chronological order ===
posNums = (startNum + (posToProc - 1)) : nPositions : endNum;
posNums = posNums(posNums <= endNum);
if isempty(posNums)
    error('No folder numbers computed for this position -- check startNum/nPositions/endNum.');
end

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
fprintf('Position %d: %d cycles found (folders %s)\n', posToProc, nCycles, mat2str(foundNums));

%% === Per-cycle: middle Ch3 frame + its REAL timestamp from the XML ===
midFrameInFolder = zeros(nCycles, 1);
nFramesPerFolder = zeros(nCycles, 1);
midFrameDatetime = NaT(nCycles, 1);

for k = 1:nCycles
    names3 = sort(listFilesFast(folderList{k}, '*Ch3_*.ome.tif'));
    n = numel(names3);
    if n == 0
        error('No Ch3 files found in folder: %s', folderList{k});
    end
    nFramesPerFolder(k) = n;
    midFrameInFolder(k) = ceil(n / 2);

    xmlFiles = dir(fullfile(folderList{k}, '*.xml'));
    if numel(xmlFiles) ~= 1
        error('Expected exactly one .xml file in %s, found %d.', folderList{k}, numel(xmlFiles));
    end
    xmlPath = fullfile(xmlFiles(1).folder, xmlFiles(1).name);
    midFilename = names3{midFrameInFolder(k)};
    [seqStart, relTime] = readFrameTimeFromXML(xmlPath, midFilename);
    midFrameDatetime(k) = seqStart + seconds(relTime);
end

%% === Anchor t=0 at the experiment's absolute start (position 1, cycle 1) ===
% Falls back to this position's own cycle 1 if that reference folder
% can't be found/read (ElapsedTime_sec then only meaningful within this
% run, not comparable across different positions' outputs).
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

%% === Stimulation flag per cycle ===
if isnan(stimStartFolderNum)
    stimPeriodByCycle = false(nCycles, 1);
else
    stimPeriodByCycle = foundNums(:) >= stimStartFolderNum;
end

%% === Report + save ===
Cycle = (1:nCycles)';
FolderNum = foundNums(:);
NFramesInCycle = nFramesPerFolder;
MidFrameInFolder = midFrameInFolder;
MidFrameDatetime = midFrameDatetime;
StimPeriod = stimPeriodByCycle;

T = table(Cycle, FolderNum, NFramesInCycle, MidFrameInFolder, MidFrameDatetime, ElapsedTime_sec, StimPeriod);

fprintf('\nCycle timestamps for Position %d:\n', posToProc);
disp(T);

outFile = fullfile(parentFolder, sprintf('Position%d_CycleTimestamps.csv', posToProc));
writetable(T, outFile);
fprintf('Saved to:\n%s\n', outFile);

%% =====================================================================
%% Local functions
%% =====================================================================

function names = listFilesFast(folderPath, pattern)
    % Fast alternative to dir() for folders containing huge numbers of
    % files -- see analysis2p_multiposition.m for the full rationale.
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

function folderMap = buildFolderNumberMap(parentFolder)
    % Single pass over parentFolder's subfolders, building a
    % containers.Map from trailing suffix number (as a string key) to
    % full folder path.
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

function seqStart = readSequenceStartTime(xmlPath)
    % Real wall-clock start time of a TSeries folder's acquisition,
    % combining the PVScan tag's calendar date with the Sequence tag's
    % more precise (sub-second) time-of-day -- both describe the same
    % moment, but PVScan's date attribute rounds to whole seconds. Uses
    % \s (whitespace) rather than \b (word boundary) before the attribute
    % name -- \b was found to silently fail to match in this MATLAB
    % installation even in trivial cases, while \s is equally correct
    % here (XML attributes are always preceded by whitespace) and isn't
    % affected by whatever causes that.
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
    % assuming XML Frame order matches the sorted file list).
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
