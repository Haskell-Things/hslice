-- Slicer.
{-
 - Copyright 2016 Noah Halford and Catherine Moresco
 - Copyright 2019 Julia Longtin
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

-- FIXME: Force compilation.
{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE Rank2Types #-}

-- To treat literal strings as Text
{-# LANGUAGE OverloadedStrings #-}

import Prelude ((*), (/), (+), (-), fromIntegral, odd, pi, error, sqrt, mod, round, floor, foldMap, fmap, (<>), toRational, error, FilePath, (**))

import Control.Applicative (pure, (<*>), (<$>))

import Data.Eq ((==), (/=))

import Data.Function ((.), ($), flip)

import Data.Ord ((<=), (<), (>), max)

import Data.Tuple (fst, snd)

import Text.Read(read)

import Data.Text (Text, pack, unpack, unlines, unwords)

import Data.Text as DT (words)

import Data.String (String)

import Data.Bool(Bool, (||), (&&), otherwise)

import Data.List (nub, sortBy, lines, length, reverse, zip3, filter, tail, head, zipWith, maximum, (!!), minimum, init, splitAt, elem, take, last)

import Data.List as DL (words)

import Control.Monad ((>>=))

import Data.Maybe (Maybe(Just, Nothing), catMaybes, mapMaybe, fromMaybe)

import Text.Show(show)

import System.IO (IO, writeFile, readFile)

import Control.Monad.State(runState)

import Options.Applicative (fullDesc, progDesc, header, auto, info, helper, help, str, argument, long, short, option, metavar, execParser, Parser, optional, strOption, switch)

import Graphics.Slicer (Bed(RectBed), BuildArea(RectArea), ℝ, ℝ2, toℝ, ℕ, Fastℕ, fromFastℕ, toFastℕ, Point(Point), x,y,z, Line(Line), point, lineIntersection, scalePoint, addPoints, distance, lineFromEndpoints, endpoint, midpoint, flipLine, Facet(Facet), sides, Contour, LayerType(BaseOdd, BaseEven, Middle), pointSlopeLength, perpendicularBisector, shiftFacet, orderPoints, roundToFifth, roundPoint, shortenLineBy, accumulateValues, facetsFromSTL, cleanupFacet, makeLines, facetIntersects, getContours, simplifyContour, Extruder(Extruder), nozzleDiameter, filamentWidth, EPos(EPos), StateM, MachineState(MachineState), getEPos, setEPos)

default (ℕ, Fastℕ, ℝ)

---------------------------------------------------------------------------
-------------------- Point and Line Arithmetic ----------------------------
---------------------------------------------------------------------------

-- Given a point and slope (in xy plane), make "infinite" line (i.e. a line that
-- hits two edges of the bed
infiniteLine :: Bed -> Point -> ℝ -> Line
infiniteLine (RectBed (bedX,bedY)) p@(Point _ _ c) m = head . makeLines $ nub points
    where edges = lineFromEndpoints <$> [Point 0 0 c, Point bedX bedY c]
                                    <*> [Point 0 bedY c, Point bedX 0 c]
          longestLength = sqrt $ bedX*bedX + bedY*bedY
          halfLine@(Line p' s) = pointSlopeLength p m longestLength -- should have p' == p
          line = lineFromEndpoints (endpoint halfLine) (addPoints p' (scalePoint (-1) s))
          points = mapMaybe (lineIntersection line) edges

----------------------------------------------------------
----------- Functions to deal with STL parsing -----------
----------------------------------------------------------

-- Given the printer bed and a list of facets, center them on the print bed
centerFacets :: Bed -> [Facet] -> ([Facet], Point)
centerFacets (RectBed (bedX,bedY)) fs = (shiftFacet (Point dx dy dz) <$> fs, Point dx dy dz)
    where (dx,dy,dz) = ((bedX/2-x0), (bedY/2-y0), (-zMin))
          xMin = minimum $ x.point <$> foldMap sides fs
          yMin = minimum $ y.point <$> foldMap sides fs
          zMin = minimum $ z.point <$> foldMap sides fs
          xMax = maximum $ x.point <$> foldMap sides fs
          yMax = maximum $ y.point <$> foldMap sides fs
          (x0,y0) = ((xMax+xMin)/2-xMin, (yMax+yMin)/2-yMin)

-- Read a point when it's given a string of the form "x y z"
readPoint :: String -> Point
readPoint s = do
  let
    xval, yval, zval :: ℝ
    (xval, yval, zval) = readThree $ take 3 $ DL.words s
  Point (xval) (yval) (zval)
    where
      readThree :: [String] -> (ℝ,ℝ,ℝ)
      readThree [xv,yv,zv] = (read xv,read yv,read zv)
      readThree _ = error "unexpected value when reading point."

-- Read a list of three coordinates (as strings separated by spaces) and generate a facet.
readFacet :: [String] -> Facet
readFacet f
    | length f < 3 = error "Invalid facet"
    | otherwise = Facet . makeLines $ readPoint <$> f'
    where f' = last f : f -- So that we're cyclic

-- From STL file (as a list of Strings, each String corresponding to one line),
-- produce a list of lists of Lines, where each list of Lines corresponds to a
-- facet in the original STL
facetLinesFromSTL :: [String] -> [Facet]
facetLinesFromSTL = fmap (readFacet . cleanupFacet) . facetsFromSTL

-- Amount to extrude when making a line between two points.
extrusionAmount :: Extruder -> ExtCuraEngineOpts -> Point -> Point -> ℝ
extrusionAmount extruder opts p1 p2 = nozzleDia * t * (2 / filamentDia) * l / pi
    where l = distance p1 p2
          defaultThickness :: ℝ
          defaultThickness = 0.2
          t = fromMaybe defaultThickness $ thickness opts
          nozzleDia = nozzleDiameter extruder
          filamentDia = filamentWidth extruder

-- Given a contour and the point to start from, calculate the amount of material to extrude for each line.
extrusions :: Extruder -> ExtCuraEngineOpts -> Point -> [Point] -> [ℝ]
extrusions _ _ _ [] = []
extrusions extruder opts p c = extrusionAmount extruder opts p (head c) : extrusions extruder opts (head c) (tail c)

-----------------------------------------------------------------------
---------------------- Contour filling --------------------------------
-----------------------------------------------------------------------

-- Make infill
makeInfill :: Bed -> ExtCuraEngineOpts -> [[Point]] -> LayerType -> [Line]
makeInfill bed opts contours layerType = foldMap (infillLineInside contours) $ infillCover layerType
    where infillCover Middle = coveringInfill bed opts fillAmount zHeight
          infillCover BaseEven = coveringLinesUp bed opts zHeight
          infillCover BaseOdd = coveringLinesDown bed opts zHeight
          zHeight = z $ head $ head contours
          defaultInfill :: ℝ
          defaultInfill = 20
          fillAmount = fromMaybe defaultInfill $ infill opts

-- Get the segments of an infill line that are inside the contour
infillLineInside :: [[Point]] -> Line -> [Line]
infillLineInside contours line = (allLines !!) <$> [0,2..length allLines - 1]
    where allLines = makeLines $ sortBy orderPoints $ getInfillLineIntersections contours line

-- Find all places where an infill line intersects any contour line 
getInfillLineIntersections :: [[Point]] -> Line -> [Point]
getInfillLineIntersections contours line = nub $ mapMaybe (lineIntersection line) contourLines
    where contourLines = foldMap makeLines contours

-- Generate covering lines for a given percent infill
coveringInfill :: Bed -> ExtCuraEngineOpts -> ℝ -> ℝ -> [Line]
coveringInfill bed opts infillAmount zHeight
    | infillAmount == 0 = []
    | otherwise = pruneInfill (coveringLinesUp bed opts zHeight) <> pruneInfill (coveringLinesDown bed opts zHeight)
    where
      n :: ℝ
      n = max 1 (infillAmount/100)
      pruneInfill :: [Line] -> [Line]
      pruneInfill l = (l !!) <$> [0, (floor n)..length l-1]

-- Generate lines over entire print area
coveringLinesUp :: Bed -> ExtCuraEngineOpts -> ℝ -> [Line]
coveringLinesUp (RectBed (bedX,bedY)) opts zHeight = flip Line s . f <$> [-bedX,-bedX + separation..bedY]
    where s = Point (bedX + bedY) (bedX + bedY) 0
          f v = Point 0 v zHeight
          defaultLineThickness :: ℝ
          defaultLineThickness = 0.6
          separation = fromMaybe defaultLineThickness $ lineThickness opts

coveringLinesDown :: Bed -> ExtCuraEngineOpts -> ℝ -> [Line]
coveringLinesDown (RectBed (bedX,bedY)) opts zHeight = flip Line s . f <$> [0,separation..bedY + bedX]
    where s =  Point (bedX + bedY) (- bedX - bedY) 0
          f v = Point 0 v zHeight
          defaultLineThickness :: ℝ
          defaultLineThickness = 0.6
          separation = fromMaybe defaultLineThickness $ lineThickness opts

lineSlope :: Point -> ℝ
lineSlope m = case x m of 0 -> if y m > 0 then 10**101 else -(10**101)
                          _ -> y m / x m

-- Helper function to generate the points we'll need to make the inner perimeters
pointsForPerimeters :: Extruder -> ExtCuraEngineOpts -> Line -> [Point]
pointsForPerimeters extruder opts l = endpoint . pointSlopeLength (midpoint l) (lineSlope m) . (*nozzleDia) <$> filter (/= 0) [-n..n]
  where
    n :: ℝ
    n = fromIntegral $ perimeters - 1
    defaultPerimeterLayers :: Fastℕ
    defaultPerimeterLayers = 2
    perimeters = fromMaybe defaultPerimeterLayers $ perimeterLayers opts
    Line _ m = perpendicularBisector l
    nozzleDia :: ℝ
    nozzleDia = nozzleDiameter extruder

-- Lines to count intersections to determine if we're on the inside or outside
perimeterLinesToCheck :: Extruder -> Line -> [Line]
perimeterLinesToCheck extruder l@(Line p _) = ((`lineFromEndpoints` Point 0 0 (z p)) . endpoint . pointSlopeLength (midpoint l) (lineSlope m) . (*nozzleDia)) <$> [-1,1]
  where Line _ m = perpendicularBisector l
        nozzleDia :: ℝ
        nozzleDia = nozzleDiameter extruder

-- Find the point corresponding to the inner perimeter of a given line, given all of the
-- contours in the object
innerPerimeterPoint :: Extruder -> Line -> [Contour] -> Point
innerPerimeterPoint extruder l contours
    | length oddIntersections > 0 = snd $ head oddIntersections
    | length nonzeroIntersections > 0 = snd $ head nonzeroIntersections
    | otherwise = snd $ head intersections
    where linesToCheck = perimeterLinesToCheck extruder l
          contourLines = foldMap makeLines contours
          simplifiedContour = simplifyContour contourLines
          numIntersections l' = length $ mapMaybe (lineIntersection l') simplifiedContour
          intersections = (\a -> (numIntersections a, point a)) <$> linesToCheck
          oddIntersections = filter (odd . fst) intersections
          nonzeroIntersections = filter (\(v,_) -> v /= 0) intersections

-- Construct infinite lines on the interior for a given line
infiniteInteriorLines :: Bed -> Extruder -> ExtCuraEngineOpts -> Line -> [[Point]] -> [Line]
infiniteInteriorLines bed extruder opts l@(Line _ m) contours
    | innerPoint `elem` firstHalf = flip (infiniteLine bed) (lineSlope m) <$> firstHalf
    | otherwise = flip (infiniteLine bed) (lineSlope m) <$> secondHalf
    where innerPoint = innerPerimeterPoint extruder l contours
          defaultPerimeterLayers :: Fastℕ
          defaultPerimeterLayers = 2
          (firstHalf, secondHalf) = splitAt (fromFastℕ $ (fromMaybe defaultPerimeterLayers $ perimeterLayers opts) - 1) $ pointsForPerimeters extruder opts l

-- List of lists of interior lines for each line in a contour
allInteriors :: Bed -> Extruder -> ExtCuraEngineOpts -> [Point] -> [[Point]] -> [[Line]]
allInteriors bed extruder opts c contours = flip (infiniteInteriorLines bed extruder opts) contours <$> targetLines
    where targetLines = makeLines c

-- Make inner contours from a list of (outer) contours---note that we do not
-- retain the outermost contour.
innerContours :: Bed -> Extruder -> ExtCuraEngineOpts -> [Contour] -> [[Contour]]
innerContours bed extruder opts contours = foldMap (constructInnerContours opts .(\i -> last i : i)) interiors
    where interiors = flip (allInteriors bed extruder opts) contours <$> contours

-- Construct inner contours, given a list of lines constituting the infinite interior
-- lines. Essentially a helper function for innerContours
constructInnerContours :: ExtCuraEngineOpts -> [[Line]] -> [[Contour]]
constructInnerContours opts interiors
    | length interiors == 0 = []
    | length (head interiors) == 0 && (length interiors == 1) = []
    | length (head interiors) == 0 = constructInnerContours opts $ tail interiors
    | otherwise = [intersections] : constructInnerContours opts (tail <$> interiors)
    where intersections = catMaybes $ consecutiveIntersections $ head <$> interiors

consecutiveIntersections :: [Line] -> [Maybe Point]
consecutiveIntersections [] = [Nothing]
consecutiveIntersections [_] = [Nothing]
consecutiveIntersections (a:b:cs) = lineIntersection a b : consecutiveIntersections (b : cs)

-- Generate G-code for a given contour c.
gcodeForContour :: Extruder
                -> ExtCuraEngineOpts
                -> [Point]
                -> StateM [Text]
gcodeForContour extruder opts c = do
  currentPos <- toℝ <$> getEPos
  let
    extrusionAmounts = extrusions extruder opts (head c) (tail c)
    ePoses = accumulateValues extrusionAmounts
    newPoses = (currentPos+) <$> ePoses
    es = (" E" <>) . pack . show <$> newPoses
  setEPos . toRational $ last newPoses
  pure $ ("G1 " <>) <$> zipWith (<>) (pack . show <$> c) ("":es)

gcodeForNestedContours :: Extruder
                       -> ExtCuraEngineOpts
                       -> [[Contour]]
                       -> StateM [Text]
gcodeForNestedContours _ _ [] = pure []
gcodeForNestedContours extruder opts [c] = gcodeForContours extruder opts c
gcodeForNestedContours extruder opts (c:cs) = do
  oneContour <- firstContoursGCode
  remainingContours <- gcodeForNestedContours extruder opts cs
  pure $ oneContour <> remainingContours
    where firstContoursGCode = gcodeForContours extruder opts c

gcodeForContours :: Extruder
                 -> ExtCuraEngineOpts
                 -> [Contour]
                 -> StateM [Text]
gcodeForContours _ _ [] = pure []
gcodeForContours extruder opts [c] = gcodeForContour extruder opts c
gcodeForContours extruder opts (c:cs) = do
  oneContour <- firstContourGCode
  remainingContours <- gcodeForContours extruder opts cs
  pure $ oneContour <> remainingContours
    where firstContourGCode = gcodeForContour extruder opts c

-- G-code to travel to a point without extruding
makeTravelGCode :: Point -> Text
makeTravelGCode p = ("G1 " <>) $ pack $ show p

-- I'm not super happy about this, but it makes extrusion values correct
fixGCode :: [Text] -> [Text]
fixGCode [] = []
fixGCode [a] = [a]
fixGCode (a:b:cs) = unwords (init $ DT.words a) : b : fixGCode cs

-----------------------------------------------------------------------
----------------------------- SUPPORT ---------------------------------
-----------------------------------------------------------------------

-- A bounding box. a box around a contour.
data BBox = BBox ℝ2 ℝ2

-- Check if a bounding box is empty.
isEmpty :: BBox -> Bool
isEmpty (BBox (x1,y1) (x2,y2)) = x1 == x2 || y1 == y2

-- Get a bounding box of all contours.
boundingBoxAll :: [Contour] -> Maybe BBox
boundingBoxAll contours = if (isEmpty box) then Nothing else Just box
    where
      box  = BBox (minX, minY) (maxX, maxY)
      minX = minimum $ (\(BBox (x1,_) _) -> x1) <$> bBoxes
      minY = minimum $ (\(BBox (_,y1) _) -> y1) <$> bBoxes
      maxX = maximum $ (\(BBox _ (x2,_)) -> x2) <$> bBoxes
      maxY = maximum $ (\(BBox _ (_,y2)) -> y2) <$> bBoxes
      bBoxes = mapMaybe boundingBox contours


-- Get a bounding box of a contour.
boundingBox :: Contour -> Maybe BBox
boundingBox [] = Nothing
boundingBox contour = if (isEmpty box) then Nothing else Just box
    where
          box  = BBox (minX, minY) (maxX, maxY)
          minX = minimum $ x <$> contour
          minY = minimum $ y <$> contour
          maxX = maximum $ x <$> contour
          maxY = maximum $ y <$> contour

-- Put a fixed amount around the bounding box.
incBBox :: BBox -> ℝ -> BBox
incBBox (BBox (x1,y1) (x2,y2)) ammount = BBox (x1+ammount, y1+ammount) (x2-ammount, y2-ammount)

-- add the bounding box to a list of contours, as the first layer.
-- FIXME: magic number.
addBBox :: [Contour] -> [Contour]
addBBox contours = [Point x1 y1 z0, Point x2 y1 z0, Point x2 y2 z0, Point x1 y2 z0, Point x1 y1 z0] : contours
    where
      bbox = fromMaybe (BBox (1,1) (-1,-1)) $ boundingBoxAll contours
      (BBox (x1, y1) (x2, y2)) = incBBox bbox 1
      z0 = z $ head $ head contours

-- Generate support
-- FIXME: hard coded infill amount.
makeSupport :: Bed
            -> ExtCuraEngineOpts
            -> [[Point]]
            -> LayerType
            -> [Line]
makeSupport bed opts contours _ = fmap (shortenLineBy $ 2 * t)
                                  $ foldMap (infillLineInside (addBBox contours))
                                  $ infillCover Middle
    where infillCover Middle = coveringInfill bed opts 20 zHeight
          infillCover BaseEven = coveringLinesUp bed opts zHeight
          infillCover BaseOdd = coveringLinesDown bed opts zHeight
          defaultThickness :: ℝ
          defaultThickness = 0.2
          t = fromMaybe defaultThickness $ thickness opts
          zHeight = z $ head $ head contours

-----------------------------------------------------------------------
--------------------------- LAYERS ------------------------------------
-----------------------------------------------------------------------

-- Create contours from a list of facets
layers :: ExtCuraEngineOpts -> [Facet] -> [[[Point]]]
layers opts fs = fmap (allIntersections.roundToFifth) [maxheight,maxheight-t..0] <*> pure fs
    where zmax = maximum $ (z.point) <$> (foldMap sides fs)
          maxheight = t * fromIntegral (floor (zmax / t)::Fastℕ)
          defaultThickness :: ℝ
          defaultThickness = 0.2
          t = fromMaybe defaultThickness $ thickness opts

getLayerType :: ExtCuraEngineOpts -> (Fastℕ, Fastℕ) -> LayerType
getLayerType opts (fromStart, toEnd)
  | (fromStart <= topBottomLayers || toEnd <= topBottomLayers) && fromStart `mod` 2 == 0 = BaseEven
  | (fromStart <= topBottomLayers || toEnd <= topBottomLayers) && fromStart `mod` 2 == 1 = BaseOdd
  | otherwise = Middle
  where
    topBottomLayers :: Fastℕ
    topBottomLayers = round $ defaultBottomTopThickness / t
    defaultBottomTopThickness :: ℝ
    defaultBottomTopThickness = 0.8
    defaultThickness :: ℝ
    defaultThickness = 0.2
    t = fromMaybe defaultThickness $ thickness opts

----------------------------------------------------------------------
---------------------------- MISC ------------------------------------
----------------------------------------------------------------------

fixContour :: [Point] -> [Point]
fixContour c = head c : tail c <> [head c]

-- Find all the points in the mesh at a given z value
-- Each list in the output should have length 2, corresponding to a line segment
allIntersections :: ℝ -> [Facet] -> [[Point]]
allIntersections v fs = fmap (fmap roundPoint) $ filter (/= []) $ (facetIntersects v) <$> fs

-- Map a function to every other value in a list. This is useful for fixing non-extruding
-- lines.
mapEveryOther :: (a -> a) -> [a] -> [a]
mapEveryOther _ [] = []
mapEveryOther f [a] = [f a]
mapEveryOther f (a:b:cs) = f a : b : mapEveryOther f cs

-------------------------------------------------------------
----------------------- ENTRY POINT -------------------------
-------------------------------------------------------------

-- Input should be top to bottom, output should be bottom to top
sliceObject ::  Bed -> Extruder -> ExtCuraEngineOpts
                  -> [([Contour], Fastℕ, Fastℕ)] -> StateM [Text]
sliceObject _ _ _ [] = pure []
sliceObject bed extruder opts ((a, fromStart, toEnd):as) = do
  theRest <- sliceObject bed extruder opts as
  outerContourGCode <- gcodeForContours extruder opts contours
  innerContourGCode <- gcodeForNestedContours extruder opts interior
  let
    travelGCode = if theRest == [] then [] else makeTravelGCode <$> head contours
  supportGCode <- if support opts then fixGCode <$> gcodeForContour extruder opts supportContours else pure []
  infillGCode <- fixGCode <$> gcodeForContour extruder opts infillContours
  pure $ theRest <> outerContourGCode <> innerContourGCode <> travelGCode <> supportGCode <> infillGCode
    where
      contours = getContours a
      interior = fmap fixContour <$> innerContours bed extruder opts contours
      supportContours = foldMap (\l -> [point l, endpoint l])
                        $ mapEveryOther flipLine
                        $ makeSupport bed opts contours
                        $ getLayerType opts (fromStart, toEnd)
      infillContours = foldMap (\l -> [point l, endpoint l])
                       $ mapEveryOther flipLine
                       $ makeInfill bed opts innermostContours
                       $ getLayerType opts (fromStart, toEnd)
      allContours = zipWith (:) contours interior
      innermostContours = if interior == [] then contours else last <$> allContours

----------------------------------------------------------
------------------------ OPTIONS -------------------------
----------------------------------------------------------

-- Note: we're modeling the current engine options, and will switch to curaEngine style after the json parser is integrated.
data ExtCuraEngineOpts = ExtCuraEngineOpts
    { perimeterLayers :: Maybe Fastℕ
    , infill          :: Maybe ℝ
    , thickness       :: Maybe ℝ
    , support         :: Bool
    , outputFile      :: Maybe FilePath
--    , center     :: Maybe Point
    , lineThickness   :: Maybe ℝ
    , inputFile       :: String
    }

-- | The parser for our command line arguments.
extCuraEngineOpts :: Parser ExtCuraEngineOpts
extCuraEngineOpts = ExtCuraEngineOpts
  <$> optional (
  option auto
    (    short 'p'
      <> long "perimeter"
      <> help "How many layers go around each contour"
    )
  )
-- FIXME: constrain this to be 0 or greater.
  <*> optional (
  option auto
    (    short 'i'
      <> long "infill"
      <> metavar "INFILL"
      <> help "Infill amount (ranging from 0 to 1)"
    )
  )
  <*> optional (
  option auto
    (    short 't'
      <> long "thickness"
      <> metavar "THICKNESS"
      <> help "The layer height (in millimeters)"
    )
  )
  <*> switch
  (     long "support"
     <> help "Whether to generate support structures"
  )
  <*> optional (
  strOption
    (    short 'o'
      <> long "output"
      <> metavar "OUTPUT"
      <> help "Output file name"
      )
    )
  <*> optional (
  option auto
    (    short 'l'
      <> long "linethickness"
      <> metavar "LINETHICKNESS"
      <> help "The distance between lines of the infill (in millimeters)"
    )
  )
{-  <*> optional (
  option auto
    (    short 'c'
      <> long "center"
      <> metavar "CENTER"
      <> help "The position on the print bed to center the object."
    )
  )
-}  <*> argument str
  (  metavar "FILE"
     <> help "Input ascii STL file"
  )

-----------------------------------------------------------------------
--------------------------- Main --------------------------------------
-----------------------------------------------------------------------
run :: ExtCuraEngineOpts -> IO ()
run rawArgs = do
    let
      args = rawArgs
    stl <- readFile (inputFile args)
    let stlLines = lines stl
        (facets, _) = centerFacets printerBed $ facetLinesFromSTL stlLines
        allLayers = (filter (\l -> head l /= head (tail l)) . filter (/=[])) <$> layers args facets
        object = zip3 allLayers [1..(toFastℕ $ length allLayers)] $ reverse [1..(toFastℕ $ length allLayers)]
        (gcode, _) = runState (sliceObject printerBed extruder1 args object) (MachineState (EPos 0))
        outFile = fromMaybe "out.gcode" $ outputFile args
      in
      writeFile outFile $ unpack (startingGCode <> unlines gcode <> endingGCode)
      where
        -- FIXME: pull all of these values from a curaengine json config.
        -- The bed of the printer. assumed to be some form of rectangle, with the build area coresponding to all of the space above it.
        printerBed :: Bed
        printerBed = RectBed (150,150)
        -- The Extruder. note that this includes the diameter of the feed filament.
        extruder1 = Extruder 1.75 0.4
        startingGCode, endingGCode :: Text
        startingGCode =    "G21 ;metric values\n"
                           <> "G90 ;absolute positioning\n"
                           <> "M82 ;set extruder to absolute mode\n"
                           <> "M106 ;start with the fan on\n"
                           <> "G28 X0 Y0 ;move X/Y to min endstops\n"
                           <> "G28 Z0 ;move Z to min endstops\n"
                           <> "G29 ;Run the auto bed leveling\n"
                           <> "G1 Z15.0 F4200 ;move the platform down 15mm\n"
                           <> "G92 E0 ;zero the extruded length\n"
                           <> "G1 F200 E3 ;extrude 3mm of feed stock\n"
                           <> "G92 E0 ;zero the extruded length again\n"
                           <> "G1 F4200 ;default speed\n"
                           <> ";Put printing message on LCD screen\n"
                           <> "M117\n"
        endingGCode =    ";End GCode\n"
                         <> "M104 S0 ;extruder heater off\n"
                         <> "M140 S0 ;heated bed heater off (if you have it)\n"
                         <> "G91 ;relative positioning\n"
                         <> "G1 E-1 F300 ;retract the filament a bit before lifting the nozzle, to release some of the pressure\n"
                         <> "G1 Z+0.5 E-5 X-20 Y-20 F{travel_speed} ;move Z up a bit and retract filament even more\n"
                         <> "G28 X0 Y0 ;move X/Y to min endstops, so the head is out of the way\n"
                         <> "M107 ;fan off\n"
                         <> "M84 ;steppers off\n"
                         <> "G90 ;absolute positioning\n"

-- | The entry point. Use the option parser then run the slicer.
main :: IO ()
main = execParser opts >>= run
    where
      opts= info (helper <*> extCuraEngineOpts)
            ( fullDesc
              <> progDesc "HSlice: STL to ASCII GCode slicer."
              <> header "extcuraengine - Extended CuraEngine"
            )

