{-# LANGUAGE RecordWildCards #-}

module Seal.Chain.Update.BlockVersionModifier
       ( BlockVersionModifier (..)
       , checkBlockVersionModifier
       , applyBVM
       ) where

import           Universum

import           Control.Monad.Except (MonadError)
import           Data.Default (Default (..))
import           Data.SafeCopy (base, deriveSafeCopySimple)
import           Data.Text.Lazy.Builder (Builder)
import           Data.Time.Units (Millisecond)
import           Formatting (Format, bprint, build, int, later, (%))
import qualified Formatting.Buildable as Buildable
import           Serokell.Data.Memory.Units (Byte, memory)

import           Seal.Binary.Class (Cons (..), Field (..), deriveSimpleBi)
import           Seal.Core.Binary ()
import           Seal.Core.Common (CoinPortion, TxFeePolicy, checkCoinPortion)
import           Seal.Core.Slotting (EpochIndex, FlatSlotId)
import           Seal.Util.Orphans ()

import           Seal.Chain.Update.BlockVersionData (BlockVersionData (..), ScriptVersion)
import           Seal.Chain.Update.SoftforkRule

-- | Data which represents modifications of block (aka protocol) version.
data BlockVersionModifier = BlockVersionModifier
    { bvmScriptVersion     :: !(Maybe ScriptVersion)
    , bvmSlotDuration      :: !(Maybe Millisecond)
    , bvmMaxBlockSize      :: !(Maybe Byte)
    , bvmMaxHeaderSize     :: !(Maybe Byte)
    , bvmMaxTxSize         :: !(Maybe Byte)
    , bvmMaxProposalSize   :: !(Maybe Byte)
    , bvmMpcThd            :: !(Maybe CoinPortion)
    , bvmHeavyDelThd       :: !(Maybe CoinPortion)
    , bvmUpdateVoteThd     :: !(Maybe CoinPortion)
    , bvmUpdateProposalThd :: !(Maybe CoinPortion)
    , bvmUpdateImplicit    :: !(Maybe FlatSlotId)
    , bvmSoftforkRule      :: !(Maybe SoftforkRule)
    , bvmTxFeePolicy       :: !(Maybe TxFeePolicy)
    , bvmUnlockStakeEpoch  :: !(Maybe EpochIndex)
    } deriving (Show, Eq, Ord, Generic, Typeable)

instance NFData BlockVersionModifier
instance Hashable BlockVersionModifier

instance Default BlockVersionModifier where
    def = BlockVersionModifier
        { bvmScriptVersion     = Nothing
        , bvmSlotDuration      = Nothing
        , bvmMaxBlockSize      = Nothing
        , bvmMaxHeaderSize     = Nothing
        , bvmMaxTxSize         = Nothing
        , bvmMaxProposalSize   = Nothing
        , bvmMpcThd            = Nothing
        , bvmHeavyDelThd       = Nothing
        , bvmUpdateVoteThd     = Nothing
        , bvmUpdateProposalThd = Nothing
        , bvmUpdateImplicit    = Nothing
        , bvmSoftforkRule      = Nothing
        , bvmTxFeePolicy       = Nothing
        , bvmUnlockStakeEpoch  = Nothing
        }

instance Buildable BlockVersionModifier where
    build BlockVersionModifier {..} =
      bprint ("{ script version: "%bmodifier build%
              ", slot duration (mcs): "%bmodifier int%
              ", block size limit: "%bmodifier memory%
              ", header size limit: "%bmodifier memory%
              ", tx size limit: "%bmodifier memory%
              ", proposal size limit: "%bmodifier memory%
              ", mpc threshold: "%bmodifier build%
              ", heavyweight delegation threshold: "%bmodifier build%
              ", update vote threshold: "%bmodifier build%
              ", update proposal threshold: "%bmodifier build%
              ", update implicit period (slots): "%bmodifier int%
              ", softfork rule: "%bmodifier build%
              ", tx fee policy: "%bmodifier build%
              ", unlock stake epoch: "%bmodifier build%
              " }")
        bvmScriptVersion
        bvmSlotDuration
        bvmMaxBlockSize
        bvmMaxHeaderSize
        bvmMaxTxSize
        bvmMaxProposalSize
        bvmMpcThd
        bvmHeavyDelThd
        bvmUpdateVoteThd
        bvmUpdateProposalThd
        bvmUpdateImplicit
        bvmSoftforkRule
        bvmTxFeePolicy
        bvmUnlockStakeEpoch
      where
        bmodifier :: Format Builder (a -> Builder) -> Format r (Maybe a -> r)
        bmodifier b = later $ maybe "no change" (bprint b)

checkBlockVersionModifier
    :: (MonadError Text m)
    => BlockVersionModifier
    -> m ()
checkBlockVersionModifier BlockVersionModifier {..} = do
    whenJust bvmMpcThd checkCoinPortion
    whenJust bvmHeavyDelThd checkCoinPortion
    whenJust bvmUpdateVoteThd checkCoinPortion
    whenJust bvmUpdateProposalThd checkCoinPortion
    whenJust bvmSoftforkRule checkSoftforkRule

-- | Apply 'BlockVersionModifier' to 'BlockVersionData'.
applyBVM :: BlockVersionModifier -> BlockVersionData -> BlockVersionData
applyBVM BlockVersionModifier {..} BlockVersionData {..} =
    BlockVersionData
    { bvdScriptVersion     = fromMaybe bvdScriptVersion     bvmScriptVersion
    , bvdSlotDuration      = fromMaybe bvdSlotDuration      bvmSlotDuration
    , bvdMaxBlockSize      = fromMaybe bvdMaxBlockSize      bvmMaxBlockSize
    , bvdMaxHeaderSize     = fromMaybe bvdMaxHeaderSize     bvmMaxHeaderSize
    , bvdMaxTxSize         = fromMaybe bvdMaxTxSize         bvmMaxTxSize
    , bvdMaxProposalSize   = fromMaybe bvdMaxProposalSize   bvmMaxProposalSize
    , bvdMpcThd            = fromMaybe bvdMpcThd            bvmMpcThd
    , bvdHeavyDelThd       = fromMaybe bvdHeavyDelThd       bvmHeavyDelThd
    , bvdUpdateVoteThd     = fromMaybe bvdUpdateVoteThd     bvmUpdateVoteThd
    , bvdUpdateProposalThd = fromMaybe bvdUpdateProposalThd bvmUpdateProposalThd
    , bvdUpdateImplicit    = fromMaybe bvdUpdateImplicit    bvmUpdateImplicit
    , bvdSoftforkRule      = fromMaybe bvdSoftforkRule      bvmSoftforkRule
    , bvdTxFeePolicy       = fromMaybe bvdTxFeePolicy       bvmTxFeePolicy
    , bvdUnlockStakeEpoch  = fromMaybe bvdUnlockStakeEpoch  bvmUnlockStakeEpoch
    }

deriveSimpleBi ''BlockVersionModifier [
    Cons 'BlockVersionModifier [
        Field [| bvmScriptVersion     :: Maybe ScriptVersion |],
        Field [| bvmSlotDuration      :: Maybe Millisecond   |],
        Field [| bvmMaxBlockSize      :: Maybe Byte          |],
        Field [| bvmMaxHeaderSize     :: Maybe Byte          |],
        Field [| bvmMaxTxSize         :: Maybe Byte          |],
        Field [| bvmMaxProposalSize   :: Maybe Byte          |],
        Field [| bvmMpcThd            :: Maybe CoinPortion   |],
        Field [| bvmHeavyDelThd       :: Maybe CoinPortion   |],
        Field [| bvmUpdateVoteThd     :: Maybe CoinPortion   |],
        Field [| bvmUpdateProposalThd :: Maybe CoinPortion   |],
        Field [| bvmUpdateImplicit    :: Maybe FlatSlotId    |],
        Field [| bvmSoftforkRule      :: Maybe SoftforkRule  |],
        Field [| bvmTxFeePolicy       :: Maybe TxFeePolicy   |],
        Field [| bvmUnlockStakeEpoch  :: Maybe EpochIndex    |]
    ]]

deriveSafeCopySimple 0 'base ''BlockVersionModifier
