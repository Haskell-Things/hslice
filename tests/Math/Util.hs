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

-- Utilities
module Math.Util
         ( (-->)
         ) where

-- be explicit about where we get things from.
import Prelude (String, Bool(False))

-- A value.
import Graphics.Slicer.Math.PGA (GVal)

import Test.Hspec (Expectation, shouldBe)

-- An operator for expressions for "the left side should evaluate to the right side."
infixr 1 -->
(-->) :: [GVal] -> [GVal] -> Expectation
(-->) res exp =
  res `shouldBe` exp

