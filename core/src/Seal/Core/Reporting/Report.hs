{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE ScopedTypeVariables #-}

-- | Log report datatype & related.

module Seal.Core.Reporting.Report
       ( ReportType(..)
       , supportedApps
       , SEALProduct (..)
       , Version (..)
       , FrontendVersion (..)
       , BackendVersion (..)
       , InstallerVersion (..)
       , Network (..)
       , showNetwork
       , ReportInfo (..)
       , ProductVersion (..)
       ) where

import           Universum

import           Prelude (Show (..))

import           Data.Aeson (FromJSON (..), ToJSON (..), Value (Object, String), object, (.:), (.=))
import           Data.Aeson.Types (typeMismatch)
import qualified Data.Text as T
import           Data.Time (UTCTime)
import           Data.Time.Format (defaultTimeLocale, formatTime, iso8601DateFormat, parseTimeM)


-- | Type of report.
data ReportType
    = RCrash Int
    -- ^ This type is used only to report crash of application.
    | RError Text
    -- ^ The type of report used when a local error (most likely
    -- assertion violation or anything else that indicates a bug)
    -- happens. «Local» means that error most likely affects only one
    -- node for which this error happened.
    | RMisbehavior { rmIsCritical  :: Bool
                   -- ^ Whether misbehavior can break the system and
                   -- must be addressed ASAP.  Example of critical
                   -- misbehavior: chain quality is closed to
                   -- 50%. Example of non-critical misbehavior: fork
                   -- happened in bootstrap era. The latter should be
                   -- investigated, but doesn't mean that the system's
                   -- operability is threatened.
                   , rmDescription :: Text
                   -- ^ What exactly is suspicious\/wrong.
                    }
    -- ^ This type of report indicates global problems which most
    -- likely affect all nodes.
    | RInfo Text
    -- ^ The type of report used to send statistical or any other
    -- useful information and doesn't indicate anything
    -- bad\/strange\/suspicious.
    | RCustomReport { crEmail   :: Text
                      -- ^ The user's email address
                    , crSubject :: Text
                      -- ^ The title of the report
                    , crProblem :: Text
                      -- ^ Description of the issue(s)
                    }
    -- ^ This is a custom user report coming directly from Daedalus.
    deriving (Show, Eq)

-- TODO(ks): Phantom/GADTs for the win?

------------------------------------------------------------
-- Wrappers
------------------------------------------------------------

newtype SEALProduct = SEALProduct { getSEALProduct :: Text }
    deriving (Show, Eq)

instance FromJSON SEALProduct where
    parseJSON (String product')     = pure . SEALProduct $ product'
    parseJSON invalid               = typeMismatch "Product" invalid

instance ToJSON SEALProduct where
    toJSON (SEALProduct product')   = toJSON product'

------------------------------------------------------------

-- TODO(ks): Major, Minor - 10.3
newtype Version = Version { getVersion :: Text }
    deriving (Show, Eq)

newtype FrontendVersion = FrontendVersion { getFrontendVersion :: Version }
    deriving (Show, Eq)

instance FromJSON FrontendVersion where
    parseJSON (String version) = pure . FrontendVersion . Version $ version
    parseJSON invalid          = typeMismatch "FrontendVersion" invalid

instance ToJSON FrontendVersion where
    toJSON (FrontendVersion version) =
        toJSON $ getVersion version

------------------------------------------------------------

newtype BackendVersion = BackendVersion { getBackendVersion :: Version }
    deriving (Show, Eq)

instance FromJSON BackendVersion where
    parseJSON (String version) = pure . BackendVersion . Version $ version
    parseJSON invalid          = typeMismatch "BackendVersion" invalid

instance ToJSON BackendVersion where
    toJSON (BackendVersion version) =
        toJSON $ getVersion version

------------------------------------------------------------

newtype InstallerVersion = InstallerVersion { getInstallerVersion :: Version }
    deriving (Show, Eq)

instance FromJSON InstallerVersion where
    parseJSON (String version) = pure . InstallerVersion . Version $ version
    parseJSON invalid          = typeMismatch "InstallerVersion" invalid

instance ToJSON InstallerVersion where
    toJSON (InstallerVersion version) =
        toJSON $ getVersion version

------------------------------------------------------------

data Network
    = Mainnet
    | Testnet
    | Staging
    deriving (Show, Eq)

instance FromJSON Network where
    parseJSON (String "mainnet")    = pure Mainnet
    parseJSON (String "testnet")    = pure Testnet
    parseJSON (String "staging")    = pure Staging
    parseJSON (String _        )    = fail "Unknown network type! Supported are 'mainnet', 'testnet'."
    parseJSON invalid               = typeMismatch "InstallerVersion" invalid

instance ToJSON Network where
    toJSON Mainnet = toJSON @Text "mainnet"
    toJSON Testnet = toJSON @Text "testnet"
    toJSON Staging = toJSON @Text "staging"

showNetwork :: Network -> Text
showNetwork Testnet = "testnet"
showNetwork Mainnet = "mainnet"
showNetwork Staging = "staging"

------------------------------------------------------------

newtype ProductVersion = ProductVersion { getProductVersion :: Text }
    deriving (Eq)

instance Show ProductVersion where
    show pv = Universum.show $ getProductVersion pv

------------------------------------------------------------
-- Report info and instances
------------------------------------------------------------

-- | Metadata sent with report.
data ReportInfo = ReportInfo
    { rApplication :: Text
      -- ^ Application name, e.g. "explorer" or "deadalus".
    , rVersion     :: BackendVersion
      -- ^ Application version.
    , rBuild       :: Text
      -- ^ Build information.
    , rOS          :: Text
      -- ^ OS information.
    , rDate        :: UTCTime
      -- ^ Date report was created on.
    , rMagic       :: Int32
      -- ^ Cluster magic.
    , rReportType  :: ReportType
      -- ^ Type of report.
    } deriving (Show,Eq)

instance FromJSON ReportInfo where
    parseJSON (Object v) = do
        rApplication <- v .: "application"
        unless (rApplication `elem` supportedApps) $
            fail $ T.unpack $
            "ReportInfo.application should be in " <> T.intercalate ", " supportedApps
        rVersion        <- v .: "version"

        let int2Text :: Int -> Text
            int2Text = fromString . Universum.show

        rBuild <- v .: "build" <|> (int2Text <$> v .: "build")
        when (T.length rBuild > 100) $ fail "Build field length can't be longer than 100 chars"
        rOS <- v .: "os"
        when (T.length rOS > 100) $ fail "OS field length can't be longer than 100 chars"
        rDateStr <- v .: "date"
        rMagic <- v .: "magic"
        let failParseDate reason =
                fail $ "Can't parse date, should be in iso8601 format: " <>
                iso8601DateTimeFormat <> ", reason: " <> reason
        rDate <- either failParseDate pure $
            parseTimeM True defaultTimeLocale iso8601DateTimeFormat (T.unpack rDateStr)
        rReportType <- v .: "type"
        pure $ ReportInfo{..}
    parseJSON invalid    = typeMismatch "ReportInfo" invalid

instance ToJSON ReportInfo where
    toJSON ReportInfo {..} =
        object
            [ "application" .= rApplication
            , "version" .= rVersion
            , "build" .= rBuild
            , "os" .= rOS
            , "magic" .= rMagic
            , "date" .= formatTime defaultTimeLocale iso8601DateTimeFormat rDate
            , "type" .= rReportType
            ]

instance FromJSON ReportType where
    parseJSON (Object v) = (v .: "type") >>= \case
        String "crash"          -> RCrash <$> v .: "errno"
        String "error"          -> RError <$> v .: "message"
        String "misbehavior"    -> RMisbehavior <$> v .: "isCritical" <*> v .: "reason"
        String "info"           -> RInfo <$> v .: "description"
        String "customreport"   -> RCustomReport <$> v .: "email" <*> v .: "subject" <*> v .: "problem"
        String unknown          ->
            fail $ toString $ "ReportType: report 'type' " <> unknown <> " is unknown"
        other                   -> typeMismatch "ReportType.type: should be string" other

    parseJSON invalid    = typeMismatch "ReportType" invalid

-- Identity for text, more handy than disabling OverloadedStrings
idt :: Text -> Text
idt = identity

instance ToJSON ReportType where
    toJSON (RCrash errno) = object ["type" .= idt "crash", "errno" .= errno]
    toJSON (RError message) =
        object ["type" .= idt "error", "message" .= message]
    toJSON (RMisbehavior isCritical reason) =
        object
            [ "type" .= idt "misbehavior"
            , "isCritical" .= isCritical
            , "reason" .= reason
            ]
    toJSON (RInfo descr) = object ["type" .= idt "info", "description" .= descr]
    toJSON (RCustomReport email subject problem) =
        object
            [ "email"   .= email
            , "subject" .= subject
            , "problem" .= problem
            ]

-- TODO(ks): Seal Wallet?
supportedApps :: [Text]
supportedApps = ["daedalus", "seal-node", "mantis-node"]

-- YYYY-MM-DDTHH:MM:SS
iso8601DateTimeFormat :: [Char]
iso8601DateTimeFormat = iso8601DateFormat (Just "%H:%M:%S")


