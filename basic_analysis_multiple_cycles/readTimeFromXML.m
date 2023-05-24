%% function [stackTimes, shutterTimes, lastBaselineIndex,varargout] = readTimeFromXML(varargin)
%
% Calls function shutterStartAndStopFromText(voltName), which contains
% hardcoded information about the shutters and the light pulses.
%By: Cynthia T.Hsu

function [stackTimes, shutterTimes, lastBaselineIndex,varargout] = readTimeFromXML(varargin)

if(nargin==0),
    rootdir = 'D:\2p_Imaging\Sara'   ;
    xmlname = '20230510 R23E10 ASAP2S Ctrl_2-006.xml';
    cycleRankToReturn = 0; %Starts at 0, rather than 1.
    useAbsoluteTime = 1;
    cd(rootdir);
else,
    %Assume the parent function has already put us in the proper directory.
    xmlname = varargin{1};
    cycleRankToReturn = varargin{2};
    useAbsoluteTime=0;
end;
outname = strrep(xmlname,'.xml','_stackTimesFromXML.mat');
maxStacks = 5*31*60; %5 Hz, 20 minutes, 60 seconds.

frameTimeLabel = '<Frame relativeTime="';
voltageNameLabel = '<VoltageOutput name="';
% sequenceStartLabel = '<Sequence type="TSeries ZSeries Element" cycle="';
dateTimeLabel='<PVScan version="5.8.64.200" date="';

if(exist('rootdir','var')),
    fID = fopen(xmlname);
    subdirectoryEntered = 0;
else,
    %Two possibilities: 1) xmlname is in a folder of the same name.
    %2) We can read the relevant data out of the stackTimesFromXML file
    %("TSeries-06142021-1545-619_stackTimesFromXML.mat")
    if(~exist(xmlname,'file')),
        %Check if maybe a _stackTimesFromXML.mat" is present.
        %         if(exist(outname,'file')),
        %             A = load(outname);
        %         elseif(exist([outname '.mat'],'file')),
        %             A = load([outname '.mat']);
        %         else,
        xmlStartIndex = strfind(xmlname,'.xml');
        cd(xmlname(1:(xmlStartIndex-1)));
        subdirectoryEntered = 1;
        fID = fopen(xmlname);
        
        %         else,
        %             subdirectoryEntered = 0;
        %         end;
    else,
        fID = fopen(xmlname);
        subdirectoryEntered = 0;
    end;
end;
% catch,
% end;

