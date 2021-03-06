%% clear;
clear; clc;
close all;



%% Load Images 
% select image folder (model_castle, model_castle_TA or TeddyBearPNG)
image_folder = 'model_castle_TA';
image_files = dir(strcat(image_folder,'/*.png'));
N = length(image_files);

% Pre-allocating images
castle = cell(1,N);
castle_gray = cell(1,N);

fprintf('Loading images of "%s" set...',image_folder);
for i = 1:N
    castle{i} = imread([image_files(i).folder '/' image_files(i).name]);
    %castle{i} = castle{i}(500:2200,500:3500,:); % RoI
    castle_gray{i} = single(rgb2gray(castle{1,i}))./255;
end

fprintf('%d images loaded.\n\n', N);

%% Find and combine features
plot_features = 0;
% Extract features if no saved file exists
if ~exist(strcat(image_folder,'/Features.mat'),'file')
    tic;
    % delete Matches file in case it exists
    if exist(strcat(image_folder,'/Matches.mat'),'file')
        delete(strcat(image_folder,'/Matches.mat'));
    end
    
    % affine harris/hessian locations
    aff_harris_files = dir(strcat(image_folder,'/*.png.haraff.sift'));
    aff_hessian_files = dir(strcat(image_folder,'/*.png.hesaff.sift'));

    % pre-allocation of cells
    feat_SIFT = cell(1,N);
    descr_SIFT = cell(1,N);
    descr_HARRIS = cell(1,N);
    descr_HESSIAN = cell(1,N);
    descriptors = cell(1,N);
    unique_descriptors = cell(1,N);
    
    points_SIFT = cell(1,N);
    points_HARRIS = cell(1,N);
    points_HESSIAN = cell(1,N);
    all_feature_points = cell(1,N);
    unique_feature_points = cell(1,N);
    
    % feature extraction w/ multiple methods
    fprintf('No feature file found, so extracting SIFT, HARRIS and HESSIAN features:\nFinished image ');
    for i = 1:N
        % SIFT feature, descriptor extraction of HARRIS corners
        [feat_SIFT{i}, descr_SIFT{i}] = my_vl_sift(castle_gray{i},1e-5);
        % AFFINE HARRIS descriptor
        matrix_harris = dlmread([aff_harris_files(i).folder '/' aff_harris_files(i).name], ' ', 2, 0);
        descr_HARRIS{i} = matrix_harris(:,6:end)';
        % AFFINE HESSIAN descriptor
        matrix_hessian = dlmread([aff_hessian_files(i).folder '/' aff_hessian_files(i).name], ' ', 2, 0);
        descr_HESSIAN{i} = matrix_hessian(:,6:end)';
        % Combine descriptors
        descriptors{i} = [descr_SIFT{i} descr_HARRIS{i} descr_HESSIAN{i}];
        
        % Get feature locations
        points_SIFT{i} = feat_SIFT{i}(1:2,:);
        points_HARRIS{i} = round(matrix_harris(:,1:2),0)'; % round the points
        points_HESSIAN{i} = round(matrix_hessian(:,1:2),0)';
        % combine all feature points in 2xN format
        
        all_feature_points{i} = [points_SIFT{i} points_HARRIS{i} points_HESSIAN{i}];
        % get unique feature points
        [unique_feature_points{i},ind_unique] = unique(all_feature_points{i}','rows');
        % transpose it to 2xn
        unique_feature_points{i} = unique_feature_points{i}';
        % get new descriptors
        unique_descriptors{i} = descriptors{i}(:,ind_unique);
        fprintf('%d/%d... ', i,N);    
    end
    % plot the features to test the threshold values
    plot_features = 1;
    % save it
    save(strcat(image_folder,'/Features.mat'),'all_feature_points', 'descriptors');
    save(strcat(image_folder,'/Features_unique.mat'),'unique_feature_points', 'unique_descriptors');
    save(strcat(image_folder,'/Features_SHH.mat'),'points_SIFT', 'points_HARRIS', 'points_HESSIAN');    
    fprintf('\nCompleted feature extraction\n\n');
    toc;
else
    fprintf('Feature file found, loading features...');
    load(strcat(image_folder,'/Features.mat'));
    %load(strcat(image_folder,'/Features_unique.mat'))
    load(strcat(image_folder,'/Features_SHH.mat'))
    fprintf('loading complete\n\n');
end

% plot the features to test the threshold values
if (plot_features)
    i = 15;
    plotFeatures(castle, i, points_SIFT, points_HARRIS, points_HESSIAN)
end

%% Find matches

if ~exist(strcat(image_folder,'/Matches.mat'),'file')
    tic;
    fprintf('No matches file found, so computing matches:\nFinished image ');
    [match_indices, matched_points_left, matched_points_right]...
        = getMatches(all_feature_points, descriptors);
    % save it
    save(strcat(image_folder,'/Matches.mat'), 'match_indices', 'matched_points_left', 'matched_points_right');
    
    fprintf('\nFinished computing matches.\n\n');
    toc;
else
    fprintf('Matches file found, loading matches...');
    load(strcat(image_folder,'/Matches.mat'))
    fprintf('loading complete\n\n');
end

%% 2.) Normalized eight-point RANSAC
if ~exist(strcat(image_folder,'/Matches_best.mat'),'file')
    tic;
    fprintf('No file containing best matches found:\n');
    fprintf('Finding best matches with normalized 8-point RANSAC...\n');
    % Pre-allocate cells
    best_matched_points_left = cell(1,N);
    best_matched_points_right = cell(1,N);
    best_match_indices = cell(1,N);
    n_inliers = zeros(1,N);
    idx_inliers = cell(1,N);
    Fund_mat = zeros(3,3,N);

    RANSAC_thr = ones(1,N)*1e-4;
    n_loops = 1000;
    % lower the threshold for castle pairs with less matches
    if contains(image_folder,'castle')
        RANSAC_thr(13) = 1e-3;    
        RANSAC_thr(14) = 5e-3;
        RANSAC_thr(15) = 5e-2;
        RANSAC_thr(16) = 5e-3;
        RANSAC_thr(17) = 1e-3;
        RANSAC_thr(18) = 1e-3;
    end

    % Loop over all images
    for i = 1:N
        % perform RANSAC implementation of the normalized 8-point algorithm
        [Fund_mat(:,:,i), idx_inliers{i}, best_matched_points_left{i}, best_matched_points_right{i}]...
            = eight_point_ransac(matched_points_left{i}, matched_points_right{i}, RANSAC_thr(i), n_loops);
        % get the indices of the best matches
        best_match_indices{i} = match_indices{i}(:,idx_inliers{i});
        % index stats for printing/plotting
        n_points = size(matched_points_left{i},2);
        n_inliers(i) = length(idx_inliers{i});
        fprintf('Image pair %d out of %d finished.. returned %d/%d inliers.\n', i,N, n_inliers(i), n_points);
    end
    
    % save it
    save(strcat(image_folder,'/Matches_best.mat'), 'best_match_indices', 'Fund_mat', ...
        'best_matched_points_left', 'best_matched_points_right',...
        'idx_inliers', 'n_inliers');
    
    fprintf('\nFinished RANSAC.\n\n');
    toc;
