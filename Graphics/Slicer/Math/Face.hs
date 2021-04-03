-- Slicer.
{-
 - Copyright 2020 Julia Longtin
 -
 - This program is free software: you can redistribute it and/or modify
 - it under the terms of the GNU Affero General Public License as published by
 - the Free Software Foundation, either version 3 of the License, or
 - (at your option) any later version.
 -
 - This program is distributed in the hope that it will be useful,
 - but WITHOUT ANY WARRANTY; without even the implied warranty of
 - MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 - GNU Affero General Public License for more details.

 - You should have received a copy of the GNU Affero General Public License
 - along with this program.  If not, see <http://www.gnu.org/licenses/>.
 -}

-- So we can pattern match against the last item in a list.
{-# LANGUAGE ViewPatterns #-}

module Graphics.Slicer.Math.Face (Face(Face), NodeTree(NodeTree), addLineSegs, leftRegion, rightRegion, convexMotorcycles, Node(Node), makeFirstNodes, Motorcycle(Motorcycle), findStraightSkeleton, StraightSkeleton(StraightSkeleton), Spine(Spine), facesFromStraightSkeleton, averageNodes, getFirstArc) where

import Prelude (Int, (==), otherwise, (<$>), ($), length, Show, (/=), error, (<>), show, Eq, Show, (<>), (<), (/), floor, fromIntegral, Either(Left, Right), (+), (*), (-), (++), (>), min, Bool(True,False), zip, head, (&&), (.), (||), fst, take, drop, filter, init, null, tail, last, concat, snd, not, reverse, break, and, (>=), String)

import Data.List (elemIndex, sortOn, dropWhile)

import Data.List.NonEmpty (NonEmpty)

import Data.Maybe( Maybe(Just,Nothing), fromMaybe,  catMaybes, isJust, fromJust, isNothing)

import Graphics.Slicer.Math.Definitions (Contour(PointSequence), Point2, mapWithFollower, mapWithNeighbors, addPoints)

import Graphics.Slicer.Math.GeometricAlgebra (addVecPair)

import Graphics.Slicer.Math.Line (LineSeg(LineSeg), lineSegFromEndpoints, LineSegError(LineSegFromPoint), makeLineSegsLooped)

import Graphics.Slicer.Math.PGA (lineIsLeft, distancePPointToPLine, pToEPoint2, PLine2(PLine2), PPoint2, plinesIntersectIn, Intersection(NoIntersection, HitEndPoint, HitStartPoint), PIntersection(PCollinear,IntersectsIn,PParallel,PAntiParallel), eToPLine2, translatePerp, intersectsWith, eToPPoint2, flipPLine2, pPointsOnSameSideOfPLine, pLineIsLeft, normalizePLine2, distanceBetweenPPoints)

import Graphics.Slicer.Machine.Infill (makeInfill, InfillType)

import Graphics.Implicit.Definitions (ℝ, Fastℕ)

-- | A Face:
--   A portion of a contour, with a real side, and arcs (line segments between nodes) dividing it from other faces.
--   Faces have no holes, and their arcs and nodes (lines and points) are derived from a straight skeleton of a contour.
data Face = Face { _edge :: LineSeg, _firstArc :: PLine2, _arcs :: [PLine2], _lastArc :: PLine2 }
  deriving (Show, Eq)

-- | A Motorcycle. a Ray eminating from an intersection between two line segments toward the interior of a contour. Motorcycles are only emitted when the angle between tho line segments make this point a reflex vertex.
data Motorcycle = Motorcycle { _inSeg :: LineSeg, _outSeg :: LineSeg, _path :: PLine2 }
  deriving (Show, Eq)

-- | A Node:
--   A point in our straight skeleton where two arcs intersect, resulting in another arc, OR a point where two lines of a contour intersect, emmiting a line toward the interior of a contour.
data Node = Node { _inArcs :: Either (LineSeg, LineSeg) [PLine2], _outArc :: Maybe PLine2 }
  deriving (Show, Eq)

-- | A Spine component:
--   Similar to a node, only without the in and out heirarchy. always connects to outArcs from the last generation in a NodeTree.
--   Used for glueing node sets together.
data Spine = Spine { _spineArcs :: NonEmpty PLine2 }
  deriving (Show, Eq)

-- | A nodeTree:
--   A set of set of nodes, divided into 'generations', where each generation is a set of nodes that (may) result in the next set of nodes.
--   Note that not all of the outArcs in a given generation necessarilly are used in the next generation, but they must all be used by subsequent generations in order for a nodetree to be complete.
--   With the exception of the last generation, which may have an outArc.
newtype NodeTree = NodeTree [[Node]]
  deriving (Show, Eq)

-- | The straight skeleton of a contour.
data StraightSkeleton = StraightSkeleton { _nodeSets :: [[NodeTree]], _spineNodes :: [Spine] }
  deriving (Show, Eq)


-- Find the straight skeleton for a given contour, when a given set of holes is cut in it.
-- FIXME: woefully incomplete.
findStraightSkeleton :: Contour -> [Contour] -> StraightSkeleton
findStraightSkeleton contour@(PointSequence pts) holes
  -- Triangles without holes are trivial. hard code a quick path.
  | null holes && length pts == 3 = StraightSkeleton ([[skeletonOfConcaveRegion (linesOfContour contour) True]]) []
  -- This same routine should handle all closed contours with no holes and no convex motorcycles.
  | null holes && length outsideContourMotorcycles == 0 = StraightSkeleton ([[skeletonOfConcaveRegion (linesOfContour contour) True]]) []
  -- Use the algorithm from Christopher Tscherne's master's thesis.
  | null holes && length outsideContourMotorcycles == 1 = tscherneMerge dividingMotorcycle maybeOpposingNode leftSide rightSide
  | otherwise = error "Do not know how to calculate a straight skeleton for this contour!"
  where
    dividingMotorcycle = head outsideContourMotorcycles
    leftSide  = leftRegion contour dividingMotorcycle
    rightSide = rightRegion contour dividingMotorcycle
    -- | find nodes where the arc coresponding to them is collinear with the dividing Motorcycle.
    -- FIXME: Yes, this is implemented wrong. it needs to find only the one node opposing the dividing motorcycle, not every line that could be an opposing node.
    --        construct a line segment from the node and the motorcycle, and see what segments intersect?
    maybeOpposingNode
      | length outsideContourMotorcycles == 1 && length opposingNodes == 1 = Just $ head opposingNodes
      | length outsideContourMotorcycles == 1 && null opposingNodes        = Nothing
      | otherwise                                                          = error "more than one opposing node. impossible situation."
      where
        opposingNodes =  filter (\(Node _ (Just outArc)) -> plinesIntersectIn outArc (pathOf dividingMotorcycle) == PCollinear) $ concaveNodes contour
        pathOf (Motorcycle _ _ path) = path
    outsideContourMotorcycles = convexMotorcycles contour
    -- | not yet used, but at least implemented properly.
--    motorcyclesOfHoles = concaveMotorcycles <$> holes

-- | Apply the merge algorithm from Christopher Tscherne's master's thesis.
tscherneMerge :: Motorcycle -> Maybe Node -> NodeTree -> NodeTree -> StraightSkeleton
tscherneMerge dividingMotorcycle@(Motorcycle (LineSeg rightPoint _) (LineSeg startPoint2 endDistance2) path) opposingNodes leftSide rightSide
  -- If the two sides do not have an influence on one another, and the last line out of the two sides intersects the motorcycle at the same point, tie the sides and the motorcycle together.
  | null (crossoverNodes leftSide leftPoint dividingMotorcycle) &&
    null (crossoverNodes rightSide rightPoint dividingMotorcycle) &&
    isNothing opposingNodes &&
    plinesIntersectIn (finalPLine leftSide) path == plinesIntersectIn (finalPLine rightSide) path =
      StraightSkeleton [[leftSide, rightSide, NodeTree [[motorcycleToNode dividingMotorcycle]]]] []
  -- If the two sides do not have an influence on one another, and the last line out of the two sides intersects the motorcycle at the same point, tie the sides, the motorcycle, and the opposing motorcycle together.
  -- FIXME: nodeSets should always be stored in clockwise order.
  | null (crossoverNodes leftSide leftPoint dividingMotorcycle) &&
    null (crossoverNodes rightSide rightPoint dividingMotorcycle) &&
    isJust opposingNodes &&
    plinesIntersectIn (finalPLine leftSide) path == plinesIntersectIn (finalPLine rightSide) path =
      StraightSkeleton [[leftSide, rightSide, NodeTree [[motorcycleToNode dividingMotorcycle]], NodeTree [[fromJust opposingNodes]]]] []
  | otherwise = error $ "failing to apply Tscherne's method.\n" <>
                        show (crossoverNodes leftSide leftPoint dividingMotorcycle)  <> "\n" <>
                        show (crossoverNodes rightSide rightPoint dividingMotorcycle)  <> "\n" <>
                        show opposingNodes <> "\n" <>
                        show (finalPLine leftSide) <> "\n" <>
                        show (finalPLine rightSide) <> "\n" <>
                        show leftSide <> "\n" <>
                        show rightSide <> "\n" <>
                        show dividingMotorcycle <> "\n"
  where
    leftPoint = addPoints startPoint2 endDistance2
    finalPLine :: NodeTree -> PLine2
    finalPLine (NodeTree generations)
      | null generations = error "cannot have final PLine of empty side!\n"
      | otherwise = outOf $ last $ last generations
      where
        outOf (Node _ (Just p)) = p
        outOf (Node _ Nothing) = error "skeleton of a side ended in a node with no endpoint?"
    motorcycleToNode :: Motorcycle -> Node
    motorcycleToNode (Motorcycle inSeg outSeg mcpath) = Node (Left (inSeg,outSeg)) $ Just mcpath
    crossoverNodes :: NodeTree -> Point2 -> Motorcycle -> [Node]
    crossoverNodes (NodeTree generations) pointOnSide (Motorcycle _ _ mcpath) = concat (crossoverGen <$> init generations)
      where
        crossoverGen :: [Node] -> [Node]
        crossoverGen generation = filter (\a -> Just True == intersectionSameSide mcpath (eToPPoint2 pointOnSide) a) generation
  -- determine if a node is on one side of the motorcycle, or the other.
  -- assumes the starting point of the second line segment is a point on the path.
    intersectionSameSide :: PLine2 -> PPoint2 -> Node -> Maybe Bool
    intersectionSameSide mcpath pointOnSide node = pPointsOnSameSideOfPLine (saneIntersection $ plinesIntersectIn (fst $ plineAncestors node) (snd $ plineAncestors node)) pointOnSide mcpath
      where
        plineAncestors :: Node -> (PLine2, PLine2)
        plineAncestors (Node (Left (seg1,seg2)) _)      = (eToPLine2 seg1, eToPLine2 seg2)
        plineAncestors (Node (Right (pline1:pline2:[])) _) = (pline1, pline2)
        plineAncestors myNode@(Node (Right (_)) _) = error $ "less than two ancestors in a Node: " <> show myNode <> "\n"  
        saneIntersection :: PIntersection -> PPoint2
        saneIntersection (IntersectsIn ppoint) = ppoint
        saneIntersection a = error $ "insane result of intersection of two ancestor lines:" <> show a <> "\n"

-- | Calculate a partial straight skeleton, for the part of a contour that is on the left side of the point that a motorcycle's path starts at.
--   meaning we will evaluate the line segments from the point the motorcycle left from, to the segment it intersects, in the order they are in the original contour.
leftRegion :: Contour -> Motorcycle -> NodeTree
leftRegion contour motorcycle = skeletonOfConcaveRegion (matchLineSegments contour motorcycle) False
  where
    -- Return the line segments we're responsible for straight skeletoning.
    matchLineSegments :: Contour -> Motorcycle -> [LineSeg]
    matchLineSegments c (Motorcycle inSeg outSeg path)
      | wrapDirection   = drop stopSegmentIndex (linesOfContour c) ++ take startSegmentIndex (linesOfContour c)
      | unwrapDirection = take (startSegmentIndex - stopSegmentIndex) $ drop stopSegmentIndex $ linesOfContour c
      | otherwise = error "this should be impossible."
        where
          -- test whether we can gather our segments from the stop segment to the end ++ first one until the segment the motorcycle hits...
          wrapDirection   = findSegFromStart c outSeg motorcycleInSegment == outSeg
          -- .. or by starting at the stop segment, and stopping after the segment the motorcycle hits
          unwrapDirection = findSegFromStart c outSeg motorcycleInSegment == motorcycleInSegment
          stopSegmentIndex = segIndex motorcycleOutSegment (linesOfContour c)
          -- the segment that a motorcycle intersects the contour on, or if it intersected between two segments, the first of the two segments (from the beginning of the contour).
          motorcycleInSegment  = fst motorcycleIntersection
          -- the segment that a motorcycle intersects the contour on, or if it intersected between two segments, the last of the two segments (from the beginning of the contour).
          motorcycleOutSegment = fromMaybe (fst motorcycleIntersection) (snd motorcycleIntersection)
          motorcycleIntersection = motorcycleIntersectsAt c inSeg outSeg path
          startSegmentIndex = segIndex outSeg (linesOfContour c)

-- | Calculate a partial straight skeleton, for the part of a contour that is on the 'right' side of a contour, when the contour is bisected by a motorcycle.
--   by right side, we mean consisting of the segments from the point the motorcycle left from, to the intersection, in the order they are in the original contour.
rightRegion :: Contour -> Motorcycle -> NodeTree
rightRegion contour motorcycle = skeletonOfConcaveRegion (matchLineSegments contour motorcycle) False
  where
    -- Return the line segments we're responsible for straight skeletoning.
    matchLineSegments :: Contour -> Motorcycle -> [LineSeg]
    matchLineSegments c (Motorcycle inSeg outSeg path)
      | wrapDirection   = drop startSegmentIndex (linesOfContour c) ++ take stopSegmentIndex (linesOfContour c)
      | unwrapDirection = take (stopSegmentIndex - startSegmentIndex) $ drop startSegmentIndex $ linesOfContour c
      | otherwise = error "this should be impossible."
        where
          -- test whether we can gather our segments from the stop segment to the end ++ first one until the segment the motorcycle hits...
          wrapDirection    = findSegFromStart c outSeg motorcycleInSegment == motorcycleInSegment
          -- .. or by starting at the stop segment, and stopping after the segment the motorcycle hits
          unwrapDirection  = findSegFromStart c outSeg motorcycleInSegment == outSeg
          stopSegmentIndex = 1 + segIndex motorcycleInSegment (linesOfContour c)
          -- the segment that a motorcycle intersects the contour on, or if it intersected between two segments, the first of the two segments (from the beginning of the contour).
          motorcycleInSegment  = fst motorcycleIntersection
          -- the segment that a motorcycle intersects the contour on, or if it intersected between two segments, the last of the two segments (from the beginning of the contour).
          -- motorcycleOutSegment = fromMaybe (fst motorcycleIntersection) (snd motorcycleIntersection)
          motorcycleIntersection = motorcycleIntersectsAt c inSeg outSeg path
          startSegmentIndex = segIndex outSeg (linesOfContour c)

-- | Find the non-reflex virtexes of a contour and draw motorcycles from them. Useful for contours that are a 'hole' in a bigger contour.
--   This function is meant to be used on the exterior contour.
convexMotorcycles :: Contour -> [Motorcycle]
convexMotorcycles contour = catMaybes $ onlyMotorcycles <$> zip (linePairs contour) (mapWithFollower convexPLines $ linesOfContour contour)
  where
    onlyMotorcycles :: ((LineSeg, LineSeg), Maybe PLine2) -> Maybe Motorcycle
    onlyMotorcycles ((seg1, seg2), maybePLine)
      | isJust maybePLine = Just $ Motorcycle seg1 seg2 $ flipPLine2 $ fromJust maybePLine
      | otherwise         = Nothing

-- | Find the non-reflex virtexes of a contour, and draw Nodes from them.
--   This function is meant to be used on the exterior contour.
concaveNodes :: Contour -> [Node]
concaveNodes contour = catMaybes $ onlyNodes <$> zip (linePairs contour) (mapWithFollower concavePLines $ linesOfContour contour)
  where
    onlyNodes :: ((LineSeg, LineSeg), Maybe PLine2) -> Maybe Node
    onlyNodes ((seg1, seg2), maybePLine)
      | isJust maybePLine = Just $ Node (Left (seg1,seg2))  maybePLine
      | otherwise         = Nothing

-- | Find the non-reflex virtexes of a contour and draw motorcycles from them.
--   A reflex virtex is any point where the line in and the line out are convex, when looked at from inside of the contour.
--   This function is meant to be used on interior contours.
{-
concaveMotorcycles :: Contour -> [Motorcycle]
concaveMotorcycles contour = catMaybes $ onlyMotorcycles <$> zip (linePairs contour) (mapWithFollower concavePLines $ linesOfContour contour)
  where
    onlyMotorcycles :: ((LineSeg, LineSeg), Maybe PLine2) -> Maybe Motorcycle
    onlyMotorcycles ((seg1, seg2), maybePLine)
      | isJust maybePLine = Just $ Motorcycle seg1 seg2 $ fromJust maybePLine
      | otherwise         = Nothing
-}

-- | Find the reflex virtexes of a contour, and draw Nodes from them.
--   This function is meant to be used on interior contours.
{-
convexNodes :: Contour -> [Node]
convexNodes contour = catMaybes $ onlyNodes <$> zip (linePairs contour) (mapWithFollower convexPLines $ linesOfContour contour)
  where
    onlyNodes :: ((LineSeg, LineSeg), Maybe PLine2) -> Maybe Node
    onlyNodes ((seg1, seg2), maybePLine)
      | isJust maybePLine = Just $ Node (Left (seg1,seg2)) $ fromJust maybePLine
      | otherwise         = Nothing
-}

-- | Examine two line segments, and determine if they are convex. if they are, construct a PLine2 bisecting them.
convexPLines :: LineSeg -> LineSeg -> Maybe PLine2
convexPLines seg1 seg2
  | Just True == lineIsLeft seg1 seg2  = Just $ PLine2 $ addVecPair pv1 pv2
  | otherwise                          = Nothing
  where
    (PLine2 pv1) = eToPLine2 seg1
    (PLine2 pv2) = flipPLine2 $ eToPLine2 seg2

-- Examine two line segments, and determine if they are concave. if they are, construct a PLine2 bisecting them.
concavePLines :: LineSeg -> LineSeg -> Maybe PLine2
concavePLines seg1 seg2
  | Just True == lineIsLeft seg1 seg2  = Nothing
  | otherwise                          = Just $ PLine2 $ addVecPair pv1 pv2
  where
    (PLine2 pv1) = eToPLine2 seg1
    (PLine2 pv2) = flipPLine2 $ eToPLine2 seg2

-- | Make a first generation set of nodes, AKA, a set of motorcycles that come from the points where line segments meet, toward the inside of the contour.
makeFirstNodes :: [LineSeg] -> [Node]
makeFirstNodes segs
  | null segs = error "got empty list at makeFirstNodes.\n"
  | otherwise = init $ mapWithFollower makeFirstNode segs
  where
    makeFirstNode :: LineSeg -> LineSeg -> Node
    makeFirstNode seg1 seg2 = Node (Left (seg1,seg2)) $ Just $ getFirstArc seg1 seg2

-- | Make a first generation set of nodes, AKA, a set of motorcycles that come from the points where line segments meet, toward the inside of the contour.
makeFirstNodesLooped :: [LineSeg] -> [Node]
makeFirstNodesLooped segs
  | null segs = error "got empty list at makeFirstNodes.\n"
  | otherwise = mapWithFollower makeFirstNode segs
  where
    makeFirstNode :: LineSeg -> LineSeg -> Node
    makeFirstNode seg1 seg2 = Node (Left (seg1,seg2)) $ Just $ getFirstArc seg1 seg2

-- | Get a PLine in the direction of the inside of the contour, at the angle bisector of the intersection of the two given line segments.
--   Note that we normalize the output of eToPLine2, because by default, it does not output normalized lines.
getFirstArc :: LineSeg -> LineSeg -> PLine2
getFirstArc seg1@(LineSeg start1 _) seg2@(LineSeg start2 _) = getInsideArc start1 (normalizePLine2 $ eToPLine2 seg1) start2 (normalizePLine2 $ eToPLine2 seg2)

-- | Get a PLine along the angle bisector of the intersection of the two given line segments, pointing in the 'acute' direction.
--   Note that we normalize our output, but don't bother normalizing our input lines, as the ones we output and the ones getFirstArc outputs are normalized.
--   Note that we know that the inside is to the right of the first line given, and that the first line points toward the intersection.
getInsideArc :: Point2 -> PLine2 -> Point2 -> PLine2 -> PLine2
getInsideArc _ pline1 _ pline2@(PLine2 pv2)
  | pline1 == pline2 = error "need to be able to return two PLines."
  | noIntersection pline1 pline2 = error $ "no intersection between pline " <> show pline1 <> " and " <> show pline2 <> ".\n"
  | otherwise = normalizePLine2 $ PLine2 $ addVecPair flippedPV1 pv2
  where
      (PLine2 flippedPV1) = flipPLine2 pline1

-- | Get a PLine along the angle bisector of the intersection of the two given line segments, pointing in the 'obtuse' direction.
--   Note: we normalize our output lines, but don't bother normalizing our input lines, as the ones we output and the ones getFirstArc outputs are normalized.
--   Note: the outer PLine returned by two PLines in the same direction should be two PLines, whch are the same line in both directions.
getOutsideArc :: Point2 -> PLine2 -> Point2 -> PLine2 -> PLine2
getOutsideArc point1 pline1 point2 pline2
  | pline1 == pline2 = error "need to be able to return two PLines."
  | noIntersection pline1 pline2 = error $ "no intersection between pline " <> show pline1 <> " and " <> show pline2 <> ".\n"
  | l1TowardPoint && l2TowardPoint = flipPLine2 $ getInsideArc point1 pline1 (pToEPoint2 $ intersectionOf pline1 pline2) (flipPLine2 pline2)
  | l1TowardPoint                  = flipPLine2 $ getInsideArc point1 pline1 point2 pline2
  | l2TowardPoint                  = getInsideArc point2 pline2 point1 pline1
  | otherwise                      = getInsideArc (pToEPoint2 $ intersectionOf pline1 pline2) (flipPLine2 pline2) point1 pline1
    where
      l1TowardPoint = towardIntersection point1 pline1 (intersectionOf pline1 pline2)
      l2TowardPoint = towardIntersection point2 pline2 (intersectionOf pline1 pline2)

noIntersection :: PLine2 -> PLine2 -> Bool
noIntersection pline1 pline2 = not $ pLinesIntersectInPoint pline1 pline2
  where
  -- | check if two line segments intersect.
  pLinesIntersectInPoint :: PLine2 -> PLine2 -> Bool
  pLinesIntersectInPoint pl1 pl2 = isPoint $ plinesIntersectIn pl1 pl2
    where
      isPoint (IntersectsIn _) = True
      isPoint _ = False

-- Note: PLine must be normalized.
towardIntersection :: Point2 -> PLine2 -> PPoint2 -> Bool
towardIntersection p1 pl1 in1
  | p1 == pToEPoint2 in1                                      = False
  | (normalizePLine2 $ eToPLine2 $ constructedLineSeg) == pl1 = True
  | otherwise                                                 = False
  where
    constructedLineSeg :: LineSeg
    constructedLineSeg = foundLineSeg $ maybeConstructedLineSeg
      where
      foundLineSeg (Left a)  = error $ "encountered " <> show a <> "error."
      foundLineSeg (Right a) = a
      maybeConstructedLineSeg = lineSegFromEndpoints p1 (pToEPoint2 in1)

-- | For a given pair of nodes, construct a new node, where it's parents are the two given nodes, and the line leaving it is along the the obtuse bisector.
averageNodes :: Node -> Node -> Node
averageNodes n1@(Node _ (Just pline1)) n2@(Node _ (Just pline2)) = Node (Right (pline1:pline2:[])) $ Just $ getOutsideArc (pointOf n1) pline1 (pointOf n2) pline2
averageNodes n1 n2 = error $ "Cannot get the average of nodes if one of the nodes does not have an out!\nNode1: " <> show n1 <> "\nNode2: " <> show n2 <> "\n"

-- Find the euclidian point that is at the intersection of the lines of a node.
pointOf :: Node -> Point2
pointOf (Node (Left (_,(LineSeg point _))) _) = point
pointOf (Node (Right (pline1:pline2:_)) _) = pToEPoint2 $ intersectionOf pline1 pline2
pointOf node = error $ "cannot find a point intersection for this node: " <> show node <> "\n"

-- error types.

data PartialNodes = PartialNodes [[Node]] String
  deriving (Show, Eq)

-- | Recurse on a set of nodes until we have a complete straight skeleton.
--   Only works on a sequnce of concave line segments, when there are no holes.
skeletonOfConcaveRegion :: [LineSeg] -> Bool -> NodeTree
skeletonOfConcaveRegion inSegs loop = separateNodeTrees (firstNodes inSegs loop)
  where
    -- Generate the first generation of nodes, from the passed in line segments.
    -- If the line segments are a loop, use the appropriate function to create the initial Nodes.
    firstNodes :: [LineSeg] -> Bool -> [Node]
    firstNodes firstSegs segsInLoop
      | segsInLoop = makeFirstNodesLooped firstSegs
      | otherwise  = makeFirstNodes firstSegs

    -- | create multiple NodeTrees from a set of generations of nodes.
    -- FIXME: geometry may require spines, which are still a concept in flux.
    separateNodeTrees :: [Node] -> NodeTree
    separateNodeTrees initialGeneration
      | length (res initialGeneration) > 0 = NodeTree $ (res initialGeneration)
      | otherwise = error "no Nodes to generate a nodetree from?"
      where
        -- | apply the recursive solver.
        res :: [Node] -> [[Node]]
        res inGen = [initialGeneration] ++ errorIfLeft (skeletonOfNodes inGen)

    errorIfLeft :: Either PartialNodes [[Node]] -> [[Node]]
    errorIfLeft (Left failure) = error $ "Fail!\n" <> show failure <> "\n"
    errorIfLeft (Right val)    = val

    -- | recursively try to solve the node set.
    skeletonOfNodes :: [Node] -> Either PartialNodes [[Node]]
    skeletonOfNodes nodes
      | length nodes >= 3 &&
        endsAtSamePoint nodes = if loop
                                then Right [[Node (Right $ outOf <$> nodes) Nothing]]
                                else Right []
      | length nodes == 3 &&
        hasShortestPair       = Right $ [[averageOfShortestPair]] ++ errorIfLeft (skeletonOfNodes nextGen)
      | length nodes == 2 &&
        pairHasIntersection   = Right $ [[averageOfPair]]
      | otherwise = Left $ PartialNodes [nodes] "NOMATCH"
      where
        ------------------------------------------------------------------------------
        -- functions that are the same, regardless of number of nodes we are handling.
        ------------------------------------------------------------------------------

        -- | Get the output PLine of a node, if it exists.
        outOf (Node _ (Just p)) = p
        outOf (Node _ Nothing) = error "skeleton of a side ended in a node with no endpoint?"

        -- | Check if the intersection of two nodes results in a point or not.
        intersectsInPoint :: Node -> Node -> Bool
        intersectsInPoint (Node _ (Just pline1)) (Node _ (Just pline2)) = isPoint $ plinesIntersectIn pline1 pline2
          where
            isPoint (IntersectsIn _) = True
            isPoint _                = False
        intersectsInPoint node1 node2 = error $ "cannot intersect a node with no output:\nNode1: " <> show node1 <> "\nNode2: " <> show node2 <> "\n"

        -- | When a set of nodes end in the same point, we may need to create a Node with all of the nodes, and no output. This checks for that case.
        endsAtSamePoint :: [Node] -> Bool
        endsAtSamePoint myNodes
          |  length myNodes > 2 ||
            (length myNodes > 1 && null (collinearNodePairsOf myNodes)) = and $ mapWithFollower (==) $ mapWithFollower intersectionOf (outOf <$> (myNodes ++ (firstCollinearNodes $ collinearNodePairsOf myNodes)))
          | otherwise          = False
          where
            firstCollinearNodes :: [(Node, Node)] -> [Node]
            firstCollinearNodes nodePairs = fst <$> nodePairs 
            collinearNodePairsOf :: [Node] -> [(Node, Node)]
            collinearNodePairsOf nodeSet = catMaybes $ (\(node1, node2) -> if isCollinear node1 node2 then Just (node1, node2) else Nothing) <$> getPairs nodeSet
              where
                getPairs :: [a] -> [(a,a)]
                getPairs [] = []
                getPairs (x:xs) = (((,) x) <$> xs) ++ getPairs xs
                isCollinear :: Node -> Node -> Bool
                isCollinear (Node _ (Just pline1)) (Node _ (Just pline2)) = plinesIntersectIn pline1 pline2 == PCollinear
                isCollinear _ _ = False
        -- Find the projective point that is at the intersection of the lines of a node.
        pPointOf (Node (Left (_,(LineSeg point _))) _) = eToPPoint2 point
        pPointOf (Node (Right (pline1:pline2:_)) _)   = intersectionOf pline1 pline2
        pPointOf a                                     = error $ "tried to find projective point of a node with less than two PLines: " <> show a <> "\n"

        ---------------------------------------------------------------
        -- Functions used when we have 3 line segments to reason about.
        ---------------------------------------------------------------
        hasShortestPair :: Bool
        hasShortestPair = and $ mapWithFollower intersectsInPoint nodes
        averageOfShortestPair = averageNodes (fst shortestPair) (snd shortestPair)
        shortestPair :: (Node, Node)
        (shortestPair, remainingNode)
          | distanceToIntersection (head nodes) (head $ tail nodes) <
            distanceToIntersection (head $ tail nodes) (head $ tail $ tail nodes) = ((head nodes, head $ tail nodes), head (tail $ tail nodes))
          | distanceToIntersection (head nodes) (head $ tail nodes) >
            distanceToIntersection (head $ tail nodes) (head $ tail $ tail nodes) = ((head $ tail nodes, head $ tail $ tail nodes), head nodes)
          | otherwise                                                             = error "has no shortest pair."
        distanceToIntersection :: Node -> Node -> ℝ
        distanceToIntersection node1@(Node _ (Just pline1)) node2@(Node _ (Just pline2)) = min (distanceBetweenPPoints (pPointOf node1) (intersectionOf pline1 pline2)) (distanceBetweenPPoints (pPointOf node2) (intersectionOf pline1 pline2))
        distanceToIntersection node1 node2 = error $ "cannot find distance between nodes with no exit:\n" <> show node1 <> "\n" <> show node2 <> "\n" 
        nextGen :: [Node]
        nextGen = [averageOfShortestPair, remainingNode]

        ---------------------------------------------------------------
        -- Functions used when we have 2 line segments to reason about.
        ---------------------------------------------------------------
        pairHasIntersection = and (init $ mapWithFollower intersectsInPoint nodes)
        averageOfPair = averageNodes (head nodes) (head $ tail nodes)

linesOfContour :: Contour -> [LineSeg]
linesOfContour (PointSequence contourPoints) = makeLineSegsLooped contourPoints

-- Get pairs of lines from the contour, including one pair that is the last line paired with the first.
linePairs :: Contour -> [(LineSeg, LineSeg)]
linePairs c = mapWithFollower (\a b -> (a,b)) $ linesOfContour c

-- | Get the index of a specific segment, in a list of segments.
segIndex :: LineSeg -> [LineSeg] -> Int
segIndex seg segs = fromMaybe (error "cannot find item") $ elemIndex seg segs

-- | Search a contour starting at the beginning, and return the first of the two line segments given
findSegFromStart :: Contour -> LineSeg -> LineSeg -> LineSeg
findSegFromStart c seg1 seg2 = head $ catMaybes $ foundSeg seg1 seg2 <$> linesOfContour c
  where
    foundSeg s1 s2 sn
      | sn == s1  = Just s1
      | sn == s2  = Just s2
      | otherwise = Nothing

-- | Find where a motorcycle intersects a contour, if the motorcycle is emitted from between the two given segments.
--   If the motorcycle lands between two segments, return the second segment, as well.
motorcycleIntersectsAt :: Contour -> LineSeg -> LineSeg -> PLine2 -> (LineSeg, Maybe LineSeg)
motorcycleIntersectsAt contour inSeg outSeg path
  | length (getMotorcycleIntersections path contour) == 2 && length foundSegEvents == 1 = head foundSegEvents
  | otherwise = error $ "handle more than one intersection point here." <> show (getMotorcycleIntersections path contour) <> "\n"
  where
    foundSegEvents = filter (\(seg, maybeSeg) -> (seg /= inSeg && seg /= outSeg) &&
                                                   (isNothing maybeSeg ||
                                                    (fromJust maybeSeg /= inSeg && fromJust maybeSeg /= outSeg))) $ getMotorcycleIntersections path contour
    -- find one of the two segments given, returning the one closest to the head of the given contour.
    getMotorcycleIntersections :: PLine2 -> Contour -> [(LineSeg, Maybe LineSeg)]
    getMotorcycleIntersections myline c = catMaybes $ mapWithNeighbors saneIntersections $ zip (linesOfContour c) $ intersectsWith (Right myline) . Left <$> linesOfContour c
      where
        saneIntersections :: (LineSeg, Either Intersection PIntersection) -> (LineSeg, Either Intersection PIntersection) -> (LineSeg, Either Intersection PIntersection) -> Maybe (LineSeg, Maybe LineSeg)
        saneIntersections  _ (seg, Right (IntersectsIn _))      _ = Just (seg, Nothing)
        saneIntersections  _ (_  , Left  NoIntersection)        _ = Nothing
        saneIntersections  _ (_  , Right PParallel)             _ = Nothing
        saneIntersections  _ (_  , Right PAntiParallel)         _ = Nothing
        saneIntersections  _                              (seg , Left (HitStartPoint _ _)) (seg2 , Left (HitEndPoint   _ _)) = Just (seg, Just seg2)
        saneIntersections (_  , Left (HitStartPoint _ _)) (_   , Left (HitEndPoint   _ _))  _                                = Nothing
        saneIntersections  _                              (_   , Left (HitEndPoint   _ _)) (_    , Left (HitStartPoint _ _)) = Nothing
        saneIntersections (seg, Left (HitEndPoint   _ _)) (seg2, Left (HitStartPoint _ _))  _                                = Just (seg, Just seg2)
        saneIntersections l1 l2 l3 = error $ "insane result of saneIntersections:\n" <> show l1 <> "\n" <> show l2 <> "\n" <> show l3 <> "\n"

-- | take a straight skeleton, and create faces from it.
-- If you have a line segment you want the first face to contain, supply it for a re-order.
facesFromStraightSkeleton :: StraightSkeleton -> Maybe LineSeg -> [Face]
facesFromStraightSkeleton (StraightSkeleton nodeLists spine) maybeStart
  | null spine && length nodeLists == 1 = findFaces (head nodeLists) maybeStart
  | otherwise                           = error "cannot yet handle spines, or more than one NodeList."
  where
    -- find all of the faces of a set of nodeTrees.
    findFaces :: [NodeTree] -> Maybe LineSeg -> [Face]
    findFaces nodeTrees maybeStartSeg
      | null nodeTrees = []
      | length nodeTrees == 1 && lastOutOf (head nodeTrees) == Nothing && maybeStartSeg == Nothing = rawFaces
      | length nodeTrees == 1 && lastOutOf (head nodeTrees) == Nothing                             = facesFromIndex (fromJust maybeStartSeg)
      | length nodeTrees > 1 && maybeStartSeg == Nothing = rawFaces
      | length nodeTrees > 1                             = facesFromIndex (fromJust maybeStartSeg)
      | otherwise            = error $ "abandon hope!\n" <> show (length nodeLists) <> "\n" <> show nodeLists <> "\n" <> show (length nodeTrees) <> "\n" <> show nodeTrees <> "\n" <> show rawFaces <> "\n"
      where
        lastOutOf :: NodeTree -> Maybe PLine2
        lastOutOf (NodeTree nodeGens) = (\(Node _ a) -> a) (head $ last nodeGens)
        rawFaces = (findFacesRecurse nodeTrees) ++
                   if length nodeTrees > 1 then [intraNodeFace (last nodeTrees) (head nodeTrees)] else []
        facesFromIndex :: LineSeg -> [Face]
        facesFromIndex target = take (length rawFaces) $ dropWhile (\(Face a _ _ _) -> a /= target) $ rawFaces ++ rawFaces
        -- Recursively find faces.
        findFacesRecurse []               = []
        findFacesRecurse (tree1:[])       = facesOfNodeTree tree1
        findFacesRecurse (tree1:tree2:[]) = facesOfNodeTree tree2 ++ (intraNodeFace tree1 tree2: facesOfNodeTree tree1)
        findFacesRecurse (tree1:tree2:xs) = findFacesRecurse (tree2:xs) ++ (intraNodeFace tree1 tree2: facesOfNodeTree tree1)
        -- Create a single face for the space between two nodetrees.
        intraNodeFace :: NodeTree -> NodeTree -> Face
        intraNodeFace nodeTree1 nodeTree2
          | nodeTree1 == nodeTree2          = error $ "two identical nodes given.\n" <> show nodeTree1 <> "\n"
          | nodeTree1 `isRightOf` nodeTree2 = if (last $ leftPLinesOf nodeTree2) == (last $ rightPLinesOf nodeTree1)
                                              then Face (rightSegOf nodeTree1) (outOf $ leftNodeOf nodeTree2) ((init $ leftPLinesOf nodeTree2) ++ (tail $ reverse $ init $ rightPLinesOf nodeTree1)) (outOf $ rightNodeOf nodeTree1)
                                              else Face (rightSegOf nodeTree1) (outOf $ leftNodeOf nodeTree2) ((init $ leftPLinesOf nodeTree2) ++ (       reverse $ init $ rightPLinesOf nodeTree1)) (outOf $ rightNodeOf nodeTree1)
          | nodeTree1 `isLeftOf` nodeTree2  = if (last $ rightPLinesOf nodeTree1) == (last $ leftPLinesOf nodeTree2)
                                              then Face (rightSegOf nodeTree2) (outOf $ leftNodeOf nodeTree1) ((init $ rightPLinesOf nodeTree1) ++ (tail $ reverse $ init $ leftPLinesOf nodeTree2)) (outOf $ rightNodeOf nodeTree2)
                                              else Face (rightSegOf nodeTree2) (outOf $ leftNodeOf nodeTree1) ((init $ rightPLinesOf nodeTree1) ++ (       reverse $ init $ leftPLinesOf nodeTree2)) (outOf $ rightNodeOf nodeTree2)
          | otherwise = error $ "merp.\n" <> show nodeTree1 <> "\n" <> show nodeTree2 <> "\n" 
          where
            isLeftOf :: NodeTree -> NodeTree -> Bool
            isLeftOf nt1 nt2 = leftSegOf nt1 == rightSegOf nt2
            isRightOf :: NodeTree -> NodeTree -> Bool
            isRightOf nt1 nt2 = rightSegOf nt1 == leftSegOf nt2
            rightSegOf :: NodeTree -> LineSeg
            rightSegOf nodeTree = (\(Node (Left (_,outSeg)) _) -> outSeg) $ (rightNodeOf nodeTree)
            rightNodeOf :: NodeTree -> Node
            rightNodeOf (NodeTree nodeSets) = snd $ pathRight nodeSets (head $ last nodeSets)
            rightPLinesOf :: NodeTree -> [PLine2]
            rightPLinesOf (NodeTree nodeSets) = fst $ pathRight nodeSets (head $ last nodeSets)
            leftSegOf :: NodeTree -> LineSeg
            leftSegOf nodeTree = (\(Node (Left (outSeg,_)) _) -> outSeg) $ (leftNodeOf nodeTree)
            leftNodeOf :: NodeTree -> Node
            leftNodeOf (NodeTree nodeSets) = snd $ pathLeft nodeSets (head $ last nodeSets)
            leftPLinesOf :: NodeTree -> [PLine2]
            leftPLinesOf (NodeTree nodeSets) = fst $ pathLeft nodeSets (head $ last nodeSets)
            -- | Find all of the PLines between this node, and the node that is part of the original contour.
            --   When branching, use the 'left' branch, which should be the first pline in a given node.
            pathLeft :: [[Node]] -> Node -> ([PLine2], Node)
            pathLeft nodeSets target@(Node (Left _) (Just plineOut)) = ([plineOut], target)
            pathLeft nodeSets target@(Node (Right plinesIn) plineOut)
              | isJust plineOut     = ((fromJust plineOut):childPlines, endNode)
              | plineOut == Nothing = (                    childPlines, endNode)
              where
                (childPlines, endNode) = pathLeft (tail nodeSets) (findNodeByOutput (head nodeSets) $ head plinesIn)
            -- | Find all of the PLines between this node, and the node that is part of the original contour.
            --   When branching, use the 'right' branch, which should be the last pline in a given node.
            pathRight :: [[Node]] -> Node -> ([PLine2], Node)
            pathRight nodeSets target@(Node (Left _) (Just plineOut)) = ([plineOut], target)
            pathRight nodeSets target@(Node (Right plinesIn) plineOut)
              | isJust plineOut     = ((fromJust plineOut):childPlines, endNode)
              | plineOut == Nothing = (                    childPlines, endNode)
              where
                (childPlines, endNode) = pathRight (tail nodeSets) (findNodeByOutput (head nodeSets) $ last plinesIn)
            outOf :: Node -> PLine2
            outOf (Node _ (Just a)) = a
            outOf a@(Node _ _) = error $ "could not find outOf of a node: " <> show a <> "\n"
    -- | Create a set of faces from a nodetree.
    -- FIXME: doesn't handle more than one generation deep, yet.
    facesOfNodeTree :: NodeTree -> [Face]
    facesOfNodeTree (NodeTree allNodeSets)
      | length allNodeSets > 1 = areaBeneath (init allNodeSets) (head $ last allNodeSets)
      | otherwise = []
      where
        areaBeneath :: [[Node]] -> Node -> [Face]
        areaBeneath nodeSets target@(Node (Right inArcs) outArc)
          | length nodeSets == 1 && isJust outArc     = init $ mapWithFollower makeTriangleFace $ findNodeByOutput (head nodeSets) <$> inArcs
          | length nodeSets == 1 && outArc == Nothing =        mapWithFollower makeTriangleFace $ findNodeByOutput (head nodeSets) <$> inArcs
        areaBeneath _ target@(Node (Left _) _) = error $ "cannot find the area beneath an initial node: " <> show target <> "\n"
        -- | make a triangle shaped face from two nodes. the nodes must be composed of line segments on one side, and follow each other.
        makeTriangleFace :: Node -> Node -> Face
        makeTriangleFace (Node (Left (seg1,seg2)) (Just pline1)) (Node (Left (seg3,seg4)) (Just pline2))
          | seg2 == seg3 = Face seg2 pline2 [] pline1
          | seg1 == seg4 = Face seg1 pline1 [] pline2
          | otherwise = error "cannot make a triangular face from nodes that are not neighbors."
        makeTriangleFace _ _ = error "cannot make a triangular face from nodes that are not first generation."
    findNodeByOutput :: [Node] -> PLine2 -> Node
    findNodeByOutput nodes plineOut = head $ filter (\(Node _ a) -> a == Just plineOut) nodes

-- | Place line segments on a face. Might return remainders, in the form of one or multiple un-filled faces.
addLineSegs :: ℝ -> Maybe Fastℕ -> Face -> ([LineSeg], Maybe [Face])
addLineSegs lw n face@(Face edge firstArc midArcs lastArc)
  | null midArcs        = (                    foundLineSegs, twoSideRemainder)
  | length midArcs == 1 = (        subSides ++ foundLineSegs, threeSideRemainder)
  | otherwise           = (sides1 ++ sides2 ++ foundLineSegs, nSideRemainder)

  where
    -----------------------------------------------------------------------------------------
    -- functions that are the same, regardless of number of sides of the ngon we are filling.
    -----------------------------------------------------------------------------------------

    -- | The direction we need to translate our edge in order for it to be going inward.
    translateDir v         = if Just True == pLineIsLeft (eToPLine2 edge) firstArc then (-v) else v

    -- | How many lines we are going to place in this Face.
    linesToRender          = if isJust n then min linesUntilEnd $ fromJust n else linesUntilEnd

    -- | The line segments we are placing.
    foundLineSegs          = [ errorIfLeft $ lineSegFromEndpoints (pToEPoint2 $ intersectionOf newSide firstArc) (pToEPoint2 $ intersectionOf newSide lastArc) | newSide <- newSides ]
      where
        newSides = [ translatePerp (eToPLine2 edge) $ translateDir ((lw/2)+(lw * fromIntegral segmentNum)) | segmentNum <- [0..linesToRender-1] ]

    -- | The line where we are no longer able to fill this face. from the firstArc to the lastArc, along the point that the lines we place stop.
    finalSide              = errorIfLeft $ lineSegFromEndpoints (pToEPoint2 $ intersectionOf finalLine firstArc) (pToEPoint2 $ intersectionOf finalLine lastArc)
      where
        finalLine = translatePerp (eToPLine2 edge) $ translateDir (lw * fromIntegral linesToRender)
    -- | how many lines can be fit in this Face.
    linesUntilEnd :: Fastℕ
    linesUntilEnd          = floor (distanceUntilEnd / lw)

    -- | what is the distance from the edge to the place we can no longer place lines.
    distanceUntilEnd
      | length midArcs >1  = closestArcDistance
      | length midArcs==1  = if firstArcLonger
                             then distancePPointToPLine (intersectionOf firstArc midArc) (eToPLine2 edge)
                             else distancePPointToPLine (intersectionOf midArc lastArc) (eToPLine2 edge)
      | otherwise          = distancePPointToPLine (intersectionOf firstArc lastArc) (eToPLine2 edge)

    -- | Generate an error if a line segment fails to construct.
    errorIfLeft :: Either LineSegError LineSeg -> LineSeg
    errorIfLeft lnSeg      = case lnSeg of
      Left (LineSegFromPoint point) -> error $ "tried to construct a line segment from two identical points: " <> show point <> "\n"
      Right                 lineSeg -> lineSeg
      _                             -> error "unknown error"

    -----------------------------------------------------------
    -- functions only used by n-gons with more than four sides.
    -----------------------------------------------------------
    nSideRemainder
      | isJust remains1 && isJust remains2 = Just $ (fromJust remains1) ++ (fromJust remains2)
      | isJust remains1                    = remains1
      | isJust remains2                    = remains2
      | otherwise                          = error "impossible!"
    -- | Find the closest point where two of our arcs intersect, relative to our side.
    arcIntersections = init $ mapWithFollower (\a b -> (distancePPointToPLine (intersectionOf a b) (eToPLine2 edge), (a, b))) $ [firstArc] ++ midArcs ++ [lastArc]
    findClosestArc :: (ℝ, (PLine2, PLine2))
    findClosestArc         = head $ sortOn (\(a,_) -> a) arcIntersections
    closestArcDistance     = (\(a,_) -> a) findClosestArc
    closestArc             = (\(_,(b,_)) -> b) findClosestArc
    closestArcFollower     = (\(_,(_,c)) -> c) findClosestArc
    -- Return all of the arcs before and including the closest arc.
    untilArc               = if closestArc == firstArc
                             then [firstArc]
                             else fst $ break (== closestArcFollower) $ midArcs ++ [lastArc]
    afterArc               = snd $ break (== closestArcFollower) $ midArcs ++ [lastArc]
    (sides1, remains1)     = if closestArc == firstArc
                             then ([],Nothing)
                             else addLineSegs lw n (Face finalSide firstArc (tail $ init untilArc) closestArc)
    (sides2, remains2)     = if closestArc == last midArcs
                             then ([],Nothing)
                             else addLineSegs lw n (Face finalSide (head afterArc) (init $ tail afterArc) lastArc)
    ---------------------------------------------
    -- functions only used by a four-sided n-gon.
    ---------------------------------------------
    midArc
      | length midArcs==1  = head midArcs
      | otherwise          = error $ "evaluated midArc with the wrong number of items\nlw: " <> show lw <> "\nn: " <> show n <> "\nFace: " <> show face <> "\n"
    threeSideRemainder     = if distancePPointToPLine (intersectionOf firstArc midArc) (eToPLine2 edge) /= distancePPointToPLine (intersectionOf midArc lastArc) (eToPLine2 edge)
                             then subRemains
                             else Nothing
    (subSides, subRemains) = if firstArcLonger
                             then addLineSegs lw n (Face finalSide firstArc [] midArc)
                             else addLineSegs lw n (Face finalSide midArc   [] lastArc)
    firstArcLonger         = distancePPointToPLine (intersectionOf firstArc midArc) (eToPLine2 edge) > distancePPointToPLine (intersectionOf midArc lastArc) (eToPLine2 edge)
    ----------------------------------------------
    -- functions only used by a three-sided n-gon.
    ----------------------------------------------
    twoSideRemainder       = if lw * fromIntegral linesUntilEnd /= distanceUntilEnd
                             then Just [Face finalSide firstArc [] lastArc]
                             else Nothing

-- | Add infill to the area of a set of faces that was not covered in lines.
-- FIXME: unimplemented. basically, take the contour formed by the remainders of the faces, and squeeze in a line segment, if possible.
addInfill :: [Face] -> [[Face]] -> ℝ -> InfillType -> [[LineSeg]]
addInfill outsideFaces insideFaceSets lineSpacing layerType = makeInfill (facesToContour outsideFaces) (facesToContour <$> insideFaceSets) lineSpacing layerType
  where
    facesToContour faces = error "fixme!"

-- | Get the intersection point of two lines we know have an intersection point.
intersectionOf :: PLine2 -> PLine2 -> PPoint2
intersectionOf pl1 pl2 = saneIntersection $ plinesIntersectIn pl1 pl2
  where
    saneIntersection res@PCollinear        = error $ "impossible!\n" <> show res <> "\npl1: " <> show pl1 <> "\npl2: " <> show pl2 <> "\n" 
    saneIntersection res@PParallel        = error $ "impossible!\n" <> show res <> "\npl1: " <> show pl1 <> "\npl2: " <> show pl2 <> "\n" 
    saneIntersection res@PAntiParallel    = error $ "impossible!\n" <> show res <> "\npl1: " <> show pl1 <> "\npl2: " <> show pl2 <> "\n" 
    saneIntersection (IntersectsIn point) = point
