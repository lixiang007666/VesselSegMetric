function [ rSe, rSp, rAcc, SS, Confidence, SearchingMask ] = SkeletalSimilarity( SrcVessels, RefVessels, Mask, Alpha, Levels )
% If you find the metrics useful, please cite the following paper:
% Z. Yan, X. Yang and K. -T. Cheng, "A skeletal similarity metric for
% quality evaluation of retinal vessel segmentation," in the corresponding
% jornal.

% Input: SrcVessels --> the vessel segmentation generated by the method
%        RefVessels --> the manual annotation
% Output: rSe, rSp, rAcc --> revised sensitivity, specificity and accuracy
%         SS --> the skeletal similarity score
%         Confidence --> the overall confidence of the whole evaluation

minLength = 4; % the predefined minimum length of the skeleton segment
maxLength = 15; % the predefined maximum length of the skeleton segment
%Initialization
Mask(Mask>0) = 1;
[height, width] = size(RefVessels);
SrcVessels = uint8(SrcVessels);
SrcVessels(SrcVessels>0) = 1;
SrcSkeleton = bwmorph(SrcVessels,'thin',inf);
RefVessels = uint8(RefVessels);
RefVessels(RefVessels>0) = 1;
RefSkeleton = bwmorph(RefVessels,'thin',inf);

% Generate the searching range of each pixel
[ RefThickness, RefminRadius, RefmaxRadius ] = CalcThickness( RefSkeleton, RefVessels);

bin = (RefmaxRadius - RefminRadius) * 1.0 / Levels;
SearchingRadius = ceil((RefmaxRadius - RefThickness + 0.0001) * 1.0 / bin);
SearchingRadius = min(SearchingRadius, Levels);
SearchingRadius(RefSkeleton==0) = 0;

% Calc the vessel thickness of each pixel in Src
[ SrcThickness, SrcminRadius, SrcmaxRadius ] = CalcThickness( SrcSkeleton, SrcVessels);

SearchingMask = GenerateRange(SearchingRadius, Mask);
% Delete wrong skeleton segments
SrcSkeleton(SearchingMask==0) = 0;

% Segment the target skeleton map
[ SegmentID ] = SegmentSkeleton( RefSkeleton, minLength, maxLength );
SegmentID(Mask==0) = 0;
% Calculate the confidence
OriginalSkeleton = RefSkeleton;
EvaluationSkeleton = SegmentID;
EvaluationSkeleton(EvaluationSkeleton>0) = 1;
Confidence = sum(sum(EvaluationSkeleton)) * 1.0 / sum(sum(OriginalSkeleton));

% Calculate the skeletal similarity for each segment
SS = 0.0;
for Index = 1:max(max(SegmentID))
    
    SegmentRadius = SearchingRadius;
    SegmentRadius(SegmentID~=Index) = 0;
    SegmentMask = GenerateRange(SegmentRadius, Mask);
    SrcSegment = SrcSkeleton;
    SrcSegment(SegmentMask==0)=0;
    
    % Remove additionally seleted pixels
    SrcSegment = NoiseRemoval(SrcSegment, RefSkeleton, SegmentID, Index);
    [SrcX, SrcY] = find(SrcSegment>0);
    [RefX, RefY] = find(SegmentID==Index);
    
    % Calc average vessel thickness of Src skeleton
    SkeletonTemp = SrcSkeleton;
    SkeletonTemp(SrcSegment==0) = 0;
    SrcAvgThickness = sum(sum(SrcThickness.*SkeletonTemp)) / length(SrcX);
    % Calc average vessel thickness of Ref skeleton
    SkeletonTemp = RefSkeleton;
    SkeletonTemp(SegmentID~=Index) = 0;
    RefAvgThickness = sum(sum(RefThickness.*SkeletonTemp)) / length(RefX);
    
    RefAvgRange = sum(sum(SegmentRadius)) * 1.0 / length(RefX);
    
    if (length(unique(SrcX)) > length(unique(SrcY)))
        SS = SS + CalcSimilarity(SrcX, SrcY, SrcAvgThickness, RefX, RefY, RefAvgThickness, Alpha, RefAvgRange) * length(RefX);
    else
        SS = SS + CalcSimilarity(SrcY, SrcX, SrcAvgThickness, RefY, RefX, RefAvgThickness, Alpha, RefAvgRange) * length(RefX);
    end
    