stackNum = 1;
voltIndex = 0;
% shutterCellMat = cell(cycleRankToReturn,1);
% continueLoop = 1;
% if(exist('fID','var')),
while(~feof(fID) && voltIndex<=cycleRankToReturn),
    line = fgets(fID);
    frameTimeLineCharNumber = strfind(line,frameTimeLabel);
    if(~isempty(strfind(line,dateTimeLabel))),
        timeStartIndex = strfind(line,dateTimeLabel);
        endOfLine = line((timeStartIndex+numel(dateTimeLabel)):end);
        quoteIndices = strfind(endOfLine,'"');
        dateTimeString = endOfLine(1:(quoteIndices(1))-1);
        startTime_dateNum = datenum(dateTimeString);
        %         voltIndex = voltIndex+1;
        %                 display(['voltIndex=' num2str(voltIndex) ', cycleRankToReturn=' num2str(cycleRankToReturn)]);
        %     elseif(~isempty(frameTimeLineCharNumber)),
        %         display(['Okay - what is our problem here?']);
    elseif(~isempty(frameTimeLineCharNumber)&& ((voltIndex==cycleRankToReturn)||cycleRankToReturn==0)),
        %                 display(['Reading relativeTime when voltnum=' num2str(voltIndex) ', Line: ' line]);
        % <Frame relativeTime="36.872451" absoluteTime="499.962451" index="4" parameterSet="CurrentSettings">
        %
        % 1) Want to parse the line:
        
        quoteIndices = strfind(line,'"');
        relativeTime = str2num(line((quoteIndices(1)+1):(quoteIndices(2)-1))); %relativeTime reinitializes at the start of each cycle.
        absoluteTime = str2num(line((quoteIndices(3)+1):(quoteIndices(4)-1)));
        sliceIndexNum = str2num(line((quoteIndices(5)+1):(quoteIndices(6)-1)));
        if(useAbsoluteTime), %varargtou = 1
            relativeTime = absoluteTime;
        end;
        
        if(sliceIndexNum==1),%Then we are at the start of a stack.
            stackStartTime = relativeTime;
            if(exist('prevStackStartTime','var')),
                if(~exist('stackStartAndEnd','var')),
                    stackStartAndEnd = NaN(maxStacks,2);
                    stackStartAndEnd(1,1) = prevStackStartTime;
                end;
            end;
            if(exist('prevSliceTime','var')),
                stackStartAndEnd(stackNum,1) = stackStartTime;
                stackStartAndEnd(stackNum-1,2) = prevSliceTime;
            end;
            prevStackStartTime = stackStartTime;
            stackNum = stackNum+1
        end;
        %         prevSliceIndexNum = sliceIndexNum;
        prevSliceTime = relativeTime;
    elseif(~isempty(strfind(line,voltageNameLabel)) && voltIndex<=cycleRankToReturn),
        %         display(['Reading voltageName when voltnum=' num2str(voltIndex) ', Line: ' line]);
        quoteIndices = strfind(line,'"');
        voltName = line((quoteIndices(1)+1):(quoteIndices(2)-1)) %This reinitializes at the start of each cycle.
        if(voltIndex<=cycleRankToReturn),
            %             shutterStartAndEnd = voltageOutRelativeToStackfromText(voltName);
            if(cycleRankToReturn==0),
            else,
            [shutterTimes,seconds_baseline] = shutterStartAndStopFromText(voltName);
            end;
            
        end;
        voltIndex = voltIndex+1
    else,
        %                         display(['Exiting when voltnum=' num2str(voltIndex) ', Line: ' line]);
        % %         display(['No relevant info found in: ' line]);
        %         if(~isempty(frameTimeLineCharNumber)),
        %             pause;
        %         end;
    end;
end;

if(~exist('shutterTimes','var')),
    shutterTimes = [];
end;
%
stackStartAndEnd(stackNum-1,2) = prevSliceTime; %stackStartTime;
trueMaxFrame = find(isnan(stackStartAndEnd(:,1)),1)-1;
if(~isempty(trueMaxFrame)),
    stackTimes = stackStartAndEnd(1:trueMaxFrame,:);
else,
    stackTimes = stackStartAndEnd;
end;
% stackStartAndEnd(stackNum-1,2) = prevSliceTime;
if(exist('seconds_baseline','var') && ~isnan(seconds_baseline)),
    firstActivationIndex = find(stackTimes(:,1)>seconds_baseline,1);
    lastBaselineIndex = firstActivationIndex-1;
else,
    lastBaselineIndex = 1;
end;

fclose(fID);

if(subdirectoryEntered),
    cd ..
end;

% if(~exist('A','var')),
save(outname,'stackTimes','startTime_dateNum');
% else,
%     %Variable 'A' contains all the necessary information (theoretically).
%     %Parent function expects the following outputs:
%     %     [stackTimes, shutterTimes, lastBaselineIndex];
%     A = A.stackTimes;
% end;
% clearvars -except stackTimes shutterTimes
% %Lastly, need to select for the stackStartAndEnd of the cycle in question
% sortedStackStarts = sort(stackStartAndEnd(:,1),'ascend');
% % sorted
% cycleStartIndices = find(stackStartAndEnd(:,1)==0);


% stackTimes, shutterTimes
% stackTimes = stackStartAndEnd(cycleStartIndices(cycleRankToReturn):(cycleStartIndices(cycleRankToReturn)-1));
% shutterTimes = shutterCellMat(voltIndex);