else
    fprintf('Best matches file found, loading best matches...');
    load(strcat(image_folder,'/Matches_best.mat'))
    fprintf('loading complete\n\n');
end    


%% plot the epipolar lines of m (random) inliers of (random) image pair 
k = 15;
m = randperm(n_inliers(k),min(n_inliers(k),20)); % pick up to 10 random unique samples
plotMatches(castle{k}, castle{k+1}, best_matched_points_left{k}(:,m), best_matched_points_right{k}(:,m));


%% 3) Chaining: create point view matrix using BEST matches
fprintf('Constructing pointview matrix from best matches...');
point_mat_ind = chaining(best_match_indices);

fprintf("Finished\n\n")
%%
k = randi(size(point_mat_ind,2));
%k = 15907;
figure;
pts_SFM = plotPointMatrix(castle, all_feature_points, point_mat_ind, k);


%% 4) Structure-from-Motion
fprintf('Computing Structure from Motion...\n');
% nr. of images to compare matches between ( > 2), report says 3 or 4
m = 3;
[S, M, D, set_mutuals, C, p] = getStructurefromMotion(m, point_mat_ind, all_feature_points);
fprintf('Stucture from Motion completed.\n\n');

%% 4) Image Stitching
fprintf('Stitching 3D point sets...');
[S_stitched, T, b, c, S_transformed] = stitching(S, set_mutuals);
fprintf('stitching completed.\n\n');

%% 5) Bundle Adjustment

%% 6a) Get pointcloud 
%%%%%%% get cloud
cloud = getCloud(castle, S_stitched, D);

% remove noise
%[cloud, ~] = pcdenoise(cloud, 'NumNeighbors', 50);
figure;
ax = pcshow(cloud,'MarkerSize', 500);
xlabel('x axis');
ylabel('y axis');
zlabel('z axis');

%% 6b) Get surface plot
% get triangulation of pointcloud
surf_thr = 60;
[XYZr, Colorsr, simp_idx, simp_idx_filt] = getSurf(cloud,surf_thr);

% triplot w/ colors
figure;
trisurf(simp_idx,XYZr(:,1),XYZr(:,2),XYZr(:,3),[1:size(XYZr,1)]','FaceColor','flat','EdgeColor','none');
colormap(double(Colorsr)./256);

% filtered triplot w/ colors
figure;
trisurf(simp_idx_filt,XYZr(:,1),XYZr(:,2),XYZr(:,3),[1:size(XYZr,1)]','FaceColor','flat','EdgeColor','none')
colormap(double(Colorsr)./256);

    