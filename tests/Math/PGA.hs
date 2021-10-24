{- ORMOLU_DISABLE -}
{- HSlice.
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

-- Shamelessly stolen from ImplicitCAD.

module Math.PGA (linearAlgSpec, geomAlgSpec, pgaSpec, proj2DGeomAlgSpec, facetSpec, contourSpec, lineSpec) where

-- Be explicit about what we import.
import Prelude (($), Bool(True, False), (<$>), (==), (>=), error, head, sqrt, (/=), otherwise, abs, (&&), (+))

-- Hspec, for writing specs.
import Test.Hspec (describe, Spec, it, pendingWith, Expectation)

-- QuickCheck, for writing properties.
import Test.QuickCheck (property, NonZero(NonZero), Positive(Positive))

import Test.QuickCheck.IO ()

import Data.Coerce (coerce)

import Data.Either (Either(Right), fromRight)

import Data.List (foldl')

import Data.Maybe (fromMaybe, Maybe(Just, Nothing), fromJust)

import Data.Set (singleton, fromList)

import Slist (slist)

-- The numeric type in HSlice.
import Graphics.Slicer (ℝ)

-- A euclidian point.
import Graphics.Slicer.Math.Definitions(Point2(Point2), Contour(LineSegContour), LineSeg(LineSeg), roundPoint2)

-- Our Geometric Algebra library.
import Graphics.Slicer.Math.GeometricAlgebra (GNum(GEZero, GEPlus, G0), GVal(GVal), GVec(GVec), addValPair, subValPair, addVal, subVal, addVecPair, subVecPair, mulScalarVec, divVecScalar, scalarPart, vectorPart, (•), (∧), (⋅), (⎣))

-- Our 2D Projective Geometric Algebra library.
import Graphics.Slicer.Math.PGA (PPoint2(PPoint2), PLine2(PLine2), eToPPoint2, eToPLine2, join2PPoint2, translatePerp, pointOnPerp, angleBetween, distancePPointToPLine, pPointsOnSameSideOfPLine)

-- Our Contour library.
import Graphics.Slicer.Math.Contour (contourContainsContour, getContours, pointsOfContour, numPointsOfContour, justOneContourFrom, lineSegsOfContour, makeLineSegContour, makePointContour)

import Graphics.Slicer.Machine.Contour (shrinkContour, expandContour)

-- Our Infill library.
import Graphics.Slicer.Machine.Infill (InfillType(Horiz, Vert), makeInfill)

-- Our Facet library.
import Graphics.Slicer.Math.Skeleton.Cells (findFirstCellOfContour, findDivisions, findNextCell, getNodeTreeOfCell, nodeTreesFromDivision)
import Graphics.Slicer.Math.Skeleton.Concave (getFirstArc, makeENodes, averageNodes, eNodesOfOutsideContour)
import Graphics.Slicer.Math.Skeleton.Definitions (ENode(ENode), Motorcycle(Motorcycle), RemainingContour(RemainingContour), StraightSkeleton(StraightSkeleton), INode(INode), INodeSet(INodeSet), CellDivide(CellDivide), DividingMotorcycles(DividingMotorcycles), Cell(Cell))
import Graphics.Slicer.Math.Skeleton.Face (Face(Face), facesOf, orderedFacesOf)
import Graphics.Slicer.Math.Skeleton.Line (addInset)
import Graphics.Slicer.Math.Skeleton.Motorcycles (convexMotorcycles, crashMotorcycles, CrashTree(CrashTree))
import Graphics.Slicer.Math.Skeleton.NodeTrees (makeNodeTree, mergeNodeTrees)
import Graphics.Slicer.Math.Skeleton.Skeleton (findStraightSkeleton)

-- Our Utility library, for making these tests easier to read.
import Math.Util ((-->))

-- Default all numbers in this file to being of the type ImplicitCAD uses for values.
default (ℝ)

contourSpec :: Spec
contourSpec = do
  describe "Contours (math/contour)" $ do
    it "contours made from a list of point pairs retain their order" $
      getContours cl1 --> [c1]
    it "contours made from an out of order list of point pairs is put into order" $
      getContours oocl1 --> [c1]
    it "detects a bigger contour containing a smaller contour" $
      contourContainsContour c1 c2 --> True
    it "ignores a smaller contour contained in a bigger contour" $
      contourContainsContour c2 c1 --> False
    it "ignores two contours that do not contain one another" $
      contourContainsContour c1 c3 --> False
  where
    cp1 = [Point2 (1,0), Point2 (1,1), Point2 (0,1), Point2 (0,0)]
    oocl1 = [(Point2 (1,0), Point2 (0,0)), (Point2 (0,1), Point2 (1,1)), (Point2 (0,0), Point2 (0,1)), (Point2 (1,1), Point2 (1,0))]
    cl1 = [(Point2 (0,0), Point2 (0,1)), (Point2 (0,1), Point2 (1,1)), (Point2 (1,1), Point2 (1,0)), (Point2 (1,0), Point2 (0,0))]
    c1 = makePointContour cp1
    c2 = makePointContour [Point2 (0.75,0.25), Point2 (0.75,0.75), Point2 (0.25,0.75), Point2 (0.25,0.25)]
    c3 = makePointContour [Point2 (3,0), Point2 (3,1), Point2 (2,1), Point2 (2,0)]

lineSpec :: Spec
lineSpec = do
  describe "Contours (math/line)" $ do
    it "contours converted from points to lines then back to points give the input list" $
      pointsOfContour (makePointContour cp1) --> cp1
  where
    cp1 = [Point2 (1,0), Point2 (1,1), Point2 (0,1), Point2 (0,0)]

linearAlgSpec :: Spec
linearAlgSpec = do
  describe "Contours (machine/contour)" $ do
    it "a contour mechanically shrunk has the same amount of points as the input contour" $
      numPointsOfContour (fromMaybe (error "got Nothing") $ shrinkContour 0.1 [] c1) --> numPointsOfContour c1
    it "a contour mechanically shrunk by zero is the same as the input contour" $
      shrinkContour 0 [] c1 --> Just cl1
    it "a contour mechanically expanded has the same amount of points as the input contour" $
      numPointsOfContour (fromMaybe (error "got Nothing") $ expandContour 0.1 [] c1) --> numPointsOfContour c1
    it "a contour mechanically shrunk and expanded is about equal to where it started" $
      (roundPoint2 <$> pointsOfContour (fromMaybe (error "got Nothing") $ expandContour 0.1 [] $ fromMaybe (error "got Nothing") $ shrinkContour 0.1 [] c2)) --> roundPoint2 <$> pointsOfContour c2
  describe "Infill (machine/infill)" $ do
    it "infills exactly one line inside of a box big enough for only one line (Horizontal)" $ do
      pendingWith "https://github.com/julialongtin/hslice/issues/31"
      makeInfill c1 [] 0.5 Horiz --> [[LineSeg (Point2 (0,0.5)) (Point2 (1,0))]]
    it "infills exactly one line inside of a box big enough for only one line (Vertical)" $ do
      pendingWith "https://github.com/julialongtin/hslice/issues/31"
      makeInfill c1 [] 0.5 Vert --> [[LineSeg (Point2 (0.5,0)) (Point2 (0,1))]]
  describe "Contours (Skeleton/line)" $ do
    it "a contour algorithmically shrunk has the same amount of points as the input contour" $
      numPointsOfContour (justOneContourFrom $ addInset 1 0.1 $ facesOf $ fromMaybe (error "got Nothing") $ findStraightSkeleton c1 []) --> numPointsOfContour c1
    it "a contour algorithmically shrunk and mechanically expanded is about equal to where it started" $
      roundPoint2 <$> pointsOfContour (fromMaybe (error "got Nothing") $ expandContour 0.1 [] $ justOneContourFrom $ addInset 1 0.1 $ orderedFacesOf c2l1 $ fromMaybe (error "got Nothing") $ findStraightSkeleton c2 []) --> roundPoint2 <$> pointsOfContour c2
  where
    cp1 = [Point2 (1,0), Point2 (1,1), Point2 (0,1), Point2 (0,0)]
    c1 = makePointContour cp1
    cl1 = makeLineSegContour (lineSegsOfContour c1)
    c2 = makePointContour [Point2 (0.75,0.25), Point2 (0.75,0.75), Point2 (0.25,0.75), Point2 (0.25,0.25)]
    c2l1 = LineSeg (Point2 (0.75,0.25)) (Point2 (0,0.5))

geomAlgSpec :: Spec
geomAlgSpec = do
  describe "GVals (Math/GeometricAlgebra)" $ do
    -- 1e1+1e1 = 2e1
    it "adds two values with a common basis vector" $
      addValPair (GVal 1 (singleton (GEPlus 1))) (GVal 1 (singleton (GEPlus 1))) --> [GVal 2 (singleton (GEPlus 1))]
    -- 1e1+1e2 = e1+e2
    it "adds two values with different basis vectors" $
      addValPair (GVal 1 (singleton (GEPlus 1))) (GVal 1 (singleton (GEPlus 2))) --> [GVal 1 (singleton (GEPlus 1)), GVal 1 (singleton (GEPlus 2))]
    -- 2e1-1e1 = e1
    it "subtracts two values with a common basis vector" $
      subValPair (GVal 2 (singleton (GEPlus 1))) (GVal 1 (singleton (GEPlus 1))) --> [GVal 1 (singleton (GEPlus 1))]
    -- 1e1-1e2 = e1-e2
    it "subtracts two values with different basis vectors" $
      subValPair (GVal 1 (singleton (GEPlus 1))) (GVal 1 (singleton (GEPlus 2))) --> [GVal 1 (singleton (GEPlus 1)), GVal (-1.0) (singleton (GEPlus 2))]
    -- 1e1-1e1 = 0
    it "subtracts two identical values with a common basis vector and gets nothing" $
      subValPair (GVal 1 (singleton (GEPlus 1))) (GVal 1 (singleton (GEPlus 1))) --> []
    -- 1e0+1e1+1e2 = e0+e1+e2
    it "adds a value to a list of values" $
      addVal [GVal 1 (singleton (GEZero 1)), GVal 1 (singleton (GEPlus 1))] (GVal 1 (singleton (GEPlus 2))) --> [GVal 1 (singleton (GEZero 1)), GVal 1 (singleton (GEPlus 1)), GVal 1 (singleton (GEPlus 2))]
    -- 2e1+1e2-1e1 = e1+e2
    it "subtracts a value from a list of values" $
      subVal [GVal 2 (singleton (GEPlus 1)), GVal 1 (singleton (GEPlus 2))] (GVal 1 (singleton (GEPlus 1))) --> [GVal 1 (singleton (GEPlus 1)), GVal 1 (singleton (GEPlus 2))]
    -- 1e1+1e2-1e1 = e2
    it "subtracts a value from a list of values, eliminating an entry with a like basis vector" $
      subVal [GVal 1 (singleton (GEPlus 1)), GVal 1 (singleton (GEPlus 2))] (GVal 1 (singleton (GEPlus 1))) --> [GVal 1 (singleton (GEPlus 2))]
  describe "GVecs (Math/GeometricAlgebra)" $ do
    -- 1e1+1e1 = 2e1
    it "adds two (multi)vectors" $
      addVecPair (GVec [GVal 1 (singleton (GEPlus 1))]) (GVec [GVal 1 (singleton (GEPlus 1))]) --> GVec [GVal 2 (singleton (GEPlus 1))]
    -- 1e1-1e1 = 0
    it "subtracts a (multi)vector from another (multi)vector" $
      subVecPair (GVec [GVal 1 (singleton (GEPlus 1))]) (GVec [GVal 1 (singleton (GEPlus 1))]) --> GVec []
    -- 2*1e1 = 2e1
    it "multiplies a (multi)vector by a scalar (mulScalarVec)" $
      mulScalarVec 2 (GVec [GVal 1 (singleton (GEPlus 1))]) --> GVec [GVal 2 (singleton (GEPlus 1))]
    it "multiplies a (multi)vector by a scalar (G0)" $
      GVec [GVal 2 (singleton G0)] • GVec [GVal 1 (singleton (GEPlus 1))] --> GVec [GVal 2 (singleton (GEPlus 1))]
    -- 2e1/2 = e1
    it "divides a (multi)vector by a scalar" $
      divVecScalar (GVec [GVal 2 (singleton (GEPlus 1))]) 2 --> GVec [GVal 1 (singleton (GEPlus 1))]
    -- 1e1|1e2 = 0
    it "the dot product of two orthoginal basis vectors is nothing" $
      GVec [GVal 1 (singleton (GEPlus 1))] ⋅ GVec [GVal 1 (singleton (GEPlus 2))] --> GVec []
    it "the dot product of two vectors is comutative (a⋅b == b⋅a)" $
      GVec (addValPair (GVal 1 (singleton (GEPlus 1))) (GVal 1 (singleton (GEPlus 2)))) ⋅ GVec (addValPair (GVal 2 (singleton (GEPlus 2))) (GVal 2 (singleton (GEPlus 2)))) -->
      GVec (addValPair (GVal 2 (singleton (GEPlus 1))) (GVal 2 (singleton (GEPlus 2)))) ⋅ GVec (addValPair (GVal 1 (singleton (GEPlus 2))) (GVal 1 (singleton (GEPlus 2))))
    -- 2e1|2e1 = 4
    it "the dot product of a vector with itsself is it's magnitude squared" $
      scalarPart (GVec [GVal 2 (singleton (GEPlus 1))] ⋅ GVec [GVal 2 (singleton (GEPlus 1))]) --> 4
    it "the like product of a vector with itsself is it's magnitude squared" $
      scalarPart (GVec [GVal 2 (singleton (GEPlus 1))] ⎣ GVec [GVal 2 (singleton (GEPlus 1))]) --> 4
    -- (2e1^1e2)|(2e1^1e2) = -4
    it "the dot product of a bivector with itsself is the negative of magnitude squared" $
      scalarPart (GVec [GVal 2 (fromList [GEPlus 1, GEPlus 2])] ⋅ GVec [GVal 2 (fromList [GEPlus 1, GEPlus 2])]) --> (-4)
    -- 1e1^1e1 = 0
    it "the wedge product of two identical vectors is nothing" $
      vectorPart (GVec [GVal 1 (singleton (GEPlus 1))] ∧ GVec [GVal 1 (singleton (GEPlus 1))]) --> GVec []
    it "the wedge product of two vectors is anti-comutative (u∧v == -v∧u)" $
      GVec [GVal 1 (singleton (GEPlus 1))] ∧ GVec [GVal 1 (singleton (GEPlus 2))] -->
      GVec [GVal (-1) (singleton (GEPlus 2))] ∧ GVec [GVal 1 (singleton (GEPlus 1))]
  describe "Operators (Math/GeometricAlgebra)" $ do
    it "the multiply operations that should result in nothing all result in nothing" $
      foldl' addVecPair (GVec []) [
                                   GVec [GVal 1 (singleton (GEZero 1))] • GVec [GVal 1 (singleton (GEZero 1))]
                                 , GVec [GVal 1 (singleton (GEZero 1))] • GVec [GVal 1 (fromList [GEZero 1, GEPlus 1])]
                                 , GVec [GVal 1 (singleton (GEZero 1))] • GVec [GVal 1 (fromList [GEZero 1, GEPlus 2])]
                                 , GVec [GVal 1 (singleton (GEZero 1))] • GVec [GVal 1 (fromList [GEZero 1, GEPlus 1, GEPlus 2])]
                                 , GVec [GVal 1 (fromList [GEZero 1, GEPlus 1])] • GVec [GVal 1 (singleton (GEZero 1))]
                                 , GVec [GVal 1 (fromList [GEZero 1, GEPlus 1])] • GVec [GVal 1 (fromList [GEZero 1, GEPlus 1])]
                                 , GVec [GVal 1 (fromList [GEZero 1, GEPlus 1])] • GVec [GVal 1 (fromList [GEZero 1, GEPlus 2])]
                                 , GVec [GVal 1 (fromList [GEZero 1, GEPlus 1])] • GVec [GVal 1 (fromList [GEZero 1, GEPlus 1, GEPlus 2])]
                                 , GVec [GVal 1 (fromList [GEZero 1, GEPlus 2])] • GVec [GVal 1 (singleton (GEZero 1))]
                                 , GVec [GVal 1 (fromList [GEZero 1, GEPlus 2])] • GVec [GVal 1 (fromList [GEZero 1, GEPlus 1])]
                                 , GVec [GVal 1 (fromList [GEZero 1, GEPlus 2])] • GVec [GVal 1 (fromList [GEZero 1, GEPlus 2])]
                                 , GVec [GVal 1 (fromList [GEZero 1, GEPlus 2])] • GVec [GVal 1 (fromList [GEZero 1, GEPlus 1, GEPlus 2])]
                                 , GVec [GVal 1 (fromList [GEZero 1, GEPlus 1, GEPlus 2])] • GVec [GVal 1 (singleton (GEZero 1))]
                                 , GVec [GVal 1 (fromList [GEZero 1, GEPlus 1, GEPlus 2])] • GVec [GVal 1 (fromList [GEZero 1, GEPlus 1])]
                                 , GVec [GVal 1 (fromList [GEZero 1, GEPlus 1, GEPlus 2])] • GVec [GVal 1 (fromList [GEZero 1, GEPlus 2])]
                                 , GVec [GVal 1 (fromList [GEZero 1, GEPlus 1, GEPlus 2])] • GVec [GVal 1 (fromList [GEZero 1, GEPlus 1, GEPlus 2])]
                                 ] --> GVec []
    it "the multiply operations that should result in 1 all result in 1" $
      foldl' addVecPair (GVec []) [
                                   GVec [GVal 1 (singleton (GEPlus 1))] • GVec [GVal 1 (singleton (GEPlus 1))]
                                 , GVec [GVal 1 (singleton (GEPlus 2))] • GVec [GVal 1 (singleton (GEPlus 2))]
                                 ] --> GVec [GVal 2 (singleton G0)]
    it "the multiply operations that should result in -1 all result in -1" $
      foldl' addVecPair (GVec []) [
                                   GVec [GVal 1 (fromList [GEPlus 1, GEPlus 2])] • GVec [GVal 1 (fromList [GEPlus 1, GEPlus 2])]
                                 ] --> GVec [GVal (-1) (singleton G0)]
    it "the multiply operations that should result in e0 all result in e0" $
      foldl' addVecPair (GVec []) [
                                   GVec [GVal 1 (fromList [GEZero 1, GEPlus 1])] • GVec [GVal 1 (singleton (GEPlus 1))]
                                 , GVec [GVal 1 (fromList [GEZero 1, GEPlus 2])] • GVec [GVal 1 (singleton (GEPlus 2))]
                                 ] --> GVec [GVal 2 (singleton (GEZero 1))]
    it "the multiply operations that should result in e1 all result in e1" $
      foldl' addVecPair (GVec []) [
                                   GVec [GVal 1 (fromList [GEPlus 1, GEPlus 2])] • GVec [GVal 1 (singleton (GEPlus 2))]
                                 ] --> GVec [GVal 1 (singleton (GEPlus 1))]
    it "the multiply operations that should result in e2 all result in e2" $
      foldl' addVecPair (GVec []) [
                                   GVec [GVal 1 (singleton (GEPlus 1))] • GVec [GVal 1 (fromList [GEPlus 1, GEPlus 2])]
                                 ] --> GVec [GVal 1 (singleton (GEPlus 2))]
    it "the multiply operations that should result in e01 all result in e01" $
      foldl' addVecPair (GVec []) [
                                   GVec [GVal 1 (singleton (GEZero 1))] • GVec [GVal 1 (singleton (GEPlus 1))]
                                 , GVec [GVal 1 (singleton (GEPlus 2))] • GVec [GVal 1 (fromList [GEZero 1, GEPlus 1, GEPlus 2])]
                                 , GVec [GVal 1 (fromList [GEPlus 1, GEPlus 2])] • GVec [GVal 1 (fromList [GEZero 1, GEPlus 2])]
                                 , GVec [GVal 1 (fromList [GEZero 1, GEPlus 1, GEPlus 2])] • GVec [GVal 1 (singleton (GEPlus 2))]
                                 ] --> GVec [GVal 4 (fromList [GEZero 1, GEPlus 1])]
    it "the multiply operations that should result in e02 all result in e02" $
      foldl' addVecPair (GVec []) [
                                   GVec [GVal 1 (singleton (GEZero 1))] • GVec [GVal 1 (singleton (GEPlus 2))]
                                 , GVec [GVal 1 (fromList [GEZero 1, GEPlus 1])] • GVec [GVal 1 (fromList [GEPlus 1, GEPlus 2])]
                                 ] --> GVec [GVal 2 (fromList [GEZero 1, GEPlus 2])]
    it "the multiply operations that should result in e12 all result in e12" $
      foldl' addVecPair (GVec []) [
                                   GVec [GVal 1 (singleton (GEPlus 1))] • GVec [GVal 1 (singleton (GEPlus 2))]
                                 ] --> GVec [GVal 1 (fromList [GEPlus 1, GEPlus 2])]
    it "the multiply operations that should result in e012 all result in e012" $
      foldl' addVecPair (GVec []) [
                                   GVec [GVal 1 (singleton (GEZero 1))] • GVec [GVal 1 (fromList [GEPlus 1, GEPlus 2])]
                                 , GVec [GVal 1 (singleton (GEPlus 2))] • GVec [GVal 1 (fromList [GEZero 1, GEPlus 1])]
                                 , GVec [GVal 1 (fromList [GEZero 1, GEPlus 1])] • GVec [GVal 1 (singleton (GEPlus 2))]
                                 , GVec [GVal 1 (fromList [GEPlus 1, GEPlus 2])] • GVec [GVal 1 (singleton (GEZero 1))]
                                 ] --> GVec [GVal 4 (fromList [GEZero 1, GEPlus 1, GEPlus 2])]
    it "the multiply operations that should result in -e0 all result in -e0" $
      foldl' addVecPair (GVec []) [
                                   GVec [GVal 1 (singleton (GEPlus 1))] • GVec [GVal 1 (fromList [GEZero 1, GEPlus 1])]
                                 , GVec [GVal 1 (singleton (GEPlus 2))] • GVec [GVal 1 (fromList [GEZero 1, GEPlus 2])]
                                 , GVec [GVal 1 (fromList [GEPlus 1, GEPlus 2])] • GVec [GVal 1 (fromList [GEZero 1, GEPlus 1, GEPlus 2])]
                                 , GVec [GVal 1 (fromList [GEZero 1, GEPlus 1, GEPlus 2])] • GVec [GVal 1 (fromList [GEPlus 1, GEPlus 2])]
                                 ] --> GVec [GVal (-4) (singleton (GEZero 1))]
    it "the multiply operations that should result in -e1 all result in -e1" $
      foldl' addVecPair (GVec []) [
                                   GVec [GVal 1 (singleton (GEPlus 2))] • GVec [GVal 1 (fromList [GEPlus 1, GEPlus 2])]
                                 ] --> GVec [GVal (-1) (singleton (GEPlus 1))]
    it "the multiply operations that should result in -e2 all result in -e2" $
      foldl' addVecPair (GVec []) [
                                   GVec [GVal 1 (fromList [GEPlus 1, GEPlus 2])] • GVec [GVal 1 (singleton (GEPlus 1))]
                                 ] --> GVec [GVal (-1) (singleton (GEPlus 2))]
    it "the multiply operations that should result in -e01 all result in -e01" $
      foldl' addVecPair (GVec []) [
                                   GVec [GVal 1 (singleton (GEPlus 1))] • GVec [GVal 1 (singleton (GEZero 1))]
                                 , GVec [GVal 1 (fromList [GEZero 1, GEPlus 2])] • GVec [GVal 1 (fromList [GEPlus 1, GEPlus 2])]
                                 ] --> GVec [GVal (-2) (fromList [GEZero 1, GEPlus 1])]
    it "the multiply operations that should result in -e02 all result in -e02" $
      foldl' addVecPair (GVec []) [
                                   GVec [GVal 1 (singleton (GEPlus 1))] • GVec [GVal 1 (fromList [GEZero 1, GEPlus 1, GEPlus 2])]
                                 , GVec [GVal 1 (singleton (GEPlus 2))] • GVec [GVal 1 (singleton (GEZero 1))]
                                 , GVec [GVal 1 (fromList [GEPlus 1, GEPlus 2])] • GVec [GVal 1 (fromList [GEZero 1, GEPlus 1])]
                                 , GVec [GVal 1 (fromList [GEZero 1, GEPlus 1, GEPlus 2])] • GVec [GVal 1 (singleton (GEPlus 1))]
                                 ] --> GVec [GVal (-4) (fromList [GEZero 1, GEPlus 2])]
    it "the multiply operations that should result in -e12 all result in -e12" $
      foldl' addVecPair (GVec []) [
                                   GVec [GVal 1 (singleton (GEPlus 2))] • GVec [GVal 1 (singleton (GEPlus 1))]
                                 ] --> GVec [GVal (-1) (fromList [GEPlus 1, GEPlus 2])]
    it "the multiply operations that should result in -e012 all result in -e012" $
      foldl' addVecPair (GVec []) [
                                   GVec [GVal 1 (singleton (GEPlus 1))] • GVec [GVal 1 (fromList [GEZero 1, GEPlus 2])]
                                 , GVec [GVal 1 (fromList [GEZero 1, GEPlus 2])] • GVec [GVal 1 (singleton (GEPlus 1))]
                                 ] --> GVec [GVal (-2) (fromList [GEZero 1, GEPlus 1, GEPlus 2])]