end

SegmentID(SegmentID>0) = 1;
SS = SS / sum(sum(SegmentID));

PositiveMask = SearchingMask + RefVessels;
PositiveMask(PositiveMask>0) = 1;
PositiveMask(Mask==0) = 0;
TP = SS * sum(sum(PositiveMask));
FN = (1 - SS) * sum(sum(PositiveMask));
FP = sum(sum(SrcVessels.*(1-PositiveMask).*Mask));
TN = sum(sum((1-SrcVessels).*(1-PositiveMask).*Mask));
rSe = TP * 100.0 / (TP + FN);
rSp = TN * 100.0 / (TN + FP);
rAcc = (TP + TN) * 100 / (TP + FN +TN + FP);

function [ Score ] = CalcSimilarity(SrcX, SrcY, SrcAvgThickness, RefX, RefY, RefAvgThickness, Alpha, RefAvgRange)
% Function to calculate the simialrity between two group of discrete pixels
% in the source and the reference skeleton maps
% Input:  SrcX, SrcY --> pixels in the source skeleton map that lie in the
%                       searching range of a skeleton segment in the reference skeleton map
%         RefX, RefY --> pixels of the skeleton segment in the reference map
% Output: Score --> the skeletal similarity for the skeleton segment in the
%                   reference map
Score = 0.0;

Temp = []; Temp(1) = RefX(1);
index = 2;
while(index<=length(RefX))
    if ismember(RefX(index), Temp)
        RefX(index) = RefX(index) + 0.01;
        continue;
    else
        Temp(index) = RefX(index);
    end
    index = index + 1;
end
RefPolyComplete = fit(RefX, RefY, 'poly3');
RefPoly = [RefPolyComplete.p1, RefPolyComplete.p2, RefPolyComplete.p3];

if ((length(SrcX) > 0.6 * length(RefX)) && (length(SrcX) > 3))
    Temp = []; Temp(1) = SrcX(1);
    index = 2;
    while(index<=length(SrcX))
        if ismember(SrcX(index), Temp)
            SrcX(index) = SrcX(index) + 0.01;
            continue;
        else
            Temp(index) = SrcX(index);
        end
        index = index + 1;
    end
    SrcPolyComplete = fit(SrcX, SrcY, 'poly3');
    SrcPoly = [SrcPolyComplete.p1, SrcPolyComplete.p2, SrcPolyComplete.p3];
    
    Similarity = abs(dot(SrcPoly, RefPoly) / (norm(SrcPoly) + 1e-10) / norm(RefPoly + 1e-10));
    
    Thickness = 1.0 - abs(RefAvgThickness-SrcAvgThickness) * 1.0 / RefAvgRange;
    Thickness = max(Thickness, 0);
    
    Score = (1 - Alpha) * Similarity + Alpha * Thickness;
    
end

function [ UpdatedSegment ] = NoiseRemoval(SrcSegment, RefSkeleton, SegmentID, ID)
[height, width] = size(SegmentID);
UpdatedSegment = SrcSegment;
[X, Y] = find(SrcSegment>0);
for Index = 1:length(X)
    minRadius = 10;
    minID = 0;
    if (SegmentID(X(Index),Y(Index))>0)
        if (SegmentID(X(Index),Y(Index))~=ID)
            UpdatedSegment(X(Index),Y(Index)) = 0;
        end
        continue;
    else
        for x = max(X(Index)-5, 1):min(X(Index)+5, height)
            for y = max(Y(Index)-5, 1):min(Y(Index)+5, width)
                if ((x==X(Index)) && (y==Y(Index)))
                    continue;       
                end
                if (RefSkeleton(x,y)>0)
                    if ((sqrt((x-X(Index))^2+(y-Y(Index))^2)<minRadius) || ((sqrt((x-X(Index))^2+(y-Y(Index))^2)==minRadius) && (SegmentID(x,y)==ID)))
                        minID=SegmentID(x,y);
                        minRadius = sqrt((x-X(Index))^2+(y-Y(Index))^2);
                    end
                end
            end
        end
    end
    if (minID~=ID)
        UpdatedSegment(X(Index),Y(Index)) = 0;
    end
end
