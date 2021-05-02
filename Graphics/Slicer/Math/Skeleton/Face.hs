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

-- inherit instances when deriving.
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE DerivingStrategies #-}

{-
 - This file contains two things that should probably be in separate files:
 - Code for creating a series of faces, covering a straight skeleton.
 - Code for taking a series of faces, and applying inset line segments and infill to them.
 -}
module Graphics.Slicer.Math.Skeleton.Face (Face(Face), addLineSegsToFace, facesFromStraightSkeleton, addInfill) where

import Prelude ((==), otherwise, (<$>), ($), length, Show, (/=), error, (<>), show, Eq, Show, (<>), (<), (/), floor, fromIntegral, Either(Left, Right), (+), (*), (-), (++), (>), min, Bool(True), head, (&&), (||), fst, take, filter, init, null, tail, last, concat, not, reverse, maybe)

import Data.List (sortOn, dropWhile, takeWhile)

import Data.Maybe( Maybe(Just,Nothing), isJust, fromJust, isNothing)

import Graphics.Slicer.Math.Definitions (mapWithFollower)

import Graphics.Slicer.Math.Line (LineSeg, lineSegFromEndpoints, LineSegError(LineSegFromPoint))

import Graphics.Slicer.Math.Skeleton.Definitions (StraightSkeleton(StraightSkeleton), ENode(ENode), INode(INode), NodeTree(NodeTree), Arcable(hasArc, outOf), intersectionOf)

import Graphics.Slicer.Math.PGA (distancePPointToPLine, pToEPoint2, PLine2, eToPLine2, translatePerp, pLineIsLeft)

import Graphics.Slicer.Machine.Infill (makeInfill, InfillType)

import Graphics.Implicit.Definitions (ℝ, Fastℕ)

--------------------------------------------------------------------
-------------------------- Face Placement --------------------------
--------------------------------------------------------------------

