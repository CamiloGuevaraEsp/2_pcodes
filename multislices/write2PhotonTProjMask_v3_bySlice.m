%INPUTS: Cycle and channel of data to take a Z projection of.
%OUTPUTS:
%Saves a struct which contains "avgIntensity"
%%numFrames: total # of frames.
%%sumFrame: sum of intensities at each position.
%
% 02/11/2023

function [sumFrame,numFrames] = write2PhotonTProjMask_v3_bySlice(varargin)

% close all; clear all;
if(nargin==0),
    rootdir = '/Users/camilog/Downloads/test_images';
    TSeriesFolder = 'TSeries-11082022-1509-1030'; %Heron
    %Every image in the TSeries folder is in this format:
    %TSeries-10222019-1549-340_Cycle00001_Ch1_000013.ome;
    TImgRoot = [TSeriesFolder '_Cycle00001_Ch2_'];
    %Cycle number indicates the stack number in the TSeries.
    slicesPerStack = 3;
else, %The variables we entered in above are being called by an external script.
    rootdir = varargin{1};
    TSeriesFolder = varargin{2};
    TImgRoot = [TSeriesFolder '_Cycle00006_Ch' varargin{3} '_'];
end;

suffix = [num2str(slicesPerStack) 'sliceMask.mat'];
if(strfind(TImgRoot,'_Ch2_')),
    %     img2mask = strrep(TImgRoot,'_Ch2_', '_Ch1_TprojMask.mat');
    %     outname = [TImgRoot '_maskedByCh1.mat'];
    outname = [TImgRoot '_' suffix];
else,
    img2mask = strrep(TImgRoot,'_Ch1_', ['_Ch1_' suffix]);
    outname = img2mask;
end;

cd(rootdir);
cd(TSeriesFolder);
% Last frame: 'fc2_save_2017-12-01-173304-10412';
tiffList = dir([TImgRoot '*.tif']);
display(TImgRoot);
display(numel(tiffList));

% maxFrame2read = 8548; %numel(tiffList);
maxFrame2read = 300; %numel(tiffList);
maxFrame2read = min(maxFrame2read,numel(tiffList));
medfiltSize = 1;

for(si=1:slicesPerStack),
    frameCount = 0;
    for(ti = si:slicesPerStack:maxFrame2read),
        imgName = [TImgRoot num2str(ti,'%06.0f') '.ome.tif']
        rawImg = double(medfilt2(imread(imgName),[medfiltSize medfiltSize]));
        if(~exist('imgAvgBySlice','var')),
%             allImgSum =zeros();
            imgAvgBySlice = zeros(slicesPerStack,size(rawImg,1),size(rawImg,2));
        end;
        imgAvgBySlice(si,:,:) = squeeze(imgAvgBySlice(si,:,:))+rawImg;
        frameCount = frameCount+1;
    end;
    imgAvgBySlice(si,:,:) = imgAvgBySlice(si,:,:)/frameCount;
end;

cd(rootdir);
if(nargin==0),
    save(outname,'imgAvgBySlice','slicesPerStack'); %bwThresh','bwFrame','s');
%     imwrite(uint8(bwFrame*256),strrep(outname,'.mat','.tif'));
else,
    sumFrame = allImgSum;
    numFrames = maxFrame2read;
end;
