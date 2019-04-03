{-# LANGUAGE RecordWildCards #-}

-- | Module for command-line utilites, parsers and convenient handlers.

module Seal.Client.CLI.Util
       ( attackTypeParser
       , attackTargetParser
       , defaultLoggerConfig
       , readLoggerConfig
       , stakeholderIdParser
       ) where

import           Universum hiding (try)

import           Text.Parsec (parserFail, try)
import qualified Text.Parsec.Char as P
import qualified Text.Parsec.Text as P

import           Seal.Chain.Security (AttackTarget (..), AttackType (..))
import           Seal.Core (StakeholderId)
import           Seal.Core.NetworkAddress (addrParser)
import           Seal.Crypto (decodeAbstractHash)
import           Seal.Util.Wlog (LoggerConfig (..), parseLoggerConfig,
                     productionB)

attackTypeParser :: P.Parser AttackType
attackTypeParser = P.string "No" >>
    AttackNoBlocks <$ (P.string "Blocks") <|>
    AttackNoCommitments <$ (P.string "Commitments")

stakeholderIdParser :: P.Parser StakeholderId
stakeholderIdParser = do
    token <- some P.alphaNum
    either (parserFail . toString) return $
        decodeAbstractHash (toText token)

attackTargetParser :: P.Parser AttackTarget
attackTargetParser =
    (PubKeyAddressTarget <$> try stakeholderIdParser) <|>
    (NetworkAddressTarget <$> addrParser)

-- | Default logger config. Will be used if `--log-config` argument is
-- not passed.
defaultLoggerConfig :: LoggerConfig
defaultLoggerConfig = productionB

-- | Reads logger config from given path. By default returns
-- 'defaultLoggerConfig'.
readLoggerConfig :: MonadIO m => Maybe FilePath -> m LoggerConfig
readLoggerConfig = maybe (return defaultLoggerConfig) parseLoggerConfig
