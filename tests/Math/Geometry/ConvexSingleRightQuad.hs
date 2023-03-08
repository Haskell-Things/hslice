{- ORMOLU_DISABLE -}
{- HSlice.
 - Copyright 2020-2022 Julia Longtin
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

{- tests for the properties of a quadralaterial that is convex, and has at least one right angle. -}

module Math.Geometry.ConvexSingleRightQuad (
  convexSingleRightQuadBrokenSpec,
  convexSingleRightQuadSpec
  ) where

import Prelude (Bool(False, True), Show(show), ($), (&&), (==), error, length, otherwise)

-- The Maybe library.
import Data.Maybe (fromMaybe, isJust)

-- Hspec, for writing specs.
import Test.Hspec (describe, Spec, it, Expectation)

-- QuickCheck, for writing properties.
import Test.QuickCheck (property, Positive)

-- The numeric type in HSlice.
import Graphics.Slicer (ℝ)

-- Our Contour library.
import Graphics.Slicer.Math.Contour (lineSegsOfContour)

-- Basic definitions, used in multiple places in the math library.
import Graphics.Slicer.Math.Definitions (Contour)

-- The functions for generating random geometry, for testing purposes.
import Graphics.Slicer.Math.RandomGeometry (Radian, edgesOf, onlyOneOf, randomConvexSingleRightQuad)

-- The part of our library that puts faces onto a contour. faces have one exterior side, and a number of internal sides (defined by Arcs).
import Graphics.Slicer.Math.Skeleton.Face (facesOf, orderedFacesOf)

-- The entry point for getting the straight skeleton of a contour.
import Graphics.Slicer.Math.Skeleton.Skeleton (findStraightSkeleton)

-- Shared tests, between different geometry.
import Math.Geometry.CommonTests (prop_CanPlaceFaces, prop_FacesHaveThreeToFiveSides, prop_HasFourFaces, prop_HasAStraightSkeleton, prop_NodeTreeHasFewerThanFourGenerations, prop_NoDivides, prop_NoMotorcycles, prop_StraightSkeletonHasOneNodeTree)

-- Our Utility library, for making these tests easier to read.
import Math.Util ((-->))

unit_SingleRightQuadConvexHasNoStraightSkeleton :: Bool
unit_SingleRightQuadConvexHasNoStraightSkeleton
  | isJust skeleton = True
  | otherwise = False
  where
    skeleton = findStraightSkeleton convexSingleRightQuad []
    convexSingleRightQuad = randomConvexSingleRightQuad x y rawFirstTilt rawSecondTilt rawThirdTilt rawFirstDistanceToCorner rawSecondDistanceToCorner
    x,y :: ℝ
    x = 0
    y = 0
    rawFirstTilt, rawSecondTilt, rawThirdTilt :: Radian ℝ
    rawFirstTilt = 2.0
    rawSecondTilt = 2.0
    rawThirdTilt = 3.2
    rawFirstDistanceToCorner, rawSecondDistanceToCorner :: Positive ℝ
    rawFirstDistanceToCorner = 2.0
    rawSecondDistanceToCorner = 4.0

unit_SingleRightQuadConvexStraightSkeletonBreaks :: Bool
unit_SingleRightQuadConvexStraightSkeletonBreaks
  | isJust skeleton && length (facesOf $ fromMaybe (error "whoops!") $ skeleton) == 4  = True
  | otherwise = False
  where
    skeleton = findStraightSkeleton convexSingleRightQuad []
    convexSingleRightQuad = randomConvexSingleRightQuad x y rawFirstTilt rawSecondTilt rawThirdTilt rawFirstDistanceToCorner rawSecondDistanceToCorner
    x,y :: ℝ
    x = 0
    y = 0
    rawFirstTilt, rawSecondTilt, rawThirdTilt :: Radian ℝ
    rawFirstTilt = 3.0
    rawSecondTilt = 3.0
    rawThirdTilt = 3.0
    rawFirstDistanceToCorner, rawSecondDistanceToCorner :: Positive ℝ
    rawFirstDistanceToCorner = 1.0
    rawSecondDistanceToCorner = 1.0

prop_FacesInOrder :: Contour -> Expectation
prop_FacesInOrder contour = edgesOf (orderedFacesOf firstSeg $ fromMaybe (error $ show contour) $ findStraightSkeleton contour []) --> contourAsSegs
  where
    firstSeg = onlyOneOf contourAsSegs
    contourAsSegs = lineSegsOfContour contour

convexSingleRightQuadBrokenSpec :: Spec
convexSingleRightQuadBrokenSpec = do
  describe "geometry (Convex Single Right Quads)" $ do
    it "finds a straight skeleton(unit)" $
      unit_SingleRightQuadConvexHasNoStraightSkeleton
    it "finds a straight skeleton(unit 2)" $
      unit_SingleRightQuadConvexStraightSkeletonBreaks

convexSingleRightQuadSpec :: Spec
convexSingleRightQuadSpec = do
  describe "Geometry (Single Right Quads, Convex)" $ do
    it "finds no convex motorcycles" $
      property (expectationFromConvexSingleRightQuad prop_NoMotorcycles)
    it "finds no divides" $
      property (expectationFromConvexSingleRightQuad prop_NoDivides)
    it "finds a straight skeleton" $
      property (expectationFromConvexSingleRightQuad prop_HasAStraightSkeleton)
    it "only finds one nodeTree in the straight skeleton" $
      property (expectationFromConvexSingleRightQuad prop_StraightSkeletonHasOneNodeTree)
    it "generates fewer than four generations of INodes" $
      property (boolFromConvexSingleRightQuad prop_NodeTreeHasFewerThanFourGenerations)
    it "can places face on the straight skeleton" $
      property (expectationFromConvexSingleRightQuad prop_CanPlaceFaces)
    it "only places four faces" $
      property (expectationFromConvexSingleRightQuad prop_HasFourFaces)
    -- FIXME: why do some faces have four arcs?
    it "faces have between three and five sides" $
      property (boolFromConvexSingleRightQuad prop_FacesHaveThreeToFiveSides)
    it "places faces on a convex single right quad in the order the line segments were given" $
      property (expectationFromConvexSingleRightQuad prop_FacesInOrder)
  where
    boolFromConvexSingleRightQuad :: (Contour -> Bool) -> ℝ -> ℝ -> Radian ℝ -> Radian ℝ -> Radian ℝ -> Positive ℝ -> Positive ℝ -> Bool
    boolFromConvexSingleRightQuad f x y rawFirstTilt rawSecondTilt rawThirdTilt rawFirstDistanceToCorner rawSecondDistanceToCorner = f convexSingleRightQuad
      where
        convexSingleRightQuad = randomConvexSingleRightQuad x y rawFirstTilt rawSecondTilt rawThirdTilt rawFirstDistanceToCorner rawSecondDistanceToCorner
    expectationFromConvexSingleRightQuad :: (Contour -> Expectation) -> ℝ -> ℝ -> Radian ℝ -> Radian ℝ -> Radian ℝ -> Positive ℝ -> Positive ℝ -> Expectation
    expectationFromConvexSingleRightQuad f x y rawFirstTilt rawSecondTilt rawThirdTilt rawFirstDistanceToCorner rawSecondDistanceToCorner = f convexSingleRightQuad
      where
        convexSingleRightQuad = randomConvexSingleRightQuad x y rawFirstTilt rawSecondTilt rawThirdTilt rawFirstDistanceToCorner rawSecondDistanceToCorner
