{-# LANGUAGE GeneralizedNewtypeDeriving #-}

{-# OPTIONS_GHC -fno-warn-orphans #-}

module Test.Seal.Util.Modifier where

import           Seal.Util.Modifier

import           Test.QuickCheck (Arbitrary)
import           Test.QuickCheck.Instances ()

import           Universum

deriving instance (Eq k, Hashable k, Arbitrary k, Arbitrary v) =>
    Arbitrary (MapModifier k v)
