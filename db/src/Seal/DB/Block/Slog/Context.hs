{-# LANGUAGE RecordWildCards #-}

-- | Functions operation on 'SlogContext' and its subtypes.

module Seal.DB.Block.Slog.Context
       ( mkSlogGState
       , mkSlogContext
       , cloneSlogGState
       , slogGetLastSlots
       , slogPutLastSlots
       ) where

import           Universum

import           Formatting (int, sformat, (%))
import qualified System.Metrics as Ekg

import           Seal.Chain.Block (HasBlockConfiguration, HasSlogGState (..),
                     LastBlkSlots, SlogContext (..), SlogGState (..),
                     fixedTimeCQSec, sgsLastBlkSlots)
import           Seal.Core (BlockCount)
import           Seal.Core.Metrics.Constants (withSealNamespace)
import           Seal.Core.Reporting (MetricMonitorState, mkMetricMonitorState)
import           Seal.DB.Block.GState.BlockExtra (getLastSlots)
import           Seal.DB.Class (MonadDBRead)

-- | Make new 'SlogGState' using data from DB.
mkSlogGState :: (MonadIO m, MonadDBRead m) => m SlogGState
mkSlogGState = do
    _sgsLastBlkSlots <- getLastSlots >>= newIORef
    return SlogGState {..}

-- | Make new 'SlogContext' using data from DB.
mkSlogContext
    :: forall m
     . (MonadIO m, MonadDBRead m, HasBlockConfiguration)
    => BlockCount
    -> Ekg.Store
    -> m SlogContext
mkSlogContext k store = do
    _scGState <- mkSlogGState

    let mkMMonitorState :: Text -> m (MetricMonitorState a)
        mkMMonitorState = flip mkMetricMonitorState store
    -- Chain quality metrics stuff.
    let metricNameK = sformat ("chain_quality_last_k_("%int%")_blocks_%") k
    let metricNameOverall = "chain_quality_overall_%"
    let metricNameFixed =
            sformat ("chain_quality_last_"%int%"_sec_%")
                fixedTimeCQSec
    _scCQkMonitorState <- mkMMonitorState metricNameK
    _scCQOverallMonitorState <- mkMMonitorState metricNameOverall
    _scCQFixedMonitorState <- mkMMonitorState metricNameFixed

    -- Other metrics stuff.
    _scDifficultyMonitorState <- mkMMonitorState "total_main_blocks"
    _scEpochMonitorState <- mkMMonitorState "current_epoch"
    _scLocalSlotMonitorState <- mkMMonitorState "current_local_slot"
    _scGlobalSlotMonitorState <- mkMMonitorState "current_global_slot"
    let crucialValuesName = withSealNamespace "crucial_values"
    _scCrucialValuesLabel <-
        liftIO $ Ekg.createLabel crucialValuesName store
    return SlogContext {..}

-- | Make a copy of existing 'SlogGState'.
cloneSlogGState :: (MonadIO m) => SlogGState -> m SlogGState
cloneSlogGState SlogGState {..} =
    SlogGState <$> (readIORef _sgsLastBlkSlots >>= newIORef)

-- | Read 'LastBlkSlots' from in-memory state.
slogGetLastSlots ::
       (MonadReader ctx m, HasSlogGState ctx, MonadIO m) => m LastBlkSlots
slogGetLastSlots = view (slogGState . sgsLastBlkSlots) >>= readIORef

-- | Update 'LastBlkSlots' in 'SlogContext'.
slogPutLastSlots ::
       (MonadReader ctx m, HasSlogGState ctx, MonadIO m)
    => LastBlkSlots
    -> m ()
slogPutLastSlots slots =
    view (slogGState . sgsLastBlkSlots) >>= flip writeIORef slots