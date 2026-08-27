%% PatchWarMoveFile

%Te only solution to apply patchwarp was to separate the files from
%diferent slices, treat them as a single plane, apply Patchwarp and save
%them in a separate folder. 
%Run the first section before applying the code patchwarp_demo.m and apply
%the second sections one it is done. 
%First version by Camilo Guevara April 26th 2023
%% Move the original files to separate folders defined by the slice
clear all

% Change the following variables
num_slices = 3; 
rootdir = '/Users/camilog/Downloads/test_images/TSeries-11082022-1509-1030';
TImgRoot = 'TSeries-11082022-1509-1030'
cd(rootdir)

%Don't edit 
tifflist = dir(['*tif'])
num_elements = numel(tifflist);
save num_elements

parfor i = 1:num_slices
    foldername = ['slice_' num2str(i, '%1.0f') '_folder']
    display(foldername)
    mkdir (foldername)
    %cd(foldername)
    for j = i: num_slices : numel(tifflist)
        tiff_to_move = [TImgRoot '_Cycle00001_Ch2_' num2str(j, '%06.0f') '.ome.tif'];
        copyfile(tiff_to_move, foldername)
    end

end
f = msgbox("Now go to Patchwarp :) "); 
%% 
%Moving all the corrected to a corrected folder 

cd(rootdir)
corrected_foldername = 'motionCorrected'; 
mkdir(corrected_foldername);
correctedDir = [rootdir '/' corrected_foldername]
TImgRoot = 'TSeries-11082022-1509-1030'
parfor i = 1:num_slices
    foldername = ['slice_' num2str(i, '%1.0f') '_folder/corrected/post_warp']
    slicedir = [rootdir '/' foldername];
    %mkdir (foldername)
    cd(slicedir)
    for j = i: num_slices : num_elements
        tiff_to_move = [TImgRoot '_Cycle00001_Ch2_' num2str(j, '%06.0f') '.ome_corrected_warped.tif'];
        copyfile(tiff_to_move, correctedDir)
    end
end
