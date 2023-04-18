%% function extractRegionsFromMultiSlice_ROIs
%It is not creating the intensities.mat file.
%It is only taking the ROIs from the last slice 
%One of the regions repeats across all the slices 


% April 7, 2023
% Assumes user previously ran write2PhotonTProjMask_v3_bySlice.m and uiDrawMultipleMasks_multiSliceGUI.m
%April 18 2023
%C.G. solved the bug that consisted that if  number of ROIS in slice n+1
%were less that number of ROIs in slice n. For slice n+1 it kept some of
%the rois from slice n. 


%Inputs:
%1) rootdir (where we store the output data).
%2) TSeries folder (where we keep the raw data)
%3) TImgRoot - this refers to the frames we want to extract pixel intensity values from. Generally do
%not have to change this (except to specify Ch2 versus Ch1); should match
%TSeriesFolder.
%4) TMaskRoot - this refers to the name of the images we want to use for
%the mask. In cases where there is mCherry (Ch1) present, then use this to
%mask. Otherwise, use Ch2 for the mask.
%5) TProjMask: Helps restrict the field of view to the region where the
%cells are.

%OUTPUT:
% A.regionPropsArray = regionPropsArray;
% A.TProjMask = TProjMask;
% save(outname,'-struct','A.mat

function extractRegionsFromMultiSlice_ROIs()
rootdir = '/Users/camilog/Downloads/test_images'; %Heron
TSeriesFolder = 'TSeries-11082022-1509-1030'; %Heron

cycleStart = 1; %3103;
cycleStartString = ['Cycle' num2str(cycleStart,'%05.0f')];

TImgRoot = [TSeriesFolder '_' cycleStartString '_Ch2_'];%000001.ome
% TMaskRoot = strrep(TImgRoot,'Ch2','Ch1');
% TProjMask = [TSeriesFolder '_Cycle00001_Ch2__maskReg3.mat']
%Include the .mat here so it create the .iNTENSITIES!!!!!!!!!
TProjMask = 'TSeries-11082022-1509-1030_Cycle00001_Ch2__3sliceuserDrawnMask18-Apr-2023 170944.mat';

%cycleList = [1:73];
cycleList = 1;
%If Piezo is not used, each stack is a separate cycle.
% cycleList = [1:1:475]; %1793]; %cycleStart 685 1368 2051]; % 938 1406 66 130 194 402 610 818 1174];
% cycleList = 1:73; %[3103 6205]; %1:73; %cycleStart:73; %:73; %[2 1046]; %In high speed T-series, just one cycle for the entire series.
readChannel1 = 0;
writeVid = 0;
upperStretchLim = 0.1;
medfiltSize = 1;

cd(rootdir);

if(writeVid),
    %     vidObj = VideoWriter([TImgRoot '_BWthresh' num2str(bwThresh) '_upperStretchLim ' num2str(upperStretchLim) '_medfilt'  num2str(medfiltSize) '.avi']);
    vidObj = VideoWriter([TImgRoot '_upperStretchLim ' num2str(upperStretchLim) '.avi']);
end;
A = load(TProjMask);
roiData = A.roiData
%"roiData" is a cell type array where each row contains the information for
%a different ROI. Column 1 contains the x-values, column 2 contains the
%y-values, and column 3 contains the slice where said ROI is located.
numSlices = size(A.imgAvgBySlice,1);
frameSize = size(A.imgAvgBySlice,2:3)
% Until here is doing OK. 

if(writeVid),
    open(vidObj);
end;

%What we want to do first in the MultiSlice_ROI version of the script is to
%first determine which slices we're going to look at.

sliceList = NaN(size(roiData,1),1);
for(ri = 1:size(roiData,1)),
    sliceCell = roiData{ri,3};
    
    if(~isempty(sliceCell))
        sliceList(ri)=sliceCell;
        %sliceList = sliceList(~isnan(sliceList));
    end;
end;

[uniqueSliceList, ia, ic] = unique(sliceList,'stable');
%uniqueSliceList = uniqueSliceList(~isnan(uniqueSliceList)); 

%The main error here is that if the ROIs are in descending order (for
%example slice 1 = 3 ROIs; slice 2 = 2 ROIs; slice 3 = 1 ROI, it will
%complete the rest with the remaining roid from previous slices

regionPropsBySlice = cell(size(sliceList));
mainROIindex = 1;
for(si=1:numel(uniqueSliceList)),
    sliceNum = uniqueSliceList(si);
    if(~isnan(sliceNum))
        roiIndices = find(sliceList==sliceNum)
        thisSliceMask = zeros(frameSize);
        for(ri=1:numel(roiIndices)),
            roiX = roiData{roiIndices(ri),1};
            %roiX = roiData{ri,1};
            roiY = roiData{roiIndices(ri),2};
            %roiY = roiData{ri,2};
            roiBW = roipoly(frameSize(1),frameSize(2),roiX,roiY);
            thisSliceMask = thisSliceMask|roiBW;
        end;
        %Once we've identified added all of the regions on this slice to our
        %mask, we can then run regionprops on this slice.
        thisSliceRegions = regionprops(thisSliceMask,'Area','BoundingBox','Centroid','PixelIdxList'); %,'PixelValues');
