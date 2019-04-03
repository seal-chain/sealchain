{-# LANGUAGE DeriveAnyClass  #-}
{-# LANGUAGE TemplateHaskell #-}
module Test.Seal.Binary.BiSerialize
    ( tests
    ) where

import           Universum

import           Hedgehog (Property)
import qualified Hedgehog as H

import           Seal.Binary.Class (Cons (..), Field (..), cborError,
                     deriveIndexedBi)
import           Test.Seal.Binary.Helpers.GoldenRoundTrip (goldenTestBi)
import           Test.Seal.Util.Golden (discoverGolden)

--------------------------------------------------------------------------------
-- Since `deriveSimpleBi` no longer works on sum types, we cannot do a simple
-- comparison property between `deriveSimpleBi` and `deriveIndexedBi`. Instead,
-- this module contains golden tests. The tests were generated by the following
-- process (done before sumtypes were disallowed from `deriveSimpleBi`):
--
-- 1. Generate values of type TestSimple (either by hand or via `genTestSimple`)
-- 2. Use `deriveSimpleBi` Bi instance to serialize the value to a file
-- 3. Translate the value to type TestIndexed via `simpleToIndexed`
-- 4. Hardcode the result of (3.) into a golden test, which checks equivalence
--    with the output of (2.)
--
-- This ensures that our encoding scheme was preserved, at least on a set of
-- points which exercise all the constructors of `TestIndexed`.
--------------------------------------------------------------------------------

data TestIndexed
    = TiInt Int
    | TiIntList [Int]
    | TiChar2 Char Char
    | TiInteger Integer
    | TiMaybeInt (Maybe Int)
    | TiChar2Permuted Char Char
    | TiPair TestIndexed TestIndexed
    deriving (Eq, Show, Typeable)

deriveIndexedBi ''TestIndexed [
    Cons 'TiInt [
        Field [| 0 :: Int         |]
        ],
    Cons 'TiIntList [
        Field [| 0 :: [Int]       |]
        ],
    Cons 'TiChar2 [
        Field [| 0 :: Char        |],
        Field [| 1 :: Char        |]
        ],
    Cons 'TiInteger [
        Field [| 0 :: Integer     |]
        ],
    Cons 'TiMaybeInt [
        Field [| 0 :: Maybe Int   |]
        ],
    Cons 'TiChar2Permuted [
        Field [| 1 :: Char        |],
        Field [| 0 :: Char        |]
        ],
    Cons 'TiPair [
        Field [| 0 :: TestIndexed |],
        Field [| 1 :: TestIndexed |]
        ]
    ]

--------------------------------------------------------------------------------
-- Golden tests
--------------------------------------------------------------------------------

golden_TestSimpleIndexed1 :: Property
golden_TestSimpleIndexed1 = goldenTestBi ti "test/golden/TestSimpleIndexed1"
  where
      ti = TiPair
         (TiPair
             (TiChar2 '\154802' '\268555')
             (TiMaybeInt (Just 3110389958050278305)))
         (TiChar2 '\622348' '\696570')

golden_TestSimpleIndexed2 :: Property
golden_TestSimpleIndexed2 = goldenTestBi ti "test/golden/TestSimpleIndexed2"
  where
    ti = TiPair
       (TiPair
           (TiChar2 '\817168' '\1089248')
           (TiPair
               (TiChar2 '\230385' '\1065928')
               (TiIntList [518227513268840239,3102008451401682492
                          ,3028399834958998823,-1792258639827871709
                          ,-4045193945739409444])))
       (TiChar2Permuted '\427120' '\104794')

golden_TestSimpleIndexed3 :: Property
golden_TestSimpleIndexed3 = goldenTestBi ti "test/golden/TestSimpleIndexed3"
  where
    ti = TiPair (TiInteger (-515200628427138351744076))
                (TiInt 4238472394723423)

golden_TestSimpleIndexed4 :: Property
golden_TestSimpleIndexed4 = goldenTestBi ti "test/golden/TestSimpleIndexed4"
  where
    ti = TiPair
        (TiChar2 '\118580' '\1076905')
        (TiPair
            (TiMaybeInt (Just 2108646761465188277))
            (TiPair
                (TiInteger (-736109340637048771303587))
                (TiPair
                    (TiInt 5991005317022714617)
                    (TiInt (-7567206666529693526)))))

