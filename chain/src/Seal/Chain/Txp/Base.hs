{-# LANGUAGE RecordWildCards #-}

-- | Helpers for core types.

module Seal.Chain.Txp.Base
       ( addrBelongsTo
       , addrBelongsToSet
       , emptyTxPayload
       , flattenTxPayload
       , txOutStake
       , bootDustThreshold
       ) where

import           Universum

import           Control.Lens (ix)
import qualified Data.ByteArray as ByteArray
import qualified Data.HashSet as HS
import           Data.List (zipWith)
import qualified Data.Map.Strict as M

import           Seal.Chain.Genesis (GenesisWStakeholders (..))
import           Seal.Chain.Txp.Tx (TxOut (..))
import           Seal.Chain.Txp.TxAux (TxAux (..))
import           Seal.Chain.Txp.TxOutAux (TxOutAux (..))
import           Seal.Chain.Txp.TxPayload (TxPayload (..), mkTxPayload)
import           Seal.Core (AddrStakeDistribution (..), Address (..), Coin,
                     Currency (..), CoinPortion, StakeholderId, StakesList,
                     aaStakeDistribution, addrAttributesUnwrapped,
                     applyCoinPortionDown)
import           Seal.Crypto (hash)
import           Seal.Crypto.Random (deterministic, randomNumber)

-- | A predicate for `TxOutAux` which checks whether given address
-- belongs to it.
addrBelongsTo :: TxOutAux -> Address -> Bool
addrBelongsTo TxOutAux {..} = (== txOutAddress toaOut)

-- | Extended version of `addBelongsTo`, allows to compare against several
-- addresses.
addrBelongsToSet :: TxOutAux -> HashSet Address -> Bool
TxOutAux {..} `addrBelongsToSet` addrs = txOutAddress toaOut `HS.member` addrs

-- | Use this function if you need to know how a 'TxOut' distributes stake
-- (e.g. for the purpose of running follow-the-satoshi).
txOutStake :: GenesisWStakeholders -> TxOut -> StakesList
txOutStake genesisStakeholders (TxOutSeal {..}) =
    case aaStakeDistribution (addrAttributesUnwrapped txOutAddress) of
        BootstrapEraDistr            -> (bootstrapEraDistr genesisStakeholders) txOutSeal
        SingleKeyDistr sId           -> [(sId, txOutSeal)]
        UnsafeMultiKeyDistr distrMap -> computeMultiKeyDistr (M.toList distrMap)
  where
    outValueInteger = moneyToInteger txOutSeal
    -- For all stakeholders in this list (which is 'Ord'-ered) except
    -- the first one we use 'applyCoinPortionDown'. For the first one
    -- we take the difference. It is safe because sum of portions must
    -- be 1.
    computeMultiKeyDistr :: [(StakeholderId, CoinPortion)] -> StakesList
    computeMultiKeyDistr [] =
        error $ "txOutStake: impossible happened, " <>
        "multi key distribution is empty"
    computeMultiKeyDistr ((headStakeholder, _):rest) =
        let restDistr = computeMultiKeyDistrRest rest
            restDistrSum = sumMoneys $ map snd restDistr
            headStake = outValueInteger - restDistrSum
        -- 'unsafeIntegerToMoney' is safe by construction
        in (headStakeholder, unsafeIntegerToMoney headStake) : restDistr
    computeMultiKeyDistrRest :: [(StakeholderId, CoinPortion)] -> StakesList
    computeMultiKeyDistrRest = map (second (`applyCoinPortionDown` txOutSeal))

txOutStake _ _ = []

-- | Convert 'TxPayload' into a flat list of `TxAux`s.
flattenTxPayload :: TxPayload -> [TxAux]
flattenTxPayload UnsafeTxPayload {..} =
    zipWith TxAux (toList _txpTxs) _txpWitnesses

emptyTxPayload :: TxPayload
emptyTxPayload = mkTxPayload []

----------------------------------------------------------------------------
-- Details
----------------------------------------------------------------------------

-- | If output has less coins than this value, 'BootstrapEraDistr'
-- will use custom algorithm.
bootDustThreshold :: GenesisWStakeholders -> Coin
bootDustThreshold (GenesisWStakeholders bootHolders) =
    -- it's safe to use it here because weights are word16 and should
    -- be really low in production, so this sum is not going to be
    -- even more than 10-15 coins.
    unsafeIntegerToMoney . sum $ map fromIntegral $ toList bootHolders

-- Compute bootstrap era distribution.
--
-- This function splits coin into chunks of @weightsSum@ and
-- distributes them between bootstrap era stakeholders. Remainder is
-- assigned randomly (among bootstrap era stakeholders) based on hash of the
-- coin.
--
-- If coin is lower than 'bootDustThreshold' then this function
-- distributes coins among first stakeholders in the list according to
-- their weights. The list is ordered by 'StakeholderId's.
bootstrapEraDistr :: GenesisWStakeholders -> Coin -> [(StakeholderId, Coin)]
bootstrapEraDistr bs@(GenesisWStakeholders bootWHolders) c
    | c < bootDustThreshold bs =
          snd $ foldr foldrFunc (0::Word64,[]) (M.toList bootWHolders)
    | otherwise =
          bootHolders `zip` stakeCoins
  where
    foldrFunc (s,w) r@(totalSum, res) = case compare totalSum cval of
        EQ -> r
        GT -> error "bootstrapEraDistr: totalSum > cval can't happen"
        LT -> let w' = (fromIntegral w :: Word64)
                  toInclude = bool w' (cval - totalSum) (totalSum + w' > cval)
              in (totalSum + toInclude
                 ,(s, mkMoney toInclude):res)

    weights :: [Word64]
    weights = map fromIntegral $ toList bootWHolders

    weightsSum :: Word64
    weightsSum = sum weights

    bootHolders :: [StakeholderId]
    bootHolders = M.keys bootWHolders

    (d :: Word64, m :: Word64) = divMod cval weightsSum

    -- Person who will get the remainder.
    -- Must be in range `[0, addrsNum)` as long as randomNumber is valid.
    remReceiver :: Int
    remReceiver = fromIntegral $ deterministic (ByteArray.convert $ hash c)
        $ randomNumber (toInteger addrsNum)

    cval :: Word64
    cval = unsafeGetMoney c

    addrsNum :: Int
    addrsNum = length bootHolders

    stakeCoins :: [Coin]
    stakeCoins =
        map (\w -> mkMoney $ w * d) weights &
        ix remReceiver %~ unsafeAddMoney (mkMoney m)