%         display(sliceNum);
        regionPropsBySlice{sliceNum,1} = thisSliceRegions;
    end;
end;


for(ci = 1:numel(cycleList)),
    cd(TSeriesFolder);
    cycleText = ['Cycle' num2str(cycleList(ci),'%05.0f')]
    imgRootForCycle = strrep(TImgRoot,cycleStartString,cycleText);
    tiffList = dir([imgRootForCycle '*.ome.tif']); 
    
    outname = strrep(TProjMask, '.mat',['_' cycleText '_' 'Intensities.mat']);
    maxFrame2read = numel(tiffList);
    regionPropsArray = cell(maxFrame2read,2);
    %for i = 1:maxFrame2read
    for(si=1:numel(uniqueSliceList))
        sliceNum = uniqueSliceList(si);

        if(~isnan(sliceNum)),
            thisSliceRegions = regionPropsBySlice{sliceNum,1};
            if(numel(thisSliceRegions)>0)
                %ti is restarting, so it will only save the last one 
                for(ti = sliceNum:numSlices:maxFrame2read),
                    if(ti<=200 || mod(ti,100)==0),
                        display(ti);
                        if(ti==200),
                            display(['Have demonstrated first 200 frames are read. Now outputting once every 100 frames.']);
                        end;
                    end;
                    imgName = [imgRootForCycle num2str(ti,'%06.0f') '.ome.tif'];
                    if(exist(imgName,'file'))
                        try,
                            rawImg = imread(imgName); %This rawImg contains the data that we probably want to extract data from (GCamp6m)
                        catch,
                            rawImg(:) = NaN; %(size(rawImg,1),size(rawImg,2));
                        end;
                        if(readChannel1),
                            maskName = strrep(imgName,'Ch2','Ch1');
                            if(exist(maskName,'file')),
                                try,
                                    maskImg = imread(maskName);
                                    %                 display(['Successfully read in ' maskName]);
                                catch,
                                    maskImg(:) = NaN;
                                    display(['Could not read ' maskName]);
                                end;
                            else,
                                maskImg(:) = NaN;
                                display(['Could not find a file matching maskName']);
                            end;
                        end;
                        imageDataInStack = double(rawImg(:));
                        %                     maskDataInStack = double(maskImg(:));

                        meanImg = imageDataInStack; %mean(imageDataInStack,2);
                        %                     meanMask = maskDataInStack; %mean(maskDataInStack,2);

                        medFiltFrame = double(medfilt2(uint16(reshape(meanImg,size(rawImg,1),size(rawImg,2))),[medfiltSize medfiltSize]));
                        %                     ctrlMedFiltFrame = double(medfilt2(uint16(reshape(meanMask,size(rawImg,1),size(rawImg,2))),[medfiltSize medfiltSize]));
                        display(['Processing ' num2str(numel(thisSliceRegions)) ' regions on slice ' num2str(sliceNum) ' t=' num2str(ti)])
                        pxIntensitiesForRegions = cell(size(thisSliceRegions,1),2); 
                        realAreas = cell(1,size(thisSliceRegions,2));
                        for(ri = 1:numel(thisSliceRegions)),
                            thisRegion = thisSliceRegions(ri);
                            if(0), %writeVid),
                                plot(thisRegion.BoundingBox(1),thisRegion.BoundingBox(2),'ro');
                            end;

                            %
                            realAreas{ri} = thisRegion;
                            pxIntensitiesForRegions{ri,2} = medFiltFrame(thisRegion.PixelIdxList);
                            pxIntensitiesForRegions{ri,1} = ones(size(thisRegion.PixelIdxList)); %ctrlMedFiltFrame(thisRegion.PixelIdxList);
                            %             display(thisRegion.BoundingBox);
                        end;

                        regionPropsArray{ti,1} = realAreas;
                        %regionPropsArray{i,1} = realAreas;
                        %$regionPropsArray{i,2} = pxIntensitiesForRegions;

                        regionPropsArray{ti,2} = pxIntensitiesForRegions;

                    end;
                end;
            end;
                else,
        display(['Skipping slice ' num2str(sliceNum)]);

        end;
    end;
    %end
    cd(rootdir);
    A.regionPropsArray = regionPropsArray;
    A.TProjMask = TProjMask;
    A.TSeriesFolder = TSeriesFolder;
    A.regionPropsBySlice = regionPropsBySlice;
    save(outname,'-struct','A','-v7.3');
end;
if(writeVid),
    close(vidObj);
end;