golden_TestSimpleIndexed5 :: Property
golden_TestSimpleIndexed5 = goldenTestBi ti "test/golden/TestSimpleIndexed5"
  where
    ti = TiPair
        (TiPair
            (TiMaybeInt (Just 2108646761465188277))
            (TiPair
                (TiInteger (-736109340637048771303587))
                (TiPair
                    (TiInt 5991005317022714617)
                    (TiInt (-7567206666529693526)))))
        (TiPair
            (TiChar2Permuted 'a' 'q')
            (TiPair
                (TiIntList [1..100])
                (TiChar2 'f' 'z')))

--------------------------------------------------------------------------------
-- Main test export
--------------------------------------------------------------------------------

tests :: IO Bool
tests =
  H.checkParallel $$discoverGolden


--------------------------------------------------------------------------------
-- Old code for TestSimple
--------------------------------------------------------------------------------

{-
data TestSimple
    = TsInt
        { unTsInt :: Int }
    | TsIntList
        { unTsIntList :: [Int] }
    | TsChar2
        { unTsChar2L :: Char
        , unTsChar2R :: Char }
    | TsInteger
        { unTsInteger :: Integer }
    | TsMaybeInt
        { unTsMaybeInt :: Maybe Int }
    | TsChar2Permuted
        { unTsChar2PermutedL :: Char
        , unTsChar2PermutedR :: Char }
    | TsPair
        { unTsPairL :: TestSimple
        , unTsPairR :: TestSimple }
    deriving (Eq, Show, Typeable)

deriveSimpleBi ''TestSimple [
    Cons 'TsInt [
        Field [| unTsInt            :: Int        |]
        ],
    Cons 'TsIntList [
        Field [| unTsIntList        :: [Int]      |]
        ],
    Cons 'TsChar2 [
        Field [| unTsChar2L         :: Char       |],
        Field [| unTsChar2R         :: Char       |]
        ],
    Cons 'TsInteger [
        Field [| unTsInteger        :: Integer    |]
        ],
    Cons 'TsMaybeInt [
        Field [| unTsMaybeInt       :: Maybe Int  |]
        ],
    Cons 'TsChar2Permuted [
        Field [| unTsChar2PermutedR :: Char       |],
        Field [| unTsChar2PermutedL :: Char       |]
        ],
    Cons 'TsPair [
        Field [| unTsPairL          :: TestSimple |],
        Field [| unTsPairR          :: TestSimple |]
        ]
    ]

-- The validity of our comparison tests relies on this function. Fortunately,
-- it's a pretty straightforward translation.
simpleToIndexed :: TestSimple -> TestIndexed
simpleToIndexed (TsInt i)             = TiInt i
simpleToIndexed (TsIntList is)        = TiIntList is
simpleToIndexed (TsChar2 l r)         = TiChar2 l r
simpleToIndexed (TsInteger i)         = TiInteger i
simpleToIndexed (TsMaybeInt mi)       = TiMaybeInt mi
simpleToIndexed (TsChar2Permuted l r) = TiChar2Permuted l r
simpleToIndexed (TsPair l r)          = TiPair (simpleToIndexed l)
                                               (simpleToIndexed r)

--------------------------------------------------------------------------------

genTestSimple :: Range.Size -> Gen TestSimple
genTestSimple sz
  | sz > 0    = Gen.choice (pairType : flatTypes)
  | otherwise = Gen.choice flatTypes
  where
    pairType  = TsPair <$> genTestSimple (sz `div` 2)
                       <*> genTestSimple (sz `div` 2)
    flatTypes =
        [ TsInt <$> Gen.int Range.constantBounded
        , TsIntList <$> Gen.list (Range.linear 0 20) (Gen.int Range.constantBounded)
        , TsChar2 <$> Gen.unicode <*> Gen.unicode
        , TsInteger <$> Gen.integral (Range.linear (- bignum) bignum)
        , TsMaybeInt <$> Gen.maybe (Gen.int Range.constantBounded)
        , TsChar2Permuted <$> Gen.unicode <*> Gen.unicode
        ]
    bignum = 2 ^ (80 :: Integer)
-}