-- | A property test making sure that the scalar part of the little-dot product of two PPoints is always -1.
prop_ScalarDotScalar :: ℝ -> ℝ -> ℝ -> ℝ -> Bool
prop_ScalarDotScalar v1 v2 v3 v4 = scalarPart (rawPPoint2 (v1,v2) ⋅ rawPPoint2 (v3,v4)) == (-1)  
  where
    rawPPoint2 (x,y) = (\(PPoint2 v) -> v) $ eToPPoint2 (Point2 (x,y))

-- | A property test making sure that the wedge product of two PLines along two different axises is always in e1e2.
prop_TwoAxisAlignedLines :: (NonZero ℝ) -> (NonZero ℝ) -> (NonZero ℝ) -> (NonZero ℝ) -> Expectation
prop_TwoAxisAlignedLines d1 d2 r1 r2 = (\(GVec gVals) -> bases gVals) ((\(PLine2 a) -> a) (eToPLine2 (LineSeg (Point2 ((coerce d1),0)) (Point2 (coerce r1,0)))) ∧ (\(PLine2 a) -> a) (eToPLine2 (LineSeg (Point2 (0,coerce d2)) (Point2 (0,coerce r2))))) --> [fromList [GEPlus 1, GEPlus 2]]
  where
    bases gvals = (\(GVal _ base) -> base) <$> gvals

-- | A property test making sure that the scalar part of the big-dot product of two identical PLines is not zero.
prop_TwoOverlappingLinesScalar :: ℝ -> ℝ -> (NonZero ℝ) -> (NonZero ℝ) -> Bool
prop_TwoOverlappingLinesScalar x y dx dy = scalarPart (((\(PLine2 a) -> a) $ randomPLine x y dx dy) • ((\(PLine2 a) -> a) $ randomPLine x y dx dy)) /= 0

-- | A property test for making sure that there is never a vector result of the big-dot product of two identical PLines.
prop_TwoOverlappingLinesVector :: ℝ -> ℝ -> (NonZero ℝ) -> (NonZero ℝ) -> Expectation
prop_TwoOverlappingLinesVector x y dx dy = vectorPart (((\(PLine2 a) -> a) $ randomPLine x y dx dy) • ((\(PLine2 a) -> a) $ randomPLine x y dx dy)) --> GVec []

proj2DGeomAlgSpec :: Spec
proj2DGeomAlgSpec = do
  describe "Points (Math/PGA)" $
    -- ((1e0^1e1)+(-1e0^1e2)+(1e1+1e2))|((-1e0^1e1)+(1e0^1e2)+(1e1+1e2)) = -1
    it "the dot product of any two projective points is -1" $
      property prop_ScalarDotScalar
  describe "Lines (Math/PGA)" $ do
    -- (-2e2)*2e1 = 4e12
    it "the intersection of a line along the X axis and a line along the Y axis is the origin point" $
      (\(PLine2 a) -> a) (eToPLine2 (LineSeg (Point2 (-1,0)) (Point2 (2,0)))) ∧ (\(PLine2 a) -> a) (eToPLine2 (LineSeg (Point2 (0,-1)) (Point2 (0,2)))) --> GVec [GVal 4 (fromList [GEPlus 1, GEPlus 2])]
    it "the intersection of two axis aligned lines is a multiple of e1e2" $
      property prop_TwoAxisAlignedLines
    -- (-2e0+1e1)^(2e0-1e2) = -1e01+2e02-e12
    it "the intersection of a line two points above the X axis, and a line two points to the right of the Y axis is at (2,2) in the upper right quadrant" $
      vectorPart ((\(PLine2 a) -> a) (eToPLine2 (LineSeg (Point2 (2,0)) (Point2 (0,1)))) ∧ (\(PLine2 a) -> a) (eToPLine2 (LineSeg (Point2 (0,2)) (Point2 (1,0))))) -->
      GVec [GVal (-2) (fromList [GEZero 1, GEPlus 1]), GVal 2 (fromList [GEZero 1, GEPlus 2]), GVal (-1) (fromList [GEPlus 1, GEPlus 2])]
    it "the geometric product of any two overlapping lines is only a Scalar" $
      property prop_TwoOverlappingLinesScalar
    it "the geometric product of any two overlapping lines does not have produce a vector component" $
      property prop_TwoOverlappingLinesVector
    it "A line constructed from a line segment is correct" $
      eToPLine2 (LineSeg (Point2 (0,0)) (Point2 (1,1))) --> pl1
    it "A line constructed from by joining two points is correct" $
      join2PPoint2 (eToPPoint2 (Point2 (0,0))) (eToPPoint2 (Point2 (1,1))) --> pl1
  where
    pl1 = PLine2 $ GVec [GVal 1 (singleton (GEPlus 1)), GVal (-1) (singleton (GEPlus 2))]

-- | A property test making sure a PPoint projected from an axis-aligned line is along the opposite axis.
prop_AxisProjection :: (Positive ℝ) -> Bool -> Bool -> (Positive ℝ) -> Expectation
prop_AxisProjection v xAxis whichDirection dv
  | xAxis == True = if whichDirection == True
                    then pointOnPerp (randomLineSeg 0 0 (coerce v) 0) (Point2 (0,0)) (coerce dv) --> Point2 (0,(coerce dv))
                    else pointOnPerp (randomLineSeg 0 0 (-(coerce v)) 0) (Point2 (0,0)) (coerce dv) --> Point2 (0,-(coerce dv))
  | otherwise = if whichDirection == True
                then pointOnPerp (randomLineSeg 0 0 0 (coerce v)) (Point2 (0,0)) (coerce dv) --> Point2 (-(coerce dv),0)
                else pointOnPerp (randomLineSeg 0 0 0 (-(coerce v))) (Point2 (0,0)) (coerce dv) --> Point2 ((coerce dv),0)

-- | A property test making sure the distance between a point an an axis is equal to the corresponding euclidian component of the point.
prop_DistanceToAxis :: (NonZero ℝ) -> (NonZero ℝ) -> Bool -> Expectation
prop_DistanceToAxis v v2 xAxis
  | xAxis == True = distancePPointToPLine (eToPPoint2 $ Point2 (coerce v2,coerce v)) (eToPLine2 $ LineSeg (Point2 (0,0)) (Point2 (1,0))) --> abs (coerce v)
  | otherwise = distancePPointToPLine (eToPPoint2 $ Point2 (coerce v,coerce v2)) (eToPLine2 $ LineSeg (Point2 (0,0)) (Point2 (0,1))) --> abs (coerce v)

-- | A property test making sure two points on the same side of an axis show as being on the same side of the axis.
prop_SameSideOfAxis :: (NonZero ℝ) -> (NonZero ℝ) -> (Positive ℝ) -> (Positive ℝ) -> Bool -> Bool -> Expectation
prop_SameSideOfAxis v1 v2 p1 p2 xAxis positive
  | xAxis == True = if positive
                    then pPointsOnSameSideOfPLine (eToPPoint2 (Point2 (coerce v1,coerce p1))) (eToPPoint2 (Point2 (coerce v2,coerce p2))) (eToPLine2 (LineSeg (Point2 (0,0)) (Point2 (1,0)))) --> Just True
                    else pPointsOnSameSideOfPLine (eToPPoint2 (Point2 (coerce v1,-(coerce p1)))) (eToPPoint2 (Point2 (coerce v2,-(coerce p2)))) (eToPLine2 (LineSeg (Point2 (0,0)) (Point2 (1,0)))) --> Just True
  | otherwise = if positive
                then pPointsOnSameSideOfPLine (eToPPoint2 (Point2 (coerce p1,coerce v1))) (eToPPoint2 (Point2 (coerce p2,coerce v2))) (eToPLine2 (LineSeg (Point2 (0,0)) (Point2 (0,1)))) --> Just True
                else pPointsOnSameSideOfPLine (eToPPoint2 (Point2 (-(coerce p1),coerce v1))) (eToPPoint2 (Point2 (-(coerce p1),coerce v2))) (eToPLine2 (LineSeg (Point2 (0,0)) (Point2 (0,1)))) --> Just True

-- | A property test making sure that two points on opposite sides of an axis show as being on the opposite sides of the axis.
prop_OtherSideOfAxis :: (NonZero ℝ) -> (NonZero ℝ) -> (Positive ℝ) -> (Positive ℝ) -> Bool -> Bool -> Expectation
prop_OtherSideOfAxis v1 v2 p1 p2 xAxis positive
  | xAxis == True = if positive
                    then pPointsOnSameSideOfPLine (eToPPoint2 (Point2 (coerce v1,coerce p1))) (eToPPoint2 (Point2 (coerce v2,-(coerce p2)))) (eToPLine2 (LineSeg (Point2 (0,0)) (Point2 (1,0)))) --> Just False
                    else pPointsOnSameSideOfPLine (eToPPoint2 (Point2 (coerce v1,-(coerce p1)))) (eToPPoint2 (Point2 (coerce v2,coerce p2))) (eToPLine2 (LineSeg (Point2 (0,0)) (Point2 (1,0)))) --> Just False
  | otherwise = if positive
                then pPointsOnSameSideOfPLine (eToPPoint2 (Point2 (coerce p1,coerce v1))) (eToPPoint2 (Point2 (-(coerce p2),coerce v2))) (eToPLine2 (LineSeg (Point2 (0,0)) (Point2 (0,1)))) --> Just False
                else pPointsOnSameSideOfPLine (eToPPoint2 (Point2 (-(coerce p1),coerce v1))) (eToPPoint2 (Point2 (coerce p1,coerce v2))) (eToPLine2 (LineSeg (Point2 (0,0)) (Point2 (0,1)))) --> Just False

-- | A helper function. constructs a random PLine.
randomPLine :: ℝ -> ℝ -> (NonZero ℝ) -> (NonZero ℝ) -> PLine2
randomPLine x y dx dy = eToPLine2 $ LineSeg (Point2 (coerce x, coerce y)) (Point2 (coerce dx, coerce dy))

-- | A helper function. constructs a random LineSeg.
-- FIXME: can construct 0 length segments, and fail.
randomLineSeg :: ℝ -> ℝ -> ℝ -> ℝ -> LineSeg
randomLineSeg x y dx dy = LineSeg (Point2 (coerce x, coerce y)) (Point2 (coerce dx, coerce dy))

pgaSpec :: Spec
pgaSpec = do
  describe "Translation (math/PGA)" $ do
    it "a translated line translated back is the same line" $
     translatePerp (translatePerp (eToPLine2 l1) 1) (-1) --> eToPLine2 l1
  describe "Projection (math/PGA)" $ do
    it "a projection on the perpendicular bisector of an axis aligned line is on the other axis" $
      property prop_AxisProjection
  describe "Distance measurement (math/PGA)" $ do
    it "the distance between a point at (x,y) and an axis is equal to x for the x axis, and y for the y axis" $
      property prop_DistanceToAxis
  describe "Layout Inspection (math/PGA)" $ do
    it "two points on the same side of a line show as being on the same side of the line" $
      property prop_SameSideOfAxis
    it "two points on different sides of a line show as being on different sides of a line" $
      property prop_OtherSideOfAxis
  where
    l1 = LineSeg (Point2 (1,1)) (Point2 (2,2))

-- | ensure that a right angle with one side parallel with an axis and the other side parallel to the other axis results in a line through the origin point.
-- NOTE: hack, using angleBetween to filter out minor numerical imprecision.
prop_AxisAlignedRightAngles :: Bool -> Bool -> ℝ -> (Positive ℝ) -> Expectation
prop_AxisAlignedRightAngles xPos yPos offset rawMagnitude
  | xPos == True && yPos == True =
    getFirstArc (LineSeg (Point2 (offset,offset+mag)) (Point2 (0,-mag))) (LineSeg (Point2 (offset,offset)) (Point2 (mag,0))) `angleBetween` PLine2 (GVec [GVal 0.7071067811865475 (singleton (GEPlus 1)), GVal (-0.7071067811865475) (singleton (GEPlus 2))]) --> 1.0000000000000002
  | xPos == True =
    getFirstArc (LineSeg (Point2 (offset,-(offset+mag))) (Point2 (0,mag))) (LineSeg (Point2 (offset,-offset)) (Point2 (mag,0))) `angleBetween` PLine2 (GVec [GVal (-0.7071067811865475) (singleton (GEPlus 1)), GVal (-0.7071067811865475) (singleton (GEPlus 2))]) --> 1.0000000000000002
  | xPos == False && yPos == True =
    getFirstArc (LineSeg (Point2 (-offset,offset+mag)) (Point2 (0,-mag))) (LineSeg (Point2 (-offset,offset)) (Point2 (-mag,0))) `angleBetween` PLine2 (GVec [GVal 0.7071067811865475 (singleton (GEPlus 1)), GVal 0.7071067811865475 (singleton (GEPlus 2))]) --> 1.0000000000000002
  | otherwise =
    getFirstArc (LineSeg (Point2 (-offset,-(offset+mag))) (Point2 (0,mag))) (LineSeg (Point2 (-offset,-offset)) (Point2 (-mag,0))) `angleBetween` PLine2 (GVec [GVal (-0.7071067811865475) (singleton (GEPlus 1)), GVal 0.7071067811865475 (singleton (GEPlus 2))]) --> 1.0000000000000002
  where
    mag :: ℝ
    mag = coerce rawMagnitude

-- | ensure that a 135 degree angle with one side parallel with an axis and in the right place results in a line through the origin point.
-- NOTE: hack, using angleBetween and >= to filter out minor numerical imprecision.
prop_AxisAligned135DegreeAngles :: Bool -> Bool -> ℝ -> (Positive ℝ) -> Bool
prop_AxisAligned135DegreeAngles xPos yPos offset rawMagnitude
  | xPos == True && yPos == True =
    getFirstArc (LineSeg (Point2 (offset,offset+mag)) (Point2 (0,-mag))) (LineSeg (Point2 (offset,offset)) (Point2 (mag,-mag))) `angleBetween` PLine2 (GVec [GVal 0.3826834323650899 (singleton (GEPlus 1)), GVal (-0.9238795325112867) (singleton (GEPlus 2))]) >= 1.0
  | xPos == True =
    getFirstArc (LineSeg (Point2 (offset,-(offset+mag))) (Point2 (0,mag))) (LineSeg (Point2 (offset,-offset)) (Point2 (mag,mag))) `angleBetween` PLine2 (GVec [GVal (-0.3826834323650899) (singleton (GEPlus 1)), GVal (-0.9238795325112867) (singleton (GEPlus 2))]) >= 1.0
  | xPos == False && yPos == True =
    getFirstArc (LineSeg (Point2 (-offset,offset+mag)) (Point2 (0,-mag))) (LineSeg (Point2 (-offset,offset)) (Point2 (-mag,-mag))) `angleBetween` PLine2 (GVec [GVal 0.3826834323650899 (singleton (GEPlus 1)), GVal 0.9238795325112867 (singleton (GEPlus 2))]) >= 1.0
  | otherwise =
    getFirstArc (LineSeg (Point2 (-offset,-(offset+mag))) (Point2 (0,mag))) (LineSeg (Point2 (-offset,-offset)) (Point2 (-mag,mag))) `angleBetween` PLine2 (GVec [GVal (-0.3826834323650899) (singleton (GEPlus 1)), GVal 0.9238795325112867 (singleton (GEPlus 2))]) >= 1.0
  where
    mag :: ℝ
    mag = coerce rawMagnitude

