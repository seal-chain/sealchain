-- | Types used in LRC.

module Seal.Chain.Lrc.Types
       ( RichmenSet
       , RichmenStakes
       , FullRichmenData
       ) where

import           Universum

import           Seal.Core.Common (Coin, StakeholderId)

-- | Hashset of richmen (i. e. stakeholders whose stake is greater
-- than some threshold).
type RichmenSet = HashSet StakeholderId

-- | Richmen and their stakes.
type RichmenStakes = HashMap StakeholderId Coin

-- | Full richmen data consists of total stake at some point and stake
-- distribution among richmen.
type FullRichmenData = (Coin, RichmenStakes)
