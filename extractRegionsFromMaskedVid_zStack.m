%C.G. Interpretation of this code:
% It loads the .tif images and create a z projection of it, then it define
% a threshold based on the minimum, maximun and median pixel value, create
% a binary mask of the z-projection based on that threshold. 
%Saves the z-projection, the thesholded images and properties such as the
%pixel centroid coordinate and area. 
%Two questions:
%1: Why is maxframes2read = 300
%2: Why is the threshold defined in that way (line 105)? 
% INPUTS: Cycle and channel of data to take a Z projection of.
%OUTPUTS:
%Saves a struct which contains "avgIntensity"
%%numFrames: total # of frames.
%%sumFrame: sum of intensities at each position.
%
% Not yet complete as of 05/02/21
%By: Cynthia T. Hsu 

function [sumFrame,numFrames] = write2PhotonTProjMask(varargin)

% close all; clear all;
if(nargin==0),
    rootdir = '/Users/camilog/Downloads/test_images';
    TSeriesFolder = 'TSeries-11082022-1509-1030';
    %Only change variables above this line
    %--------------------------------------------------
%     rootdir = 'D:\Rebecca\GH146'; %D:\Hugin\HugLexA_csChrimson_hugArclight\
%     TSeriesFolder = 'TSeries-08192022-1429-887';
    %Every image in the TSeries folder is in this format:
    %TSeries-10222019-1549-340_Cycle00001_Ch1_000013.ome;
    
    TImgRoot = [TSeriesFolder '_Cycle00001_Ch2_'];
    %Cycle number indicates the time stamp.
    %
    
    %The last time I used this script when I remembered what I was doing:
    %     rootdir = 'D:\84C10Gal4_UASGCaMP_RFP_180607\'
    %     TSeriesFolder = 'TSeries-06072018-1333-279';
    %     TImgRoot = [TSeriesFolder '_Cycle00001_Ch2_'];
else, %The variables we entered in above are being called by an external script.
    rootdir = varargin{1};
    TSeriesFolder = varargin{2};
    TImgRoot = [TSeriesFolder '_Cycle00006_Ch' varargin{3} '_'];
end;

if(strfind(TImgRoot,'_Ch2_')),
    %     img2mask = strrep(TImgRoot,'_Ch2_', '_Ch1_TprojMask.mat');
    %     outname = [TImgRoot '_maskedByCh1.mat'];
    outname = [TImgRoot '_mask.mat'];
else,
    img2mask = strrep(TImgRoot,'_Ch1_', '_Ch1_mask.mat');
    outname = img2mask;
end;

maxNumFrames = 120*4*20; %120 seconds, 4 Hz, 20 slices - this is super important for the 90 minute recordings because otherwise this script will take forever to run when it really shouldn't.


medfiltSize = 1;

cd(rootdir);
cd(TSeriesFolder);
% Last frame: 'fc2_save_2017-12-01-173304-10412';
tiffList = dir([TImgRoot '*.tif']);
display(TImgRoot);
display(numel(tiffList));

% maxFrame2read = 8548; %numel(tiffList);
maxFrame2read = 300; %numel(tiffList);
maxFrame2read = min(maxFrame2read,numel(tiffList));

% regionPropsArray = cell(maxFrame2read,1);
for(ti = 1:maxFrame2read),
    if(mod(ti,15)>7),
%         display(ti);
        imgName = [TImgRoot num2str(ti,'%06.0f') '.ome.tif']
%         try,
%C.G. Apply a median filter to each image and then it sums it. Creating a
%projection of the z-stack
            rawImg = double(medfilt2(imread(imgName),[medfiltSize medfiltSize]));
            %     rawImg_doubleVec =double(rawImg(:));
            %     display(size(rawImg));
            % dbquit
            %         if(ti == 1),
            if(~exist('allImgSum','var')),
                
                allImgSum =zeros(size(rawImg,1),size(rawImg,2));
            end;
            allImgSum = allImgSum+rawImg;
            
%         catch,
%         end;
    end;
end;

cd(rootdir);
if(nargin==0),
    avgImg = allImgSum/maxFrame2read;
    [n,xout] = hist(avgImg(:),1:128);
    figure; plot(xout,n);
    medianPxVal = median(avgImg(:));
    maxPxVal = max(avgImg(:));
    minPxVal = min(avgImg(:));
    % bwThresh = 2*medianPxVal/maxPxVal;
    % try,
    bwThresh = (medianPxVal+(medianPxVal-minPxVal))/maxPxVal;
    if(bwThresh>1),
        cumsum_n = cumsum(n/sum(n));
        highIndex = find(cumsum_n>0.98,1);
        bwThresh = xout(highIndex)/maxPxVal;
    end;
    
    figure; imagesc(avgImg/maxPxVal);
    
    bwFrame = im2bw(avgImg/maxPxVal,bwThresh);
    
    s = regionprops(bwFrame>0,'Area','Centroid');
    
    imshow(uint8(avgImg));

    %Shows the thresholded pixels 
    figure; imshow(uint8(bwFrame*256));
    % for(si = 1:numel(s)),
    %     text(s(si).Centroid(1),s(si).Centroid(2),num2str(si),'r');
    % end;
    
    % img2mask = strrep(TImgRoot,'_Ch2_', '_Ch1_mask.mat']);
    save(outname,'avgImg','bwThresh','bwFrame','s');
    imwrite(uint8(bwFrame*256),strrep(outname,'.mat','.tif'));
else,
    sumFrame = allImgSum;
    numFrames = maxFrame2read;
end;
% catch,
%     save(outname,'avgImg');
% imwrite(strrep(outname,'.mat'),'.tif',uint8(bwFrame*256));
%
% end;