-- | ensure that a 45 degree angle with one side parallel with the X axis and in the right place results in a line through the origin point.
-- NOTE: hack, using angleBetween to filter out minor numerical imprecision.
prop_AxisAligned45DegreeAngles :: Bool -> Bool -> ℝ -> (Positive ℝ) -> Expectation
prop_AxisAligned45DegreeAngles xPos yPos offset rawMagnitude
  | xPos == True && yPos == True =
    getFirstArc (LineSeg (Point2 (offset+mag,offset+mag)) (Point2 (-mag,-mag))) (LineSeg (Point2 (offset,offset)) (Point2 (mag,0))) `angleBetween` PLine2 (GVec [GVal 0.3826834323650899 (singleton (GEPlus 1)), GVal (-0.9238795325112867) (singleton (GEPlus 2))]) --> 1.0
  | xPos == True =
    getFirstArc (LineSeg (Point2 (offset+mag,-(offset+mag))) (Point2 (-mag,mag))) (LineSeg (Point2 (offset,-offset)) (Point2 (mag,0))) `angleBetween` PLine2 (GVec [GVal  (-0.3826834323650899) (singleton (GEPlus 1)), GVal (-0.9238795325112867) (singleton (GEPlus 2))]) --> 1.0
  | xPos == False && yPos == True =
    getFirstArc (LineSeg (Point2 (-(offset+mag),offset+mag)) (Point2 (mag,-mag))) (LineSeg (Point2 (-offset,offset)) (Point2 (-mag,0))) `angleBetween` PLine2 (GVec [GVal 0.3826834323650899 (singleton (GEPlus 1)), GVal 0.9238795325112867 (singleton (GEPlus 2))]) --> 1.0
  | otherwise =
    getFirstArc (LineSeg (Point2 (-(offset+mag),-(offset+mag))) (Point2 (mag,mag))) (LineSeg (Point2 (-offset,-offset)) (Point2 (-mag,0))) `angleBetween` PLine2 (GVec [GVal (-0.3826834323650899) (singleton (GEPlus 1)), GVal 0.9238795325112867 (singleton (GEPlus 2))]) --> 1.0
  where
    mag :: ℝ
    mag = coerce rawMagnitude

