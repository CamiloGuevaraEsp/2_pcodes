%Stuck in five rois even though I change x in roiData = cell(x,3)
%By Cynthia T. Hsu
%April 18 2023
%C.G solved the bug that the number of possible ROIS was only 5. In this
%version the user input the number of Rois they want. 

function uiDrawMultipleMasks_multiSliceGUI()
close all;
num_ROIs = 6; 
[file,path] = uigetfile('*.mat');

cd(path);
maskmat = load(file);

f=figure;
imgAvgBySlice = maskmat.imgAvgBySlice;
imagesc(squeeze(imgAvgBySlice(1,:,:))); %Display the first slice by default.

%% c = popup menu we use to control the slice selection.
c = uicontrol(f,'Style','popupmenu');
c.Position = [20 20 60 20];

%
numSlices = size(imgAvgBySlice,1);
sliceSelectionString = cell(1,numSlices);
for(si = 1:numSlices)
    sliceSelectionString{si} = num2str(si);
end;

c.String = sliceSelectionString; %{'Celsius','Kelvin','Fahrenheit'};
c.Callback = @selection;

    function selection(src,event)
        val = c.Value;
        str = c.String;
        selectedString = str{val};
        selectedNum = str2num(selectedString);
        imagesc(squeeze(imgAvgBySlice(selectedNum,:,:)));
    end

%% add ROI

addROI_button = uicontrol(f,'Style','pushbutton','Position',[80 20 60 20]);
addROI_button.String = 'Add ROI';
addROI_button.Callback = @addROI;
numROIs = 0;
roiData = cell(num_ROIs,3); % Let's start with 5 ROIs as a default and increase as necessary.
% X, Y, and Z stored in columns 1, 2, and 3 of the cell array.

    function addROI(src,event)
        numROIs = numROIs+1;

        %generate roiMenu
        roiMenu = uicontrol(f,'Style','popupmenu');
        roiMenu.Position = [140 20 60 20];
        roiSelectionString = cell(1,numROIs);
        if(numROIs>size(roiData,1)),
            temp = roiData;
            roiData = cell(numROIs,3);
            for(roiIndex = 1:numROIs),
                roiData{roiIndex,1} = temp{roiIndex,1};
                roiData{roiIndex,2} = temp{roiIndex,2};
                roiData{roiIndex,3} = temp{roiIndex,3};
            end;
        end;
        temp = roiData;
        for(roiIndex = 1:numROIs)
            roiSelectionString{roiIndex}=num2str(roiIndex);
        end;
        roiMenu.String = roiSelectionString;
        roiMenu.Callback = @roipolyWrapper; %(src,event)roipolyWrapper(src,event,roiIndex); %(src,roiIndex);
        roiMenu.Value = numROIs;
    end;

    function roipolyWrapper(src,event) %,roiMenuSelection)

        roiMenuSelection = src.Value; %roiMenu.Value;
        selectedROI_x = roiData{roiMenuSelection,1};
        %         str = roiMenu.String;
        if(isempty(selectedROI_x) || numel(selectedROI_x)==0),
            [~,xi,yi] = roipoly;
            roiData{roiMenuSelection,1} = xi;
            roiData{roiMenuSelection,2} = yi;
            roiData{roiMenuSelection,3} = c.Value;
        else,
            imagesc(squeeze(imgAvgBySlice(roiData{roiMenuSelection,3},:,:)));
            roiX = roiData{roiMenuSelection,1};
            roiY = roiData{roiMenuSelection,2};
            %             display(size(roiX));
            %             display(size(roiY));
            hold on;
            plot(roiX,roiY,'wo-','LineWidth',3);
            hold off;
            c.Value = roiData{roiMenuSelection,3};
        end;
        %         end;
    end;

    %% save ROIs

saveROI_button = uicontrol(f,'Style','pushbutton','Position',[200 20 60 20]);
saveROI_button.String = 'Save ROIs';
saveROI_button.Callback = @saveROIs;
numROIs = 0;
%roiData = cell(6,3); % Let's start with 5 ROIs as a default and increase as necessary.
% X, Y, and Z stored in columns 1, 2, and 3 of the cell array.

    function saveROIs(src,event),
        try,
        timestampedSuffix = ['userDrawnMask' strrep(datevec(clock),':','')];
        catch,
            timestampedSuffix = ['userDrawnMask' strrep(datestr(clock),':','')];
        end;
        newFileName = strrep(file, 'Mask',timestampedSuffix);
        save(newFileName,'imgAvgBySlice','roiData');
    end;

end % GUI functions seem to require an "end" command