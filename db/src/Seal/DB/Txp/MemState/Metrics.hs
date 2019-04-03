-- | 'StateLockMetrics' for txp.

module Seal.DB.Txp.MemState.Metrics
    ( recordTxpMetrics
    ) where

import           Universum

import           Data.Aeson.Types (ToJSON (..))
import           Formatting (sformat, shown, (%))
import qualified System.Metrics as Metrics
import qualified System.Metrics.Gauge as Metrics.Gauge

import           Seal.Chain.Txp (MemPool (_mpSize))
import           Seal.Core.JsonLog.LogEvents (JLEvent (..), JLMemPool (..),
                     MemPoolModifyReason (..))
import           Seal.Core.Metrics.Constants (withSealNamespace)
import           Seal.DB.GState.Lock (StateLockMetrics (..))
import           Seal.Util.Wlog (logDebug)

-- | 'StateLockMetrics' to record txp MemPool metrics.
recordTxpMetrics :: Metrics.Store -> TVar MemPool -> IO (StateLockMetrics MemPoolModifyReason)
recordTxpMetrics ekgStore memPoolVar = do
    ekgMemPoolSize <-
        Metrics.createGauge (withSealNamespace "MemPoolSize") ekgStore
    ekgMemPoolWaitTimeApplyBlock <-
        Metrics.createGauge (withSealNamespace "MemPoolWaitTimeApplyBlock_microseconds") ekgStore
    ekgMemPoolModifyTimeApplyBlock <-
        Metrics.createGauge (withSealNamespace "MemPoolModifyTimeApplyBlock_microseconds") ekgStore
    ekgMemPoolWaitTimeApplyBlockWithRollback <-
        Metrics.createGauge (withSealNamespace "MemPoolWaitTimeApplyBlockWithRollback_microseconds") ekgStore
    ekgMemPoolModifyTimeApplyBlockWithRollback <-
        Metrics.createGauge (withSealNamespace "MemPoolModifyTimeApplyBlockWithRollback_microseconds") ekgStore
    ekgMemPoolWaitTimeProcessTx <-
        Metrics.createGauge (withSealNamespace "MemPoolWaitTimeProcessTx_microseconds") ekgStore
    ekgMemPoolModifyTimeProcessTx <-
        Metrics.createGauge (withSealNamespace "MemPoolModifyTimeProcessTx_microseconds") ekgStore
    ekgMemPoolQueueLength <-
        Metrics.createGauge (withSealNamespace "MemPoolQueueLength") ekgStore

    -- An exponential moving average is used for the time gauges (wait
    -- and modify durations). The parameter alpha is chosen somewhat
    -- arbitrarily.
    -- FIXME take alpha from configuration/CLI, or use a better
    -- estimator.
    let alpha :: Double
        alpha = 0.75

    -- This TxpMetrics specifies what to do when waiting on the
    -- mempool lock, when the mempool lock has been granted, and
    -- when that lock has been released. It updates EKG metrics
    -- and also logs each data point at debug level.
    pure StateLockMetrics
        { slmWait = \reason -> do
              liftIO $ Metrics.Gauge.inc ekgMemPoolQueueLength
              qlen <- liftIO $ Metrics.Gauge.read ekgMemPoolQueueLength
              logDebug $ sformat ("MemPool metrics wait: "%shown%" queue length is "%shown) reason qlen

        , slmAcquire = \reason timeWaited -> do
              liftIO $ Metrics.Gauge.dec ekgMemPoolQueueLength
              let ekgMemPoolWaitTime = case reason of
                      ApplyBlock             -> ekgMemPoolWaitTimeApplyBlock
                      ApplyBlockWithRollback -> ekgMemPoolWaitTimeApplyBlockWithRollback
                      ProcessTransaction     -> ekgMemPoolWaitTimeProcessTx
              timeWaited' <- liftIO $ Metrics.Gauge.read ekgMemPoolWaitTime
              -- Assume a 0-value estimate means we haven't taken
              -- any samples yet.
              let new_ = if timeWaited' == 0
                        then fromIntegral timeWaited
                        else round $ alpha * fromIntegral timeWaited + (1 - alpha) * fromIntegral timeWaited'
              liftIO $ Metrics.Gauge.set ekgMemPoolWaitTime new_
              logDebug $ sformat ("MemPool metrics acquire: "%shown
                                  %" wait time was "%shown) reason timeWaited

        , slmRelease = \reason timeWaited timeElapsed memAllocated -> do
              qlen <- liftIO $ Metrics.Gauge.read ekgMemPoolQueueLength
              oldMemPoolSize <- liftIO $ Metrics.Gauge.read ekgMemPoolSize
              newMemPoolSize <- _mpSize <$> readTVarIO memPoolVar
              liftIO $ Metrics.Gauge.set ekgMemPoolSize (fromIntegral newMemPoolSize)
              let ekgMemPoolModifyTime = case reason of
                      ApplyBlock             -> ekgMemPoolModifyTimeApplyBlock
                      ApplyBlockWithRollback -> ekgMemPoolModifyTimeApplyBlockWithRollback
                      ProcessTransaction     -> ekgMemPoolModifyTimeProcessTx
              timeElapsed' <- liftIO $ Metrics.Gauge.read ekgMemPoolModifyTime
              let new_ = if timeElapsed' == 0
                        then fromIntegral timeElapsed
                        else round $ alpha * fromIntegral timeElapsed + (1 - alpha) * fromIntegral timeElapsed'
              liftIO $ Metrics.Gauge.set ekgMemPoolModifyTime new_
              logDebug $ sformat ("MemPool metrics release: "%shown
                                  %" modify time was "%shown%" size is "%shown)
                         reason timeElapsed newMemPoolSize
              pure . toJSON . JLMemPoolEvent $ JLMemPool
                  reason
                  (fromIntegral timeWaited)
                  (fromIntegral qlen)
                  (fromIntegral timeElapsed)
                  (fromIntegral oldMemPoolSize)
                  (fromIntegral newMemPoolSize)
                  (fromIntegral memAllocated)
        }