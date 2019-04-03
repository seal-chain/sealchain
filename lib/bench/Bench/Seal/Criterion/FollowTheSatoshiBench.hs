module Bench.Seal.Criterion.FollowTheSatoshiBench
    ( runBenchmark
    ) where

import           Criterion.Main (Benchmark, bench, defaultConfig,
                     defaultMainWith, env, whnf)
import           Criterion.Types (Config (..))
import           Formatting (int, sformat, (%))
import           Test.QuickCheck (Arbitrary (..), Gen, generate, infiniteListOf)
import           Universum

import           Seal.Chain.Lrc (followTheSatoshi)
import           Seal.Core (pcEpochSlots)
import           Seal.Core.Common (Coin, StakeholderId)

import           Bench.Configuration (benchProtocolConstants)
import           Test.Seal.Core.Arbitrary.Unsafe ()
import           Test.Seal.Crypto.Arbitrary ()
import           Test.Seal.Util.QuickCheck.Arbitrary (arbitraryUnsafe)

type UtxoSize = Int

-- [CSL-192]: make a trick and use special unsafe arbitrary instances
-- for generation of such things
arbitraryUtxoOfSize :: UtxoSize -> Gen [(StakeholderId, Coin)]
arbitraryUtxoOfSize n = take n <$> infiniteListOf arbitraryUnsafe

ftsBench :: UtxoSize -> Benchmark
ftsBench n = env genArgs $ bench msg . whnf (uncurry (followTheSatoshi epochSlots))
    where genArgs = generate $ (,) <$> arbitrary <*> arbitraryUtxoOfSize n
          msg = toString $ sformat ("followTheSatoshi: Utxo of size "%int) n
          epochSlots = pcEpochSlots benchProtocolConstants

ftsConfig :: Config
ftsConfig = defaultConfig
    { reportFile = Just "followTheSatoshi.html"
    }

runBenchmark :: IO ()
runBenchmark = defaultMainWith ftsConfig $ map ftsBench [1000, 10000, 100000]