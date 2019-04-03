{-# LANGUAGE TypeFamilies #-}

-- | Richmen computation for the update system.

module Seal.DB.Lrc.Consumer.Update
       (
       -- * The 'RichmenComponent' instance
         updateRichmenComponent

       -- * The consumer
       , usLrcConsumer

       -- * Functions for getting richmen
       , getUSRichmen
       , tryGetUSRichmen
       ) where

import           Universum

import           Seal.Chain.Lrc (FullRichmenData, RichmenComponent (..))
import           Seal.Chain.Update (BlockVersionData (..))
import           Seal.Core (EpochIndex)
import           Seal.DB (MonadDB, MonadDBRead, MonadGState)
import           Seal.DB.Lrc.Consumer (LrcConsumer,
                     lrcConsumerFromComponentSimple)
import           Seal.DB.Lrc.Context (HasLrcContext, lrcActionOnEpochReason)
import           Seal.DB.Lrc.RichmenBase

----------------------------------------------------------------------------
-- RichmenComponent
----------------------------------------------------------------------------

updateRichmenComponent :: BlockVersionData -> RichmenComponent FullRichmenData
updateRichmenComponent genesisBvd = RichmenComponent
    { rcToData            = identity
    , rcTag               = "us"
    , rcInitialThreshold  = bvdUpdateVoteThd genesisBvd
    , rcConsiderDelegated = True
    }

----------------------------------------------------------------------------
-- The consumer
----------------------------------------------------------------------------

-- | Consumer will be called on every Richmen computation.
usLrcConsumer :: (MonadGState m, MonadDB m) => BlockVersionData -> LrcConsumer m
usLrcConsumer genesisBvd = lrcConsumerFromComponentSimple
    (updateRichmenComponent genesisBvd)
    bvdUpdateVoteThd

----------------------------------------------------------------------------
-- Getting richmen
----------------------------------------------------------------------------

-- | Wait for LRC results to become available and then get update system
-- ricmen data for the given epoch.
getUSRichmen
    :: (MonadIO m, MonadDBRead m, MonadReader ctx m, HasLrcContext ctx)
    => BlockVersionData
    -> Text               -- ^ Function name (to include into error message)
    -> EpochIndex         -- ^ Epoch for which you want to know the richmen
    -> m FullRichmenData
getUSRichmen genesisBvd fname epoch = lrcActionOnEpochReason
    epoch
    (fname <> ": couldn't get US richmen")
    (tryGetUSRichmen genesisBvd)

-- | Like 'getUSRichmen', but doesn't wait and doesn't fail.
--
-- Returns a 'Maybe'.
tryGetUSRichmen
    :: MonadDBRead m
    => BlockVersionData
    -> EpochIndex
    -> m (Maybe FullRichmenData)
tryGetUSRichmen = getRichmen . updateRichmenComponent
