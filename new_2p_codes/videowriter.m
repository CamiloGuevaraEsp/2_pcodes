% --- Single TSeries Ch3 Movie Generator ---
clear; clc; close all;

%% Select TSeries folder
baseFolder = uigetdir(pwd, 'Select TSeries folder');

if baseFolder == 0
    error('No folder selected.');
end

%% Output filename
[~, folderName] = fileparts(baseFolder);
videoFile = fullfile(baseFolder, [folderName '_Ch3_FIRE.mp4']);

%% Find Ch3 files
filesCh3 = dir(fullfile(baseFolder, '*Ch3_*.ome.tif'));

if isempty(filesCh3)
    error('No Ch3 files found.');
end

namesCh3 = sort({filesCh3.name}');
nFrames = numel(namesCh3);

fprintf('Found %d frames\n', nFrames);

%% Settings
frameRate = 60;
lut = (jet(256));


%% Find global maximum pixel value
fprintf('Finding global maximum intensity...\n');

globalMax = 0;

for i = 1:nFrames
    frame = double(imread(fullfile(baseFolder,namesCh3{i})));
    globalMax = max(globalMax, max(frame(:)));
end

fprintf('Global maximum pixel value = %.0f\n', globalMax);
%% Create video
v = VideoWriter(videoFile,'MPEG-4');
v.FrameRate = frameRate;
open(v);

fprintf('Generating movie...\n');

for i = 1:nFrames

    frame = double(imread(fullfile(baseFolder,namesCh3{i})));

    % Scale by global maximum
    img = frame / globalMax;

    % Clip just in case
    img(img > 1) = 1;

    % Apply hot LUT
    imgIdx = uint8(img * 255);
    rgb = ind2rgb(imgIdx, lut);

    % Write frame
    writeVideo(v, im2uint8(rgb));

    if mod(i,100)==0
        fprintf('%d / %d frames\n',i,nFrames);
    end

end

close(v);

fprintf('\nMovie saved:\n%s\n', videoFile);