{-# LANGUAGE TemplateHaskell #-}

module Test.Seal.Launcher.Json
       ( tests
       ) where

import           Universum

import qualified Data.HashMap.Strict as HM
import qualified Data.Set as S
import           Hedgehog (Property)
import qualified Hedgehog as H

import           Ntp.Client (NtpConfiguration (..))
import           Seal.Chain.Block (BlockConfiguration (..))
import           Seal.Chain.Delegation (DlgConfiguration (..))
import           Seal.Chain.Genesis (FakeAvvmOptions (..),
                     GenesisAvvmBalances (..), GenesisDelegation (..),
                     GenesisInitializer (..), GenesisProtocolConstants (..),
                     GenesisSpec (..), StaticConfig (..),
                     TestnetBalanceOptions (..))
import           Seal.Chain.Ssc (SscConfiguration (..))
import           Seal.Chain.Txp (TxpConfiguration (..))
import           Seal.Chain.Update
import           Seal.Configuration (NodeConfiguration (..))
import           Seal.Core.Common (Coeff (..), CoinPortion (..), SharedSeed (..),
                     TxFeePolicy (..), TxSizeLinear (..))
import           Seal.Core.ProtocolConstants (VssMaxTTL (..), VssMinTTL (..))
import           Seal.Core.Slotting (EpochIndex (..))
import           Seal.Crypto.Configuration (ProtocolMagic (..),
                     ProtocolMagicId (..), RequiresNetworkMagic (..))
import           Seal.Launcher.Configuration (Configuration (..),
                     WalletConfiguration (..))

import           Test.Seal.Util.Golden (discoverGolden, goldenTestJSONDec)
--------------------------------------------------------------------------------
-- Configuration
--------------------------------------------------------------------------------

-- Decode-only golden tests for ensuring that, when decoding the legacy
-- `Configuration` JSON format, the `RequiresNetworkMagic` field defaults to
-- the correct `RequiresNetworkMagic`.

golden_Configuration_Legacy_NoNetworkMagicField :: Property
golden_Configuration_Legacy_NoNetworkMagicField =
    goldenTestJSONDec
        testGoldenConf_NoNetworkMagicField
            "test/golden/json/Configuration_Legacy_NoNetworkMagicField"

testGoldenConf_NoNetworkMagicField :: Configuration
testGoldenConf_NoNetworkMagicField = Configuration
    { ccGenesis = GCSpec
        ( UnsafeGenesisSpec
            { gsAvvmDistr = GenesisAvvmBalances (HM.fromList [])
            , gsFtsSeed = SharedSeed "skovoroda Ggurda boroda provoda "
            , gsHeavyDelegation = UnsafeGenesisDelegation (HM.fromList [])
            , gsBlockVersionData = BlockVersionData
                { bvdScriptVersion = 0
                , bvdSlotDuration = 7000
                , bvdMaxBlockSize = 2000000
                , bvdMaxHeaderSize = 2000000
                , bvdMaxTxSize = 4096
                , bvdMaxProposalSize = 700
                , bvdMpcThd = CoinPortion 100000000000000
                , bvdHeavyDelThd = CoinPortion 100000000000000
                , bvdUpdateVoteThd = CoinPortion 100000000000000
                , bvdUpdateProposalThd = CoinPortion 100000000000000
                , bvdUpdateImplicit = 10
                , bvdSoftforkRule = SoftforkRule
                    { srInitThd = CoinPortion 100000000000000
                    , srMinThd = CoinPortion 100000000000000
                    , srThdDecrement = CoinPortion 100000000000000
                    }
                , bvdTxFeePolicy =
                      TxFeePolicyTxSizeLinear
                          (TxSizeLinear
                              (Coeff 155381.000000000) (Coeff 43.946000000))
                , bvdUnlockStakeEpoch = EpochIndex 1844
                }
            , gsProtocolConstants = GenesisProtocolConstants
                { gpcK = 2
                , gpcProtocolMagic = ProtocolMagic
                                         (ProtocolMagicId 55550001) RequiresMagic
                , gpcVssMaxTTL = VssMaxTTL 6
                , gpcVssMinTTL = VssMinTTL 2
                }
            , gsInitializer = GenesisInitializer
                { giTestBalance = TestnetBalanceOptions
                    { tboPoors = 12
                    , tboRichmen = 4
                    , tboTotalBalance = 600000000000000000
                    , tboRichmenShare = 0.99
                    , tboUseHDAddresses = True
                    }
                , giFakeAvvmBalance = FakeAvvmOptions
                    { faoCount = 10
                    , faoOneBalance = 100000
                    }
                , giAvvmBalanceFactor = CoinPortion 100000000000000
                , giUseHeavyDlg = True
                , giSeed = 0
                }
            }
        )
    , ccNtp = NtpConfiguration
        { ntpcServers =
            [ "0.pool.ntp.org"
            , "2.pool.ntp.org"
            , "3.pool.ntp.org"
            ]
        , ntpcResponseTimeout = 30000000
        , ntpcPollDelay = 1800000000
        }
    , ccUpdate = UpdateConfiguration
        { ccApplicationName = ApplicationName "seal"
        , ccLastKnownBlockVersion = BlockVersion 0 0 0
        , ccApplicationVersion = 0
        , ccSystemTag = SystemTag "linux64"
        }
    , ccSsc = SscConfiguration
        { ccMpcSendInterval = 10
        , ccMdNoCommitmentsEpochThreshold = 3
        , ccNoReportNoSecretsForEpoch1 = False
        }
    , ccDlg = DlgConfiguration
        { ccDlgCacheParam = 500
        , ccMessageCacheTimeout = 30
        }
    , ccTxp = TxpConfiguration
        { ccMemPoolLimitTx = 200
        , tcAssetLockedSrcAddrs = S.fromList []
        }
    , ccBlock = BlockConfiguration
        { ccNetworkDiameter = 3
        , ccRecoveryHeadersMessage = 20
        , ccStreamWindow = 2048
        , ccNonCriticalCQBootstrap = 0.95
        , ccCriticalCQBootstrap = 0.8888
        , ccNonCriticalCQ = 0.8
        , ccCriticalCQ = 0.654321
        , ccCriticalForkThreshold = 2
        , ccFixedTimeCQ = 10
        }
    , ccNode = NodeConfiguration
        { ccNetworkConnectionTimeout = 15000
        , ccConversationEstablishTimeout = 30000
        , ccBlockRetrievalQueueSize = 100
        , ccPendingTxResubmissionPeriod = 7
        , ccWalletProductionApi = False
        , ccWalletTxCreationDisabled = False
        , ccExplorerExtendedApi = False
        }
    , ccWallet = WalletConfiguration { ccThrottle = Nothing }
    , ccReqNetMagic = RequiresNoMagic
    }

tests :: IO Bool
tests = H.checkSequential $$discoverGolden
