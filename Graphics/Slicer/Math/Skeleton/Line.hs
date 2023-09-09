{- ORMOLU_DISABLE -}
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
{-# LANGUAGE DerivingStrategies #-}

-- | Functions for for applying inset line segments to a series of faces, and for adding infill to a face.
module Graphics.Slicer.Math.Skeleton.Line (insetBy, insetMany, infiniteInset) where

import Prelude (Eq, Integer, Show, (==), all, concat, max, otherwise, (<$>), (<=), (&&), (||), ($), (/=), error, (<>), show, (<>), (/), floor, fromIntegral, (*), (-), (.), (<>), (>), (<), min, Bool(True, False), filter, fst, maybe, mempty, null, snd)

import Data.Either (isRight)

import Data.List (dropWhile, init, intercalate, last, length, nub, sortOn, tail, takeWhile, transpose)

import Data.List.Extra (unsnoc)

import Data.Maybe (Maybe(Just,Nothing), catMaybes, fromMaybe, fromJust, isJust, isNothing, mapMaybe)

import Slist (head, isEmpty, len, slist)

import Slist.Type (Slist(Slist))

import Graphics.Slicer.Math.Contour (makePointContour)

import Graphics.Slicer.Math.Definitions (Contour, LineSeg, Point2, distance, mapWithFollower, endPoint, makeLineSeg, startPoint)

import Graphics.Slicer.Math.Ganja (dumpGanja)

import Graphics.Slicer.Math.GeometricAlgebra (ulpVal)

import Graphics.Slicer.Math.Intersections (intersectionBetween, intersectionOf, isAntiParallel, noIntersection)

import Graphics.Slicer.Math.Skeleton.Face (Face(Face))

import Graphics.Slicer.Math.Lossy (distancePPointToPLineWithErr, pToEPoint2)

import Graphics.Slicer.Math.PGA (PIntersection (IntersectsIn, PAntiCollinear, PAntiParallel, PCollinear, PParallel), PLine2Err, PPoint2Err, ProjectiveLine, ProjectiveLine2, ProjectivePoint, distance2PP, eToPL, fuzzinessOfP, normalizeL, pLineErrAtPPoint, plinesIntersectIn, pLineIsLeft, pToEP, translateL)

import Graphics.Slicer.Machine.Contour (cleanContour)

import Graphics.Implicit.Definitions (ℝ, Fastℕ)

------------------------------------------------------------------
------------------ Line Segment Placement ------------------------
------------------------------------------------------------------

data InsetLine = InsetLine { _segment :: LineSeg, _insetLine :: (ProjectiveLine, PLine2Err), _insetStart :: (ProjectivePoint, PPoint2Err), _insetStop :: (ProjectivePoint, PPoint2Err) }
  deriving (Eq, Show)

-- Provide just the segment of an InsetLine.
segmentFrom :: InsetLine -> LineSeg
segmentFrom (InsetLine seg _ _ _) = seg

-- Provide the Line of an InsetLine
lineFrom :: InsetLine -> (ProjectiveLine, PLine2Err)
lineFrom (InsetLine _ line _ _) = line

-- Provide the projective start point of an InsetLine.
startFrom :: InsetLine -> (ProjectivePoint, PPoint2Err)
startFrom (InsetLine _ _ point _) = point

-- Provide the projective end point of an InsetLine.
endFrom :: InsetLine -> (ProjectivePoint, PPoint2Err)
endFrom (InsetLine _ _ _ point) = point

-- | Inset the given set of faces, returning new outside contours, and a new set of faces.
-- Requires the faces are a closed set, AKA, a set of faces created from a contour.
-- FIXME: handle inset requests that result in multiple contours.
insetBy :: ℝ -> Slist Face -> ([Contour], [Face])
insetBy distanceBetweenSegs faces
  -- no result? no resulting faces.
  | all null lineSegSets = mempty
  -- If we fail to inset, bail.
  | null contours = ([], [])
  -- there cannot be such a thing as 2 faces remaining.
  -- assume we passed the endpoints of all faces.
  | length remainingFaces < 3 = (contours, [])
  | otherwise = (contours, remainingFaces)
  where
    contours = reclaimContours lineSegSets
    lineSegSets = fst <$> res
    remainingFaces = concat $ mapMaybe snd res
    res = addInsetsToFace distanceBetweenSegs (Just 1) <$> (\(Slist a _) -> a) faces

-- | Inset a set of faces a number of times, returning new outside contours, and a new set of faces.
-- Requires the faces are a closed set, AKA, a set of faces created from a contour.
-- FIXME: handle inset requests that result in multiple contours.
insetMany :: ℝ -> Fastℕ -> Slist Face -> ([Contour], [Face])
insetMany distanceBetweenSegs count faces
  -- no result? no resulting faces.
  | all null lineSegSets = mempty
  -- If we fail to inset, bail.
  | null contours = ([], [])
  -- there cannot be such a thing as 2 faces remaining.
  -- assume we passed the endpoints of all faces.
  | length remainingFaces < 3 = (contours, [])
  | otherwise = (contours, remainingFaces)
  where
    contours = reclaimContours lineSegSets
    lineSegSets = fst <$> res
    remainingFaces = concat $ mapMaybe snd res
    res = addInsetsToFace distanceBetweenSegs (Just count) <$> (\(Slist a _) -> a) faces

-- FUTUREWORK: Add a function that takes the contour formed by the remainders of the faces, and squeezes in aline segment, if possible.

-- | Cover a contour with lines, aligned to the faces of the contour.
-- FIXME: this should be returning a ContourTree.
infiniteInset :: ℝ -> Slist Face -> [Contour]
infiniteInset distanceBetweenSegs faces
  -- no result? no resulting faces.
  | all null lineSegSets = mempty
  | length (concat lineSegSets) < 3 = error $ "less than three, but not zero?\n" <> show lineSegSets <> "\n"
  | otherwise = contours
  where
    contours = reclaimContours lineSegSets
    lineSegSets = fst <$> res
    res = addInsetsToFace distanceBetweenSegs Nothing <$> (\(Slist a _) -> a) faces

-- | Place line segments on a face, parallel to the edge. Might return remainders, in the form of un-filled faces.
-- FIXME: return a ((ProjectivePoint, PPoint2Err), (ProjectivePoint, PPoint2Err)) pair, so we can operate on it during contour reclamation without precision loss.
addInsetsToFace :: ℝ -> Maybe Fastℕ -> Face -> ([InsetLine], Maybe [Face])
addInsetsToFace distanceBetweenSegs insets face
  -- we were called, but instructed to do nothing.
  | isJust insets && fromJust insets < 1 = ([], Just [face])
  | len midArcs == 0 = (foundInsets, twoSideRemainder)
  | len midArcs == 1 = (foundInsets <> twoSideSubInsets, threeSideRemainder)
  | otherwise        = (foundInsets <> sides1 <> sides2, nSideRemainder)
  where
    -- | Run checks on our input face.
    checkedFace@(Face edge firstArc midArcs@(Slist rawMidArcs _) lastArc) = checkFace face
      where
        checkFace inFace@(Face myEdge myFirstArc (Slist myMidArcs _) myLastArc)
          | all (isRight . fromMaybe (error "wheee!")) intersections = inFace
          | otherwise = error $ "given a degenerate face: \n"
                             <> show face <> "\n"
                             <> show intersections <> "\n"
                             <> show insets <> "\n"
          where
            intersections = mapWithFollower intersectionBetween $ eToPL myEdge : myFirstArc : myMidArcs <> [myLastArc]
    edgeLine = eToPL edge

    -- | Subtract the line segments we place in this round from the input inset count.
    -- Used to determine if we should recurse.
    -- Just 0 or less == terminate, do not recurse.
    -- Nothing = recurse until we run out of space in the Face.
    subInsets = if isJust insets
                then Just $ fromJust insets - linesToPlace
                else Nothing

    -----------------------------------------------------------------------------------------
    -- functions that are the same, regardless of number of sides of the ngon we are filling.
    -----------------------------------------------------------------------------------------
    -- | The direction we need to translate our edge in order for it to be going inward.
    translateDir v         = case fst edgeLine `pLineIsLeft` fst firstArc of
                               (Just True) -> (-v)
                               (Just False) -> v
                               Nothing -> error $ "cannot happen: edge and firstArc do not intersect?\n"
                                               <> show distanceBetweenSegs <> "\n"
                                               <> show insets <> "\n"
                                               <> show face <> "\n"
                                               <> show (normalizeL $ fst edgeLine) <> "\n"
                                               <> show (normalizeL $ fst firstArc) <> "\n"
                                               <> show (plinesIntersectIn firstArc edgeLine) <> "\n"
                                               <> dumpGanja face <> "\n"

    -- | How many lines we are going to place in this recursion. If inset is Nothing, cover the face entirely.
    linesToPlace           = maybe availableLines (min availableLines) insets
      where
        availableLines     = linesUntilEnd distanceBetweenSegs checkedFace

    -- | The insets we are placing in this round.
    foundInsets            = catMaybes maybeFoundInsets
    maybeFoundInsets       = [ maybeMakeInset newSide (safeIntersectionOf newSide lastArc) (safeIntersectionOf newSide firstArc) | newSide <- newSides ]
      where
        newSides = [ translateL (fst edgeLine) $ translateDir (-distanceBetweenSegs * fromIntegral segmentNum) | segmentNum <- [1..linesToPlace] ]
        -- | Maybe make a line segment. Maybe not.
        -- Filters out the case where we try to construct an empty segment, EG: we have inset to the point we have only a point, not a line segment.
        maybeMakeInset l (a, aErr) (b, bErr)
          | (pToEPoint2 a) == (pToEPoint2 b) = Nothing
          | otherwise = Just $ InsetLine (makeLineSeg (pToEPoint2 a) (pToEPoint2 b)) l (a, aErr) (b, bErr)
        -- | A wrapper, for generating smart errors.
        safeIntersectionOf a b
          | noIntersection a b = error $ "given a non-intersecting pair of lines."
                                      <> show a <> "\n"
                                      <> show b <> "\n"
                                      <> show (plinesIntersectIn a b) <> "\n"
                                      <> showInputs
          | otherwise = intersectionOf a b

    -- | The line across which we are no longer able to fill this face, and must fill sub faces.
    finalLine               = lineFrom finalInset
    finalInset
      | null maybeFoundInsets = error $ "no insets placed.\n" <> showInputs <> show linesToPlace <> "\n" <> show (closestArcAndDistance checkedFace) <> "\n"
      | null foundInsets      = error "only inset placed was a point."
      | otherwise             = last foundInsets
    -- | Nothing if we placed no insets, otherwise Just the last inset placed.
    maybeFinalInset
      | null maybeFoundInsets = Nothing
      | otherwise           = last maybeFoundInsets

    -- | what to return when no result is necessary (we have run into the end of the face).
    noResult = ([],Nothing)

    -- | dump our inputs, in case of failure.
    showInputs = "edge: " <> show edge <> "\n"
              <> "firstArc: \n" <> show firstArc <> "\n"
              <> "midArcs: \n" <> show midArcs <> "\n"
              <> "lastArc: \n" <> show lastArc <> "\n"
    -----------------------------------------------------------
    -- functions only used by n-gons with more than four sides.
    -----------------------------------------------------------
    -- the remainder, or remainders, after lines have been placed.
    nSideRemainder
      | null foundInsets = Just [checkedFace]
      | isNothing subInsets = recurseRes
      | fromJust subInsets > 0 = Just [checkedFace]
      | otherwise = recurseRes
        where
          recurseRes = case fromMaybe [] remains1 <> fromMaybe [] remains2 of
                       [] -> error "no remains for an nSideRemainder?"
                       res -> Just res

    -- | The arc and the arc after it, that intersect in a point closest to the edge.
    (closestArc, closestArcFollower) = fst $ closestArcAndDistance checkedFace

    -- | Return all of the arcs before and including the closest arc.
    untilArc               = if closestArc == firstArc
                             then []
                             else takeWhile (/= closestArcFollower) $ rawMidArcs <> [lastArc]
    -- | Return all of the arcs after the closest arc.
    afterArc               = if closestArcFollower == lastArc
                             then []
                             else tail $ dropWhile (/= closestArcFollower) $ rawMidArcs <> [lastArc]

    (sides1, remains1)
      | closestArc == firstArc = noResult
      | otherwise              = nSideSubResult firstArc untilArc
    (sides2, remains2)
      | closestArcFollower == lastArc = noResult
      | otherwise              = nSideSubResult closestArcFollower afterArc

    -- | recurse, so we get the remainder and line segments of the remaining parts of the Face.
    nSideSubResult begin arcs
      | isNothing maybeFinalInset = noResult
      | otherwise = case unsnoc arcs of
                      Nothing -> error "unpossible!"
                      Just (myMidArcs, myLastArc) -> addInsetsToFace distanceBetweenSegs subInsets (makeFace 1 (segmentFrom finalInset) begin (slist myMidArcs) myLastArc)

    ---------------------------------------------
    -- functions only used by a four-sided n-gon.
    ---------------------------------------------
    -- Determine if this face has a remainder, if that remainder has three sides, or if the remainder has two sides.
    threeSideRemainder :: Maybe [Face]
    threeSideRemainder
      -- If we weren't anle to place a line segment, we're done.
      | null foundInsets = Nothing
      | otherwise = case plinesIntersectIn midArc lastPlacedLine of
                      -- always an error. our line segments are placed in the opposite direction as our midarc.
                      PCollinear -> error "a constructed line segment cannot be colinear with the midArc"
                      PParallel -> error "a constructed line segment cannot be parallel with the midArc"
                      -- FIXME: this should happen only when we have inset completely, and the edge and midArc are anti-parallel.
                      PAntiCollinear -> if isAntiParallel edgeLine midArc || edgeDistanceToLastPlacedInset < distanceUntilEnd checkedFace
                                        then Just [makeFaceNoCheck (segmentFrom finalInset) firstArc midArcs lastArc]
                                        else Nothing
{-
                                          error $ "anticollinear should not have happened.\n"<> "edge: " <> show edge <> "\n"
                                                     <> "distanceBetweenSegs: " <> show distanceBetweenSegs <> "\n"
                                                     <> "foundInsets: " <> show foundInsets <> "\n"
                                                     <> "midArc: " <> show midArc <> "\n"
                                                     <> "intersection of midArc and lastPlacedLine: " <> show (plinesIntersectIn midArc lastPlacedLine) <> "\n"
                                                     <> "maybeFinalLine: " <> show maybeFinalInset <> "\n"
                                                     <> showInputs
-}
                      -- these are natural, when edge and midArc are parallel..
                      PAntiParallel -> Just [makeFaceNoCheck (segmentFrom finalInset) firstArc midArcs lastArc]
                      _ -> Just [makeFaceNoCheck (segmentFrom finalInset) firstArc midArcs lastArc]

    -- Recurse, so we get the remainder and line segments of the three sided n-gon left over.
    (twoSideSubInsets, _)
      | null foundInsets = noResult
      | isNothing maybeFinalInset = noResult
      | otherwise          = case plinesIntersectIn midArc lastPlacedLine of
                               PCollinear -> noResult
                               PAntiCollinear -> noResult
                               _ -> if firstArcEndsFarthest edge firstArc (head midArcs) lastArc
                                    then if noIntersection midArc finalLine
                                         -- our triangle is so small, two sides are considered colinear. abort.
                                         then noResult
                                         else addInsetsToFace distanceBetweenSegs subInsets (makeFace 3 (segmentFrom finalInset) firstArc (slist []) midArc)
                                    else if noIntersection midArc finalLine
                                         -- our triangle is so small, two sides are considered colinear. abort.
                                         then noResult
                                         else addInsetsToFace distanceBetweenSegs subInsets (makeFace 4 (segmentFrom finalInset) midArc (slist []) lastArc)
    lastPlacedInset = segmentFrom $ last foundInsets
    lastPlacedLine = lineFrom $ last foundInsets
    edgeDistanceToLastPlacedInset = max (distance (startPoint edge) (startPoint lastPlacedInset))
                                          (distance (endPoint edge) (endPoint lastPlacedInset))
    midArc = case midArcs of
               (Slist [oneArc] 1) -> oneArc
               (Slist _ _) -> error $ "evaluated midArc with the wrong insets of items.\n"
                                   <> "d: " <> show distanceBetweenSegs <> "\n"
                                   <> "n: " <> show insets <> "\n"
                                   <> "Face: " <> show face <> "\n"
    ----------------------------------------------
    -- functions only used by a three-sided n-gon.
    ----------------------------------------------
    twoSideRemainder     = if isJust maybeFinalInset && distanceBetweenSegs * fromIntegral linesToPlace /= distanceUntilEnd checkedFace
                           then Just [makeFaceNoCheck (segmentFrom finalInset) firstArc (slist []) lastArc]
                           else Nothing

-- | How many lines can be drawn onto a given Face, parallel to the face.
linesUntilEnd :: ℝ -> Face -> Fastℕ
linesUntilEnd distanceBetweenSegs face = floor (distanceUntilEnd face / distanceBetweenSegs)

-- | What is the distance from the edge of a face to the place where we can no longer place lines.
distanceUntilEnd :: Face -> ℝ
distanceUntilEnd face@(Face edge firstArc midArcs lastArc)
  | isEmpty midArcs  = distancePPointToPLineWithErr crossIntersection edgeLine
  | len midArcs == 1 = if firstArcEndsFarthest edge firstArc midArc lastArc
                       then distancePPointToPLineWithErr firstIntersection edgeLine
                       else distancePPointToPLineWithErr lastIntersection edgeLine
  | otherwise        = snd $ closestArcAndDistance face
  where
    firstIntersection = safeIntersectionOf firstArc midArc
    lastIntersection  = safeIntersectionOf midArc lastArc
    crossIntersection = safeIntersectionOf firstArc lastArc
    safeIntersectionOf a b
      | noIntersection a b = error $ "given a non-intersecting pair of lines."
                                <> show a <> "\n"
                                <> show b <> "\n"
                                <> show (plinesIntersectIn a b) <> "\n"
                                <> showInputs
      | otherwise = intersectionOf a b
    showInputs = "edge: " <> show edge <> "\n"
              <> "firstArc: \n" <> show firstArc <> "\n"
              <> "midArcs: \n" <> show midArcs <> "\n"
              <> "lastArc: \n" <> show lastArc <> "\n"
    edgeLine = eToPL edge
    midArc = head midArcs

-- | for a face with four sides, see which arc attached to the face ends the furthest away from the line of the face.
firstArcEndsFarthest :: (ProjectiveLine2 a) => LineSeg -> (a, PLine2Err) -> (a, PLine2Err) -> (a, PLine2Err) -> Bool
firstArcEndsFarthest edge firstArc midArc lastArc = distancePPointToPLineWithErr firstIntersection edgeLine > distancePPointToPLineWithErr lastIntersection edgeLine
  where
    firstIntersection = safeIntersectionOf firstArc midArc
    lastIntersection  = safeIntersectionOf midArc lastArc
    safeIntersectionOf a b
      | noIntersection a b = error $ "given a non-intersecting pair of lines."
                                <> show a <> "\n"
                                <> show b <> "\n"
                                <> show (plinesIntersectIn a b) <> "\n"
                                <> showInputs
      | otherwise = intersectionOf a b
    showInputs = "edge: " <> show edge <> "\n"
              <> "firstArc: \n" <> show firstArc <> "\n"
              <> "midArc: \n" <> show midArc <> "\n"
              <> "lastArc: \n" <> show lastArc <> "\n"
    edgeLine = eToPL edge

closestArcAndDistance :: Face -> (((ProjectiveLine, PLine2Err), (ProjectiveLine, PLine2Err)), ℝ)
closestArcAndDistance (Face edge firstArc (Slist rawMidArcs _) lastArc) = case sortOn snd arcIntersections of
                   [] -> error "empty arcIntersections?"
                   [pair] -> pair
                   (pair:_) -> pair
  where
    -- | Find the closest point where two of our arcs intersect, relative to our side.
    arcIntersections = init $ mapWithFollower (\a b -> ((a, b), distancePPointToPLineWithErr (safeIntersectionOf a b) (eToPL edge))) $ firstArc : rawMidArcs <> [lastArc]
      where
        safeIntersectionOf a b
          | noIntersection a b = error $ "given a non-intersecting pair of lines."
                                 <> show a <> "\n"
                                 <> show b <> "\n"
                                 <> show (plinesIntersectIn a b) <> "\n"
                                 <> showInputs
          | otherwise = intersectionOf a b
    showInputs = "edge: " <> show edge <> "\n"
              <> "firstArc: \n" <> show firstArc <> "\n"
              <> "midArcs: \n" <> show rawMidArcs <> "\n"
              <> "lastArc: \n" <> show lastArc <> "\n"

-- | Take the output of many calls to addInsetsToFace, and construct contours from them.
reclaimContours :: [[InsetLine]] -> [Contour]
reclaimContours lineSegSets
  -- every ring was reclaimed, and cleaned. return success.
  | all isJust reclaimedRings && all isJust cleanedContours = catMaybes cleanedContours
  | all isJust reclaimedRings = error $ "failed to clean a contour in rings: " <> show rings <> "\n" <> "input linsSegSets:\n" <> show lineSegSets <> "\n"
  | otherwise = catMaybes cleanedContours
  where
    cleanedContours = cleanContour <$> concat (catMaybes reclaimedRings)
    reclaimedRings = reclaimRing <$> rings
    -- The input set of line segments has all of the line segments that cover a face in the same list.
    -- by transposing them, we get lists of rings around the object, rather than individually covered faces.
    -- by filtering lineSegSets we filter out any face that had no segments placed.
    -- by filtering for the length, we handle merge events.
    rings = filter (\a -> length a > 2) $ transpose $ filter (/= []) lineSegSets

-- | take ring(s) of line segments, and generate contours.
-- FIXME: not handling split events yet.
reclaimRing :: [InsetLine] -> Maybe [Contour]
reclaimRing ring
  -- Don't even try to reclaim something that can not qualify as a 2d shape with volume.
  | length ring < 3 = noResult
  -- No split events. return success.
  | all (isJust . fst) reclaimContour' = Just reconstructedContours
  | length (filter (\(a,_) -> isJust a) reclaimContour') < 3 = noResult
  | null reconstructedContours = noResult
  | otherwise = case filter (\(a,_) -> isNothing a) reclaimContour' of
                  -- An odd number of breaks is either a floating point induced error, or an attempt to completely inset a contour.
                  [a] -> error $ "found a single break in ring: " <> show ring <> " at " <> show (snd a) <> "\n"
                  -- FIXME: this should actually be a split operation, or a segment removal operation.
                  _ -> noResult
  where
    noResult = Nothing
    reconstructedContours = catMaybes [maybeMakePointContour $ nub $ catMaybes $ fst <$> reclaimContour']
      where
        maybeMakePointContour points
          | length points < 3 = error $ "too few points: " <> show (length points) <> "\n" -- Nothing
          | otherwise = Just $ makePointContour points
    -- reclaim a contour.
    reclaimContour' = mapWithFollower recovery ring
      where
        -- detect if two inset lines SHOULD end at the same point, and if they do, return the point.
        recovery :: InsetLine -> InsetLine -> (Maybe Point2, (LineSeg, LineSeg))
        recovery inset1 inset2
          | endPoint seg1 == startPoint seg2 = (Just $ endPoint seg1, (seg1, seg2))
          | noIntersection line1 line2 = (Nothing, (seg1, seg2))
          | l1l2Distance <= ulpVal l1l2DistanceErrRaw = (Just leastErrPoint, (seg1,seg2))
          | l1l2Distance <= l1l2DistanceErr = (Just leastErrPoint, (seg1,seg2))
          | otherwise = (Nothing, (seg1,seg2))
          where
            seg1 = segmentFrom inset1
            seg2 = segmentFrom inset2
            line1 = lineFrom inset1
            line2 = lineFrom inset2
            l1EndPoint = endFrom inset1
            l2StartPoint = startFrom inset2
            leastErrPoint :: Point2
            leastErrPoint = fst $ pToEP leastErrPPoint
            leastErrPPoint
              | fuzzinessOfP l1EndPoint < fuzzinessOfP l2StartPoint &&
                fuzzinessOfP l1EndPoint < fuzzinessOfP newPoint = fst l1EndPoint
              | fuzzinessOfP l2StartPoint < fuzzinessOfP l1EndPoint &&
                fuzzinessOfP l2StartPoint < fuzzinessOfP newPoint = fst l2StartPoint
              | otherwise = fst newPoint
              where
                newPoint = intersectionOf line1 line2
            --- FIXME: magic number
            l1l2DistanceErr = 512 * ulpVal (l1l2DistanceErrRaw
                                            <> pLineErrAtPPoint line1 (fst l1EndPoint)
                                            <> pLineErrAtPPoint line2 (fst l2StartPoint))
            (l1l2Distance, (_, _, l1l2DistanceErrRaw)) = distance2PP l1EndPoint l2StartPoint

-- | A face constructor that checks that a face is valid during construction.
makeFace :: Integer -> LineSeg -> (ProjectiveLine, PLine2Err) -> Slist (ProjectiveLine, PLine2Err) -> (ProjectiveLine, PLine2Err) -> Face
makeFace breadCrumb edge firstArc arcs lastArc = res
  where
    res = checkFace $ Face edge firstArc arcs lastArc
    checkFace inFace@(Face myEdge myFirstArc (Slist myMidArcs _) myLastArc)
      | all isIntersection intersections = inFace
      | otherwise = error $ "Tried to generate a degenerate face: "
                         <> show breadCrumb <> "\n"
                         <> show inFace <> "\n"
                         <> intercalate "\n" (show <$> intersections) <> "\n"
      where
        isIntersection intersection = case intersection of
                                        (IntersectsIn _ _) -> True
                                        _ -> False
        intersections = mapWithFollower plinesIntersectIn $ eToPL myEdge : myFirstArc : myMidArcs <> [myLastArc]

-- | a Face constructor with no checking.
makeFaceNoCheck :: LineSeg -> (ProjectiveLine, PLine2Err) -> Slist (ProjectiveLine, PLine2Err) -> (ProjectiveLine, PLine2Err) -> Face
makeFaceNoCheck edge firstArc arcs lastArc = res
  where
    res = Face edge firstArc arcs lastArc
