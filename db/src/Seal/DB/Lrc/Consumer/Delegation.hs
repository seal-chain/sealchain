{-# LANGUAGE TypeFamilies #-}

-- | Richmen computation for delegation.

module Seal.DB.Lrc.Consumer.Delegation
       (
       -- * The 'RichmenComponent'
         dlgRichmenComponent

       -- * The consumer
       , dlgLrcConsumer

       -- * Functions for getting richmen
       , getDlgRichmen
       , tryGetDlgRichmen
       ) where

import           Universum

import           Seal.Chain.Lrc (RichmenComponent (..), RichmenSet)
import           Seal.Chain.Update (BlockVersionData (..))
import           Seal.Core (EpochIndex)
import           Seal.DB (MonadDB, MonadDBRead, MonadGState)
import           Seal.DB.Lrc.Consumer (LrcConsumer,
                     lrcConsumerFromComponentSimple)
import           Seal.DB.Lrc.Context (HasLrcContext, lrcActionOnEpochReason)
import           Seal.DB.Lrc.RichmenBase
import           Seal.Util.Util (getKeys)

----------------------------------------------------------------------------
-- RichmenComponent
----------------------------------------------------------------------------

dlgRichmenComponent :: BlockVersionData -> RichmenComponent RichmenSet
dlgRichmenComponent genesisBvd = RichmenComponent
    { rcToData            = getKeys . snd
    , rcTag               = "dlg"
    , rcInitialThreshold  = bvdHeavyDelThd genesisBvd
    , rcConsiderDelegated = False
    }

----------------------------------------------------------------------------
-- The consumer
----------------------------------------------------------------------------

-- | Consumer will be called on every Richmen computation.
dlgLrcConsumer :: (MonadGState m, MonadDB m) => BlockVersionData -> LrcConsumer m
dlgLrcConsumer genesisBvd = lrcConsumerFromComponentSimple
    (dlgRichmenComponent genesisBvd)
    bvdHeavyDelThd

----------------------------------------------------------------------------
-- Getting richmen
----------------------------------------------------------------------------

-- | Wait for LRC results to become available and then get delegation ricmen
-- data for the given epoch.
getDlgRichmen
    :: (MonadIO m, MonadDBRead m, MonadReader ctx m, HasLrcContext ctx)
    => BlockVersionData
    -> Text               -- ^ Function name (to include into error message)
    -> EpochIndex         -- ^ Epoch for which you want to know the richmen
    -> m RichmenSet
getDlgRichmen genesisBvd fname epoch = lrcActionOnEpochReason
    epoch
    (fname <> ": couldn't get delegation richmen")
    (tryGetDlgRichmen genesisBvd)

-- | Like 'getDlgRichmen', but doesn't wait and doesn't fail.
tryGetDlgRichmen
    :: MonadDBRead m => BlockVersionData -> EpochIndex -> m (Maybe RichmenSet)
tryGetDlgRichmen = getRichmen . dlgRichmenComponent
