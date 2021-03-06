-- | We want to store each epoch's seed in the database. This module does
-- that. It's done so that we'd be able to reuse previous epoch's seed in
-- case we can't generate a seed for current epoch (see [CSL-50]).
module Seal.DB.Lrc.Seed
       ( -- * Operations
         getSeed
       , putSeed

         -- * Initialization
       , prepareLrcSeed
       ) where

import           Universum

import           Seal.Binary.Class (serialize')
import           Seal.Core (EpochIndex (..), SharedSeed)
import           Seal.DB.Class (MonadDB, MonadDBRead)
import           Seal.DB.Lrc.Common (getBi, putBi)

getSeed :: MonadDBRead m => EpochIndex -> m (Maybe SharedSeed)
getSeed epoch = getBi (seedKey epoch)

putSeed :: MonadDB m => EpochIndex -> SharedSeed -> m ()
putSeed epoch = putBi (seedKey epoch)

prepareLrcSeed :: MonadDB m => SharedSeed -> m ()
prepareLrcSeed = unlessM isInitialized . putSeed (EpochIndex 0)

isInitialized :: MonadDBRead m => m Bool
isInitialized = isJust <$> getSeed (EpochIndex 0)

----------------------------------------------------------------------------
-- Keys
----------------------------------------------------------------------------

seedKey :: EpochIndex -> ByteString
seedKey = mappend "s/" . serialize'
