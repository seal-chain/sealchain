module Bench.Seal.Criterion.TxSigningBench
       ( runBenchmark
       ) where

import           Criterion.Main (Benchmark, bench, defaultConfig,
                     defaultMainWith, env, whnf)
import           Criterion.Types (Config (..))
import           Test.QuickCheck (generate)
import           Universum

import           Seal.Chain.Ssc ()
import           Seal.Chain.Txp (TxId, TxSig, TxSigData (..))
import           Seal.Crypto (SecretKey, SignTag (SignTx), sign)

import           Test.Seal.Chain.Txp.Arbitrary.Unsafe ()
import           Test.Seal.Util.QuickCheck.Arbitrary (arbitraryUnsafe)

import           Bench.Configuration (benchProtocolMagic)

signTx :: (SecretKey, TxId) -> TxSig
signTx (sk, thash) = sign benchProtocolMagic SignTx sk txSigData
  where
    txSigData = TxSigData
        { txSigTxHash = thash
        }

txSignBench :: Benchmark
txSignBench = env genArgs $ bench "Transactions signing" . whnf signTx
  where genArgs = generate $ (,)
                  <$> arbitraryUnsafe
                  <*> arbitraryUnsafe

txSignConfig :: Config
txSignConfig = defaultConfig
    { reportFile = Just "txSigning.html"
    }

runBenchmark :: IO ()
runBenchmark = defaultMainWith txSignConfig [txSignBench]