-- | A Face:
--   A portion of a contour, with a real side, and arcs (line segments between nodes) dividing it from other faces.
--   Faces have no holes, and their arcs and nodes (line segments and points) are generated from a StraightSkeleton of a Contour.
data Face = Face { _edge :: LineSeg, _firstArc :: PLine2, _arcs :: [PLine2], _lastArc :: PLine2 }
  deriving Eq
  deriving stock Show

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
      | length nodeTrees == 1 && isNothing (lastOutOf $ head nodeTrees) && isNothing maybeStartSeg = rawFaces
      | length nodeTrees == 1 && isNothing (lastOutOf $ head nodeTrees)                            = facesFromIndex (fromJust maybeStartSeg)
      | length nodeTrees > 1  && isNothing maybeStartSeg                                              = rawFaces
      | length nodeTrees > 1                                                                          = facesFromIndex (fromJust maybeStartSeg)
      | otherwise            = error $ "abandon hope!\n" <> show (length nodeLists) <> "\n" <> show nodeLists <> "\n" <> show (length nodeTrees) <> "\n" <> show nodeTrees <> "\n" <> show rawFaces <> "\n"
      where
        rawFaces = findFacesRecurse nodeTrees ++
                   if length nodeTrees > 1 then [intraNodeFace (last nodeTrees) (head nodeTrees)] else []
        facesFromIndex :: LineSeg -> [Face]
        facesFromIndex target = take (length rawFaces) $ dropWhile (\(Face a _ _ _) -> a /= target) $ rawFaces ++ rawFaces
        -- Recursively find faces.
        findFacesRecurse :: [NodeTree] -> [Face]
        findFacesRecurse []               = []
        findFacesRecurse [tree1]          = facesOfNodeTree tree1
        findFacesRecurse [tree1,tree2]    = facesOfNodeTree tree2 ++ (intraNodeFace tree1 tree2 : facesOfNodeTree tree1)
        findFacesRecurse (tree1:tree2:xs) = findFacesRecurse (tree2:xs) ++ (intraNodeFace tree1 tree2 : facesOfNodeTree tree1)
        -- Create a single face for the space between two NodeTrees. like areaBetween, but for two separate NodeTrees.
        intraNodeFace :: NodeTree -> NodeTree -> Face
        intraNodeFace newNodeTree1 newNodeTree2
          | newNodeTree1 == newNodeTree2          = error $ "two identical nodes given.\n" <> show newNodeTree1 <> "\n"
          | newNodeTree1 `isRightOf` newNodeTree2 = if last (firstPLinesOf newNodeTree2) == last (lastPLinesOf newNodeTree1)
                                              then makeFace (lastENodeOf newNodeTree2) (init (firstPLinesOf newNodeTree2) ++ tail (reverse $ init $ lastPLinesOf newNodeTree1)) (firstENodeOf newNodeTree1)
                                              else makeFace (lastENodeOf newNodeTree2) (init (firstPLinesOf newNodeTree2) ++       reverse  (init $ lastPLinesOf newNodeTree1)) (firstENodeOf newNodeTree1)
          | newNodeTree1 `isLeftOf` newNodeTree2  = if last (lastPLinesOf newNodeTree1) == last (firstPLinesOf newNodeTree2)
                                              then makeFace (firstENodeOf newNodeTree1) (init (lastPLinesOf newNodeTree1) ++ tail (reverse $ init $ firstPLinesOf newNodeTree2)) (lastENodeOf newNodeTree2)
                                              else makeFace (firstENodeOf newNodeTree1) (init (lastPLinesOf newNodeTree1) ++       reverse  (init $ firstPLinesOf newNodeTree2)) (lastENodeOf newNodeTree2)
          | otherwise = error $ "merp.\n" <> show newNodeTree1 <> "\n" <> show newNodeTree2 <> "\n" 
          where
            isLeftOf :: NodeTree -> NodeTree -> Bool
            isLeftOf nt1 nt2 = firstSegOf nt1 == lastSegOf nt2
            isRightOf :: NodeTree -> NodeTree -> Bool
            isRightOf nt1 nt2 = lastSegOf nt1 == firstSegOf nt2
            lastSegOf :: NodeTree -> LineSeg
            lastSegOf nodeTree = (\(ENode (_,outSeg) _) -> outSeg) (lastENodeOf nodeTree)
            firstSegOf :: NodeTree -> LineSeg
            firstSegOf nodeTree = (\(ENode (outSeg,_) _) -> outSeg) (firstENodeOf nodeTree)
            lastENodeOf :: NodeTree -> ENode
            lastENodeOf nodeTree = (\(_,_,c) -> c) $ pathLast nodeTree
            firstENodeOf :: NodeTree -> ENode
            firstENodeOf nodeTree = (\(_,_,c) -> c) $ pathFirst nodeTree
            lastPLinesOf :: NodeTree -> [PLine2]
            lastPLinesOf nodeTree = (\(a,_,_) -> a) $ pathLast nodeTree
            firstPLinesOf :: NodeTree -> [PLine2]
            firstPLinesOf nodeTree = (\(a,_,_) -> a) $ pathFirst nodeTree

        -- | Create a set of faces from a nodetree.
        -- FIXME: doesn't handle more than one generation deep, yet.
        facesOfNodeTree :: NodeTree -> [Face]
        facesOfNodeTree newNodeTree@(NodeTree myENodes myINodeSets)
          | null myINodeSets = []
          | otherwise = areaBeneath myENodes (init myINodeSets) $ latestINodeOf newNodeTree
          where
            -- cover the space occupied by all of the ancestors of this node with a series of faces.
            areaBeneath :: [ENode] -> [[INode]] -> INode -> [Face]
            areaBeneath eNodes iNodeSets target@(INode (inArcs) _)
              | null iNodeSets && hasArc target              = init $ mapWithFollower makeTriangleFace $ findENodeByOutput eNodes <$> inArcs
              | null iNodeSets                               =        mapWithFollower makeTriangleFace $ findENodeByOutput eNodes <$> inArcs
              | length iNodeSets == 1 && not (hasArc target) = concat $ mapWithFollower (\a b -> areaBeneath eNodes (init iNodeSets) a ++ [areaBetween eNodes (init iNodeSets) target a b]) (head iNodeSets)
              | otherwise                                    = error $ "areabeneath: " <> show iNodeSets <> "\n" <> show target <> "\n" <> show (length iNodeSets) <> "\n"
              where
                -- | make a face from two nodes. the nodes must be composed of line segments on one side, and follow each other.
                makeTriangleFace :: ENode -> ENode -> Face
                makeTriangleFace node1 node2 = makeFace node1 [] node2

            -- cover the space between the last path of the first node and the first path of the second node with a single Face. It is assumed that both nodes have the same parent.
            areaBetween :: [ENode] -> [[INode]] -> INode -> INode -> INode -> Face
            areaBetween eNodes iNodeSets parent iNode1 iNode2
              | null iNodeSets = if (lastDescendent eNodes (iNode1)) /= (last eNodes) -- Handle the case where we are creating a face across the open end of the contour.
                                 then makeFace (lastDescendent eNodes iNode1) [lastPLineOf parent] (findMatchingDescendent eNodes iNode2 $ lastDescendent eNodes iNode1)
                                 else makeFace (firstDescendent eNodes iNode1) [firstPLineOf parent] (findMatchingDescendent eNodes iNode2 $ firstDescendent eNodes iNode1)
              | otherwise = error $
                               show iNode1 <> "\n" <> show (findENodeByOutput eNodes (firstPLineOf iNode1)) <> "\n" <> show (findENodeByOutput eNodes(lastPLineOf iNode1)) <> "\n"
                            <> show iNode2 <> "\n" <> show (findENodeByOutput eNodes (firstPLineOf iNode2)) <> "\n" <> show (findENodeByOutput eNodes (lastPLineOf iNode2)) <> "\n"
                            <> show iNodeSets <> "\n"
              where
                -- find the first immediate child of the given node.
                firstDescendent :: [ENode] -> INode -> ENode
                firstDescendent myNodeSets myParent = findENodeByOutput myNodeSets $ firstPLineOf myParent

                -- find the last immediate child of the given node.
                lastDescendent :: [ENode] -> INode -> ENode
                lastDescendent myNodeSets myParent = findENodeByOutput myNodeSets $ lastPLineOf myParent

                -- | using the set of all first generation nodes, a second generation node, and a first generation node, find out which one of the first generation children of the given second generation node shares a side with the first generation node.
                findMatchingDescendent :: [ENode] -> INode -> ENode -> ENode
                findMatchingDescendent nodes myParent target@(ENode (seg1,seg2) _)
                  | length res == 1 = head res
                  | otherwise = error $ show nodes <> "\n" <> show myParent <> "\n" <> show target <> "\n" <> show (firstDescendent nodes myParent) <> "\n" <> show (lastDescendent nodes myParent) <> "\n" <> show res <> "\n"
                  where
                    res = filter (\(ENode (sseg1, sseg2) _) -> sseg2 == seg1 || sseg1 == seg2) [firstDescendent nodes myParent, lastDescendent nodes myParent]

                firstPLineOf :: INode -> PLine2
                firstPLineOf (INode [] _) = error "empty iNode?"
                firstPLineOf (INode (a:_) _) = a
                lastPLineOf :: INode -> PLine2
                lastPLineOf (INode plines _)
                  | null plines = error "empty PLines?"
                  | otherwise   = last plines

    -- | in a NodeTree, the last generation is always a single item. retrieve this item.
    latestINodeOf :: NodeTree -> INode
    latestINodeOf (NodeTree _ iNodeSets) = head $ last iNodeSets

    -- | get the last output PLine of a NodeTree, if there is one. otherwise, Nothing.
    lastOutOf :: NodeTree -> Maybe PLine2
    lastOutOf newNodeTree = (\(INode _ outArc) -> outArc) $ latestINodeOf newNodeTree

    -- FIXME: merge pathFirst and pathLast. they differ by only one line.
    -- | Find all of the Nodes and all of the arcs between the last of the nodeTree and the node that is part of the original contour.
    --   When branching, follow the last PLine in a given node.
    pathFirst :: NodeTree -> ([PLine2], [INode], ENode)
    pathFirst newNodeTree@(NodeTree eNodes iNodeSets)
      | null iNodeSets  = ([outOf (last eNodes)], [], last eNodes)
      | otherwise = pathFirstInner (init iNodeSets) eNodes (latestINodeOf newNodeTree)
      where
        pathFirstInner :: [[INode]] -> [ENode] -> INode -> ([PLine2], [INode], ENode)
        pathFirstInner myINodeSets myENodes target@(INode (plinesIn) _)
          | hasArc target = (outOf target : childPlines, target: endNodes, finalENode)
          | otherwise     = (               childPlines, target: endNodes, finalENode)
          where
            pLineToFollow = head plinesIn
            (childPlines, endNodes, finalENode)
              | length myINodeSets < 2 = ([outOf $ findENodeByOutput myENodes pLineToFollow], [], findENodeByOutput myENodes pLineToFollow)
              | otherwise              = pathFirstInner (init myINodeSets) myENodes (findINodeByOutput (init myINodeSets) pLineToFollow)

    -- | Find all of the Nodes and all of the arcs between the last of the nodeTree and the node that is part of the original contour.
    --   When branching, follow the last PLine in a given node.
    pathLast :: NodeTree -> ([PLine2], [INode], ENode)
    pathLast newNodeTree@(NodeTree eNodes iNodeSets)
      | null iNodeSets  = ([outOf (last eNodes)], [], last eNodes)
      | otherwise = pathLastInner (init iNodeSets) eNodes (latestINodeOf newNodeTree)
      where
        pathLastInner :: [[INode]] -> [ENode] -> INode -> ([PLine2], [INode], ENode)
        pathLastInner myINodeSets myENodes target@(INode (plinesIn) _)
          | hasArc target = (outOf target : childPlines, target: endNodes, finalENode)
          | otherwise     = (               childPlines, target: endNodes, finalENode)
          where
            pLineToFollow = last plinesIn
            (childPlines, endNodes, finalENode)
              | length myINodeSets < 2 = ([outOf $ findENodeByOutput myENodes pLineToFollow], [], findENodeByOutput myENodes pLineToFollow)
              | otherwise              = pathLastInner (init myINodeSets) myENodes (findINodeByOutput (init myINodeSets) pLineToFollow)

    -- | Find a node with an output of the PLine given. start at the most recent generation, and check backwards.
    findINodeByOutput :: [[INode]] -> PLine2 -> INode
    findINodeByOutput iNodeSets plineOut
      | null iNodeSets             = error "could not find inode. empty set?"
      | length iNodesInThisGen == 1 = head iNodesInThisGen
      | length iNodeSets > 1 &&
        null iNodesInThisGen       = findINodeByOutput (init iNodeSets) plineOut
      | null iNodesInThisGen       = error $ "could not find inode.\n" <> show iNodeSets <> "\n" <> show plineOut <> "\n"
      | otherwise                  = error "more than one node in a given generation with the same PLine out!"
      where
        iNodesInThisGen = filter (\(INode _ a) -> a == Just plineOut) (last iNodeSets)

    -- | Find an exterior Node with an output of the PLine given.
    findENodeByOutput :: [ENode] -> PLine2 -> ENode
    findENodeByOutput eNodes plineOut
      | null eNodes               = error "could not find enode. empty set?"
      | length nodesMatching == 1 = head nodesMatching
      | null nodesMatching        = error "could not find exterior node."
      | otherwise                 = error "more than one exterior node with the same PLine out!"
      where
        nodesMatching = filter (\(ENode _ a) -> a == plineOut) eNodes

    -- | make a face from two nodes, and a set of arcs. the nodes must be composed of line segments on one side, and follow each other.
    makeFace :: ENode -> [PLine2] -> ENode -> Face
    makeFace node1@(ENode (seg1,seg2) pline1) arcs node2@(ENode (seg3,seg4) pline2)
      | seg2 == seg3 = Face seg2 pline2 arcs pline1
      | seg1 == seg4 = Face seg1 pline1 arcs pline2
      | otherwise = error $ "cannot make a face from nodes that are not neighbors: \n" <> show node1 <> "\n" <> show node2 <> "\n"

