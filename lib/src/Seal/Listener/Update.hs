{-# LANGUAGE RankNTypes          #-}
{-# LANGUAGE ScopedTypeVariables #-}

-- TODO rename the module / move defintions / whatever.
-- It's not about the network at all.

module Seal.Listener.Update
       ( UpdateMode
       , handleProposal
       , handleVote
       ) where

import           Universum

import           Formatting (build, sformat, (%))
import           UnliftIO (MonadUnliftIO)

import           Seal.Chain.Genesis as Genesis (Config)
import           Seal.Chain.Update (HasUpdateConfiguration, UpdateParams,
                     UpdateProposal (..), UpdateVote (..))
import           Seal.DB.Class (MonadDB, MonadGState)
import           Seal.DB.Lrc (HasLrcContext)
import           Seal.DB.Update (UpdateContext, processProposal, processVote)
import           Seal.Infra.Recovery.Info (MonadRecoveryInfo)
import           Seal.Infra.Reporting (MonadReporting)
import           Seal.Infra.Shutdown.Class (HasShutdownContext)
import           Seal.Infra.Slotting (MonadSlots)
import           Seal.Infra.StateLock (StateLock)
import           Seal.Util.Util (HasLens (..))
import           Seal.Util.Wlog (WithLogger, logNotice, logWarning)




type UpdateMode ctx m
    = ( WithLogger m
      , MonadIO m
      , MonadUnliftIO m
      , MonadMask m
      , MonadGState m
      , MonadDB m
      , MonadReader ctx m
      , HasLrcContext ctx
      , HasLens UpdateContext ctx UpdateContext
      , HasLens UpdateParams ctx UpdateParams
      , HasLens StateLock ctx StateLock
      , HasShutdownContext ctx
      , HasUpdateConfiguration
      , MonadReporting m
      , MonadRecoveryInfo ctx m
      , MonadSlots ctx m
      )

handleProposal
    :: forall ctx m . UpdateMode ctx m
    => Genesis.Config
    -> (UpdateProposal, [UpdateVote])
    -> m Bool
handleProposal genesisConfig (proposal, votes) = do
    res <- processProposal genesisConfig proposal
    logProp proposal res
    let processed = isRight res
    processed <$ when processed (mapM_ processVoteLog votes)
  where
    processVoteLog :: UpdateVote -> m ()
    processVoteLog vote = processVote genesisConfig vote >>= logVote vote
    logVote vote (Left cause) =
        logWarning $ sformat ("Proposal is accepted but vote "%build%
                              " is rejected, the reason is: "%build)
                     vote cause
    logVote vote (Right _) = logVoteAccepted vote

    logProp prop (Left cause) =
        logWarning $ sformat ("Processing of proposal "%build%
                              " failed, the reason is: "%build)
              prop cause
    -- Update proposals are accepted rarely (at least before Shelley),
    -- so it deserves 'Notice' severity.
    logProp prop (Right _) =
        logNotice $ sformat ("Processing of proposal "%build%" is successful")
              prop

----------------------------------------------------------------------------
-- UpdateVote
----------------------------------------------------------------------------

handleVote
    :: UpdateMode ctx m
    => Genesis.Config
    -> UpdateVote
    -> m Bool
handleVote genesisConfig uv = do
    res <- processVote genesisConfig uv
    logProcess uv res
    pure $ isRight res
  where
    logProcess vote (Left cause) =
        logWarning $ sformat ("Processing of vote "%build%
                              "failed, the reason is: "%build)
                     vote cause
    logProcess vote (Right _) = logVoteAccepted vote

----------------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------------

-- Update votes are accepted rarely (at least before Shelley), so
-- it deserves 'Notice' severity.
logVoteAccepted :: WithLogger m => UpdateVote -> m ()
logVoteAccepted =
    logNotice . sformat ("Processing of vote "%build%"is successfull")
