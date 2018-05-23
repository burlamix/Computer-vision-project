clear; clc; close(gcf);

%% Pre-allocating images
N  = 19;
castle = cell(1,19);
castle_gray = cell(1,19);
feats = cell(1,19);
desc = cell(1,19);

%% Load Images and Perform SIFT
tic;
for i = 1:N
    fname = sprintf('model_castle/8ADT%d.JPG',8585+i);
    castle{i} = imread(fname);
    castle{i} = castle{i}(500:2200,500:3500,:);
    castle_gray{i} = single(rgb2gray(castle{1,i}))./255;
    [feats{i}, desc{i}] = vl_sift(castle_gray{i}, 'PeakThresh', 0.01, 'EdgeThresh',10);
    Xfeats = feats{i}(1,:);
    Yfeats = feats{i}(2,:);
    fprintf('finished image %d/19\n', i);        
%     hold off
%     imshow(castle{i});
%     hold on
%     scatter(Xfeats,Yfeats);
%     pause()
toc;    
end
close(gcf)
matches = cell(1,18);
for i = 1:(N-1)
    matches{i} = vl_ubcmatch(desc{i},desc{i+1});
end
toc;

%% save stuff
save SIFTmatches feats desc matches N
save Images castle castle_gray
clear;
toc;

%% Load
tic
fprintf("reading input...");
load Images
load SIFTmatches
fprintf("done\n");
toc

%% RANSAC

pix_thr = 8;
fprintf("Applying RANSAC...");

% pre-allocate stuff
p_L = cell(1,N-1);
p_R= cell(1,N-1);
pL_best = cell(1,N-1);
pR_best = cell(1,N-1);
n_inliers = zeros(1,N-1);
T = cell(1,N-1);

% plot&save figures y/n
save_figs = 0;
for i = 1:(N-1)
    p_L{i} = feats{i}(1:2,matches{i}(1,:));
    p_R{i} = feats{i+1}(1:2,matches{i}(2,:));
    [n_inliers(i), pix_dist, pL_best{i}, pR_best{i}, T{i}] =ransac_func(p_L{i}, p_R{i}, pix_thr); 
    
    if (save_figs)
        plotMatches(castle{i},castle{i+1}, p_L{i}, p_R{i});
        figname = sprintf("./matched_images/matches_%d.png",i);
        saveas(gcf,char(figname))
        close(gcf)
    
        plotMatches(castle{i},castle{i+1}, pL_best{i}, pR_best{i})
        figname = sprintf("./matched_images/matches_%d_RANSAC.png",i);
        saveas(gcf,char(figname))
        close(gcf)
        fprintf("saved fig. %d/%d",i,18);
    end
end
 




%% structure from motion 
% for 2 img at time (no idea how for more that 2 as write on the pdf ?!)
%scatter3(M(:,1),M(:,2),M(:,3))
% not sure if it works...
%also probably there is a smart way to put all together the point and
%select from it

fundamental_method = "ransac";

for i = 1:(N-1)
    switch fundamental_method
        
        case "ransac"
            N = length(p_L{i});
            % compute fundamental matrix w/ ransac
            [pL_n, TL] = normalizePoints([p_L{i}; ones(1,N)]);
            [pR_n, TR] = normalizePoints([p_R{i}; ones(1,N)]);
            
            % use fundamental ransac
            samp_thr = 0.0001;
            [Fn, inliers, samp_dist{i}, pL_best{i}, pR_best{i}] = ransac_fundamental(pL_n, pR_n, samp_thr);
            N = length(pL_best{i});
            % unnormalize points
            pL_best{i} = inv(TL)*pL_best{i};
            pR_best{i} = inv(TR)*pR_best{i};
            pL_best{i} = pL_best{i}(1:2,:);
            pR_best{i} = pR_best{i}(1:2,:);
            
        case "normalized"
            N = length(pL_best{i});
            % normalize points from ransac
            [pL_n, TL] = normalizePoints([pL_best{i}; ones(1,N)]);
            [pR_n, TR] = normalizePoints([pR_best{i}; ones(1,N)]);
            
            % compute fundamental matrix
            Fn  = computeFundamental(pL_n, pR_n);
            
    end
    % unnormalize F
    F{i} = TL'*Fn*TR;
    
    % plot epipolar lines
    plotEpilines(castle{i}, castle{i+1}, [pL_best{i}; ones(1,N)], [pR_best{i};ones(1,N)], F{i})
    %pause;
    hold off
    
    
    D{i} = [pL_best{i}; pR_best{i}];
    [U,W,V] = svd(D{i});


    U3 = U(:,1:3);
    V3 = V(:,1:3);
    W3 = W(1:3,1:3);

    % motion and structure
    M{i} = U3*sqrt(W3);
    S{i} = sqrt(W3)*(V3');
    
    
    %scatter3(S(1,:),S(2,:),S(3,:))
    %scatter3(M(:,1),M(:,2),M(:,3))
end
%%   3 images
k = 0;
for i =1:length(pR_best{1})
    [idx_knn, dist] = knnsearch(pL_best{2}', pR_best{1}(:,i)', 'K', 1);
    if dist < 0.0001
        k = k + 1;
        pL_new{2}(:,k) = pL_best{2}(:,idx_knn);
        pR_new{1}(:,k) = pR_best{1}(:,i);
        
        pR_new{2}(:,k) = pR_best{2}(:,idx_knn);
        pL_new{1}(:,k) = pL_best{1}(:,i);
    end
end

%% 3 plot
[~,idx] = datasample(pL_new{1},3,2,'Replace',false); % 3 points
plotMatches3Im(castle{1}, castle{2}, castle{3}, pL_new{1}(:,idx), pR_new{1}(:,idx), pR_new{2}(:,idx))

%% 


Tform_L_old = maketform('affine',T{1}');
Tform_L_new = affine2d(T{1}');

%Tform_C_old = maketform('affine',(T{2}');
%Tform_C_new = affine2d(T{2}');

Tform_R = maketform('affine',eye(3));

width = size(castle{1},2);
height = size(castle{1},1);

[xL_limits, yL_limits] = outputLimits(Tform_L_new, [1 width], [1 height]);

xmin = floor(min(xL_limits(1)));
xmax = ceil(max(xL_limits(2),width));
ymin = floor(min(yL_limits(1)));
ymax = ceil(max(yL_limits(2),height)); 

xdata = [xmin xmax];
ydata = [ymin ymax];

fprintf("xydata defined\n")

%R_center = imtransform(castle_gray{2}, Tform_C_old, 'bicubic', 'Xdata', xdata, 'Ydata', ydata, 'FillValues', NaN);
R_right = imtransform(castle_gray{2}, Tform_R, 'bicubic', 'Xdata', xdata, 'Ydata', ydata, 'FillValues', NaN);
R_left = imtransform(castle_gray{1}, Tform_L_old, 'bicubic', 'Xdata', xdata, 'Ydata', ydata, 'FillValues', NaN);

fprintf("new im transforms:\n")

R(:,:,1)=R_right;
%R(:,:,2)=R_center;
R(:,:,2)=R_left;
Z = nanmean(R,3);
fprintf("nanmean complete")
imshow(Z);