------------------------------------------------------------------
------------------ Line Segment Placement ------------------------
------------------------------------------------------------------

-- | Place line segments on a face. Might return remainders, in the form of one or multiple un-filled faces.
addLineSegsToFace :: ℝ -> Maybe Fastℕ -> Face -> ([LineSeg], Maybe [Face])
addLineSegsToFace lw n face@(Face edge firstArc midArcs lastArc)
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
    linesToRender          = maybe linesUntilEnd (min linesUntilEnd) n

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
      | isJust remains1 && isJust remains2 = Just $ fromJust remains1 ++ fromJust remains2
      | isJust remains1                    = remains1
      | isJust remains2                    = remains2
      | otherwise                          = error "impossible!"
    -- | Find the closest point where two of our arcs intersect, relative to our side.
    arcIntersections = init $ mapWithFollower (\a b -> (distancePPointToPLine (intersectionOf a b) (eToPLine2 edge), (a, b))) $ [firstArc] ++ midArcs ++ [lastArc]
    findClosestArc :: (ℝ, (PLine2, PLine2))
    findClosestArc         = head $ sortOn fst arcIntersections
    closestArcDistance     = fst findClosestArc
    closestArc             = (\(_,(b,_)) -> b) findClosestArc
    closestArcFollower     = (\(_,(_,c)) -> c) findClosestArc
    -- Return all of the arcs before and including the closest arc.
    untilArc               = if closestArc == firstArc
                             then [firstArc]
                             else takeWhile (/= closestArcFollower) $ midArcs ++ [lastArc]
    afterArc               = dropWhile (/= closestArcFollower) $ midArcs ++ [lastArc]
    (sides1, remains1)     = if closestArc == firstArc
                             then ([],Nothing)
                             else addLineSegsToFace lw n (Face finalSide firstArc (tail $ init untilArc) closestArc)
    (sides2, remains2)     = if closestArc == last midArcs
                             then ([],Nothing)
                             else addLineSegsToFace lw n (Face finalSide (head afterArc) (init $ tail afterArc) lastArc)
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
                             then addLineSegsToFace lw n (Face finalSide firstArc [] midArc)
                             else addLineSegsToFace lw n (Face finalSide midArc   [] lastArc)
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
addInfill outsideFaces insideFaceSets = makeInfill (facesToContour outsideFaces) (facesToContour <$> insideFaceSets)
  where
    facesToContour faces = error "fixme!"

