{-# LANGUAGE TypeFamilies #-}

module Seal.Chain.Ssc.Functions
       ( hasCommitment
       , hasOpening
       , hasShares
       , hasVssCertificate

       -- * SscPayload
       , verifySscPayload

       -- * VSS
       , vssThreshold
       , getStableCertsPure
       ) where

import           Universum hiding (id)

import           Control.Lens (to)
import           Control.Monad.Except (MonadError (throwError))
import qualified Data.HashMap.Strict as HM
import           Serokell.Util.Verify (isVerSuccess)

import           Seal.Chain.Block.IsHeader (IsMainHeader, headerSlotL)
import           Seal.Chain.Genesis as Genesis (Config (..),
                     configBlkSecurityParam, configVssCerts)
import           Seal.Chain.Ssc.Base (checkCertTTL, isCommitmentId, isOpeningId,
                     isSharesId, verifySignedCommitment, vssThreshold)
import           Seal.Chain.Ssc.CommitmentsMap (CommitmentsMap (..))
import           Seal.Chain.Ssc.Error (SscVerifyError (..))
import           Seal.Chain.Ssc.Payload (SscPayload (..))
import           Seal.Chain.Ssc.Toss.Base (verifyEntriesGuardM)
import           Seal.Chain.Ssc.Types (SscGlobalState (..))
import qualified Seal.Chain.Ssc.VssCertData as VCD
import           Seal.Chain.Ssc.VssCertificatesMap (VssCertificatesMap)
import           Seal.Core (EpochIndex (..), SlotId (..), StakeholderId,
                     pcBlkSecurityParam)
import           Seal.Core.Slotting (crucialSlot)
import           Seal.Util.Some (Some)

----------------------------------------------------------------------------
-- Simple predicates for SSC.Types
----------------------------------------------------------------------------

hasCommitment :: StakeholderId -> SscGlobalState -> Bool
hasCommitment id = HM.member id . getCommitmentsMap . _sgsCommitments

hasOpening :: StakeholderId -> SscGlobalState -> Bool
hasOpening id = HM.member id . _sgsOpenings

hasShares :: StakeholderId -> SscGlobalState -> Bool
hasShares id = HM.member id . _sgsShares

hasVssCertificate :: StakeholderId -> SscGlobalState -> Bool
hasVssCertificate id = VCD.member id . _sgsVssCertificates

----------------------------------------------------------------------------
-- SscPayload Part
----------------------------------------------------------------------------

-- CHECK: @verifySscPayload
-- Verify payload using header containing this payload.
--
-- For each DS datum we check:
--
--   1. Whether it's stored in the correct block (e.g. commitments have to be
--      in first 2 * blkSecurityParam blocks, etc.)
--
--   2. Whether the message itself is correct (e.g. commitment signature is
--      valid, etc.)
--
-- We also do some general sanity checks.
verifySscPayload
    :: MonadError SscVerifyError m
    => Genesis.Config -> Either EpochIndex (Some IsMainHeader) -> SscPayload -> m ()
verifySscPayload genesisConfig eoh payload = case payload of
    CommitmentsPayload comms certs -> do
        whenHeader eoh isComm
        commChecks comms
        certsChecks certs
    OpeningsPayload        _ certs -> do
        whenHeader eoh isOpen
        certsChecks certs
    SharesPayload          _ certs -> do
        whenHeader eoh isShare
        certsChecks certs
    CertificatesPayload      certs -> do
        whenHeader eoh isOther
        certsChecks certs
  where
    whenHeader (Left _) _       = pass
    whenHeader (Right header) f = f $ header ^. headerSlotL

    epochId = either identity (view $ headerSlotL . to siEpoch) eoh
    pc = configProtocolConstants genesisConfig
    k = pcBlkSecurityParam pc
    isComm  slotId = unless (isCommitmentId k slotId) $ throwError $ NotCommitmentPhase slotId
    isOpen  slotId = unless (isOpeningId k slotId) $ throwError $ NotOpeningPhase slotId
    isShare slotId = unless (isSharesId k slotId) $ throwError $ NotSharesPhase slotId
    isOther slotId = unless (all not $
                      map ($ slotId) [isCommitmentId k, isOpeningId k, isSharesId k]) $
                      throwError $ NotIntermediatePhase slotId

    -- We *forbid* blocks from having commitments/openings/shares in blocks
    -- with wrong slotId (instead of merely discarding such commitments/etc)
    -- because it's the miner's responsibility not to include them into the
    -- block if they're late.
    --
    -- CHECK: For commitments specifically, we also
    --
    --   * check there are only commitments in the block
    --   * use verifySignedCommitment, which checks commitments themselves,
    --     e.g. checks their signatures (which includes checking that the
    --     commitment has been generated for this particular epoch)
    --
    -- #verifySignedCommitment
    commChecks commitments = do
        let checkComm = isVerSuccess . verifySignedCommitment
                (configProtocolMagic genesisConfig)
                epochId
        verifyEntriesGuardM fst snd CommitmentInvalid
                            (pure . checkComm)
                            (HM.toList . getCommitmentsMap $ commitments)

    -- CHECK: Vss certificates checker
    --
    --   * VSS certificates are signed properly
    --   * VSS certificates have valid TTLs
    --
    -- #checkCert
    certsChecks certs =
        verifyEntriesGuardM identity identity CertificateInvalidTTL
                            (pure . checkCertTTL pc epochId)
                            (toList certs)

----------------------------------------------------------------------------
-- Modern
----------------------------------------------------------------------------

getStableCertsPure
    :: Genesis.Config
    -> EpochIndex
    -> VCD.VssCertData
    -> VssCertificatesMap
getStableCertsPure genesisConfig epoch certs
    | epoch == 0 = configVssCerts genesisConfig
    | otherwise = VCD.certs $ VCD.setLastKnownSlot
        (crucialSlot (configBlkSecurityParam genesisConfig) epoch)
        certs
