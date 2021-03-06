{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE TypeFamilies    #-}

-- | Functions which work in 'GlobalToilM' and are part of Toil logic
-- related to stakes.

module Seal.Chain.Txp.Toil.Stakes
       ( applyTxsToStakes
       , rollbackTxsStakes
       ) where

import           Universum

import qualified Data.HashMap.Strict as HM
import qualified Data.HashSet as HS
import           Formatting (sformat, (%))
import           Serokell.Util.Text (listJson)

import           Seal.Chain.Genesis (GenesisWStakeholders)
import           Seal.Chain.Txp.Base (txOutStake)
import           Seal.Chain.Txp.Toil.Monad (GlobalToilM, getStake, getTotalStake,
                     setStake, setTotalStake)
import           Seal.Chain.Txp.Tx (Tx (..))
import           Seal.Chain.Txp.TxAux (TxAux (..))
import           Seal.Chain.Txp.TxOutAux (TxOutAux (..))
import           Seal.Chain.Txp.Undo (TxUndo)
import           Seal.Core (Currency (..), StakesList)
import           Seal.Util.Wlog (logDebug)

-- | Apply transactions to stakes.
applyTxsToStakes :: Monad m => GenesisWStakeholders -> [(TxAux, TxUndo)] -> GlobalToilM m ()
applyTxsToStakes bootStakeholders txun = do
    let (txOutPlus, txInMinus) = concatStakes bootStakeholders txun
    recomputeStakes txOutPlus txInMinus

-- | Rollback application of transactions to stakes.
rollbackTxsStakes :: Monad m => GenesisWStakeholders -> [(TxAux, TxUndo)] -> GlobalToilM m ()
rollbackTxsStakes bootStakeholders txun = do
    let (txOutMinus, txInPlus) = concatStakes bootStakeholders txun
    recomputeStakes txInPlus txOutMinus

----------------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------------

-- Compute new stakeholder's stakes by lists of spent and received coins.
recomputeStakes
    :: Monad m
    => StakesList
    -> StakesList
    -> GlobalToilM m ()
recomputeStakes plusDistr minusDistr = do
    let (plusStakeHolders, plusCoins) = unzip plusDistr
        (minusStakeHolders, minusCoins) = unzip minusDistr
        needResolve =
            HS.toList $
            HS.fromList plusStakeHolders `HS.union`
            HS.fromList minusStakeHolders
    resolvedStakesRaw <- mapM resolve needResolve
    let resolvedStakes = map fst resolvedStakesRaw
    let createdStakes = concatMap snd resolvedStakesRaw
    unless (null createdStakes) $
        logDebug $ sformat ("Stakes for "%listJson%" will be created in StakesDB") createdStakes
    totalStake <- getTotalStake
    let (positiveDelta, negativeDelta) = (sumMoneys plusCoins, sumMoneys minusCoins)
        newTotalStake = unsafeIntegerToMoney $
                        moneyToInteger totalStake + positiveDelta - negativeDelta
    let newStakes
          = HM.toList $
            -- It's safe befause user's stake can't be more than a
            -- limit. Also we first add then subtract, so we return to
            -- the word64 range.
            map unsafeIntegerToMoney $
            calcNegStakes minusDistr
                (calcPosStakes $ zip needResolve resolvedStakes ++ plusDistr)
    setTotalStake newTotalStake
    mapM_ (uncurry setStake) newStakes
  where
    resolve ad = getStake ad >>= \case
        Just x -> pure (x, [])
        Nothing -> pure (mkMoney 0, [ad])
    calcPosStakes = foldl' plusAt HM.empty
    -- This implementation does all the computation using
    -- Integer. Maybe it's possible to do it in word64. (@volhovm)
    calcNegStakes distr hm = foldl' minusAt hm distr
    plusAt hm (key, c) = HM.insertWith (+) key (moneyToInteger c) hm
    minusAt hm (key, c) =
        HM.alter (maybe err (\v -> Just (v - moneyToInteger c))) key hm
      where
        err = error ("recomputeStakes: no stake for " <> show key)

-- Concatenate stakes of the all passed transactions and undos.
concatStakes :: GenesisWStakeholders -> [(TxAux, TxUndo)] -> (StakesList, StakesList)
concatStakes bootStakeholders (unzip -> (txas, undo)) =
    (txasTxOutDistr, undoTxInDistr)
  where
    onlyKnownUndos = catMaybes . toList
    txasTxOutDistr = concatMap concatDistr txas
    undoTxInDistr = concatMap (txOutStake bootStakeholders . toaOut)
                    (foldMap onlyKnownUndos undo)
    concatDistr (TxAux UnsafeTx {..} _) =
        concatMap (txOutStake bootStakeholders . toaOut)
        $ toList (map TxOutAux _txUtxoOutputs)
