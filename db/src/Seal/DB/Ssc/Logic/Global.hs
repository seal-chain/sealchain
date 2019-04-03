{-# LANGUAGE Rank2Types #-}

-- | Thin wrapper around `calculateSeed` used in LRC worker.

module Seal.DB.Ssc.Logic.Global
       (
       -- * Seed
         sscCalculateSeed
       ) where

import           Universum

import           Seal.Chain.Lrc (RichmenStakes)
import           Seal.Chain.Ssc (MonadSscMem, SscGlobalQuery, SscSeedError,
                     VssCertificatesMap (..), calculateSeed, sgsCommitments,
                     sgsOpenings, sgsShares, sgsVssCertificates,
                     sscRunGlobalQuery, vcVssKey)
import qualified Seal.Chain.Ssc as Ssc
import           Seal.Chain.Update (BlockVersionData)
import           Seal.Core (EpochIndex (..), SharedSeed)
import           Seal.DB (MonadDBRead)
import           Seal.DB.Lrc (HasLrcContext, getSscRichmen)

----------------------------------------------------------------------------
-- Seed
----------------------------------------------------------------------------

-- | Calculate 'SharedSeed' for given epoch using 'SscGlobalState'.
sscCalculateSeed
    :: forall ctx m.
       ( MonadSscMem ctx m
       , MonadDBRead m
       , HasLrcContext ctx
       , MonadIO m
       )
    => BlockVersionData
    -> EpochIndex
    -> m (Either SscSeedError SharedSeed)
sscCalculateSeed genesisBvd epoch = do
    -- We take richmen for the previous epoch because during N-th epoch we
    -- were using richmen for N-th epoch for everything – so, when we are
    -- calculating the seed for N+1-th epoch, we should still use data from
    -- N-th epoch.
    richmen <- getSscRichmen genesisBvd "sscCalculateSeed" (epoch - 1)
    sscRunGlobalQuery $ sscCalculateSeedQ richmen

sscCalculateSeedQ
    :: RichmenStakes
    -> SscGlobalQuery (Either SscSeedError SharedSeed)
sscCalculateSeedQ richmen =
    calculateSeed
    <$> view sgsCommitments
    <*> (map vcVssKey . getVssCertificatesMap . Ssc.certs <$>
         view sgsVssCertificates)
    <*> view sgsOpenings
    <*> view sgsShares
    <*> pure richmen
