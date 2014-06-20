-- Copyright (c) 2014 Eric McCorkle.  All rights reserved.
--
-- Redistribution and use in source and binary forms, with or without
-- modification, are permitted provided that the following conditions
-- are met:
--
-- 1. Redistributions of source code must retain the above copyright
--    notice, this list of conditions and the following disclaimer.
--
-- 2. Redistributions in binary form must reproduce the above copyright
--    notice, this list of conditions and the following disclaimer in the
--    documentation and/or other materials provided with the distribution.
--
-- 3. Neither the name of the author nor the names of any contributors
--    may be used to endorse or promote products derived from this software
--    without specific prior written permission.
--
-- THIS SOFTWARE IS PROVIDED BY THE AUTHORS AND CONTRIBUTORS ``AS IS''
-- AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED
-- TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A
-- PARTICULAR PURPOSE ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHORS
-- OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
-- SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
-- LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF
-- USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
-- ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
-- OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT
-- OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
-- SUCH DAMAGE.
{-# OPTIONS_GHC -Wall -Werror -funbox-strict-fields #-}
{-# LANGUAGE DeriveDataTypeable #-}

-- | Defines a datatype representing an isomorphism between the
-- datatype ty (or some subset thereof) and the natural numbers
-- (represented as 'Integer's).
--
-- 'Encoding's consist of several components, the most important of
-- which are the 'encode' and 'decode' functions.  These functions are
-- define an isomorphism to a range of natural number starting at
-- zero, meaning they are expected to obey the following laws:
-- * @encode . decode == id@
-- * @encode a == encode b@ only if @a == b@
-- * @(encEncode e) a >= 0@
-- * If @encSize e == Just n@, then @(encEncode e) a < n@
--
-- The 'size' value gives the number of mappings in the 'Encoding'.  For
-- an infinite isomorphism, @size == Nothing@, otherwise, @size ==
-- Just n@ for an 'Encoding' of size @n@.
--
-- The dimensions of the datatype are described by the type @dim@.
-- Dimensions in this context are used to indicate a notion of
-- /depth/, which is useful in some applications for 'Encoding's.  The
-- dimension type is expected to have an 'Enum' instance. It is up to
-- the implementation to determine what constitutes a dimension;
-- however, dimensions should determine a notion of depth independent
-- of all other dimensions.  For example, a matrix has two dimensions,
-- whereas a binary tree has one.  Depending on our intended
-- application, we might define an @n@-ary tree to have two
-- dimensions: one indicating the depth of the tree, and one
-- indicating the largest node degree.
--
-- The 'maxDepth' function should give the maximum depth for a given
-- dimension, or 'Nothing' if there is no maximum.
--
-- The 'depth' function indicates the depth in a given dimension for a
-- given 'ty'.
--
-- The 'highestIndex' function gives the highest number to which any
-- 'ty' up to and including a given depth in a given dimension will be
-- mapped, or 'Nothing' if there is no such limit.
--
-- It is always valid to define a dimensionless mapping, where @dim ==
-- Unit@ and every @ty@ has depth 0.
module Data.ArithEncode(
       -- * Basic Definitions

       -- ** Constructors
       Encoding,
       mkEncoding,
       mkDimlessEncoding,
       mkInfEncoding,
       mkInfDimlessEncoding,

       -- ** Using Encodings
       IllegalArgument(..),
       encode,
       decode,
       size,
       maxDepth,
       depth,
       highestIndex,

       -- * Building Encodings

       -- ** Basic Encodings
       identity,
       singleton,
       integral,
       interval,
       fromHashableList,
       fromOrdList,

       -- ** Constructions
       wrap,
       optional,
       mandatory,
       nonzero,
       exclude,
       either,
       {-
       disjointUnion,
       product,
       product3,
       product4,
       product5,
       product6,
       product7,
       product8,
       product9,
       product10,
       pair,
       triple,
       quad,
       quint,
       set,
       finiteMap,
       finiteSeq-}
       ) where

import Control.Exception
import Data.Bits
import Data.Hashable
import Data.List hiding (elem)
import Data.Maybe
import Data.Typeable
import Prelude hiding (elem, either)

import qualified Data.Array as Array
import qualified Data.Either as Either
import qualified Data.HashMap as HashMap
import qualified Data.Map as Map
--import qualified Data.Set as Set

-- | An exception to be thrown if an illegal argument is given to
-- 'encode', 'decode', 'depth', or 'highestIndex'.
data IllegalArgument = IllegalArgument !String
  deriving Typeable

instance Show IllegalArgument where
  show (IllegalArgument "") = "Illegal argument"
  show (IllegalArgument s) = "Illegal argument: " ++ s

instance Exception IllegalArgument

-- | Type for an encoding.
data Encoding dim ty =
  Encoding {
    -- | Encode a @ty@ as a positive integer.
    encEncode :: ty -> Integer,
    -- | Decode a positive integer into a @ty@.
    encDecode :: Integer -> ty,
    -- | The size of an encoding, or 'Nothing' if it is infinite.
    encSize :: !(Maybe Integer),
    -- | Get the maximum depth of a given dimension.
    encMaxDepth :: dim -> Maybe Integer,
    -- | Get the depth of a given @ty@ in a given dimension.
    encDepth :: dim -> ty -> Integer,
    -- | Get the higest number to which any 'ty' of a given depth in a
    -- given dimension will map.
    encHighestIndex :: dim -> Integer -> Maybe Integer
  }

-- | Create an encoding from all the necessary components.
mkEncoding :: Enum dim
           => (ty -> Integer)
           -- ^ The encoding function.
           -> (Integer -> ty)
           -- ^ The decoding function.  Can assume all inputs are positive.
           -> Maybe Integer
           -- ^ The number of mappings, or 'Nothing' if it is infinite.
           -> (dim -> Maybe Integer)
           -- ^ A function indicating the maximum depth of any dimension.
           -> (dim -> ty -> Integer)
           -- ^ A function indicating the depth of a @ty@ in dimension @dim@.
           -> (dim -> Integer -> Maybe Integer)
           -- ^ A function indicating the last number mapping to a
           -- @ty@ less than a given depth in a given dimension.
           -> Encoding dim ty
mkEncoding encodefunc decodefunc sizeval maxdepthfunc depthfunc highindexfunc =
  Encoding { encEncode = encodefunc, encDecode = decodefunc,
             encSize = sizeval, encMaxDepth = maxdepthfunc,
             encDepth = depthfunc, encHighestIndex = highindexfunc }

-- | Create an infinite-sized encoding.
mkInfEncoding :: Enum dim
              => (ty -> Integer)
              -- ^ The encoding function.
              -> (Integer -> ty)
              -- ^ The decoding function.  Can assume all inputs are positive.
              -> (dim -> Maybe Integer)
              -- ^ A function indicating the maximum depth of any dimension.
              -> (dim -> ty -> Integer)
              -- ^ A function indicating the depth of a @ty@ in dimension @dim@.
              -> (dim -> Integer -> Maybe Integer)
              -- ^ A function indicating the last number mapping to a
              -- @ty@ less than a given depth in a given dimension.
              -> Encoding dim ty
mkInfEncoding encodefunc decodefunc =
  mkEncoding encodefunc decodefunc Nothing

-- | Create a dimensionless (potentially finite) encoding.
mkDimlessEncoding :: (ty -> Integer)
                  -- ^ The encoding function.
                  -> (Integer -> ty)
                  -- ^ The decoding function.  Can assume all inputs
                  -- are positive.
                  -> Maybe Integer
                     -- ^ The number of mappings, or 'Nothing' if it is infinite.
                  -> Encoding () ty
mkDimlessEncoding encodefunc decodefunc sizeval =
  mkEncoding encodefunc decodefunc sizeval (\() -> Just 0)
             (\() _ -> 0) (\() _ -> sizeval)

-- | Create an infinite, dimensionless encoding.
mkInfDimlessEncoding :: (ty -> Integer)
                     -- ^ The encoding function.
                     -> (Integer -> ty)
                     -- ^ The decoding function.  Can assume all
                     -- inputs are positive.
                     -> Encoding () ty
mkInfDimlessEncoding encodefunc decodefunc =
  mkDimlessEncoding encodefunc decodefunc Nothing

-- | Encode a @ty@ as a positive 'Integer'.
encode :: Encoding dim ty
       -- ^ Encoding to use.
       -> ty
       -- ^ Value to encode.
       -> Integer
       -- ^ Encoded value.
encode encoding = encEncode encoding

-- | Decode a @ty@ from a positive 'Integer'.
decode :: Encoding dim ty
       -- ^ Encoding to use.
       -> Integer
       -- ^ Number to decode.
       -> ty
       -- ^ Decoded value.
decode encoding num
  | num < 0 =
    throw (IllegalArgument ("decode argument " ++ show num ++ " is negative"))
  | maybe False (<= num) (size encoding) =
    throw (IllegalArgument ("decode argument " ++ show num ++
                            " is out of bounds"))
  | otherwise = (encDecode encoding) num

-- | Get the size of an 'Encoding', or 'Nothing' if it is infinite.
size :: Encoding dim ty
     -- ^ Encoding to use.
     -> Maybe Integer
     -- ^ Number of values mapped, or 'Nothing' for infinity.
size = encSize

-- | Get the maximum depth of a given dimension.
maxDepth :: Encoding dim ty
         -- ^ Encoding to use.
         -> dim
         -- ^ Dimension.
         -> Maybe Integer
         -- ^ Maximum depth of @dim@.
maxDepth encoding = encMaxDepth encoding

-- | Get the depth of a value.
depth :: Encoding dim ty
      -- ^ Encoding to use.
      -> dim
      -- ^ Dimension.
      -> ty
      -- ^ Dimension.
      -> Integer
      -- ^ Maximum depth of @dim@.
depth encoding = encDepth encoding

-- | Get the higest @n@ to which any value of depth no greater than
-- the given bound will be mapped using the given encoding.
highestIndex :: Encoding dim ty
             -- ^ Encoding to use.
             -> dim
             -- ^ Dimension.
             -> Integer
             -- ^ Bound on depth.
             -> Maybe Integer
             -- ^ Maximum depth of @dim@.
highestIndex encoding = encHighestIndex encoding

-- | The identity encoding.
identity :: Encoding () Integer
identity = mkInfDimlessEncoding id id

-- | A singleton encoding.  Maps a singular value to 0.
singleton :: ty -> Encoding () ty
singleton val = mkDimlessEncoding (\_ -> 0) (\_ -> val) (Just 1)

-- | An encoding of /all/ integers into the positive integers.
integral :: Integral n => Encoding () n
integral =
  let
    encodefunc num
      | num < 0 = ((abs (toInteger num) - 1) `shiftL` 1) `setBit` 0
      | otherwise = (toInteger num) `shiftL` 1

    decodefunc num
      | num `testBit` 0 = fromInteger (-((num `shiftR` 1) + 1))
      | otherwise = fromInteger (num `shiftR` 1)
  in
    mkInfDimlessEncoding encodefunc decodefunc

-- | Build an encoding from a finite range of 'Integral's.
interval :: (Show n, Integral n)
                 => n
                 -- ^ The (inclusive) lower bound on the range.
                 -> n
                 -- ^ The (exclusive) upper bound on the range.
                 -> Encoding () n
interval lower upper
  | lower <= upper =
    let
      biglower = toInteger lower

      encodefunc num
        | num < lower =
          throw (IllegalArgument ("value " ++ show num ++
                                  " is less than lower bound " ++ show lower))
        | num > upper =
          throw (IllegalArgument ("value " ++ show num ++
                                  " is greater or equal to upper bound " ++
                                  show upper))
        | otherwise = (toInteger num) - biglower

      decodefunc num = fromInteger (num + biglower)

      sizeval = Just ((toInteger upper) - (toInteger lower) + 1)
    in
       mkDimlessEncoding encodefunc decodefunc sizeval
  | otherwise = error "Lower bound is not less than upper bound"

-- | Build an encoding from a list of 'Hashable' items.
fromHashableList :: (Hashable ty, Ord ty)
                 => [ty]
                 -- ^ A list of items to encode.
                 -> Encoding () ty
                 -- ^ An encoding mapping the items in the list to
                 -- natural numbers.
fromHashableList elems =
  let
    len = length elems
    revmap = Array.listArray (0, len) elems
    fwdmap = HashMap.fromList (zip elems [0..len])
    encodefunc = toInteger . (HashMap.!) fwdmap
    decodefunc = (Array.!) revmap . fromInteger
    sizeval = Just (toInteger len)
  in
    mkDimlessEncoding encodefunc decodefunc sizeval

-- | Build an encoding from a list of 'Hashable' items.
fromOrdList :: Ord ty
            => [ty]
            -- ^ A list of items to encode.
            -> Encoding () ty
            -- ^ An encoding mapping the items in the list to natural
            -- numbers.
fromOrdList elems =
  let
    len = length elems
    revmap = Array.listArray (0, len) elems
    fwdmap = Map.fromList (zip elems [0..len])
    encodefunc = toInteger . (Map.!) fwdmap
    decodefunc = (Array.!) revmap . fromInteger
    sizeval = Just (toInteger len)
  in
    mkDimlessEncoding encodefunc decodefunc sizeval

-- | Wrap an encoding using a pair of functions.  These functions must
-- also define an isomorphism.
--
-- The resulting encoding from
-- > wrapEncoding fwd rev enc
-- implements @depth@ as @depth enc . fwd@, which only works if @fwd@
-- preserves all depths.  For more complex cases, use @mkEncoding@ to
-- define a new encoding.
wrap :: (a -> b)
     -- ^ The forward encoding function.
     -> (b -> a)
     -- ^ The reverse encoding function.
     -> Encoding dim b
     -- ^ The inner encoding.
     -> Encoding dim a
wrap fwd rev enc @ Encoding { encEncode = encodefunc,
                              encDecode = decodefunc,
                              encDepth = depthfunc } =
  enc { encEncode = encodefunc . fwd,
        encDecode = rev . decodefunc,
        encDepth = (\dim -> depthfunc dim . fwd) }

-- | Generate an encoding for @Maybe ty@ from an inner encoding for
-- @ty@.  This adds one level of depth: @Nothing@ has depth @0@, and
-- the rest of the depths are determined by adding one to the depths
-- from the inner encoding.
optional :: Encoding dim ty -> Encoding dim (Maybe ty)
optional Encoding { encEncode = encodefunc, encDecode = decodefunc,
                    encSize = sizeval, encMaxDepth = maxdepthfunc,
                    encDepth = depthfunc, encHighestIndex = highestindexfunc } =
  let
    newsize = sizeval >>= return . (+ 1)
    newmaxdepth dim = maxdepthfunc dim >>= return . (+ 1)

    newencode Nothing = 0
    newencode (Just val) = 1 + encodefunc val

    newdecode 0 = Nothing
    newdecode num = Just (decodefunc (num - 1))

    newdepth _ Nothing = 0
    newdepth dim (Just val) = (depthfunc dim val) + 1

    newhighestindex _ 0 = Just 0
    newhighestindex dim val = highestindexfunc dim (val - 1)
  in
    Encoding { encEncode = newencode, encDecode = newdecode,
               encSize = newsize, encMaxDepth = newmaxdepth,
               encDepth = newdepth, encHighestIndex = newhighestindex }

-- | The dual of @optional@.  This construction assumes that @Nothing@
-- maps to @0@, and removes it from the input domain.  It also assumes
-- that @Nothing@ has depth @0@, and everything else has a higher
-- depth.
--
-- Using this construction on encodings for @Maybe ty@ which are not
-- produced by @optional@ may have unexpected results.
mandatory :: Encoding dim (Maybe ty) -> Encoding dim ty
mandatory Encoding { encEncode = encodefunc, encDecode = decodefunc,
                    encSize = sizeval, encMaxDepth = maxdepthfunc,
                    encDepth = depthfunc, encHighestIndex = highestindexfunc } =
  let
    dec n = n - 1
    newencode = dec . encodefunc . Just
    newdecode = fromJust . decodefunc . (+ 1)
    newsize = sizeval >>= return . dec
    newmaxdepth dim = maxdepthfunc dim >>= return . dec
    newdepth dim = dec . depthfunc dim . Just
    newhighestindex dim = highestindexfunc dim . dec
  in
    Encoding { encEncode = newencode, encDecode = newdecode,
               encSize = newsize, encMaxDepth = newmaxdepth,
               encDepth = newdepth, encHighestIndex = newhighestindex }

-- | Removes the mapping to @0@ (ie. the first mapping).  This has the
-- same effect as @exclude [x]@, where @x@ is the value that maps to
-- @0@.  It is also similar to @mandatory@, except that it does not
-- change the base type.
nonzero :: Encoding dim ty -> Encoding dim ty
nonzero enc @ Encoding { encEncode = encodefunc, encDecode = decodefunc,
                         encSize = sizeval, encHighestIndex = highindexfunc } =
  let
    dec n = n - 1
    newencode = dec . encodefunc
    newdecode = decodefunc . (+ 1)
    newsize = sizeval >>= return . dec
    newhighestindex dim num = highindexfunc dim num >>= return . dec
  in
    enc { encEncode = newencode, encDecode = newdecode,
          encSize = newsize, encHighestIndex = newhighestindex }

-- | A simple binary tree structure, for use with exclude.
data BinTree key val =
    Branch key val (BinTree key val) (BinTree key val)
  | Nil

-- | Simple binary tree lookup, for use with exclude.
closestBelow :: Ord key => key -> BinTree key val -> Maybe val
closestBelow target =
  let
    closestBelow' out Nil = out
    closestBelow' out (Branch k v left right) =
      case compare k target of
        LT -> closestBelow' (Just v) right
        _ -> closestBelow' out left
  in
    closestBelow' Nothing

-- | Simple binary tree lookup, for use with exclude.
closestWithin :: Ord key => key -> BinTree key val -> Maybe val
closestWithin target =
  let
    closestWithin' out Nil = out
    closestWithin' out (Branch k v left right) =
      case compare k target of
        GT -> closestWithin' out left
        _ -> closestWithin' (Just v) right
  in
    closestWithin' Nothing

-- | Convert a list to a binary tree, for use with excludes.
toBinTree :: [(key, val)] -> BinTree key val
toBinTree vals =
  let
    toBinTree' 0 [] = Nil
    toBinTree' 0 _ = error "Zero size with non-empty list"
    toBinTree' _ [] = error "Empty list with non-zero size"
    toBinTree' len vals' =
      let
        halflo = len `shiftR` 1
        halfhi = len - halflo
        (lows, (k, v) : highs) = splitAt halflo vals'
        left = toBinTree' halflo lows
        right = toBinTree' (halfhi - 1) highs
      in
        Branch k v left right
  in
    toBinTree' (length vals) vals

-- | Removes the mapping to the items in the list.  The resulting
-- @encode@, @decode@, and @highestIndex@ are O(@length excludes@), so
-- this should only be used with a very short excludes list.
exclude :: [ty] -> Encoding dim ty -> Encoding dim ty
exclude [] enc = enc
exclude excludes enc @ Encoding { encEncode = encodefunc,
                                  encDecode = decodefunc,
                                  encHighestIndex = highindexfunc,
                                  encSize = sizeval } =
  let
    sortedlist = sort (map encodefunc excludes)

    fwdoffsets :: [(Integer, Integer)]
    (_, fwdoffsets) = mapAccumL (\offset v -> (offset + 1, (v, offset)))
                                1 sortedlist
    fwdtree = toBinTree fwdoffsets

    revoffsets :: [(Integer, Integer)]
    revoffsets =
      let
        foldfun :: [(Integer, Integer)] -> (Integer, Integer) ->
                   [(Integer, Integer)]
        foldfun accum @ ((v', _) : rest) elem @ (v, _)
          | v == v' = elem : rest
          | otherwise = elem : accum
        foldfun _ _ = error "Should not fold over an empty list"

        (first : adjusted) =
          map (\(v, offset) -> (v - (offset - 1), offset)) fwdoffsets
      in
        reverse (foldl foldfun [first] adjusted)

    revtree = toBinTree revoffsets

    toExcluded n =
      case closestBelow n fwdtree of
        Just offset -> n - offset
        Nothing -> n

    fromExcluded n =
      case closestWithin n revtree of
        Just offset -> n + offset
        Nothing -> n

    newEncode = toExcluded . encodefunc
    newDecode = decodefunc . fromExcluded

    newHighestIndex dim depthval =
      do
        maxdepth <- highindexfunc dim depthval
        case closestWithin maxdepth fwdtree of
          Just offset
            | offset <= maxdepth -> return (maxdepth - offset)
            | otherwise -> return 0
          Nothing -> return maxdepth

    newSize =
      do
        n <- sizeval
        return $! (n - (toInteger (length excludes)))
  in
    enc { encEncode = newEncode, encDecode = newDecode,
          encSize = newSize, encHighestIndex = newHighestIndex }

-- | Combine two encodings into a single encoding that returns an
-- @Either@ of the two types.
either :: Encoding dim1 ty1
       -- ^ The @Encoding@ that will be represented by @Left@.
       -> Encoding dim2 ty2
       -- ^ The @Encoding@ that will be represented by @Right@.
       -> Encoding (Either dim1 dim2) (Either ty1 ty2)
either Encoding { encEncode = encode1, encDecode = decode1,
                  encMaxDepth = maxDepth1, encSize = sizeval1,
                  encDepth = depth1, encHighestIndex = highindex1 }
       Encoding { encEncode = encode2, encDecode = decode2,
                  encMaxDepth = maxDepth2, encSize = sizeval2,
                  encDepth = depth2, encHighestIndex = highindex2 } =
  let
    -- There are three cases here, depending on the size of the two
    -- mappings.  This does replicate code, but it also does a lot of
    -- figuring things when the encoding is created as opposed to
    -- later.
    (isLeft, leftIdxFwd, rightIdxFwd, leftIdxRev, rightIdxRev) =
      case (sizeval1, sizeval2) of
        -- Simplest case: both mappings are infinite.  Map all the
        -- evens to the left, and all the odds to the right.
        (Nothing, Nothing) ->
          (\num -> not (testBit num 0),
           \idx -> idx `shiftL` 1,
           \idx -> setBit (idx `shiftL` 1) 0,
           \idx -> idx `shiftR` 1,
           \idx -> idx `shiftR` 1)
        -- Left is smaller: do the even/odd mapping until we exhaust
        -- the left, then just map directly to the right.
        (Just size1, _) | maybe True (size1 <) sizeval2 ->
          let
            size1shifted = (size1 `shiftL` 1)
            isLeft' num = num < size1shifted && not (testBit num 0)
            leftIdxFwd' idx = idx `shiftL` 1

            rightIdxFwd' idx
              | size1 <= idx = size1shifted + (idx - size1)
              | otherwise = setBit (idx `shiftL` 1) 0

            leftIdxRev' idx = idx `shiftR` 1

            rightIdxRev' idx
              | size1shifted <= idx = size1 + (idx - size1shifted)
              | otherwise = idx `shiftR` 1
          in
            (isLeft', leftIdxFwd', rightIdxFwd', leftIdxRev', rightIdxRev')
        -- Right is smaller: do the even/odd mapping until we exhaust
        -- the right, then just map directly to the left.
        (_, Just size2) ->
          let
            size2shifted = (size2 `shiftL` 1)
            isLeft' num = num > size2shifted || not (testBit num 0)

            leftIdxFwd' idx
              | size2 <= idx = size2shifted + (idx - size2)
              | otherwise = idx `shiftL` 1

            rightIdxFwd' idx = setBit (idx `shiftL` 1) 0

            leftIdxRev' idx
              | size2shifted <= idx = size2 + (idx - size2shifted)
              | otherwise = idx `shiftR` 1

            rightIdxRev' idx = idx `shiftR` 1
          in
            (isLeft', leftIdxFwd', rightIdxFwd', leftIdxRev', rightIdxRev')
        _ -> error "This case should never happen"

    newSize =
      do
        size1 <- sizeval1
        size2 <- sizeval2
        return (size1 + size2)

    eitherIndex lfunc rfunc idx
      | isLeft idx = lfunc (leftIdxRev idx)
      | otherwise = rfunc (rightIdxRev idx)

    newEncode = Either.either (leftIdxFwd . encode1) (rightIdxFwd . encode2)
    newDecode = eitherIndex (Left . decode1) (Right . decode2)
    newMaxDepth = Either.either maxDepth1 maxDepth2

    newHighestIndex (Left dim) =
      maybe Nothing (Just . leftIdxFwd . (\n -> n - 1)) . highindex1 dim
    newHighestIndex (Right dim) =
      maybe Nothing (Just . rightIdxFwd . (\n -> n - 1)) . highindex2 dim

    newDepth (Left dim) (Left val) = depth1 dim val
    newDepth (Right dim) (Right val) = depth2 dim val
    newDepth _ _ = 0
  in
    Encoding { encEncode = newEncode, encDecode = newDecode,
               encSize = newSize, encMaxDepth = newMaxDepth,
               encDepth = newDepth, encHighestIndex = newHighestIndex }
{-
-- | An alias for @product2@.
pair = product2

-- | An alias for @product3@.
triple = product3

-- | An alias for @product4@.
quad = product4

-- | An alias for @product5@
quint = product5

-- | A datatype representing the dimensions of a set.
data SetDim dim =
    -- | A dimension representing the size of the set.
    SetSize
    -- | A dimension representing the dimensions of the elements.  The
    -- depth of a set in a given element dimension is the maximum of
    -- the depths of all its elements in that dimension.
  | SetElem dim

-- | Build an encoding for /finite/ sets of values of a given datatype
-- from an encoding for that datatype.
set :: Ord ty => Encoding dim ty -> Encoding (SetDim dim) (Set ty)
set Encoding { encEncode = encodefunc,
               encDepth = depthfunc, encMaxDepth = maxdepthfunc,
               encHighestIndex = highindexfunc, encSize = sizeval } =
  let
    newEncode = Set.foldl (\n -> setBit n . fromInteger . encodefunc) 0

    newsize =
      do
        elems <- sizeval
        return (2 ^ elems)

    newDepth SetSize s = Set.size s
    newDepth (SetElem dim) s = maximum (map (maxdepthfunc dim) (Set.elems s))

    newMaxDepth SetSize = sizeval
    newMaxDepth (SetElem dim) = maxdepthfunc dim

    newHighestIndex SetSize n =
      let
        highidx end out bitidx
          | bitidx == end = out
          | otherwise = highidx end (setBit out bitidx) (bitidx - 1)
    newHighestIndex (SetElem dim) n =
      do
        idx <- highindexfunc dim n
        return (2 ^ n)
  in
    Encoding { encEncode = newencode,
               encDepth = newDepth, encMaxDepth = newMaxDepth,
               encHighestIndex = newHighestIndex, encSize = newSize }
-}
