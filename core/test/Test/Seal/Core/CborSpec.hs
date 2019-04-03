{-# LANGUAGE AllowAmbiguousTypes       #-}
{-# LANGUAGE DeriveGeneric             #-}
{-# LANGUAGE ExistentialQuantification #-}
{-# LANGUAGE GADTs                     #-}
{-# LANGUAGE TemplateHaskell           #-}

{-# OPTIONS_GHC -fno-warn-orphans #-}

module Test.Seal.Core.CborSpec
       ( spec
       ) where

import           Universum

import           Test.Hspec (Spec, describe)
import           Test.QuickCheck (Arbitrary (..))
import           Test.QuickCheck.Arbitrary.Generic (genericArbitrary,
                     genericShrink)

import           Seal.Binary.Class (Bi (..), serialize, unsafeDeserialize)
import           Seal.Core

import           Seal.Core.Attributes (Attributes (..), decodeAttributes,
                     encodeAttributes)
import           Seal.Core.Merkle (MerkleTree)

import           Test.Seal.Binary.Helpers (binaryTest)
import           Test.Seal.Core.Arbitrary ()
import           Test.Seal.Core.Chrono ()
import           Test.Seal.Crypto.Arbitrary ()

----------------------------------------

data X1 = X1 { x1A :: Int }
    deriving (Eq, Ord, Show, Generic)

data X2 = X2 { x2A :: Int, x2B :: String }
    deriving (Eq, Ord, Show, Generic)

instance Arbitrary X1 where
    arbitrary = genericArbitrary
    shrink = genericShrink

instance Arbitrary X2 where
    arbitrary = genericArbitrary
    shrink = genericShrink

instance Bi (Attributes X1) where
    encode = encodeAttributes [(0, serialize . x1A)]
    decode = decodeAttributes (X1 0) $ \n v acc -> case n of
        0 -> pure $ Just $ acc { x1A = unsafeDeserialize v }
        _ -> pure $ Nothing

instance Bi (Attributes X2) where
    encode = encodeAttributes [(0, serialize . x2A), (1, serialize . x2B)]
    decode = decodeAttributes (X2 0 []) $ \n v acc -> case n of
        0 -> return $ Just $ acc { x2A = unsafeDeserialize v }
        1 -> return $ Just $ acc { x2B = unsafeDeserialize v }
        _ -> return $ Nothing

----------------------------------------


spec :: Spec
spec = describe "Cbor Bi instances" $ do
        describe "Core.Address" $ do
            binaryTest @Address
            binaryTest @Address'
            binaryTest @AddrType
            binaryTest @AddrStakeDistribution
            binaryTest @AddrSpendingData
        describe "Core.Types" $ do
            binaryTest @Timestamp
            binaryTest @TimeDiff
            binaryTest @EpochIndex
            binaryTest @Coin
            binaryTest @CoinPortion
            binaryTest @LocalSlotIndex
            binaryTest @SlotId
            binaryTest @EpochOrSlot
            binaryTest @SharedSeed
            binaryTest @ChainDifficulty
            binaryTest @(Attributes ())
            binaryTest @(Attributes AddrAttributes)
        describe "Core.Fee" $ do
            binaryTest @Coeff
            binaryTest @TxSizeLinear
            binaryTest @TxFeePolicy
        describe "Merkle" $ do
            binaryTest @(MerkleTree Int32)