facetSpec :: Spec
facetSpec = do
  describe "Arcs (Skeleton/Concave)" $ do
    it "finds the outside arcs of right angles with their sides parallel to the axises" $
      property prop_AxisAlignedRightAngles
    it "finds the outside arcs of 135 degree angles with one side parallel to an axis" $
      property prop_AxisAligned135DegreeAngles
    it "finds the outside arcs of 45 degree angles with one side parallel to an axis" $
      property prop_AxisAligned45DegreeAngles
    it "finds the inside arc of the first corner of c2" $
      makeENodes c2c1 --> [ENode (LineSeg (Point2 (0.0,0.0)) (Point2 (1.0,1.0)), LineSeg (Point2 (1.0,1.0)) (Point2 (-2.0,0.0)))
                                 (PLine2 (GVec [GVal (-0.541196100146197) (singleton (GEZero 1)), GVal (-0.3826834323650897) (singleton (GEPlus 1)), GVal 0.9238795325112867 (singleton (GEPlus 2))]))
                          ]
    it "finds the inside arc of the second corner of c2" $
      makeENodes c2c2 --> [ENode (LineSeg (Point2 (1.0,1.0)) (Point2 (-2.0,-0.0)), LineSeg (Point2 (-1.0,1.0)) (Point2 (0.0,-2.0)))
                                 (PLine2 (GVec [GVal (-0.7071067811865475) (singleton (GEPlus 1)), GVal (-0.7071067811865475) (singleton (GEPlus 2))]))
                          ]
    it "finds the inside arc of the third corner of c2" $
      makeENodes c2c3 --> [ENode (LineSeg (Point2 (-1.0,1.0)) (Point2 (0.0,-2.0)), LineSeg (Point2 (-1.0,-1.0)) (Point2 (2.0,0.0)))
                                 (PLine2 (GVec [GVal 0.7071067811865475 (singleton (GEPlus 1)), GVal (-0.7071067811865475) (singleton (GEPlus 2))]))
                          ]
    it "finds the inside arc of the fourth corner of c2" $
      makeENodes c2c4 --> [ENode (LineSeg (Point2 (-1.0,-1.0)) (Point2 (2.0,0.0)), LineSeg (Point2 (1.0,-1.0)) (Point2 (-1.0,1.0)))
                                 (PLine2 (GVec [GVal 0.541196100146197 (singleton (GEZero 1)), GVal 0.3826834323650897 (singleton (GEPlus 1)), GVal 0.9238795325112867 (singleton (GEPlus 2))]))
                          ]
    it "finds the arc resulting from a node at the intersection of the outArc of two nodes (corner3 and corner4 of c2)" $
      averageNodes c2c3E1 c2c4E1 --> INode (PLine2 (GVec [GVal 0.7071067811865475 (singleton (GEPlus 1)), GVal (-0.7071067811865475) (singleton (GEPlus 2))]))
                                           (PLine2 (GVec [GVal 0.541196100146197 (singleton (GEZero 1)), GVal 0.3826834323650897 (singleton (GEPlus 1)), GVal 0.9238795325112867 (singleton (GEPlus 2))]))
                                           (slist [])
                                           (Just (PLine2 (GVec [GVal 0.4870636221857319 (singleton (GEZero 1)), GVal 0.9807852804032305 (singleton (GEPlus 1)), GVal 0.19509032201612836 (singleton (GEPlus 2))])))
    it "finds the outside arc of two PLines intersecting at 90 degrees (c2)" $
      averageNodes c2c2E1 c2c3E1 --> INode (PLine2 (GVec [GVal (-0.7071067811865475) (singleton (GEPlus 1)), GVal (-0.7071067811865475) (singleton (GEPlus 2))]))
                                           (PLine2 (GVec [GVal 0.7071067811865475 (singleton (GEPlus 1)), GVal (-0.7071067811865475) (singleton (GEPlus 2))]))
                                           (slist [])
                                           (Just (PLine2 (GVec [GVal (-1.0) (singleton (GEPlus 2))])))
    it "finds the outside arc of two PLines intersecting at 90 degrees (c2)" $
      averageNodes c2c3E1 c2c2E1 --> INode (PLine2 (GVec [GVal (-0.7071067811865475) (singleton (GEPlus 1)), GVal (-0.7071067811865475) (singleton (GEPlus 2))]))
                                           (PLine2 (GVec [GVal 0.7071067811865475 (singleton (GEPlus 1)), GVal (-0.7071067811865475) (singleton (GEPlus 2))]))
                                           (slist [])
                                           (Just (PLine2 (GVec [GVal (-1.0) (singleton (GEPlus 2))])))
    it "finds the outside arc of two PLines intersecting at 90 degrees (c7)" $
      averageNodes c7c1E1 c7c2E1 --> INode (PLine2 (GVec [GVal (-0.7071067811865475) (singleton (GEPlus 1)), GVal 0.7071067811865475 (singleton (GEPlus 2))]))
                                           (PLine2 (GVec [GVal (1.0606601717798212) (singleton (GEZero 1)), GVal (-0.7071067811865475) (singleton (GEPlus 1)), GVal (-0.7071067811865475) (singleton (GEPlus 2))]))
                                           (slist [])
                                           (Just (PLine2 (GVec [GVal 0.75 (singleton (GEZero 1)), GVal (-1.0) (singleton (GEPlus 1))])))
  describe "Motorcycles (Skeleton/Motorcycles)" $ do
    it "finds one convex motorcycle in a simple shape" $
      convexMotorcycles c1 --> [Motorcycle (LineSeg (Point2 (-1.0,-1.0)) (Point2 (1.0,1.0)), LineSeg (Point2 (0.0,0.0)) (Point2 (1.0,-1.0))) (PLine2 (GVec [GVal 1.414213562373095 (singleton (GEPlus 1))]))]
  describe "Cells (Skeleton/Cells)" $ do
    it "finds the first cell of our first simple shape." $
      cellFrom (findFirstCellOfContour c0 $ findDivisions c0 $ fromJust $ crashMotorcycles c0 []) -->
        Cell (slist [(slist [
                              LineSeg (Point2 (1.0,-1.0)) (Point2 (0.0,2.0))
                            , LineSeg (Point2 (1.0,1.0)) (Point2 (-2.0,0.0))
                            , LineSeg (Point2 (-1.0,1.0)) (Point2 (1.0,-1.0))
                            ],
                       Just (CellDivide (DividingMotorcycles (Motorcycle (LineSeg (Point2 (-1.0,1.0)) (Point2 (1.0,-1.0)),LineSeg (Point2 (0.0,0.0)) (Point2 (-1.0,-1.0)))
                                                                         (PLine2 (GVec [GVal (-1.414213562373095) (fromList [GEPlus 2])])))
                                                                         (slist []))
                                                             Nothing)
                     )])
    it "finds the first cell of our second simple shape." $
      cellFrom (findFirstCellOfContour c1 $ findDivisions c1 $ fromJust $ crashMotorcycles c1 []) -->
        Cell (slist [(slist [
                              LineSeg (Point2 (0.0,0.0)) (Point2 (1.0,-1.0))
                            , LineSeg (Point2 (1.0,-1.0)) (Point2 (0.0,2.0))
                            , LineSeg (Point2 (1.0,1.0)) (Point2 (-2.0,0.0))
                            ],
                       Just (CellDivide (DividingMotorcycles (Motorcycle (LineSeg (Point2 (-1.0,-1.0)) (Point2 (1.0,1.0)),LineSeg (Point2 (0.0,0.0)) (Point2 (1.0,-1.0)))
                                                               (PLine2 (GVec [GVal 1.414213562373095 (fromList [GEPlus 1])])))
                                          (slist []))
                              Nothing)
                     )])
    it "finds the first cell of our third simple shape." $
      cellFrom (findFirstCellOfContour c2 $ findDivisions c2 $ fromJust $ crashMotorcycles c2 []) -->
        Cell (slist [(slist [
                              LineSeg (Point2 (0.0,0.0)) (Point2 (1.0,1.0))
                            , LineSeg (Point2 (1.0,1.0)) (Point2 (-2.0,0.0))
                            , LineSeg (Point2 (-1.0,1.0)) (Point2 (0.0,-2.0))
                            ],
                       Just (CellDivide (DividingMotorcycles (Motorcycle (LineSeg (Point2 (1.0,-1.0)) (Point2 (-1.0,1.0)),LineSeg (Point2 (0.0,0.0)) (Point2 (1.0,1.0)))
                                                               (PLine2 (GVec [GVal 1.414213562373095 (fromList [GEPlus 2])])))
                                          (slist []))
                              Nothing)
                     )])
    it "finds the first cell of our fourth simple shape." $
      cellFrom (findFirstCellOfContour c3 $ findDivisions c3 $ fromJust $ crashMotorcycles c3 []) -->
        Cell (slist [(slist [
                              LineSeg (Point2 (-1.0,-1.0)) (Point2 (2.0,0.0))
                            , LineSeg (Point2 (1.0,-1.0)) (Point2 (0.0,2.0))
                            , LineSeg (Point2 (1.0,1.0)) (Point2 (-1.0,-1.0))
                            ],
                       Just (CellDivide (DividingMotorcycles (Motorcycle (LineSeg (Point2 (1.0,1.0)) (Point2 (-1.0,-1.0)),LineSeg (Point2 (0.0,0.0)) (Point2 (-1.0,1.0)))
                                                               (PLine2 (GVec [GVal (-1.414213562373095) (fromList [GEPlus 1])])))
                                          (slist []))
                              Nothing)
                     )])
    it "finds the first cell of our fifth simple shape." $
      cellFrom (findFirstCellOfContour c4 $ findDivisions c4 $ fromJust $ crashMotorcycles c4 []) -->
        Cell (slist [(slist [
                              LineSeg (Point2 (1.0,-1.0)) (Point2 (0.0,2.0))
                            , LineSeg (Point2 (1.0,1.0)) (Point2 (-2.0,0.0))
                            , LineSeg (Point2 (-1.0,1.0)) (Point2 (1.0,-1.0))
                            ],
                       Just (CellDivide (DividingMotorcycles (Motorcycle (LineSeg (Point2 (-1.0,1.0)) (Point2 (1.0,-1.0)),LineSeg (Point2 (0.0,0.0)) (Point2 (-1.0,-1.0)))
                                                               (PLine2 (GVec [GVal (-1.414213562373095) (fromList [GEPlus 2])])))
                                          (slist []))
                              Nothing)
                     )])
    it "finds the remains from the first cell of our first simple shape." $
      remainderFrom (findFirstCellOfContour c0 $ findDivisions c0 $ fromJust $ crashMotorcycles c0 []) -->
      Just [RemainingContour (slist [(slist [
                                              LineSeg (Point2 (0.0,0.0)) (Point2 (-1.0,-1.0))
                                            , LineSeg (Point2 (-1.0,-1.0)) (Point2 (2.0,0.0))
                                            , LineSeg (Point2 (1.0,-1.0)) (Point2 (0.0,2.0))
                                            ]
                                     ,
                                       [])
                                    ])
           ]
    it "finds the remains from the first cell of our second simple shape." $
      remainderFrom (findFirstCellOfContour c1 $ findDivisions c1 $ fromJust $ crashMotorcycles c1 []) -->
      Just [RemainingContour (slist [(slist [
                                              LineSeg (Point2 (1.0,1.0)) (Point2 (-2.0,0.0))
                                            , LineSeg (Point2 (-1.0,1.0)) (Point2 (0.0,-2.0))
                                            , LineSeg (Point2 (-1.0,-1.0)) (Point2 (1.0,1.0))
                                            ]
                                     ,
                                       [])
                                    ])
           ]
    it "finds the remains from the first cell of our third simple shape." $
      remainderFrom (findFirstCellOfContour c2 $ findDivisions c2 $ fromJust $ crashMotorcycles c2 []) -->
      Just [RemainingContour (slist [(slist [
                                              LineSeg (Point2 (-1.0,1.0)) (Point2 (0.0,-2.0))
                                            , LineSeg (Point2 (-1.0,-1.0)) (Point2 (2.0,0.0))
                                            , LineSeg (Point2 (1.0,-1.0)) (Point2 (-1.0,1.0))
                                            ]
                                     ,
                                       [])
                                    ])
           ]
    it "finds the remains from the first cell of our fourth simple shape." $
      remainderFrom (findFirstCellOfContour c3 $ findDivisions c3 $ fromJust $ crashMotorcycles c3 []) -->
      Just [RemainingContour (slist [(slist [
                                              LineSeg (Point2 (0.0,0.0)) (Point2 (-1.0,1.0))
                                            , LineSeg (Point2 (-1.0,1.0)) (Point2 (0.0,-2.0))
                                            , LineSeg (Point2 (-1.0,-1.0)) (Point2 (2.0,0.0))
                                            ]
                                     ,
                                       [])
                                    ])
           ]
    it "finds the remains from the first cell of our fifth simple shape." $
      remainderFrom (findFirstCellOfContour c4 $ findDivisions c4 $ fromJust $ crashMotorcycles c4 []) -->
      Just [RemainingContour (slist [(slist [
                                              LineSeg (Point2 (0.0,0.0)) (Point2 (-1.0,-1.0))
                                            , LineSeg (Point2 (-1.0,-1.0)) (Point2 (2.0,0.0))
                                            , LineSeg (Point2 (1.0,-1.0)) (Point2 (0.0,2.0))
                                            ]
                                     ,
                                       [])
                                    ])
           ]
    it "finds the remains from the first cell of our sixth simple shape." $
      remainderFrom (findFirstCellOfContour c5 $ findDivisions c5 $ fromJust $ crashMotorcycles c5 []) -->
      Just [RemainingContour (slist [(slist [
                                              LineSeg (Point2 (0.0,0.0)) (Point2 (-1.0,-1.0))
                                            , LineSeg (Point2 (-1.0,-1.0)) (Point2 (2.0,0.0))
                                            , LineSeg (Point2 (1.0,-1.0)) (Point2 (1.0,1.0))
                                            ]
                                     ,
                                       [])
                                    ])
           ]
    it "finds the second cell of our first simple shape." $
      cellFrom (findNextCell $ head $ fromJust $ remainderFrom $ findFirstCellOfContour c0 $ findDivisions c0 $ fromJust $ crashMotorcycles c0 []) -->
      Cell (slist [(slist [
                            LineSeg (Point2 (0.0,0.0)) (Point2 (-1.0,-1.0))
                          , LineSeg (Point2 (-1.0,-1.0)) (Point2 (2.0,0.0))
                          , LineSeg (Point2 (1.0,-1.0)) (Point2 (0.0,2.0))
                          ],Nothing)])
    it "finds the second cell of our second simple shape." $
      cellFrom (findNextCell $ head $ fromJust $ remainderFrom $ findFirstCellOfContour c1 $ findDivisions c1 $ fromJust $ crashMotorcycles c1 []) -->
      Cell (slist [(slist [
                            LineSeg (Point2 (1.0,1.0)) (Point2 (-2.0,0.0))
                          , LineSeg (Point2 (-1.0,1.0)) (Point2 (0.0,-2.0))
                          , LineSeg (Point2 (-1.0,-1.0)) (Point2 (1.0,1.0))
                          ],Nothing)])
    it "finds the second cell of our fifth simple shape." $
      cellFrom (findNextCell $ head $ fromJust $ remainderFrom $ findFirstCellOfContour c4 $ findDivisions c4 $ fromJust $ crashMotorcycles c4 []) -->
      Cell (slist [(slist [
                            LineSeg (Point2 (0.0,0.0)) (Point2 (-1.0,-1.0))
                          , LineSeg (Point2 (-1.0,-1.0)) (Point2 (2.0,0.0))
                          , LineSeg (Point2 (1.0,-1.0)) (Point2 (0.0,2.0))
                          ],Nothing)])
    it "finds the second cell of our six simple shape." $
      cellFrom (findNextCell $ head $ fromJust $ remainderFrom $ findFirstCellOfContour c5 $ findDivisions c5 $ fromJust $ crashMotorcycles c5 []) -->
      Cell (slist [(slist [
                            LineSeg (Point2 (0.0,0.0)) (Point2 (-1.0,-1.0))
                          , LineSeg (Point2 (-1.0,-1.0)) (Point2 (2.0,0.0))
                          , LineSeg (Point2 (1.0,-1.0)) (Point2 (1.0,1.0))
                          ],Nothing)])
  describe "NodeTrees (Skeleton/Cell)" $ do
    it "finds the NodeTree of the first cell of our first simple shape." $
      getNodeTreeOfCell (cellFrom $ findFirstCellOfContour c0 $ findDivisions c0 $ fromJust $ crashMotorcycles c0 []) -->
      Right (makeNodeTree [ ENode (LineSeg (Point2 (1.0,-1.0)) (Point2 (0.0,2.0)), LineSeg (Point2 (1.0,1.0)) (Point2 (-2.0,0.0)))
                                  (PLine2 (GVec [GVal (-0.7071067811865475) (singleton (GEPlus 1)), GVal 0.7071067811865475 (singleton (GEPlus 2))]))
                          , ENode (LineSeg (Point2 (1.0,1.0)) (Point2 (-2.0,0.0)), LineSeg (Point2 (-1.0,1.0)) (Point2 (1.0,-1.0)))
                                  (PLine2 (GVec [GVal 0.541196100146197 (singleton (GEZero 1)), GVal (-0.3826834323650897) (singleton (GEPlus 1)), GVal (-0.9238795325112867) (singleton (GEPlus 2))]))
                          ]
                          (INodeSet (slist [
                                            [INode (PLine2 (GVec [GVal (-0.7071067811865475) (singleton (GEPlus 1)), GVal 0.7071067811865475 (singleton (GEPlus 2))]))
                                                   (PLine2 (GVec [GVal 0.541196100146197 (singleton (GEZero 1)), GVal (-0.3826834323650897) (singleton (GEPlus 1)), GVal (-0.9238795325112867) (singleton (GEPlus 2))]))
                                                   (slist [])
                                                   (Just (PLine2 (GVec [GVal 0.4870636221857319 (singleton (GEZero 1)), GVal (-0.9807852804032305) (singleton (GEPlus 1)), GVal (-0.19509032201612836) (singleton (GEPlus 2))])))
                                            ]
                                           ]
                                    )
                          )
            )
    it "finds the NodeTree of the second cell of our first simple shape." $
      getNodeTreeOfCell (cellFrom $ findNextCell $ head $ fromJust $ remainderFrom $ findFirstCellOfContour c0 $ findDivisions c0 $ fromJust $ crashMotorcycles c0 []) -->
      Right (makeNodeTree [ ENode (LineSeg (Point2 (0.0,0.0)) (Point2 (-1.0,-1.0)), LineSeg (Point2 (-1.0,-1.0)) (Point2 (2.0,0.0)))
                                  (PLine2 (GVec [GVal (-0.541196100146197) (singleton (GEZero 1)), GVal 0.3826834323650897 (singleton (GEPlus 1)), GVal (-0.9238795325112867) (singleton (GEPlus 2))]))
                          , ENode (LineSeg (Point2 (-1.0,-1.0)) (Point2 (2.0,0.0)), LineSeg (Point2 (1.0,-1.0)) (Point2 (0.0,2.0)))
                                  (PLine2 (GVec [GVal 0.7071067811865475 (singleton (GEPlus 1)), GVal 0.7071067811865475 (singleton (GEPlus 2))]))
                          ]
                          (INodeSet (slist [
                                            [INode (PLine2 (GVec [GVal (-0.541196100146197) (singleton (GEZero 1)), GVal 0.3826834323650897 (singleton (GEPlus 1)), GVal (-0.9238795325112867) (singleton (GEPlus 2))]))
                                                   (PLine2 (GVec [GVal 0.7071067811865475 (singleton (GEPlus 1)), GVal 0.7071067811865475 (singleton (GEPlus 2))]))
                                                   (slist [])
                                                   (Just (PLine2 (GVec [GVal (-0.4870636221857319) (singleton (GEZero 1)), GVal 0.9807852804032305 (singleton (GEPlus 1)), GVal (-0.19509032201612836) (singleton (GEPlus 2))])))
                                            ]
                                           ]
                                    )
                          )
            )
    it "finds the NodeTrees of the only divide of our first simple shape." $
      nodeTreesFromDivision (head $ findDivisions c0 $ fromJust $ crashMotorcycles c0 []) -->
      [
        makeNodeTree [ENode (LineSeg (Point2 (-1.0,1.0)) (Point2 (1.0,-1.0)),LineSeg (Point2 (0.0,0.0)) (Point2 (-1.0,-1.0))) (PLine2 (GVec [GVal (-1.414213562373095) (singleton (GEPlus 2))]))] (INodeSet (slist []))
      ]
    it "finds the NodeTree that is the divide plus the first side of our simple shape." $
     mergeNodeTrees (
                     (fromRight (error "no") $ getNodeTreeOfCell (cellFrom $ findFirstCellOfContour c0 $ findDivisions c0 $ fromJust $ crashMotorcycles c0 []))
                     : (nodeTreesFromDivision (head $ findDivisions c0 $ fromJust $ crashMotorcycles c0 []))
                    ) -->
     makeNodeTree [ ENode (LineSeg (Point2 (1.0,-1.0)) (Point2 (0.0,2.0)), LineSeg (Point2 (1.0,1.0)) (Point2 (-2.0,0.0)))
                          (PLine2 (GVec [GVal (-0.7071067811865475) (singleton (GEPlus 1)), GVal 0.7071067811865475 (singleton (GEPlus 2))]))
                  , ENode (LineSeg (Point2 (1.0,1.0)) (Point2 (-2.0,0.0)), LineSeg (Point2 (-1.0,1.0)) (Point2 (1.0,-1.0)))
                          (PLine2 (GVec [GVal 0.541196100146197 (singleton (GEZero 1)), GVal (-0.3826834323650897) (singleton (GEPlus 1)), GVal (-0.9238795325112867) (singleton (GEPlus 2))]))
                  , ENode (LineSeg (Point2 (-1.0,1.0)) (Point2 (1.0,-1.0)), LineSeg (Point2 (0.0,0.0)) (Point2 (-1.0,-1.0)))
                          (PLine2 (GVec [GVal (-1.414213562373095) (singleton (GEPlus 2))]))
                  ]
                  (INodeSet (slist [
                                     [INode (PLine2 (GVec [GVal (-0.7071067811865475) (singleton (GEPlus 1)), GVal 0.7071067811865475 (singleton (GEPlus 2))]))
                                            (PLine2 (GVec [GVal 0.541196100146197 (singleton (GEZero 1)), GVal (-0.3826834323650897) (singleton (GEPlus 1)), GVal (-0.9238795325112867) (singleton (GEPlus 2))]))
                                            (slist [])
                                            (Just (PLine2 (GVec [GVal 0.4870636221857319 (singleton (GEZero 1)), GVal (-0.9807852804032305) (singleton (GEPlus 1)), GVal (-0.19509032201612836) (singleton (GEPlus 2))])))
                                     ]
                                   , [INode (PLine2 (GVec [GVal 0.4870636221857319 (singleton (GEZero 1)), GVal (-0.9807852804032305) (singleton (GEPlus 1)), GVal (-0.19509032201612836) (singleton (GEPlus 2))]))
                                            (PLine2 (GVec [GVal (-1.414213562373095) (singleton (GEPlus 2))]))
                                            (slist [])
                                            Nothing
                                     ]
                                   ]))
    it "finds the NodeTree that is the divide plus the second side of our simple shape." $
     mergeNodeTrees (
                       (fromRight (error "no") $ getNodeTreeOfCell (cellFrom $ findNextCell $ head $ fromJust $ remainderFrom $ findFirstCellOfContour c0 $ findDivisions c0 $ fromJust $ crashMotorcycles c0 []))
                     : (nodeTreesFromDivision (head $ findDivisions c0 $ fromJust $ crashMotorcycles c0 []))
                    ) -->
     makeNodeTree [ ENode (LineSeg (Point2 (-1.0,1.0)) (Point2 (1.0,-1.0)), LineSeg (Point2 (0.0,0.0)) (Point2 (-1.0,-1.0)))
                          (PLine2 (GVec [GVal (-1.414213562373095) (singleton (GEPlus 2))]))
                  , ENode (LineSeg (Point2 (0.0,0.0)) (Point2 (-1.0,-1.0)), LineSeg (Point2 (-1.0,-1.0)) (Point2 (2.0,0.0)))
                          (PLine2 (GVec [GVal (-0.541196100146197) (singleton (GEZero 1)), GVal 0.3826834323650897 (singleton (GEPlus 1)), GVal (-0.9238795325112867) (singleton (GEPlus 2))]))
                  , ENode (LineSeg (Point2 (-1.0,-1.0)) (Point2 (2.0,0.0)), LineSeg (Point2 (1.0,-1.0)) (Point2 (0.0,2.0)))
                          (PLine2 (GVec [GVal 0.7071067811865475 (singleton (GEPlus 1)), GVal 0.7071067811865475 (singleton (GEPlus 2))]))
                  ]
                  (INodeSet (slist [
                                     [INode (PLine2 (GVec [GVal (-0.541196100146197) (singleton (GEZero 1)), GVal 0.3826834323650897 (singleton (GEPlus 1)), GVal (-0.9238795325112867) (singleton (GEPlus 2))]))
                                            (PLine2 (GVec [GVal 0.7071067811865475 (singleton (GEPlus 1)), GVal 0.7071067811865475 (singleton (GEPlus 2))]))
                                            (slist [])
                                            (Just (PLine2 (GVec [GVal (-0.4870636221857319) (singleton (GEZero 1)), GVal 0.9807852804032305 (singleton (GEPlus 1)), GVal (-0.19509032201612836) (singleton (GEPlus 2))])))
                                     ]
                                   , [INode (PLine2 (GVec [GVal (-1.414213562373095) (singleton (GEPlus 2))]))
                                            (PLine2 (GVec [GVal (-0.4870636221857319) (singleton (GEZero 1)), GVal 0.9807852804032305 (singleton (GEPlus 1)), GVal (-0.19509032201612836) (singleton (GEPlus 2))]))
                                            (slist [])
                                            Nothing
                                     ]
                                   ]))
    it "finds the nodeTree of our first simple shape (two merges)" $
     mergeNodeTrees [
                      (fromRight (error "no") $ getNodeTreeOfCell (cellFrom $ findFirstCellOfContour c0 $ findDivisions c0 $ fromJust $ crashMotorcycles c0 []))
                    , mergeNodeTrees (
                                         (fromRight (error "no") $ getNodeTreeOfCell (cellFrom $ findNextCell $ head $ fromJust $ remainderFrom $ findFirstCellOfContour c0 $ findDivisions c0 $ fromJust $ crashMotorcycles c0 []))
                                       : (nodeTreesFromDivision (head $ findDivisions c0 $ fromJust $ crashMotorcycles c0 []))
                                      )
                    ] -->
     makeNodeTree [ ENode (LineSeg (Point2 (-1.0,1.0)) (Point2 (1.0,-1.0)), LineSeg (Point2 (0.0,0.0)) (Point2 (-1.0,-1.0)))
                          (PLine2 (GVec [GVal (-1.414213562373095) (singleton (GEPlus 2))]))
                  , ENode (LineSeg (Point2 (0.0,0.0)) (Point2 (-1.0,-1.0)), LineSeg (Point2 (-1.0,-1.0)) (Point2 (2.0,0.0)))
                          (PLine2 (GVec [GVal (-0.541196100146197) (singleton (GEZero 1)), GVal 0.3826834323650897 (singleton (GEPlus 1)), GVal (-0.9238795325112867) (singleton (GEPlus 2))]))
                  , ENode (LineSeg (Point2 (-1.0,-1.0)) (Point2 (2.0,0.0)), LineSeg (Point2 (1.0,-1.0)) (Point2 (0.0,2.0)))
                          (PLine2 (GVec [GVal 0.7071067811865475 (singleton (GEPlus 1)), GVal 0.7071067811865475 (singleton (GEPlus 2))]))
                  , ENode (LineSeg (Point2 (1.0,-1.0)) (Point2 (0.0,2.0)), LineSeg (Point2 (1.0,1.0)) (Point2 (-2.0,0.0)))
                          (PLine2 (GVec [GVal (-0.7071067811865475) (singleton (GEPlus 1)), GVal 0.7071067811865475 (singleton (GEPlus 2))]))
                  , ENode (LineSeg (Point2 (1.0,1.0)) (Point2 (-2.0,0.0)), LineSeg (Point2 (-1.0,1.0)) (Point2 (1.0,-1.0)))
                          (PLine2 (GVec [GVal 0.541196100146197 (singleton (GEZero 1)), GVal (-0.3826834323650897) (singleton (GEPlus 1)), GVal (-0.9238795325112867) (singleton (GEPlus 2))]))
                  ]
                  (INodeSet (slist [
                                     [INode
                                            (PLine2 (GVec [GVal (-0.541196100146197) (singleton (GEZero 1)), GVal 0.3826834323650897 (singleton (GEPlus 1)), GVal (-0.9238795325112867) (singleton (GEPlus 2))]))
                                            (PLine2 (GVec [GVal 0.7071067811865475 (singleton (GEPlus 1)), GVal 0.7071067811865475 (singleton (GEPlus 2))]))
                                            (slist [])
                                            (Just (PLine2 (GVec [GVal (-0.4870636221857319) (singleton (GEZero 1)), GVal 0.9807852804032305 (singleton (GEPlus 1)), GVal (-0.19509032201612836) (singleton (GEPlus 2))])))
                                     ,INode (PLine2 (GVec [GVal (-0.7071067811865475) (singleton (GEPlus 1)), GVal 0.7071067811865475 (singleton (GEPlus 2))]))
                                            (PLine2 (GVec [GVal 0.541196100146197 (singleton (GEZero 1)), GVal (-0.3826834323650897) (singleton (GEPlus 1)), GVal (-0.9238795325112867) (singleton (GEPlus 2))]))
                                            (slist [])
                                            (Just (PLine2 (GVec [GVal 0.4870636221857319 (singleton (GEZero 1)), GVal (-0.9807852804032305) (singleton (GEPlus 1)), GVal (-0.19509032201612836) (singleton (GEPlus 2))])))
                                     ]
                                   , [INode
                                            (PLine2 (GVec [GVal (-1.414213562373095) (singleton (GEPlus 2))]))
                                            (PLine2 (GVec [GVal (-0.4870636221857319) (singleton (GEZero 1)), GVal 0.9807852804032305 (singleton (GEPlus 1)), GVal (-0.19509032201612836) (singleton (GEPlus 2))]))
                                            (slist [(PLine2 (GVec [GVal 0.4870636221857319 (singleton (GEZero 1)), GVal (-0.9807852804032305) (singleton (GEPlus 1)), GVal (-0.19509032201612836) (singleton (GEPlus 2))]))])
                                            Nothing
                                     ]
                                   ]))
    it "finds the nodeTree of our first simple shape (all at once)" $
     mergeNodeTrees (
                       (fromRight (error "no") $ getNodeTreeOfCell (cellFrom $ findFirstCellOfContour c0 $ findDivisions c0 $ fromJust $ crashMotorcycles c0 []))
                     : (fromRight (error "no") $ getNodeTreeOfCell (cellFrom $ findNextCell $ head $ fromJust $ remainderFrom $ findFirstCellOfContour c0 $ findDivisions c0 $ fromJust $ crashMotorcycles c0 []))
                     : (nodeTreesFromDivision (head $ findDivisions c0 $ fromJust $ crashMotorcycles c0 []))
                    ) -->
      makeNodeTree [ENode (LineSeg (Point2 (-1.0,1.0)) (Point2 (1.0,-1.0)), LineSeg (Point2 (0.0,0.0)) (Point2 (-1.0,-1.0)))
                           (PLine2 (GVec [GVal (-1.414213562373095) (singleton (GEPlus 2))]))
                   , ENode (LineSeg (Point2 (0.0,0.0)) (Point2 (-1.0,-1.0)), LineSeg (Point2 (-1.0,-1.0)) (Point2 (2.0,0.0)))
                           (PLine2 (GVec [GVal (-0.541196100146197) (singleton (GEZero 1)), GVal 0.3826834323650897 (singleton (GEPlus 1)), GVal (-0.9238795325112867) (singleton (GEPlus 2))]))
                   , ENode (LineSeg (Point2 (-1.0,-1.0)) (Point2 (2.0,0.0)), LineSeg (Point2 (1.0,-1.0)) (Point2 (0.0,2.0)))
                           (PLine2 (GVec [GVal 0.7071067811865475 (singleton (GEPlus 1)), GVal 0.7071067811865475 (singleton (GEPlus 2))]))
                   , ENode (LineSeg (Point2 (1.0,-1.0)) (Point2 (0.0,2.0)), LineSeg (Point2 (1.0,1.0)) (Point2 (-2.0,0.0)))
                           (PLine2 (GVec [GVal (-0.7071067811865475) (singleton (GEPlus 1)), GVal 0.7071067811865475 (singleton (GEPlus 2))]))
                   , ENode (LineSeg (Point2 (1.0,1.0)) (Point2 (-2.0,0.0)), LineSeg (Point2 (-1.0,1.0)) (Point2 (1.0,-1.0)))
                           (PLine2 (GVec [GVal 0.541196100146197 (singleton (GEZero 1)), GVal (-0.3826834323650897) (singleton (GEPlus 1)), GVal (-0.9238795325112867) (singleton (GEPlus 2))]))
                   ]
                  (INodeSet (slist [
                                     [INode
                                            (PLine2 (GVec [GVal (-0.541196100146197) (singleton (GEZero 1)), GVal 0.3826834323650897 (singleton (GEPlus 1)), GVal (-0.9238795325112867) (singleton (GEPlus 2))]))
                                            (PLine2 (GVec [GVal 0.7071067811865475 (singleton (GEPlus 1)), GVal 0.7071067811865475 (singleton (GEPlus 2))]))
                                            (slist [])
                                            (Just (PLine2 (GVec [GVal (-0.4870636221857319) (singleton (GEZero 1)), GVal 0.9807852804032305 (singleton (GEPlus 1)), GVal (-0.19509032201612836) (singleton (GEPlus 2))])))
                                     ,INode (PLine2 (GVec [GVal (-0.7071067811865475) (singleton (GEPlus 1)), GVal 0.7071067811865475 (singleton (GEPlus 2))]))
                                            (PLine2 (GVec [GVal 0.541196100146197 (singleton (GEZero 1)), GVal (-0.3826834323650897) (singleton (GEPlus 1)), GVal (-0.9238795325112867) (singleton (GEPlus 2))]))
                                            (slist [])
                                            (Just (PLine2 (GVec [GVal 0.4870636221857319 (singleton (GEZero 1)), GVal (-0.9807852804032305) (singleton (GEPlus 1)), GVal (-0.19509032201612836) (singleton (GEPlus 2))])))
                                     ]
                                   , [INode
                                            (PLine2 (GVec [GVal (-1.414213562373095) (singleton (GEPlus 2))]))
                                            (PLine2 (GVec [GVal (-0.4870636221857319) (singleton (GEZero 1)), GVal 0.9807852804032305 (singleton (GEPlus 1)), GVal (-0.19509032201612836) (singleton (GEPlus 2))]))
                                            (slist [(PLine2 (GVec [GVal 0.4870636221857319 (singleton (GEZero 1)), GVal (-0.9807852804032305) (singleton (GEPlus 1)), GVal (-0.19509032201612836) (singleton (GEPlus 2))]))])
                                            Nothing
                                     ]
                                   ]))
    it "finds the NodeTree of the first cell of our second simple shape." $
      getNodeTreeOfCell (cellFrom $ findFirstCellOfContour c1 $ findDivisions c1 $ fromJust $ crashMotorcycles c1 []) -->
      Right (makeNodeTree [ ENode (LineSeg (Point2 (0.0,0.0)) (Point2 (1.0,-1.0)), LineSeg (Point2 (1.0,-1.0)) (Point2 (0.0,2.0)))
                                  (PLine2 (GVec [GVal (-0.541196100146197) (singleton (GEZero 1)), GVal 0.9238795325112867 (singleton (GEPlus 1)), GVal 0.3826834323650897 (singleton (GEPlus 2))])) 
                          , ENode (LineSeg (Point2 (1.0,-1.0)) (Point2 (0.0,2.0)), LineSeg (Point2 (1.0,1.0)) (Point2 (-2.0,0.0)))
                                  (PLine2 (GVec [GVal (-0.7071067811865475) (singleton (GEPlus 1)), GVal 0.7071067811865475 (singleton (GEPlus 2))]))
                          ]
                          (INodeSet (slist [
                                            [INode (PLine2 (GVec [GVal (-0.541196100146197) (singleton (GEZero 1)), GVal 0.9238795325112867 (singleton (GEPlus 1)), GVal 0.3826834323650897 (singleton (GEPlus 2))])) 
                                                   (PLine2 (GVec [GVal (-0.7071067811865475) (singleton (GEPlus 1)), GVal 0.7071067811865475 (singleton (GEPlus 2))]))
                                                    (slist [])
                                              (Just (PLine2 (GVec [GVal (-0.4870636221857319) (singleton (GEZero 1)), GVal 0.19509032201612836 (singleton (GEPlus 1)), GVal 0.9807852804032305 (singleton (GEPlus 2))]))) 
                                            ]
                                           ]
                                    )
                          )
            )
    it "finds the NodeTree of the first cell of our third simple shape." $
      getNodeTreeOfCell (cellFrom $ findFirstCellOfContour c2 $ findDivisions c2 $ fromJust $ crashMotorcycles c2 []) -->
      Right (makeNodeTree [ ENode (LineSeg (Point2 (0.0,0.0)) (Point2 (1.0,1.0)), LineSeg (Point2 (1.0,1.0)) (Point2 (-2.0,0.0)))
                                  (PLine2 (GVec [GVal (-0.541196100146197) (singleton (GEZero 1)), GVal (-0.3826834323650897) (singleton (GEPlus 1)), GVal 0.9238795325112867 (singleton (GEPlus 2))]))
                          , ENode (LineSeg (Point2 (1.0,1.0)) (Point2 (-2.0,0.0)), LineSeg (Point2 (-1.0,1.0)) (Point2 (0.0,-2.0)))
                                  (PLine2 (GVec [GVal (-0.7071067811865475) (singleton (GEPlus 1)), GVal (-0.7071067811865475) (singleton (GEPlus 2))]))
                          ]
                          (INodeSet (slist [
                                            [INode (PLine2 (GVec [GVal (-0.541196100146197) (singleton (GEZero 1)), GVal (-0.3826834323650897) (singleton (GEPlus 1)), GVal 0.9238795325112867 (singleton (GEPlus 2))]))
                                                   (PLine2 (GVec [GVal (-0.7071067811865475) (singleton (GEPlus 1)), GVal (-0.7071067811865475) (singleton (GEPlus 2))]))
                                                    (slist [])
                                              (Just (PLine2 (GVec [GVal (-0.4870636221857319) (singleton (GEZero 1)), GVal (-0.9807852804032305) (singleton (GEPlus 1)), GVal 0.19509032201612836 (singleton (GEPlus 2))])))
                                            ]
                                           ]
                                    )
                          )
            )
  describe "Straight Skeleton (Skeleton/Skeleton)" $ do
    it "finds the straight skeleton of our first simple shape." $
      findStraightSkeleton c0 [] -->
      Just (StraightSkeleton [[ makeNodeTree [ ENode (LineSeg (Point2 (-1.0,1.0)) (Point2 (1.0,-1.0)), LineSeg (Point2 (0.0,0.0)) (Point2 (-1.0,-1.0)))
                                                     (PLine2 (GVec [GVal (-1.414213562373095) (singleton (GEPlus 2))]))
                                             , ENode (LineSeg (Point2 (0.0,0.0)) (Point2 (-1.0,-1.0)), LineSeg (Point2 (-1.0,-1.0)) (Point2 (2.0,0.0)))
                                                    (PLine2 (GVec [GVal (-0.541196100146197) (singleton (GEZero 1)), GVal 0.3826834323650897 (singleton (GEPlus 1)), GVal (-0.9238795325112867) (singleton (GEPlus 2))]))
                                             , ENode (LineSeg (Point2 (-1.0,-1.0)) (Point2 (2.0,0.0)), LineSeg (Point2 (1.0,-1.0)) (Point2 (0.0,2.0)))
                                                     (PLine2 (GVec [GVal 0.7071067811865475 (singleton (GEPlus 1)), GVal 0.7071067811865475 (singleton (GEPlus 2))]))
                                             , ENode (LineSeg (Point2 (1.0,-1.0)) (Point2 (0.0,2.0)), LineSeg (Point2 (1.0,1.0)) (Point2 (-2.0,0.0)))
                                                     (PLine2 (GVec [GVal (-0.7071067811865475) (singleton (GEPlus 1)), GVal 0.7071067811865475 (singleton (GEPlus 2))]))
                                             , ENode (LineSeg (Point2 (1.0,1.0)) (Point2 (-2.0,0.0)), LineSeg (Point2 (-1.0,1.0)) (Point2 (1.0,-1.0)))
                                                     (PLine2 (GVec [GVal 0.541196100146197 (singleton (GEZero 1)), GVal (-0.3826834323650897) (singleton (GEPlus 1)), GVal (-0.9238795325112867) (singleton (GEPlus 2))]))
                                             ]
                                             (INodeSet (slist [
                                                               [INode (PLine2 (GVec [GVal (-0.541196100146197) (singleton (GEZero 1)), GVal 0.3826834323650897 (singleton (GEPlus 1)), GVal (-0.9238795325112867) (singleton (GEPlus 2))]))
                                                                      (PLine2 (GVec [GVal 0.7071067811865475 (singleton (GEPlus 1)), GVal 0.7071067811865475 (singleton (GEPlus 2))]))
                                                                      (slist [])
                                                                      (Just (PLine2 (GVec [GVal (-0.4870636221857319) (singleton (GEZero 1)), GVal 0.9807852804032305 (singleton (GEPlus 1)), GVal (-0.19509032201612836) (singleton (GEPlus 2))])))
                                                               ,INode (PLine2 (GVec [GVal (-0.7071067811865475) (singleton (GEPlus 1)), GVal 0.7071067811865475 (singleton (GEPlus 2))]))
                                                                      (PLine2 (GVec [GVal 0.541196100146197 (singleton (GEZero 1)), GVal (-0.3826834323650897) (singleton (GEPlus 1)), GVal (-0.9238795325112867) (singleton (GEPlus 2))]))
                                                                      (slist [])
                                                                      (Just (PLine2 (GVec [GVal 0.4870636221857319 (singleton (GEZero 1)), GVal (-0.9807852804032305) (singleton (GEPlus 1)), GVal (-0.19509032201612836) (singleton (GEPlus 2))])))
                                                               ]
                                                              , [INode (PLine2 (GVec [GVal (-1.414213562373095) (singleton (GEPlus 2))]))
                                                                       (PLine2 (GVec [GVal (-0.4870636221857319) (singleton (GEZero 1)), GVal 0.9807852804032305 (singleton (GEPlus 1)), GVal (-0.19509032201612836) (singleton (GEPlus 2))]))
                                                                       (slist [(PLine2 (GVec [GVal 0.4870636221857319 (singleton (GEZero 1)), GVal (-0.9807852804032305) (singleton (GEPlus 1)), GVal (-0.19509032201612836) (singleton (GEPlus 2))]))])
                                                                       Nothing
                                                                ]
                                                              ]))
                              ]] (slist []))
    it "finds the straight skeleton of our second simple shape." $
      findStraightSkeleton c1 [] -->
      Just (StraightSkeleton [[makeNodeTree [ENode (LineSeg (Point2 (1.0,1.0)) (Point2 (-2.0,0.0)), LineSeg (Point2 (-1.0,1.0)) (Point2 (0.0,-2.0)))
                                                   (PLine2 (GVec [GVal (-0.7071067811865475) (singleton (GEPlus 1)), GVal (-0.7071067811865475) (singleton (GEPlus 2))]))
                                            ,ENode (LineSeg (Point2 (-1.0,1.0)) (Point2 (0.0,-2.0)), LineSeg (Point2 (-1.0,-1.0)) (Point2 (1.0,1.0)))
                                                   (PLine2 (GVec [GVal 0.541196100146197 (singleton (GEZero 1)), GVal 0.9238795325112867 (singleton (GEPlus 1)), GVal (-0.3826834323650897) (singleton (GEPlus 2))]))
                                            ,ENode (LineSeg (Point2 (-1.0,-1.0)) (Point2 (1.0,1.0)), LineSeg (Point2 (0.0,0.0)) (Point2 (1.0,-1.0)))
                                                   (PLine2 (GVec [GVal 1.414213562373095 (singleton (GEPlus 1))]))
                                            ,ENode (LineSeg (Point2 (0.0,0.0)) (Point2 (1.0,-1.0)), LineSeg (Point2 (1.0,-1.0)) (Point2 (0.0,2.0)))
                                                   (PLine2 (GVec [GVal (-0.541196100146197) (singleton (GEZero 1)), GVal 0.9238795325112867 (singleton (GEPlus 1)), GVal 0.3826834323650897 (singleton (GEPlus 2))]))
                                            ,ENode (LineSeg (Point2 (1.0,-1.0)) (Point2 (0.0,2.0)), LineSeg (Point2 (1.0,1.0)) (Point2 (-2.0,0.0)))
                                                   (PLine2 (GVec [GVal (-0.7071067811865475) (singleton (GEPlus 1)), GVal 0.7071067811865475 (singleton (GEPlus 2))]))
                                            ]
                                            (INodeSet (slist [
                                                              [INode (PLine2 (GVec [GVal (-0.7071067811865475) (singleton (GEPlus 1)), GVal (-0.7071067811865475) (singleton (GEPlus 2))]))
                                                                     (PLine2 (GVec [GVal 0.541196100146197 (singleton (GEZero 1)), GVal 0.9238795325112867 (singleton (GEPlus 1)), GVal (-0.3826834323650897) (singleton (GEPlus 2))]))
                                                                     (slist [])
                                                                     (Just (PLine2 (GVec [GVal 0.4870636221857319 (singleton (GEZero 1)), GVal 0.19509032201612836 (singleton (GEPlus 1)), GVal (-0.9807852804032305) (singleton (GEPlus 2))])))
                                                              ,INode (PLine2 (GVec [GVal (-0.541196100146197) (singleton (GEZero 1)), GVal 0.9238795325112867 (singleton (GEPlus 1)), GVal 0.3826834323650897 (singleton (GEPlus 2))]))
                                                                     (PLine2 (GVec [GVal (-0.7071067811865475) (singleton (GEPlus 1)), GVal 0.7071067811865475 (singleton (GEPlus 2))]))
                                                                     (slist [])
                                                                     (Just (PLine2 (GVec [GVal (-0.4870636221857319) (singleton (GEZero 1)), GVal 0.19509032201612836 (singleton (GEPlus 1)), GVal 0.9807852804032305 (singleton (GEPlus 2))])))
                                                              ]
                                                             ,[INode (PLine2 (GVec [GVal 0.4870636221857319 (singleton (GEZero 1)), GVal 0.19509032201612836 (singleton (GEPlus 1)), GVal (-0.9807852804032305) (singleton (GEPlus 2))]))
                                                                     (PLine2 (GVec [GVal 1.414213562373095 (singleton (GEPlus 1))]))
                                                                     (slist [PLine2 (GVec [GVal (-0.4870636221857319) (singleton (GEZero 1)), GVal 0.19509032201612836 (singleton (GEPlus 1)), GVal 0.9807852804032305 (singleton (GEPlus 2))])])
                                                                Nothing
                                                              ]
                                                             ]))
                              ]] (slist []))
    it "finds the straight skeleton of our third simple shape." $
      findStraightSkeleton c2 [] -->
      Just (StraightSkeleton [[makeNodeTree [ENode (LineSeg (Point2 (-1.0,1.0)) (Point2 (0.0,-2.0)), LineSeg (Point2 (-1.0,-1.0)) (Point2 (2.0,0.0)))
                                                   (PLine2 (GVec [GVal 0.7071067811865475 (singleton (GEPlus 1)), GVal (-0.7071067811865475) (singleton (GEPlus 2))]))
                                            ,ENode (LineSeg (Point2 (-1.0,-1.0)) (Point2 (2.0,0.0)), LineSeg (Point2 (1.0,-1.0)) (Point2 (-1.0,1.0)))
                                                   (PLine2 (GVec [GVal 0.541196100146197 (singleton (GEZero 1)), GVal 0.3826834323650897 (singleton (GEPlus 1)), GVal  0.9238795325112867 (singleton (GEPlus 2))]))
                                            ,ENode (LineSeg (Point2 (1.0,-1.0)) (Point2 (-1.0,1.0)), LineSeg (Point2 (0.0,0.0)) (Point2 (1.0,1.0)))
                                                   (PLine2 (GVec [GVal 1.414213562373095 (singleton (GEPlus 2))]))
                                            ,ENode (LineSeg (Point2 (0.0,0.0)) (Point2 (1.0,1.0)), LineSeg (Point2 (1.0,1.0)) (Point2 (-2.0,0.0)))
                                                   (PLine2 (GVec [GVal (-0.541196100146197) (singleton (GEZero 1)), GVal (-0.3826834323650897) (singleton (GEPlus 1)), GVal 0.9238795325112867 (singleton (GEPlus 2))]))
                                            ,ENode (LineSeg (Point2 (1.0,1.0)) (Point2 (-2.0,0.0)), LineSeg (Point2 (-1.0,1.0)) (Point2 (0.0,-2.0)))
                                                   (PLine2 (GVec [GVal (-0.7071067811865475) (singleton (GEPlus 1)), GVal (-0.7071067811865475) (singleton (GEPlus 2))]))
                                            ]
                                            (INodeSet (slist [
                                                              [INode (PLine2 (GVec [GVal 0.7071067811865475 (singleton (GEPlus 1)), GVal (-0.7071067811865475) (singleton (GEPlus 2))]))
                                                                     (PLine2 (GVec [GVal 0.541196100146197 (singleton (GEZero 1)), GVal 0.3826834323650897 (singleton (GEPlus 1)), GVal 0.9238795325112867 (singleton (GEPlus 2))]))
                                                                     (slist [])
                                                                     (Just (PLine2 (GVec [GVal 0.4870636221857319 (singleton (GEZero 1)), GVal 0.9807852804032305 (singleton (GEPlus 1)), GVal 0.19509032201612836 (singleton (GEPlus 2))])))
                                                              ,INode (PLine2 (GVec [GVal (-0.541196100146197) (singleton (GEZero 1)), GVal (-0.3826834323650897) (singleton (GEPlus 1)), GVal 0.9238795325112867 (singleton (GEPlus 2))]))
                                                                     (PLine2 (GVec [GVal (-0.7071067811865475) (singleton (GEPlus 1)), GVal (-0.7071067811865475) (singleton (GEPlus 2))]))
                                                                     (slist [])
                                                                     (Just (PLine2 (GVec [GVal (-0.4870636221857319) (singleton (GEZero 1)), GVal (-0.9807852804032305) (singleton (GEPlus 1)), GVal 0.19509032201612836 (singleton (GEPlus 2))])))
                                                              ]
                                                             ,[INode (PLine2 (GVec [GVal 0.4870636221857319 (singleton (GEZero 1)), GVal 0.9807852804032305 (singleton (GEPlus 1)), GVal 0.19509032201612836 (singleton (GEPlus 2))]))
                                                                     (PLine2 (GVec [GVal 1.414213562373095 (singleton (GEPlus 2))]))
                                                                     (slist [(PLine2 (GVec [GVal (-0.4870636221857319) (singleton (GEZero 1)), GVal (-0.9807852804032305) (singleton (GEPlus 1)), GVal 0.19509032201612836 (singleton (GEPlus 2))]))])
                                                                     Nothing
                                                              ]
                                                             ]))
                              ]] (slist []))
    it "finds the straight skeleton of our fourth simple shape." $
      findStraightSkeleton c3 [] -->
      Just (StraightSkeleton [[makeNodeTree [ENode (LineSeg (Point2 (1.0,1.0)) (Point2 (-1.0,-1.0)), LineSeg (Point2 (0.0,0.0)) (Point2 (-1.0,1.0)))
                                                   (PLine2 (GVec [GVal (-1.414213562373095) (singleton (GEPlus 1))]))
                                            ,ENode (LineSeg (Point2 (0.0,0.0)) (Point2 (-1.0,1.0)), LineSeg (Point2 (-1.0,1.0)) (Point2 (0.0,-2.0)))
                                                   (PLine2 (GVec [GVal (-0.541196100146197) (singleton (GEZero 1)), GVal (-0.9238795325112867) (singleton (GEPlus 1)), GVal (-0.3826834323650897) (singleton (GEPlus 2))]))
                                            ,ENode (LineSeg (Point2 (-1.0,1.0)) (Point2 (0.0,-2.0)), LineSeg (Point2 (-1.0,-1.0)) (Point2 (2.0,0.0)))
                                                   (PLine2 (GVec [GVal 0.7071067811865475 (singleton (GEPlus 1)), GVal (-0.7071067811865475) (singleton (GEPlus 2))]))
                                            ,ENode (LineSeg (Point2 (-1.0,-1.0)) (Point2 (2.0,0.0)), LineSeg (Point2 (1.0,-1.0)) (Point2 (0.0,2.0)))
                                                   (PLine2 (GVec [GVal 0.7071067811865475 (singleton (GEPlus 1)), GVal 0.7071067811865475 (singleton (GEPlus 2))]))
                                            ,ENode (LineSeg (Point2 (1.0,-1.0)) (Point2 (0.0,2.0)), LineSeg (Point2 (1.0,1.0)) (Point2 (-1.0,-1.0)))
                                                   (PLine2 (GVec [GVal 0.541196100146197 (singleton (GEZero 1)), GVal (-0.9238795325112867) (singleton (GEPlus 1)), GVal 0.3826834323650897 (singleton (GEPlus 2))]))
                                            ]
                                            (INodeSet (slist [
                                                              [INode (PLine2 (GVec [GVal (-0.541196100146197) (singleton (GEZero 1)), GVal (-0.9238795325112867) (singleton (GEPlus 1)), GVal (-0.3826834323650897) (singleton (GEPlus 2))]))
                                                                     (PLine2 (GVec [GVal 0.7071067811865475 (singleton (GEPlus 1)), GVal (-0.7071067811865475) (singleton (GEPlus 2))]))
                                                                     (slist [])
                                                                     (Just (PLine2 (GVec [GVal (-0.4870636221857319) (singleton (GEZero 1)), GVal (-0.19509032201612836) (singleton (GEPlus 1)), GVal (-0.9807852804032305) (singleton (GEPlus 2))])))
                                                              ,INode (PLine2 (GVec [GVal 0.7071067811865475 (singleton (GEPlus 1)), GVal 0.7071067811865475 (singleton (GEPlus 2))]))
                                                                     (PLine2 (GVec [GVal 0.541196100146197 (singleton (GEZero 1)), GVal (-0.9238795325112867) (singleton (GEPlus 1)), GVal 0.3826834323650897 (singleton (GEPlus 2))]))
                                                                     (slist [])
                                                                     (Just (PLine2 (GVec [GVal 0.4870636221857319 (singleton (GEZero 1)), GVal (-0.19509032201612836) (singleton (GEPlus 1)), GVal 0.9807852804032305 (singleton (GEPlus 2))])))
                                                              ]
                                                             ,[INode (PLine2 (GVec [GVal (-1.414213562373095) (singleton (GEPlus 1))]))
                                                                     (PLine2 (GVec [GVal (-0.4870636221857319) (singleton (GEZero 1)), GVal (-0.19509032201612836) (singleton (GEPlus 1)), GVal (-0.9807852804032305) (singleton (GEPlus 2))]))
                                                                     (slist [(PLine2 (GVec [GVal 0.4870636221857319 (singleton (GEZero 1)), GVal (-0.19509032201612836) (singleton (GEPlus 1)), GVal 0.9807852804032305 (singleton (GEPlus 2))]))])
                                                                     Nothing
                                                              ]]))
                              ]] (slist []))
    it "finds the straight skeleton of our fifth simple shape." $
      findStraightSkeleton c4 [] -->
      Just (StraightSkeleton [[makeNodeTree [
                                             ENode (LineSeg (Point2 (-1.0,1.0)) (Point2 (1.0,-1.0)), LineSeg (Point2 (0.0,0.0)) (Point2 (-1.0,-1.0)))
                                                   (PLine2 (GVec [GVal (-1.414213562373095) (singleton (GEPlus 2))]))
                                            ,ENode (LineSeg (Point2 (0.0,0.0)) (Point2 (-1.0,-1.0)), LineSeg (Point2 (-1.0,-1.0)) (Point2 (2.0,0.0)))
                                                   (PLine2 (GVec [GVal (-0.541196100146197) (singleton (GEZero 1)), GVal 0.3826834323650897 (singleton (GEPlus 1)), GVal  (-0.9238795325112867) (singleton (GEPlus 2))]))
                                            ,ENode (LineSeg (Point2 (-1.0,-1.0)) (Point2 (2.0,0.0)), LineSeg (Point2 (1.0,-1.0)) (Point2 (0.0,2.0)))
                                                   (PLine2 (GVec [GVal 0.7071067811865475 (singleton (GEPlus 1)), GVal 0.7071067811865475 (singleton (GEPlus 2))]))
                                            ,ENode (LineSeg (Point2 (1.0,-1.0)) (Point2 (0.0,2.0)), LineSeg (Point2 (1.0,1.0)) (Point2 (-2.0,0.0)))
                                                   (PLine2 (GVec [GVal (-0.7071067811865475) (singleton (GEPlus 1)), GVal 0.7071067811865475 (singleton (GEPlus 2))]))
                                            ,ENode (LineSeg (Point2 (1.0,1.0)) (Point2 (-2.0,0.0)), LineSeg (Point2 (-1.0,1.0)) (Point2 (1.0,-1.0)))
                                                   (PLine2 (GVec [GVal 0.541196100146197 (singleton (GEZero 1)), GVal (-0.3826834323650897) (singleton (GEPlus 1)), GVal  (-0.9238795325112867) (singleton (GEPlus 2))]))
                                            ]
                                            (INodeSet (slist [
                                                              [
                                                               INode (PLine2 (GVec [GVal (-0.541196100146197) (singleton (GEZero 1)), GVal 0.3826834323650897 (singleton (GEPlus 1)), GVal  (-0.9238795325112867) (singleton (GEPlus 2))]))
                                                                     (PLine2 (GVec [GVal 0.7071067811865475 (singleton (GEPlus 1)), GVal 0.7071067811865475 (singleton (GEPlus 2))]))
                                                                     (slist [])
                                                               (Just (PLine2 (GVec [GVal (-0.4870636221857319) (singleton (GEZero 1)), GVal 0.9807852804032305 (singleton (GEPlus 1)), GVal (-0.19509032201612836) (singleton (GEPlus 2))])))
                                                              ,INode (PLine2 (GVec [GVal (-0.7071067811865475) (singleton (GEPlus 1)), GVal 0.7071067811865475 (singleton (GEPlus 2))]))
                                                                     (PLine2 (GVec [GVal 0.541196100146197 (singleton (GEZero 1)), GVal (-0.3826834323650897) (singleton (GEPlus 1)), GVal  (-0.9238795325112867) (singleton (GEPlus 2))]))
                                                                     (slist [])
                                                                     (Just (PLine2 (GVec [GVal 0.4870636221857319 (singleton (GEZero 1)), GVal (-0.9807852804032305) (singleton (GEPlus 1)), GVal (-0.19509032201612836) (singleton (GEPlus 2))])))
                                                              ]
                                                             ,[INode (PLine2 (GVec [GVal (-1.414213562373095) (singleton (GEPlus 2))]))
                                                                     (PLine2 (GVec [GVal (-0.4870636221857319) (singleton (GEZero 1)), GVal 0.9807852804032305 (singleton (GEPlus 1)), GVal (-0.19509032201612836) (singleton (GEPlus 2))]))
                                                                     (slist [(PLine2 (GVec [GVal 0.4870636221857319 (singleton (GEZero 1)), GVal (-0.9807852804032305) (singleton (GEPlus 1)), GVal (-0.19509032201612836) (singleton (GEPlus 2))]))])
                                                                     Nothing
                                                              ]
                                                             ]))
                              ]] (slist []))
    it "finds the eNodes of our sixth simple shape." $
      eNodesOfOutsideContour c5 --> [
                                      ENode (LineSeg (Point2 (-1.0,-1.0)) (Point2 (2.0,0.0)),LineSeg (Point2 (1.0,-1.0)) (Point2 (1.0,1.0)))
                                            (PLine2 (GVec [GVal (-0.5411961001461969) (fromList [GEZero 1]), GVal 0.9238795325112867 (fromList [GEPlus 1]), GVal 0.3826834323650899 (fromList [GEPlus 2])]))
                                    , ENode (LineSeg (Point2 (1.0,-1.0)) (Point2 (1.0,1.0)),LineSeg (Point2 (2.0,0.0)) (Point2 (-1.0,1.0)))
                                            (PLine2 (GVec [GVal 1.0 (fromList [GEPlus 2])]))
                                    , ENode (LineSeg (Point2 (2.0,0.0)) (Point2 (-1.0,1.0)),LineSeg (Point2 (1.0,1.0)) (Point2 (-2.0,0.0)))
                                            (PLine2 (GVec [GVal 0.5411961001461969 (fromList [GEZero 1]), GVal (-0.9238795325112867) (fromList [GEPlus 1]), GVal 0.3826834323650899 (fromList [GEPlus 2])]))
                                    , ENode (LineSeg (Point2 (1.0,1.0)) (Point2 (-2.0,0.0)),LineSeg (Point2 (-1.0,1.0)) (Point2 (1.0,-1.0)))
                                            (PLine2 (GVec [GVal 0.541196100146197 (fromList [GEZero 1]), GVal (-0.3826834323650897) (fromList [GEPlus 1]), GVal (-0.9238795325112867) (fromList [GEPlus 2])]))
                                    , ENode (LineSeg (Point2 (0.0,0.0)) (Point2 (-1.0,-1.0)),LineSeg (Point2 (-1.0,-1.0)) (Point2 (2.0,0.0)))
                                            (PLine2 (GVec [GVal (-0.541196100146197) (fromList [GEZero 1]), GVal 0.3826834323650897 (fromList [GEPlus 1]), GVal (-0.9238795325112867) (fromList [GEPlus 2])]))]
    it "finds one the motorcycle of our sixth simple shape" $
      convexMotorcycles c5 --> [Motorcycle (LineSeg (Point2 (-1.0,1.0)) (Point2 (1.0,-1.0)), LineSeg (Point2 (0.0,0.0)) (Point2 (-1.0,-1.0))) (PLine2 (GVec [GVal (-1.414213562373095) (singleton (GEPlus 2))]))]
    it "finds the crashtree of our fifth shape." $
      crashMotorcycles c5 [] --> Just (CrashTree (slist [Motorcycle (LineSeg (Point2 (-1.0,1.0)) (Point2 (1.0,-1.0)), LineSeg (Point2 (0.0,0.0)) (Point2 (-1.0,-1.0))) (PLine2 (GVec [GVal (-1.414213562373095) (fromList [GEPlus 2])]))])
                                                 (slist [Motorcycle (LineSeg (Point2 (-1.0,1.0)) (Point2 (1.0,-1.0)), LineSeg (Point2 (0.0,0.0)) (Point2 (-1.0,-1.0))) (PLine2 (GVec [GVal (-1.414213562373095) (fromList [GEPlus 2])]))])
                                                 (slist []))
    it "finds the divide of our sixth shape." $
      findDivisions c5 (fromJust $ crashMotorcycles c5 []) --> [CellDivide
                                                                  (DividingMotorcycles
                                                                     (Motorcycle (LineSeg (Point2 (-1.0,1.0)) (Point2 (1.0,-1.0)), LineSeg (Point2 (0.0,0.0)) (Point2 (-1.0,-1.0))) (PLine2 (GVec [GVal (-1.414213562373095) (fromList [GEPlus 2])])))
                                                                     (slist []))
                                                                  (Just $ ENode (LineSeg (Point2 (1.0,-1.0)) (Point2 (1.0,1.0)), LineSeg (Point2 (2.0,0.0)) (Point2 (-1.0,1.0))) (PLine2 (GVec [GVal 1.0 (fromList [GEPlus 2])])))
                                                               ]
    it "finds the straight skeleton of our sixth simple shape." $
      findStraightSkeleton c5 [] -->
      Just (StraightSkeleton [[makeNodeTree [ENode (LineSeg (Point2 (-1.0,1.0)) (Point2 (1.0,-1.0)), LineSeg (Point2 (0.0,0.0)) (Point2 (-1.0,-1.0)))
                                                   (PLine2 (GVec [GVal (-1.414213562373095) (singleton (GEPlus 2))]))
                                            ,ENode (LineSeg (Point2 (0.0,0.0)) (Point2 (-1.0,-1.0)), LineSeg (Point2 (-1.0,-1.0)) (Point2 (2.0,0.0)))
                                                   (PLine2 (GVec [GVal (-0.541196100146197) (singleton (GEZero 1)), GVal 0.3826834323650897 (singleton (GEPlus 1)), GVal (-0.9238795325112867) (singleton (GEPlus 2))]))
                                            ,ENode (LineSeg (Point2 (-1.0,-1.0)) (Point2 (2.0,0.0)), LineSeg (Point2 (1.0,-1.0)) (Point2 (1.0,1.0)))
                                                   (PLine2 (GVec [GVal (-0.5411961001461969) (singleton (GEZero 1)), GVal 0.9238795325112867 (singleton (GEPlus 1)), GVal 0.3826834323650899 (singleton (GEPlus 2))]))
                                            ,ENode (LineSeg (Point2 (1.0,-1.0)) (Point2 (1.0,1.0)), LineSeg (Point2 (2.0,0.0)) (Point2 (-1.0,1.0)))
                                                   (PLine2 (GVec [GVal 1.0 (singleton (GEPlus 2))]))
                                            ,ENode (LineSeg (Point2 (2.0,0.0)) (Point2 (-1.0,1.0)), LineSeg (Point2 (1.0,1.0)) (Point2 (-2.0,0.0)))
                                                   (PLine2 (GVec [GVal 0.5411961001461969 (singleton (GEZero 1)), GVal (-0.9238795325112867) (singleton (GEPlus 1)), GVal 0.3826834323650899 (singleton (GEPlus 2))]))
                                            ,ENode (LineSeg (Point2 (1.0,1.0)) (Point2 (-2.0,0.0)), LineSeg (Point2 (-1.0,1.0)) (Point2 (1.0,-1.0)))
                                                   (PLine2 (GVec [GVal 0.541196100146197 (singleton (GEZero 1)), GVal (-0.3826834323650897) (singleton (GEPlus 1)), GVal (-0.9238795325112867) (singleton (GEPlus 2))]))
                                            ]
                                            (INodeSet (slist [
                                                              [INode (PLine2 (GVec [GVal (-0.541196100146197) (singleton (GEZero 1)), GVal 0.3826834323650897 (singleton (GEPlus 1)), GVal (-0.9238795325112867) (singleton (GEPlus 2))]))
                                                                     (PLine2 (GVec [GVal (-0.5411961001461969) (singleton (GEZero 1)), GVal 0.9238795325112867 (singleton (GEPlus 1)), GVal 0.3826834323650899 (singleton (GEPlus 2))]))
                                                                     (slist [])
                                                                     (Just (PLine2 (GVec [GVal (-0.7653668647301793) (singleton (GEZero 1)), GVal 0.9238795325112867 (singleton (GEPlus 1)), GVal (-0.38268343236508967) (singleton (GEPlus 2))])))
                                                              ,INode (PLine2 (GVec [GVal 0.5411961001461969 (singleton (GEZero 1)), GVal (-0.9238795325112867) (singleton (GEPlus 1)), GVal 0.3826834323650899 (singleton (GEPlus 2))]))
                                                                     (PLine2 (GVec [GVal 0.541196100146197 (singleton (GEZero 1)), GVal (-0.3826834323650897) (singleton (GEPlus 1)), GVal (-0.9238795325112867) (singleton (GEPlus 2))]))
                                                                     (slist [])
                                                                     (Just (PLine2 (GVec [GVal 0.7653668647301793 (singleton (GEZero 1)), GVal (-0.9238795325112867) (singleton (GEPlus 1)), GVal (-0.38268343236508967) (singleton (GEPlus 2))])))
                                                              ]
                                                             ,[
                                                               INode (PLine2 (GVec [GVal (-1.414213562373095) (singleton (GEPlus 2))]))
                                                                     (PLine2 (GVec [GVal (-0.7653668647301793) (singleton (GEZero 1)), GVal 0.9238795325112867 (singleton (GEPlus 1)), GVal (-0.38268343236508967) (singleton (GEPlus 2))]))
                                                                     (slist [
                                                                            PLine2 (GVec [GVal 1.0 (singleton (GEPlus 2))])
                                                                            ,(PLine2 (GVec [GVal 0.7653668647301793 (singleton (GEZero 1)), GVal (-0.9238795325112867) (singleton (GEPlus 1)), GVal (-0.38268343236508967) (singleton (GEPlus 2))]))
                                                                            ])
                                                                     Nothing
                                                              ]
                                                             ]))
                              ]] (slist []))
    it "finds the straight skeleton of our seventh simple shape." $
      findStraightSkeleton c6 [] -->
      Just (StraightSkeleton [[ makeNodeTree [ENode (LineSeg (Point2 (1.0,1.0)) (Point2 (-2.0,0.0)), LineSeg (Point2 (-1.0,1.0)) (Point2 (0.0,-2.0)))
                                                    (PLine2 (GVec [GVal (-0.7071067811865475) (singleton (GEPlus 1)), GVal (-0.7071067811865475) (singleton (GEPlus 2))]))
                                             ,ENode (LineSeg (Point2 (-1.0,1.0)) (Point2 (0.0,-2.0)), LineSeg (Point2 (-1.0,-1.0)) (Point2 (0.5,0.0)))
                                                    (PLine2 (GVec [GVal 0.7071067811865475 (singleton (GEPlus 1)), GVal (-0.7071067811865475) (singleton (GEPlus 2))]))
                                             ,ENode (LineSeg (Point2 (-1.0,-1.0)) (Point2 (0.5,0.0)), LineSeg (Point2 (-0.5,-1.0)) (Point2 (0.5,1.0)))
                                                    (PLine2 (GVec [GVal 0.9510565162951536 (singleton (GEZero 1)), GVal 0.8506508083520399 (singleton (GEPlus 1)), GVal 0.5257311121191337 (singleton (GEPlus 2))]))
                                             ,ENode (LineSeg (Point2 (-0.5,-1.0)) (Point2 (0.5,1.0)), LineSeg (Point2 (0.0,0.0)) (Point2 (0.5,-1.0)))
                                                    (PLine2 (GVec [GVal 1.7888543819998317 (singleton (GEPlus 1))]))
                                             ,ENode (LineSeg (Point2 (0.0,0.0)) (Point2 (0.5,-1.0)), LineSeg (Point2 (0.5,-1.0)) (Point2 (0.5,0.0)))
                                                    (PLine2 (GVec [GVal (-0.9510565162951536) (singleton (GEZero 1)), GVal 0.8506508083520399 (singleton (GEPlus 1)), GVal (-0.5257311121191337) (singleton (GEPlus 2))]))
                                             ,ENode (LineSeg (Point2 (0.5,-1.0)) (Point2 (0.5,0.0)), LineSeg (Point2 (1.0,-1.0)) (Point2 (0.0,2.0)))
                                                    (PLine2 (GVec [GVal 0.7071067811865475 (singleton (GEPlus 1)), GVal 0.7071067811865475 (singleton (GEPlus 2))]))
                                             ,ENode (LineSeg (Point2 (1.0,-1.0)) (Point2 (0.0,2.0)), LineSeg (Point2 (1.0,1.0)) (Point2 (-2.0,0.0)))
                                                    (PLine2 (GVec [GVal (-0.7071067811865475) (singleton (GEPlus 1)), GVal 0.7071067811865475 (singleton (GEPlus 2))]))
                                             ]
                                             (INodeSet (slist [
                                                               [INode (PLine2 (GVec [GVal 0.7071067811865475 (singleton (GEPlus 1)), GVal (-0.7071067811865475) (singleton (GEPlus 2))]))
                                                                      (PLine2 (GVec [GVal 0.9510565162951536 (singleton (GEZero 1)), GVal 0.8506508083520399 (singleton (GEPlus 1)), GVal 0.5257311121191337 (singleton (GEPlus 2))]))
                                                                      (slist [])
                                                                      (Just (PLine2 (GVec [GVal 0.606432399999752 (singleton (GEZero 1)), GVal 0.9932897335288758 (singleton (GEPlus 1)), GVal (-0.11565251949756605) (singleton (GEPlus 2))])))
                                                               ,INode (PLine2 (GVec [GVal (-0.9510565162951536) (singleton (GEZero 1)), GVal 0.8506508083520399 (singleton (GEPlus 1)), GVal (-0.5257311121191337) (singleton (GEPlus 2))]))
                                                                      (PLine2 (GVec [GVal 0.7071067811865475 (singleton (GEPlus 1)), GVal 0.7071067811865475 (singleton (GEPlus 2))]))
                                                                      (slist [])
                                                                      (Just (PLine2 (GVec [GVal (-0.606432399999752) (singleton (GEZero 1)), GVal 0.9932897335288758 (singleton (GEPlus 1)), GVal 0.11565251949756605 (singleton (GEPlus 2))])))
                                                               ]
                                                              ,[INode (PLine2 (GVec [GVal (-0.7071067811865475) (singleton (GEPlus 1)), GVal (-0.7071067811865475) (singleton (GEPlus 2))]))
                                                                      (PLine2 (GVec [GVal 0.606432399999752 (singleton (GEZero 1)), GVal 0.9932897335288758 (singleton (GEPlus 1)), GVal (-0.11565251949756605) (singleton (GEPlus 2))]))
                                                                      (slist [])
                                                                      (Just (PLine2 (GVec [GVal 0.6961601101968017 (singleton (GEZero 1)), GVal 0.328526568895664 (singleton (GEPlus 1)), GVal (-0.9444947292227959) (singleton (GEPlus 2))])))
                                                               ,INode (PLine2 (GVec [GVal (-0.606432399999752) (singleton (GEZero 1)), GVal 0.9932897335288758 (singleton (GEPlus 1)), GVal 0.11565251949756605 (singleton (GEPlus 2))]))
                                                                      (PLine2 (GVec [GVal (-0.7071067811865475) (singleton (GEPlus 1)), GVal 0.7071067811865475 (singleton (GEPlus 2))]))
                                                                      (slist [])
                                                                      (Just (PLine2 (GVec [GVal (-0.6961601101968017) (singleton (GEZero 1)), GVal 0.328526568895664 (singleton (GEPlus 1)), GVal 0.9444947292227959 (singleton (GEPlus 2))])))
                                                              ]
                                                              ,[INode (PLine2 (GVec [GVal 0.6961601101968017 (singleton (GEZero 1)), GVal 0.328526568895664 (singleton (GEPlus 1)), GVal (-0.9444947292227959) (singleton (GEPlus 2))]))
                                                                      (PLine2 (GVec [GVal 1.7888543819998317 (singleton (GEPlus 1))]))
                                                                      (slist [PLine2 (GVec [GVal (-0.6961601101968017) (singleton (GEZero 1)), GVal 0.328526568895664 (singleton (GEPlus 1)), GVal 0.9444947292227959 (singleton (GEPlus 2))])])
                                                                      Nothing
                                                               ]
                                                              ]))
                              ]] (slist []))
    it "finds the motorcycles of our eigth simple shape." $
      convexMotorcycles c7 --> [Motorcycle (LineSeg (Point2 (0.5,1.0)) (Point2 (0.0,-1.0)), LineSeg (Point2 (0.5,0.0)) (Point2 (-0.5,1.0)))
                                           (PLine2 (GVec [GVal 0.9472135954999579 (singleton (GEZero 1)), GVal (-1.8944271909999157) (singleton (GEPlus 1)), GVal (-0.4472135954999579) (singleton (GEPlus 2))]))
                               ,Motorcycle (LineSeg (Point2 (-1.0,0.0)) (Point2 (1.0,0.0)), LineSeg (Point2 (0.0,0.0)) (Point2 (0.0,-1.0)))
                                           (PLine2 (GVec [GVal 1.0 (singleton (GEPlus 1)), GVal (-1.0) (singleton (GEPlus 2))]))
                               ]
    it "finds a CrashTree of our eigth simple shape." $
      crashMotorcycles c7 [] -->
        Just (CrashTree (slist $ convexMotorcycles c7)
                        (slist $ convexMotorcycles c7)
                        (slist []))
    it "finds the first cell of our eigth simple shape." $
      cellFrom (findFirstCellOfContour c7 $ findDivisions c7 $ fromJust $ crashMotorcycles c7 []) -->
      Cell (slist [(slist [
                            LineSeg (Point2 (0.0,-1.0)) (Point2 (1.0,0.0))
                          , LineSeg (Point2 (1.0,-1.0)) (Point2 (0.0,2.0))
                          , LineSeg (Point2 (1.0,1.0)) (Point2 (-0.5,0.0))
                          , LineSeg (Point2 (0.5,1.0)) (Point2 (0.0,-1.0))
                          ]
                   ,
                     Just (CellDivide (DividingMotorcycles (Motorcycle (LineSeg (Point2 (0.5,1.0)) (Point2 (0.0,-1.0)), LineSeg (Point2 (0.5,0.0)) (Point2 (-0.5,1.0)))
                                                            (PLine2 (GVec [GVal 0.9472135954999579 (singleton (GEZero 1)), GVal (-1.8944271909999157) (singleton (GEPlus 1)), GVal (-0.4472135954999579) (singleton (GEPlus 2))])))
                                                           (slist []))
                                      Nothing
                          )
                   )
                  ]
           )
    it "finds the remainder of the first cell our eigth simple shape." $
      remainderFrom (findFirstCellOfContour c7 $ findDivisions c7 $ fromJust $ crashMotorcycles c7 []) -->
      Just [RemainingContour (slist [(slist [
                                              LineSeg (Point2 (0.5,0.0)) (Point2 (-0.5,1.0))
                                            , LineSeg (Point2 (0.0,1.0)) (Point2 (-1.0,0.0))
                                            , LineSeg (Point2 (-1.0,1.0)) (Point2 (0.0,-1.0))
                                            , LineSeg (Point2 (-1.0,0.0)) (Point2 (1.0,0.0))
                                            , LineSeg (Point2 (0.0,0.0)) (Point2 (0.0,-1.0))
                                            , LineSeg (Point2 (0.0,-1.0)) (Point2 (1.0,0.0))
                                            ]
                                     ,
                                       [CellDivide (DividingMotorcycles (Motorcycle (LineSeg (Point2 (-1.0,0.0)) (Point2 (1.0,0.0)),LineSeg (Point2 (0.0,0.0)) (Point2 (0.0,-1.0)))
                                                                                    (PLine2 (GVec [GVal 1.0 (fromList [GEPlus 1]),GVal (-1.0) (fromList [GEPlus 2])])))
                                                                        (slist []))
                                                                        Nothing])]
                             )]
    it "finds the second cell of our eigth simple shape." $
      cellFrom (findNextCell $ head $ fromJust $ remainderFrom $ findFirstCellOfContour c7 $ findDivisions c7 $ fromJust $ crashMotorcycles c7 []) -->
      Cell (slist [
                   (slist [LineSeg (Point2 (0.5,0.0)) (Point2 (-0.5,1.0))],Just (CellDivide (DividingMotorcycles (Motorcycle (LineSeg (Point2 (-1.0,0.0)) (Point2 (1.0,0.0)),LineSeg (Point2 (0.0,0.0)) (Point2 (0.0,-1.0)))
                                                                                                                       (PLine2 (GVec [GVal 1.0 (fromList [GEPlus 1]),GVal (-1.0) (fromList [GEPlus 2])])))
                                                                                            (slist []))
                                                                                            Nothing)),
                   (slist [ LineSeg (Point2 (0.0,0.0)) (Point2 (0.0,-1.0))
                          , LineSeg (Point2 (0.0,-1.0)) (Point2 (1.0,0.0))],Nothing)
                  ])
    it "finds the remainder of the second cell our eigth simple shape." $
      remainderFrom (findNextCell $ head $ fromJust $ remainderFrom $ findFirstCellOfContour c7 $ findDivisions c7 $ fromJust $ crashMotorcycles c7 []) -->
      Just [RemainingContour (slist [(slist [
                                              LineSeg (Point2 (0.5,0.0)) (Point2 (-0.5,1.0))
                                            , LineSeg (Point2 (0.0,1.0)) (Point2 (-1.0,0.0))
                                            , LineSeg (Point2 (-1.0,1.0)) (Point2 (0.0,-1.0))
                                            , LineSeg (Point2 (-1.0,0.0)) (Point2 (1.0,0.0))
                                            ]
                                     , [])]
                             )]
    it "finds the third cell of our eigth simple shape." $
      cellFrom (findNextCell $ head $ fromJust $ remainderFrom $ findNextCell $ head $ fromJust $ remainderFrom $ findFirstCellOfContour c7 $ findDivisions c7 $ fromJust $ crashMotorcycles c7 []) -->
      Cell (slist [
                   (slist [
                                              LineSeg (Point2 (0.5,0.0)) (Point2 (-0.5,1.0))
                                            , LineSeg (Point2 (0.0,1.0)) (Point2 (-1.0,0.0))
                                            , LineSeg (Point2 (-1.0,1.0)) (Point2 (0.0,-1.0))
                                            , LineSeg (Point2 (-1.0,0.0)) (Point2 (1.0,0.0))
                                            ], Nothing)
                  ])
    it "finds the NodeTree of the first cell of our eigth simple shape." $
      getNodeTreeOfCell (cellFrom $ findFirstCellOfContour c7 $ findDivisions c7 $ fromJust $ crashMotorcycles c7 []) -->
      Right (makeNodeTree [ ENode (LineSeg (Point2 (0.0,-1.0)) (Point2 (1.0,0.0)), LineSeg (Point2 (1.0,-1.0)) (Point2 (0.0,2.0)))
                                  (PLine2 (GVec [GVal 0.7071067811865475 (singleton (GEPlus 1)), GVal 0.7071067811865475 (singleton (GEPlus 2))]))
                          , ENode (LineSeg (Point2 (1.0,-1.0)) (Point2 (0.0,2.0)), LineSeg (Point2 (1.0,1.0)) (Point2 (-0.5,0.0)))
                                  (PLine2 (GVec [GVal (-0.7071067811865475) (singleton (GEPlus 1)), GVal 0.7071067811865475 (singleton (GEPlus 2))]))
                          , ENode (LineSeg (Point2 (1.0,1.0)) (Point2 (-0.5,0.0)), LineSeg (Point2 (0.5,1.0)) (Point2 (0.0,-1.0)))
                                  (PLine2 (GVec [GVal 1.0606601717798212 (singleton (GEZero 1)), GVal (-0.7071067811865475) (singleton (GEPlus 1)), GVal (-0.7071067811865475) (singleton (GEPlus 2))]))
                          ]
                          (INodeSet (slist [
                                            [INode (PLine2 (GVec [GVal (-0.7071067811865475) (singleton (GEPlus 1)), GVal 0.7071067811865475 (singleton (GEPlus 2))]))
                                                   (PLine2 (GVec [GVal 1.0606601717798212 (singleton (GEZero 1)), GVal (-0.7071067811865475) (singleton (GEPlus 1)), GVal (-0.7071067811865475) (singleton (GEPlus 2))]))
                                                   (slist [])
                                                   (Just (PLine2 (GVec [GVal 0.75 (singleton (GEZero 1)), GVal (-1.0) (singleton (GEPlus 1))])))
                                            ]
                                           ,[INode (PLine2 (GVec [GVal 0.7071067811865475 (singleton (GEPlus 1)), GVal 0.7071067811865475 (singleton (GEPlus 2))]))
                                                   (PLine2 (GVec [GVal 0.75 (singleton (GEZero 1)), GVal (-1.0) (singleton (GEPlus 1))]))
                                                   (slist [])
                                                   (Just (PLine2 (GVec [GVal 0.9799222236572825 (singleton (GEZero 1)), GVal (-0.3826834323650899) (singleton (GEPlus 1)), GVal 0.9238795325112867 (singleton (GEPlus 2))])))
                                            ]
                                           ]
                                    )
                          )
            )
    it "finds the straight skeleton of a triangle." $
      findStraightSkeleton triangle [] -->
      Just (StraightSkeleton [[makeNodeTree [ENode (LineSeg (Point2 (2.0,0.0)) (Point2 (-1.0,1.7320508075688772)), LineSeg (Point2 (1.0,1.7320508075688772)) (Point2 (-1.0,-1.7320508075688772)))
                                                   (PLine2 (GVec [GVal 1.0 (singleton (GEZero 1)), GVal (-1.0) (singleton (GEPlus 1))]))
                                            ,ENode (LineSeg (Point2 (1.0,1.7320508075688772)) (Point2 (-1.0,-1.7320508075688772)), LineSeg (Point2 (0.0,0.0)) (Point2 (2.0,0.0)))
                                                   (PLine2 (GVec [GVal 0.5000000000000001 (singleton (GEPlus 1)), GVal (-0.8660254037844387) (singleton (GEPlus 2))]))
                                            ,ENode (LineSeg (Point2 (0.0,0.0)) (Point2 (2.0,0.0)), LineSeg (Point2 (2.0,0.0)) (Point2 (-1.0,1.7320508075688772)))
                                                   (PLine2 (GVec [GVal (-1.0000000000000002) (singleton (GEZero 1)), GVal 0.5000000000000001 (singleton (GEPlus 1)), GVal 0.8660254037844387 (singleton (GEPlus 2))]))
                                            ]
                                            (INodeSet (slist [
                                                              [INode (PLine2 (GVec [GVal 1.0 (singleton (GEZero 1)), GVal (-1.0) (singleton (GEPlus 1))]))
                                                                     (PLine2 (GVec [GVal 0.5000000000000001 (singleton (GEPlus 1)),GVal (-0.8660254037844387) (singleton (GEPlus 2))]))
                                                                     (slist [PLine2 (GVec [GVal (-1.0000000000000002) (singleton (GEZero 1)), GVal 0.5000000000000001 (singleton (GEPlus 1)),GVal 0.8660254037844387 (singleton (GEPlus 2))])])
                                                                     Nothing
                                                              ]
                                                             ]))
                              ]] (slist []))
    it "finds the straight skeleton of a square." $
      findStraightSkeleton square [] -->
      Just (StraightSkeleton [[makeNodeTree [ENode (LineSeg (Point2 (-1.0,1.0)) (Point2 (0.0,-2.0)), LineSeg (Point2 (-1.0,-1.0)) (Point2 (2.0,0.0)))
                                                   (PLine2 (GVec [GVal 0.7071067811865475 (singleton (GEPlus 1)), GVal (-0.7071067811865475) (singleton (GEPlus 2))]))
                                            ,ENode (LineSeg (Point2 (-1.0,-1.0)) (Point2 (2.0,0.0)), LineSeg (Point2 (1.0,-1.0)) (Point2 (0.0,2.0)))
                                                   (PLine2 (GVec [GVal 0.7071067811865475 (singleton (GEPlus 1)), GVal 0.7071067811865475 (singleton (GEPlus 2))]))
                                            ,ENode (LineSeg (Point2 (1.0,-1.0)) (Point2 (0.0,2.0)), LineSeg (Point2 (1.0,1.0)) (Point2 (-2.0,0.0)))
                                                   (PLine2 (GVec [GVal (-0.7071067811865475) (singleton (GEPlus 1)), GVal 0.7071067811865475 (singleton (GEPlus 2))]))
                                            ,ENode (LineSeg (Point2 (1.0,1.0)) (Point2 (-2.0,0.0)), LineSeg (Point2 (-1.0,1.0)) (Point2 (0.0,-2.0)))
                                                   (PLine2 (GVec [GVal (-0.7071067811865475) (singleton (GEPlus 1)), GVal (-0.7071067811865475) (singleton (GEPlus 2))]))
                                            ]
                                            (INodeSet (slist [
                                                              [INode (PLine2 (GVec [GVal 0.7071067811865475 (singleton (GEPlus 1)), GVal (-0.7071067811865475) (singleton (GEPlus 2))]))
                                                                     (PLine2 (GVec [GVal 0.7071067811865475 (singleton (GEPlus 1)), GVal 0.7071067811865475 (singleton (GEPlus 2))]))
                                                                     (slist [PLine2 (GVec [GVal (-0.7071067811865475) (singleton (GEPlus 1)), GVal 0.7071067811865475 (singleton (GEPlus 2))])
                                                                            ,PLine2 (GVec [GVal (-0.7071067811865475) (singleton (GEPlus 1)), GVal (-0.7071067811865475) (singleton (GEPlus 2))])])
                                                                     Nothing
                                                              ]
                                                             ]))
                              ]] (slist []))
    it "finds the straight skeleton of a rectangle." $
      findStraightSkeleton rectangle [] -->
      Just (StraightSkeleton [[makeNodeTree [ENode (LineSeg (Point2 (-2.0,1.0)) (Point2 (0.0,-2.0)), LineSeg (Point2 (-2.0,-1.0)) (Point2 (3.0,0.0)))
                                                   (PLine2 (GVec [GVal 0.7071067811865475 (singleton (GEZero 1)), GVal 0.7071067811865475 (singleton (GEPlus 1)), GVal (-0.7071067811865475) (singleton (GEPlus 2))]))
                                            ,ENode (LineSeg (Point2 (-2.0,-1.0)) (Point2 (3.0,0.0)), LineSeg (Point2 (1.0,-1.0)) (Point2 (0.0,2.0)))
                                                   (PLine2 (GVec [GVal 0.7071067811865475 (singleton (GEPlus 1)), GVal 0.7071067811865475 (singleton (GEPlus 2))]))
                                            ,ENode (LineSeg (Point2 (1.0,-1.0)) (Point2 (0.0,2.0)), LineSeg (Point2 (1.0,1.0)) (Point2 (-3.0,0.0)))
                                                   (PLine2 (GVec [GVal (-0.7071067811865475) (singleton (GEPlus 1)), GVal 0.7071067811865475 (singleton (GEPlus 2))]))
                                            ,ENode (LineSeg (Point2 (1.0,1.0)) (Point2 (-3.0,0.0)), LineSeg (Point2 (-2.0,1.0)) (Point2 (0.0,-2.0)))
                                                   (PLine2 (GVec [GVal (-0.7071067811865475) (singleton (GEZero 1)), GVal (-0.7071067811865475) (singleton (GEPlus 1)), GVal (-0.7071067811865475) (singleton (GEPlus 2))]))
                                            ]
                                            (INodeSet (slist [
                                                              [INode (PLine2 (GVec [GVal 0.7071067811865475 (singleton (GEPlus 1)), GVal 0.7071067811865475 (singleton (GEPlus 2))]))
                                                                     (PLine2 (GVec [GVal (-0.7071067811865475) (singleton (GEPlus 1)), GVal 0.7071067811865475 (singleton (GEPlus 2))]))
                                                                     (slist [])
                                                                     (Just (PLine2 (GVec [GVal 1.0 (singleton (GEPlus 2))])))
                                                              ]
                                                             ,[INode (PLine2 (GVec [GVal 0.7071067811865475 (singleton (GEZero 1)), GVal 0.7071067811865475 (singleton (GEPlus 1)), GVal (-0.7071067811865475) (singleton (GEPlus 2))]))
                                                                     (PLine2 (GVec [GVal 1.0 (singleton (GEPlus 2))]))
                                                                     (slist [(PLine2 (GVec [GVal (-0.7071067811865475) (singleton (GEZero 1)), GVal (-0.7071067811865475) (singleton (GEPlus 1)), GVal (-0.7071067811865475) (singleton (GEPlus 2))]))])
                                                                     Nothing
                                                              ]
                                                             ]))
                              ]] (slist []))
  describe "Faces (Skeleton/Face)" $ do
    it "finds faces from a straight skeleton (c0, default order)" $
      facesOf (fromMaybe (error "got Nothing") $ findStraightSkeleton c0 []) -->
      [
        Face (LineSeg (Point2 (-1.0,-1.0)) (Point2 (2.0,0.0)))
             (PLine2 (GVec [GVal 0.7071067811865475 (singleton (GEPlus 1)), GVal 0.7071067811865475 (singleton (GEPlus 2))]))
             (slist [])
             (PLine2 (GVec [GVal (-0.541196100146197) (singleton (GEZero 1)), GVal 0.3826834323650897 (singleton (GEPlus 1)), GVal (-0.9238795325112867) (singleton (GEPlus 2))]))
      , Face (LineSeg (Point2 (1.0,-1.0)) (Point2 (0.0,2.0)))
             (PLine2 (GVec [GVal (-0.7071067811865475) (singleton (GEPlus 1)), GVal 0.7071067811865475 (singleton (GEPlus 2))]))
             (slist [PLine2 (GVec [GVal 0.4870636221857319 (singleton (GEZero 1)), GVal (-0.9807852804032305) (singleton (GEPlus 1)), GVal (-0.19509032201612836) (singleton (GEPlus 2))]),
                     PLine2 (GVec [GVal (-0.4870636221857319) (singleton (GEZero 1)), GVal 0.9807852804032305 (singleton (GEPlus 1)), GVal (-0.19509032201612836) (singleton (GEPlus 2))])])
             (PLine2 (GVec [GVal 0.7071067811865475 (singleton (GEPlus 1)), GVal 0.7071067811865475 (singleton (GEPlus 2))]))
      , Face (LineSeg (Point2 (1.0,1.0)) (Point2 (-2.0,0.0)))
             (PLine2 (GVec [GVal 0.541196100146197 (singleton (GEZero 1)), GVal (-0.3826834323650897) (singleton (GEPlus 1)), GVal (-0.9238795325112867) (singleton (GEPlus 2))]))
             (slist [])
             (PLine2 (GVec [GVal (-0.7071067811865475) (singleton (GEPlus 1)), GVal 0.7071067811865475 (singleton (GEPlus 2))]))
      , Face (LineSeg (Point2 (-1.0,1.0)) (Point2 (1.0,-1.0)))
             (PLine2 (GVec [GVal (-1.414213562373095) (singleton (GEPlus 2))]))
             (slist [PLine2 (GVec [GVal 0.4870636221857319 (singleton (GEZero 1)), GVal (-0.9807852804032305) (singleton (GEPlus 1)), GVal (-0.19509032201612836) (singleton (GEPlus 2))])])
             (PLine2 (GVec [GVal 0.541196100146197 (singleton (GEZero 1)), GVal (-0.3826834323650897) (singleton (GEPlus 1)), GVal (-0.9238795325112867) (singleton (GEPlus 2))]))
      , Face (LineSeg (Point2 (0.0,0.0)) (Point2 (-1.0,-1.0)))
             (PLine2 (GVec [GVal (-0.541196100146197) (singleton (GEZero 1)), GVal 0.3826834323650897 (singleton (GEPlus 1)), GVal (-0.9238795325112867) (singleton (GEPlus 2))]))
             (slist [PLine2 (GVec [GVal (-0.4870636221857319) (singleton (GEZero 1)), GVal 0.9807852804032305 (singleton (GEPlus 1)), GVal (-0.19509032201612836) (singleton (GEPlus 2))])])
             (PLine2 (GVec [GVal (-1.414213562373095) (singleton (GEPlus 2))]))
      ]
    it "finds faces from a straight skeleton (c0, manual order)" $
      orderedFacesOf c0l0 (fromMaybe (error "got Nothing") $ findStraightSkeleton c0 []) -->
      [
        Face (LineSeg (Point2 (0.0,0.0)) (Point2 (-1.0,-1.0)))
             (PLine2 (GVec [GVal (-0.541196100146197) (singleton (GEZero 1)), GVal 0.3826834323650897 (singleton (GEPlus 1)), GVal (-0.9238795325112867) (singleton (GEPlus 2))]))
             (slist [PLine2 (GVec [GVal (-0.4870636221857319) (singleton (GEZero 1)), GVal 0.9807852804032305 (singleton (GEPlus 1)), GVal (-0.19509032201612836) (singleton (GEPlus 2))])])
             (PLine2 (GVec [GVal (-1.414213562373095) (singleton (GEPlus 2))]))
      , Face (LineSeg (Point2 (-1.0,-1.0)) (Point2 (2.0,0.0)))
             (PLine2 (GVec [GVal 0.7071067811865475 (singleton (GEPlus 1)), GVal 0.7071067811865475 (singleton (GEPlus 2))]))
             (slist [])
             (PLine2 (GVec [GVal (-0.541196100146197) (singleton (GEZero 1)), GVal 0.3826834323650897 (singleton (GEPlus 1)), GVal (-0.9238795325112867) (singleton (GEPlus 2))]))
      , Face (LineSeg (Point2 (1.0,-1.0)) (Point2 (0.0,2.0)))
             (PLine2 (GVec [GVal (-0.7071067811865475) (singleton (GEPlus 1)), GVal 0.7071067811865475 (singleton (GEPlus 2))]))
             (slist [PLine2 (GVec [GVal 0.4870636221857319 (singleton (GEZero 1)), GVal (-0.9807852804032305) (singleton (GEPlus 1)), GVal (-0.19509032201612836) (singleton (GEPlus 2))]),
                     PLine2 (GVec [GVal (-0.4870636221857319) (singleton (GEZero 1)), GVal 0.9807852804032305 (singleton (GEPlus 1)), GVal (-0.19509032201612836) (singleton (GEPlus 2))])])
             (PLine2 (GVec [GVal 0.7071067811865475 (singleton (GEPlus 1)), GVal 0.7071067811865475 (singleton (GEPlus 2))]))
      , Face (LineSeg (Point2 (1.0,1.0)) (Point2 (-2.0,0.0)))
             (PLine2 (GVec [GVal 0.541196100146197 (singleton (GEZero 1)), GVal (-0.3826834323650897) (singleton (GEPlus 1)), GVal (-0.9238795325112867) (singleton (GEPlus 2))]))
             (slist [])
             (PLine2 (GVec [GVal (-0.7071067811865475) (singleton (GEPlus 1)), GVal 0.7071067811865475 (singleton (GEPlus 2))]))
      , Face (LineSeg (Point2 (-1.0,1.0)) (Point2 (1.0,-1.0)))
             (PLine2 (GVec [GVal (-1.414213562373095) (singleton (GEPlus 2))]))
             (slist [PLine2 (GVec [GVal 0.4870636221857319 (singleton (GEZero 1)), GVal (-0.9807852804032305) (singleton (GEPlus 1)), GVal (-0.19509032201612836) (singleton (GEPlus 2))])])
             (PLine2 (GVec [GVal 0.541196100146197 (singleton (GEZero 1)), GVal (-0.3826834323650897) (singleton (GEPlus 1)), GVal (-0.9238795325112867) (singleton (GEPlus 2))]))
      ]
    it "finds faces from a triangle (default order)" $
      facesOf (fromMaybe (error "got Nothing") $ findStraightSkeleton triangle []) --> [Face (LineSeg (Point2 (1.0,1.73205080756887729)) (Point2 (-1.0,-1.7320508075688772)))
                                                                                             (PLine2 (GVec [GVal 0.5000000000000001 (singleton (GEPlus 1)), GVal (-0.8660254037844387) (singleton (GEPlus 2))]))
                                                                                             (slist [])
                                                                                             (PLine2 (GVec [GVal 1.0 (singleton (GEZero 1)), GVal (-1.0) (singleton (GEPlus 1))]))
                                                                                       ,Face (LineSeg (Point2 (0.0,0.0)) (Point2 (2.0,0.0)))
                                                                                             (PLine2 (GVec [GVal (-1.0000000000000002) (singleton (GEZero 1)), GVal 0.5000000000000001 (singleton (GEPlus 1)), GVal 0.8660254037844387 (singleton (GEPlus 2))]))
                                                                                             (slist [])
                                                                                             (PLine2 (GVec [GVal 0.5000000000000001 (singleton (GEPlus 1)), GVal (-0.8660254037844387) (singleton (GEPlus 2))]))
                                                                                       ,Face (LineSeg (Point2 (2.0,0.0)) (Point2 (-1.0,1.7320508075688772)))
                                                                                             (PLine2 (GVec [GVal 1.0 (singleton (GEZero 1)), GVal (-1.0) (singleton (GEPlus 1))]))
                                                                                             (slist [])
                                                                                             (PLine2 (GVec [GVal (-1.0000000000000002) (singleton (GEZero 1)), GVal 0.5000000000000001 (singleton (GEPlus 1)), GVal 0.8660254037844387 (singleton (GEPlus 2))]))
                                                                                          ]
    it "finds faces from a triangle (manual order)" $
      orderedFacesOf trianglel0 (fromMaybe (error "got Nothing") $ findStraightSkeleton triangle []) --> [Face (LineSeg (Point2 (2.0,0.0)) (Point2 (-1.0,1.7320508075688772)))
                                                                                                               (PLine2 (GVec [GVal 1.0 (singleton (GEZero 1)), GVal (-1.0) (singleton (GEPlus 1))]))
                                                                                                               (slist [])
                                                                                                               (PLine2 (GVec [GVal (-1.0000000000000002) (singleton (GEZero 1)), GVal 0.5000000000000001 (singleton (GEPlus 1)), GVal 0.8660254037844387 (singleton (GEPlus 2))]))
                                                                                                         ,Face (LineSeg (Point2 (1.0,1.73205080756887729)) (Point2 (-1.0,-1.7320508075688772)))
                                                                                                               (PLine2 (GVec [GVal 0.5000000000000001 (singleton (GEPlus 1)), GVal (-0.8660254037844387) (singleton (GEPlus 2))]))
                                                                                                               (slist [])
                                                                                                               (PLine2 (GVec [GVal 1.0 (singleton (GEZero 1)), GVal (-1.0) (singleton (GEPlus 1))]))
                                                                                                         ,Face (LineSeg (Point2 (0.0,0.0)) (Point2 (2.0,0.0)))
                                                                                                               (PLine2 (GVec [GVal (-1.0000000000000002) (singleton (GEZero 1)), GVal 0.5000000000000001 (singleton (GEPlus 1)), GVal 0.8660254037844387 (singleton (GEPlus 2))]))
                                                                                                               (slist [])
                                                                                                               (PLine2 (GVec [GVal 0.5000000000000001 (singleton (GEPlus 1)), GVal (-0.8660254037844387) (singleton (GEPlus 2))]))
                                                                                             ]
    it "finds faces from a square" $
      facesOf (fromMaybe (error "got Nothing") $ findStraightSkeleton square []) --> [Face (LineSeg (Point2(-1.0,-1.0)) (Point2 (2.0,0.0)))
                                                                                           (PLine2 (GVec [GVal 0.7071067811865475 (singleton (GEPlus 1)), GVal 0.7071067811865475 (singleton (GEPlus 2))]))
                                                                                           (slist [])
                                                                                           (PLine2 (GVec [GVal  0.7071067811865475 (singleton (GEPlus 1)), GVal (-0.7071067811865475) (singleton (GEPlus 2))]))
                                                                                     ,Face (LineSeg (Point2 (1.0,-1.0)) (Point2 (0.0,2.0)))
                                                                                           (PLine2 (GVec [GVal (-0.7071067811865475) (singleton (GEPlus 1)), GVal 0.7071067811865475 (singleton (GEPlus 2))]))
                                                                                           (slist [])
                                                                                           (PLine2 (GVec [GVal 0.7071067811865475 (singleton (GEPlus 1)), GVal 0.7071067811865475(singleton (GEPlus 2))]))
                                                                                     ,Face (LineSeg (Point2 (1.0,1.0)) (Point2 (-2.0,0.0)))
                                                                                           (PLine2 (GVec [GVal (-0.7071067811865475) (singleton (GEPlus 1)), GVal (-0.7071067811865475) (singleton (GEPlus 2))]))
                                                                                           (slist [])
                                                                                           (PLine2 (GVec [GVal (-0.7071067811865475) (singleton (GEPlus 1)), GVal 0.7071067811865475 (singleton (GEPlus 2))]))
                                                                                     ,Face (LineSeg (Point2 (-1.0,1.0)) (Point2 (0.0,-2.0)))
                                                                                           (PLine2 (GVec [GVal 0.7071067811865475 (singleton (GEPlus 1)), GVal (-0.7071067811865475) (singleton (GEPlus 2))]))
                                                                                           (slist [])
                                                                                           (PLine2 (GVec [GVal (-0.7071067811865475) (singleton (GEPlus 1)), GVal (-0.7071067811865475) (singleton (GEPlus 2))]))
                                                                                     ]
    it "finds faces from a rectangle" $
      facesOf (fromMaybe (error "got Nothing") $ findStraightSkeleton rectangle [])
      --> [Face (LineSeg (Point2 (-2.0,1.0)) (Point2 (0.0,-2.0)))
                (PLine2 (GVec [GVal 0.7071067811865475 (singleton (GEZero 1)), GVal 0.7071067811865475 (singleton (GEPlus 1)), GVal (-0.7071067811865475) (singleton (GEPlus 2))]))
                (slist [])
                (PLine2 (GVec [GVal (-0.7071067811865475) (singleton (GEZero 1)), GVal (-0.7071067811865475) (singleton (GEPlus 1)), GVal (-0.7071067811865475) (singleton (GEPlus 2))]))
          ,Face (LineSeg (Point2 (-2.0,-1.0)) (Point2 (3.0,0.0)))
                (PLine2 (GVec [GVal 0.7071067811865475 (singleton (GEPlus 1)), GVal 0.7071067811865475 (singleton (GEPlus 2))]))
                (slist [PLine2 (GVec [GVal (-1.0) (singleton (GEPlus 2))])])
                (PLine2 (GVec [GVal 0.7071067811865475 (singleton (GEZero 1)), GVal 0.7071067811865475 (singleton (GEPlus 1)), GVal (-0.7071067811865475) (singleton (GEPlus 2))]))
          ,Face (LineSeg (Point2(1.0,-1.0)) (Point2 (0.0,2.0)))
                (PLine2 (GVec [GVal (-0.7071067811865475) (singleton (GEPlus 1)), GVal 0.7071067811865475 (singleton (GEPlus 2))]))
                (slist [])
                (PLine2 (GVec [GVal  0.7071067811865475 (singleton (GEPlus 1)), GVal 0.7071067811865475 (singleton (GEPlus 2))]))
          ,Face (LineSeg (Point2 (1.0,1.0)) (Point2 (-3.0,0.0)))
                (PLine2 (GVec [GVal (-0.7071067811865475) (singleton (GEZero 1)), GVal (-0.7071067811865475) (singleton (GEPlus 1)), GVal (-0.7071067811865475) (singleton (GEPlus 2))]))
                (slist [PLine2 (GVec [GVal (-1.0) (singleton (GEPlus 2))])])
                (PLine2 (GVec [GVal (-0.7071067811865475) (singleton (GEPlus 1)), GVal 0.7071067811865475 (singleton (GEPlus 2))]))
          ]

  describe "insets (Skeleton/Line)" $ do
    it "insets a triangle" $
      addInset 1 0.25 (facesOf $ fromMaybe (error "got Nothing") $ findStraightSkeleton triangle [])
      --> ([LineSegContour (Point2 (0.4330127018922193,0.25))
                           (Point2 (1.5669872981077808,1.2320508075688772))
                           (LineSeg (Point2 (1.0,1.2320508075688772)) (Point2 (-0.5669872981077807,-0.9820508075688772)))
                           (LineSeg (Point2 (0.4330127018922193,0.25)) (Point2 (1.1339745962155616,1.1102230246251565e-16)))
                           (slist [LineSeg (Point2 (1.5669872981077808,0.2500000000000001)) (Point2 (-0.5669872981077808,0.9820508075688771))])]
          ,[Face (LineSeg (Point2 (-0.43301270189221935,-0.25000000000000006)) (Point2 (1.4330127018922194,2.482050807568877)))
                 (PLine2 (GVec [GVal 0.5000000000000001 (singleton (GEPlus 1)), GVal (-0.8660254037844387) (singleton (GEPlus 2))]))
                 (slist [])
                 (PLine2 (GVec [GVal 1.0 (singleton (GEZero 1)), GVal (-1.0) (singleton (GEPlus 1))]))
           ,Face (LineSeg (Point2 (2.433012701892219,-0.25)) (Point2 (-2.8660254037844384,0.0)))
                 (PLine2 (GVec [GVal (-1.0000000000000002) (singleton (GEZero 1)), GVal 0.5000000000000001 (singleton (GEPlus 1)), GVal 0.8660254037844387 (singleton (GEPlus 2))]))
                 (slist [])
                 (PLine2 (GVec [GVal 0.5000000000000001 (singleton (GEPlus 1)),GVal (-0.8660254037844387) (singleton (GEPlus 2))]))
           ,Face (LineSeg (Point2 (1.0,2.232050807568877)) (Point2 (1.4330127018922192,-2.482050807568877)))
                 (PLine2 (GVec [GVal 1.0 (singleton (GEZero 1)), GVal (-1.0) (singleton (GEPlus 1))]))
                 (slist [])
                 (PLine2 (GVec [GVal (-1.0000000000000002) (singleton (GEZero 1)), GVal 0.5000000000000001 (singleton (GEPlus 1)), GVal 0.8660254037844387 (singleton (GEPlus 2))]))
           ])
    where
      -- c0 - c4 are the contours of a square around the origin with a 90 degree chunk missing, rotated 0, 90, 180, 270 and 360 degrees:
      --    __
      --    \ |
      --    /_|
      --
      c0 = makePointContour [Point2 (0,0), Point2 (-1,-1), Point2 (1,-1), Point2 (1,1), Point2 (-1,1)]
      c0l0 = LineSeg (Point2 (0,0)) (Point2 (-1,-1))
      c1 = makePointContour [Point2 (-1,-1), Point2 (0,0), Point2 (1,-1), Point2 (1,1), Point2 (-1,1)]
      c2 = makePointContour [Point2 (-1,-1), Point2 (1,-1), Point2 (0,0), Point2 (1,1), Point2 (-1,1)]
      c3 = makePointContour [Point2 (-1,-1), Point2 (1,-1), Point2 (1,1), Point2 (0,0), Point2 (-1,1)]
      c4 = makePointContour [Point2 (-1,-1), Point2 (1,-1), Point2 (1,1), Point2 (-1,1), Point2 (0,0)]
      c5 = makePointContour [Point2 (-1,-1), Point2 (1,-1), Point2 (2,0), Point2 (1,1), Point2 (-1,1), Point2 (0,0)]
      c6 = makePointContour [Point2 (-1,-1), Point2 (-0.5,-1), Point2 (0,0), Point2 (0.5,-1), Point2 (1,-1), Point2 (1,1), Point2 (-1,1)]
      c7 = makePointContour [Point2 (0,-1), Point2 (1,-1), Point2 (1,1), Point2 (0.5,1), Point2 (0.5,0), Point2 (0,1), Point2 (-1,1), Point2 (-1,0), Point2 (0,0)]
      -- The next corners are part of a 2x2 square around the origin with a piece missing: (c2 from above)
      --    __  <-- corner 1
      --   | /
      --   | \
      --   ~~~  <-- corner 3
      --   ^-- corner 4
      -- the exit of the convex angle and the top
      c2c1 = [ LineSeg (Point2 (0.0,0.0)) (Point2 (1.0,1.0)), LineSeg (Point2 (1.0,1.0)) (Point2 (-2.0,0.0))]
      -- the top and the left side.
      c2c2 = [ LineSeg (Point2 (1.0,1.0)) (Point2 (-2.0,0.0)), LineSeg (Point2 (-1.0,1.0)) (Point2 (0.0,-2.0))]
      c2c2E1 = ENode (LineSeg (Point2 (1.0,1.0)) (Point2 (-2.0,0.0)),LineSeg (Point2 (-1.0,1.0)) (Point2 (0.0,-2.0)))
                     (PLine2 (GVec [GVal (-0.7071067811865475) (singleton (GEPlus 1)), GVal (-0.7071067811865475) (singleton (GEPlus 2))]))
      -- the left and the bottom side.
      c2c3 = [ LineSeg (Point2 (-1.0,1.0)) (Point2 (0.0,-2.0)), LineSeg (Point2 (-1.0,-1.0)) (Point2 (2.0,0.0))]
      c2c3E1 = ENode (LineSeg (Point2 (-1.0,1.0)) (Point2 (0.0,-2.0)),LineSeg (Point2 (-1.0,-1.0)) (Point2 (2.0,0.0)))
                     (PLine2 (GVec [GVal 0.7071067811865475 (singleton (GEPlus 1)), GVal (-0.7071067811865475) (singleton (GEPlus 2))]))
      -- the bottom and the entrance to the wedge.
      c2c4 = [ LineSeg (Point2 (-1.0,-1.0)) (Point2 (2.0,0.0)), LineSeg (Point2 (1.0,-1.0)) (Point2 (-1.0,1.0))]
      -- the bottom and the entrance to the convex angle.
      c2c4E1 = ENode (LineSeg (Point2 (-1.0,-1.0)) (Point2 (2.0,0.0)) ,LineSeg (Point2 (1.0,-1.0)) (Point2 (-1.0,1.0)))
                     (PLine2 (GVec [GVal 0.541196100146197 (singleton (GEZero 1)), GVal 0.3826834323650897 (singleton (GEPlus 1)),GVal 0.9238795325112867 (singleton (GEPlus 2))]))
      -- The next corners are part of a 2x2 square around the origin with a slice and a corner missing: (c7 from above)
      --        v----- corner 2
      --  ┌───┐ ┌─┐<-- corner 1
      --  │    \│ │
      --  └───┐   │
      --      │   │
      --      └───┘
      c7c1E1 = ENode (LineSeg (Point2 (1.0,-1.0)) (Point2 (0.0,2.0)), LineSeg (Point2 (1.0,1.0)) (Point2 (-0.5,0.0)))
                     (PLine2 (GVec [GVal (-0.7071067811865475) (singleton (GEPlus 1)), GVal 0.7071067811865475 (singleton (GEPlus 2))]))
      c7c2E1 = ENode (LineSeg (Point2 (1.0,1.0)) (Point2 (-0.5,0.0)), LineSeg (Point2 (0.5,1.0)) (Point2 (0.0,-1.0)))
                     (PLine2 (GVec [GVal (1.0606601717798212) (singleton (GEZero 1)),GVal (-0.7071067811865475) (singleton (GEPlus 1)), GVal (-0.7071067811865475) (singleton (GEPlus 2))]))
      -- A simple triangle.
      triangle = makePointContour [Point2 (2,0), Point2 (1.0,sqrt 3), Point2 (0,0)]
      trianglel0 = LineSeg (Point2 (2,0)) (Point2 (-1.0,sqrt 3))
      -- A simple square.
      square = makePointContour [Point2 (-1,1), Point2 (-1,-1), Point2 (1,-1), Point2 (1,1)]
      -- A simple rectangle.
      rectangle = makePointContour [Point2 (-2,1), Point2 (-2,-1), Point2 (1,-1), Point2 (1,1)]
      cellFrom (Just (a,_)) = a
      cellFrom Nothing = error "whoops"
      remainderFrom (Just (_,a)) = a
      remainderFrom Nothing = error "whoops"
