{-# LANGUAGE RecordWildCards #-}

-- | Functionality related to 'Address' data type and related types.

module Seal.Core.Common.Address
       ( Address (..)
       , Address' (..)

       -- * Formatting
       , addressF
       , addressDetailedF
       , decodeTextAddress

       -- * Spending data checks
       , checkAddrSpendingData
       , checkPubKeyAddress
       , checkRedeemAddress

       -- * Encoding
       , addrToBase58
       , encodeAddr
       , encodeAddrCRC32

       -- * Utilities
       , addrAttributesUnwrapped
       , deriveLvl2KeyPair
       , deriveFirstHDAddress

       -- * Pattern-matching helpers
       , isRedeemAddress
       , isUnknownAddressType
       , isBootstrapEraDistrAddress

       -- * Construction
       , IsBootstrapEraAddr (..)
       , makeAddress
       , makeAddress'
       , makePubKeyAddress
       , makePubKeyAddressBoot
       , makeRootPubKeyAddress
       , makePubKeyHdwAddress
       , makeRedeemAddress

       , createHDAddressNH
       , createHDAddressH

       -- * Maximal sizes (needed for tx creation)
       , largestPubKeyAddressBoot
       , maxPubKeyAddressSizeBoot
       , largestPubKeyAddressSingleKey
       , maxPubKeyAddressSizeSingleKey
       , largestHDAddressBoot
       , maxHDAddressSizeBoot

       ) where

import           Universum

import           Control.Lens (makePrisms)
import qualified Data.Aeson as Aeson (FromJSON (..), FromJSONKey (..),
                     FromJSONKeyFunction (..), ToJSON (toJSON), ToJSONKey (..))
import qualified Data.Aeson.Types as Aeson (toJSONKeyText)
import qualified Data.ByteString as BS
import           Data.ByteString.Base58 (Alphabet (..),
                     decodeBase58, encodeBase58)
import           Data.Hashable (Hashable (..))
import           Data.SafeCopy (base, deriveSafeCopySimple)
import           Formatting (Format, bprint, build, builder, formatToString,
                     later, sformat, (%))
import qualified Formatting.Buildable as Buildable
import           Serokell.Data.Memory.Units (Byte)
import           Serokell.Util (listJson)
import           Text.JSON.Canonical (FromJSON (..), FromObjectKey (..),
                     JSValue (..), ReportSchemaErrors, ToJSON (..),
                     ToObjectKey (..))

import           Seal.Binary.Class (Bi (..), Encoding, biSize,
                     encodedCrcProtectedSizeExpr)
import qualified Seal.Binary.Class as Bi
import           Seal.Core.Attributes (Attributes (..), attrData, mkAttributes)
import           Seal.Core.Common.Coin ()
import           Seal.Core.Constants (accountGenesisIndex, wAddressGenesisIndex)
import           Seal.Core.NetworkMagic (NetworkMagic (..))
import           Seal.Crypto.Hashing (hashHexF)
import           Seal.Crypto.HD (HDAddressPayload, HDPassphrase,
                     ShouldCheckPassphrase (..), deriveHDPassphrase,
                     deriveHDPublicKey, deriveHDSecretKey, packHDAddressAttr)
import           Seal.Crypto.Signing (EncryptedSecretKey, PassPhrase, PublicKey,
                     RedeemPublicKey, SecretKey, deterministicKeyGen,
                     emptyPassphrase, encToPublic, noPassEncrypt)
import           Seal.Util.Json.Canonical ()
import           Seal.Util.Json.Parse (tryParseString)
import           Seal.Util.Util (toAesonError)

import           Seal.Core.Common.AddrAttributes
import           Seal.Core.Common.AddressHash
import           Seal.Core.Common.AddrSpendingData
import           Seal.Core.Common.AddrStakeDistribution
import           Seal.Core.Common.AddrCategory

-- | Hash of this data is stored in 'Address'. This type exists mostly
-- for internal usage.
newtype Address' = Address'
    { unAddress' :: (AddrType, AddrSpendingData, Attributes AddrAttributes)
    } deriving (Eq, Show, Generic, Typeable, Bi)
    -- TODO: We are deriving 'Bi' via 'GeneralizedNewtypeDeriving'. This is
    -- enabled in the Cabal file. It would be *very bad* if we switched to
    -- @DeriveAnyClass@ and it was derived via the 'Generic' class instead.
    --
    -- When we upgrade to GHC 8.2, we can use @DerivingStrategies@ to write:
    -- @
    -- newtype Address' = Address' { ... }
    --     deriving stock (Eq, Show, Generic, Typeable)
    --     deriving newtype (Bi)
    -- @

-- | 'Address' is where you can send coins.
data Address = Address
    { addrRoot       :: !(AddressHash Address')
    -- ^ Root of imaginary pseudo Merkle tree stored in this address.
    , addrAttributes :: !(Attributes AddrAttributes)
    -- ^ Attributes associated with this address.
    , addrType       :: !AddrType
    -- ^ The type of this address. Should correspond to
    -- 'AddrSpendingData', but it can't be checked statically, because
    -- spending data is hashed.
    } deriving (Eq, Ord, Generic, Typeable, Show)

instance NFData Address

instance Bi Address where
    encode Address{..} =
        case categoryM of 
            Nothing -> Bi.encodeCrcProtectedRaw (addrRoot, addrAttributes, addrType)
            Just _  -> Bi.encodeCrcProtected (addrRoot, addrAttributes, addrType)
      where
        categoryM = aaCategory $ attrData addrAttributes 

    decode = do
        (addrRoot, addrAttributes, addrType) <- Bi.decodeCrcProtected
        let res = Address {..}
        pure res

    encodedSizeExpr size pxy =
        encodedCrcProtectedSizeExpr size ( (,,) <$> (addrRoot       <$> pxy)
                                                <*> (addrAttributes <$> pxy)
                                                <*> (addrType       <$> pxy) )

instance Buildable [Address] where
    build = bprint listJson

instance Hashable Address where
    hashWithSalt s = hashWithSalt s . Bi.serialize

instance Monad m => ToObjectKey m Address where
    toObjectKey = pure . formatToString addressF

instance ReportSchemaErrors m => FromObjectKey m Address where
    fromObjectKey = fmap Just . tryParseString decodeTextAddress . JSString

instance Monad m => ToJSON m Address where
    toJSON = fmap JSString . toObjectKey

instance ReportSchemaErrors m => FromJSON m Address where
    fromJSON = tryParseString decodeTextAddress

instance Aeson.FromJSONKey Address where
    fromJSONKey = Aeson.FromJSONKeyTextParser (toAesonError . decodeTextAddress)

instance Aeson.ToJSONKey Address where
    toJSONKey = Aeson.toJSONKeyText (sformat addressF)

instance Aeson.FromJSON Address where
    parseJSON = toAesonError . decodeTextAddress <=< Aeson.parseJSON

instance Aeson.ToJSON Address where
    toJSON = Aeson.toJSON . sformat addressF

----------------------------------------------------------------------------
-- Formatting, pretty-printing
----------------------------------------------------------------------------

-- | A formatter showing guts of an 'Address'.
addressDetailedF :: Format r (Address -> r)
addressDetailedF =
    later $ \Address {..} ->
        bprint (builder%" address with root "%hashHexF%", attributes: "%build)
            (formattedType addrType) addrRoot addrAttributes
  where
    formattedType =
        \case
            ATPubKey      -> "PubKey"
            ATRedeem      -> "Redeem"
            ATUnknown tag -> "Unknown#" <> Buildable.build tag

-- | Currently we gonna use Bitcoin alphabet for representing addresses in
-- base58
addrAlphabet :: Alphabet
addrAlphabet = "1234S6789GBCDjxAHJmYMNPQR5TUVWXLZabcdefghiEkKnopqrstuvwFyz"

mobileDeviceAlphabet :: Alphabet
mobileDeviceAlphabet = "123m56789nBCDHSGEJKtMdPQRFTUVWXYZabcNefghijk4AopqrsLuvwxyz"

userAccountAlphabet :: Alphabet
userAccountAlphabet = "123u56789nBCDHSGEJKtMaPQRFTUVWXYZNbcdefghijkmAopqrsL4vwxyz"

addrToBase58 :: Address -> ByteString
addrToBase58 addr@Address{addrAttributes = Attributes{attrData = AddrAttributes{aaCategory = Just ACMobile}}} = 
    encodeBase58 mobileDeviceAlphabet $ Bi.serialize' addr
addrToBase58 addr@Address{addrAttributes = Attributes{attrData = AddrAttributes{aaCategory = Just ACUserAccount}}} = 
    encodeBase58 userAccountAlphabet $ Bi.serialize' addr
addrToBase58 addr = encodeBase58 addrAlphabet $ Bi.serialize' addr

instance Buildable Address where
    build = Buildable.build . decodeUtf8 @Text . addrToBase58

-- | Specialized formatter for 'Address'.
addressF :: Format r (Address -> r)
addressF = build

-- | A function which decodes base58-encoded 'Address'.
decodeTextAddress :: Text -> Either Text Address
decodeTextAddress textAddr
        | "SEALmd" `isPrefixOf` strAddr = do 
            addr <- decodeAddress mobileDeviceAlphabet
            checkAddrCategory ACMobile addr
        | "SEALua" `isPrefixOf` strAddr = do 
            addr <- decodeAddress userAccountAlphabet
            checkAddrCategory ACUserAccount addr
        | otherwise                     = decodeAddress addrAlphabet
    where
        strAddr = toString textAddr

        decodeAddress :: Alphabet -> Either Text Address
        decodeAddress alphabet = do
            let base58Err = "Invalid base58 representation of address"
            let bs = encodeUtf8 textAddr
            dbs <- maybeToRight base58Err $ decodeBase58 alphabet bs
            Bi.decodeFull' dbs
 
        checkAddrCategory :: AddrCategory -> Address -> Either Text Address 
        checkAddrCategory expectedCategory addr = 
                case (getCategory addr)  of 
                    Nothing       -> Left mismatchErr 
                    Just category -> if | category == expectedCategory -> Right addr
                                        | otherwise                    -> Left mismatchErr
            where 
                getCategory = aaCategory . attrData . addrAttributes
                mismatchErr = "Category of address mismatch"

----------------------------------------------------------------------------
-- Constructors
----------------------------------------------------------------------------
{-# ANN makeAddress  ("HLint: ignore Reduce duplication" :: Text) #-}
{-# ANN makeAddress' ("HLint: ignore Reduce duplication" :: Text) #-}

-- | Make an 'Address' from spending data and attributes.
makeAddress :: AddrSpendingData -> AddrAttributes -> Address
makeAddress spendingData attributesUnwrapped =
    Address
    { addrRoot = addressHash address'
    , addrAttributes = attributes
    , addrType = addrType'
    }
  where
    addrType' = addrSpendingDataToType spendingData
    attributes = mkAttributes attributesUnwrapped
    address' = Address' (addrType', spendingData, attributes)

-- | Make an 'Address'' from spending data and attributes.
makeAddress' :: AddrSpendingData -> AddrAttributes -> Address'
makeAddress' spendingData attributesUnwrapped = address'
  where
    addrType' = addrSpendingDataToType spendingData
    attributes = mkAttributes attributesUnwrapped
    address' = Address' (addrType', spendingData, attributes)

-- | This newtype exists for clarity. It is used to tell pubkey
-- address creation functions whether an address is intended for
-- bootstrap era.
newtype IsBootstrapEraAddr = IsBootstrapEraAddr Bool

-- | A function for making an address from 'PublicKey'.
makePubKeyAddress :: NetworkMagic -> IsBootstrapEraAddr -> PublicKey -> Address
makePubKeyAddress nm = makePubKeyAddressImpl nm Nothing

-- | A function for making an address from 'PublicKey' for bootstrap era.
makePubKeyAddressBoot :: NetworkMagic -> PublicKey -> Address
makePubKeyAddressBoot nm = makePubKeyAddress nm (IsBootstrapEraAddr True)

-- | This function creates a root public key address. Stake
-- distribution doesn't matter for root addresses because by design
-- nobody should even use these addresses as outputs, so we can put
-- arbitrary distribution there. We use bootstrap era distribution
-- because its representation is more compact.
makeRootPubKeyAddress :: NetworkMagic -> PublicKey -> Address
makeRootPubKeyAddress = makePubKeyAddressBoot

-- | A function for making an HDW address.
makePubKeyHdwAddress
    :: NetworkMagic
    -> IsBootstrapEraAddr
    -> HDAddressPayload    -- ^ Derivation path
    -> PublicKey
    -> Address
makePubKeyHdwAddress nm ibe path = makePubKeyAddressImpl nm (Just path) ibe

makePubKeyAddressImpl
    :: NetworkMagic
    -> Maybe HDAddressPayload
    -> IsBootstrapEraAddr
    -> PublicKey
    -> Address
makePubKeyAddressImpl _ path (IsBootstrapEraAddr isBootstrapEra) key =
    makeAddress spendingData attrs
  where
    spendingData = PubKeyASD key
    distr
        | isBootstrapEra = BootstrapEraDistr
        | otherwise = SingleKeyDistr (addressHash key)
    attrs =
        AddrAttributes { aaStakeDistribution = distr
                       , aaPkDerivationPath = path
                       , aaCategory = Nothing
                       }

-- | A function for making an address from 'RedeemPublicKey'.
makeRedeemAddress :: NetworkMagic -> RedeemPublicKey -> Address
makeRedeemAddress _ key = makeAddress spendingData attrs
  where
    spendingData = RedeemASD key
    attrs =
        AddrAttributes { aaStakeDistribution = BootstrapEraDistr
                       , aaPkDerivationPath = Nothing
                       , aaCategory = Nothing
                       }

-- | Create address from secret key in hardened way.
createHDAddressH
    :: NetworkMagic
    -> IsBootstrapEraAddr
    -> ShouldCheckPassphrase
    -> PassPhrase
    -> HDPassphrase
    -> EncryptedSecretKey
    -> [Word32]
    -> Word32
    -> Maybe (Address, EncryptedSecretKey)
createHDAddressH nm ibea scp passphrase hdPassphrase parent parentPath childIndex = do
    derivedSK <- deriveHDSecretKey scp passphrase parent childIndex
    let addressPayload = packHDAddressAttr hdPassphrase $ parentPath ++ [childIndex]
    let pk = encToPublic derivedSK
    return (makePubKeyHdwAddress nm ibea addressPayload pk, derivedSK)

-- | Create address from public key via non-hardened way.
createHDAddressNH
    :: NetworkMagic
    -> IsBootstrapEraAddr
    -> HDPassphrase
    -> PublicKey
    -> [Word32]
    -> Word32
    -> (Address, PublicKey)
createHDAddressNH nm ibea passphrase parent parentPath childIndex = do
    let derivedPK = deriveHDPublicKey parent childIndex
    let addressPayload = packHDAddressAttr passphrase $ parentPath ++ [childIndex]
    (makePubKeyHdwAddress nm ibea addressPayload derivedPK, derivedPK)

----------------------------------------------------------------------------
-- Checks
----------------------------------------------------------------------------

-- | Check whether given 'AddrSpendingData' corresponds to given
-- 'Address'.
checkAddrSpendingData :: AddrSpendingData -> Address -> Bool
checkAddrSpendingData asd Address {..} =
    addrRoot == addressHash address' && addrType == addrSpendingDataToType asd
  where
    address' = Address' (addrType, asd, addrAttributes)

-- | Check if given 'Address' is created from given 'PublicKey'
checkPubKeyAddress :: PublicKey -> Address -> Bool
checkPubKeyAddress pk = checkAddrSpendingData (PubKeyASD pk)

-- | Check if given 'Address' is created from given 'RedeemPublicKey'
checkRedeemAddress :: RedeemPublicKey -> Address -> Bool
checkRedeemAddress rpk = checkAddrSpendingData (RedeemASD rpk)

----------------------------------------------------------------------------
-- Utils
----------------------------------------------------------------------------

-- | Get 'AddrAttributes' from 'Address'.
addrAttributesUnwrapped :: Address -> AddrAttributes
addrAttributesUnwrapped = attrData . addrAttributes

-- | Makes account secret key for given wallet set.
deriveLvl2KeyPair
    :: NetworkMagic
    -> IsBootstrapEraAddr
    -> ShouldCheckPassphrase
    -> PassPhrase
    -> EncryptedSecretKey -- ^ key of wallet
    -> Word32 -- ^ account derivation index
    -> Word32 -- ^ address derivation index
    -> Maybe (Address, EncryptedSecretKey)
deriveLvl2KeyPair nm ibea scp passphrase wsKey accountIndex addressIndex = do
    wKey <- deriveHDSecretKey scp passphrase wsKey accountIndex
    let hdPass = deriveHDPassphrase $ encToPublic wsKey
    -- We don't need to check passphrase twice
    createHDAddressH nm ibea (ShouldCheckPassphrase False) passphrase hdPass wKey [accountIndex] addressIndex

deriveFirstHDAddress
    :: NetworkMagic
    -> IsBootstrapEraAddr
    -> PassPhrase
    -> EncryptedSecretKey -- ^ key of wallet set
    -> Maybe (Address, EncryptedSecretKey)
deriveFirstHDAddress nm ibea passphrase wsKey =
    deriveLvl2KeyPair nm ibea (ShouldCheckPassphrase False) passphrase wsKey accountGenesisIndex wAddressGenesisIndex

----------------------------------------------------------------------------
-- Pattern-matching helpers
----------------------------------------------------------------------------

-- | Check whether an 'Address' is redeem address.
isRedeemAddress :: Address -> Bool
isRedeemAddress Address {..} =
    case addrType of
        ATRedeem -> True
        _        -> False

isUnknownAddressType :: Address -> Bool
isUnknownAddressType Address {..} =
    case addrType of
        ATUnknown {} -> True
        _            -> False

-- | Check whether an 'Address' has bootstrap era stake distribution.
isBootstrapEraDistrAddress :: Address -> Bool
isBootstrapEraDistrAddress (addrAttributesUnwrapped -> AddrAttributes {..}) =
    case aaStakeDistribution of
        BootstrapEraDistr -> True
        _                 -> False

----------------------------------------------------------------------------
-- Maximal size
----------------------------------------------------------------------------

-- | Largest (considering size of serialized data) PubKey address with
-- BootstrapEra distribution. Actual size depends on CRC32 value which
-- is serialized using var-length encoding.
largestPubKeyAddressBoot :: NetworkMagic -> Address
largestPubKeyAddressBoot nm = makePubKeyAddressBoot nm goodPk

-- | Maximal size of PubKey address with BootstrapEra
-- distribution (43).
maxPubKeyAddressSizeBoot :: NetworkMagic -> Byte
maxPubKeyAddressSizeBoot = biSize . largestPubKeyAddressBoot

-- | Largest (considering size of serialized data) PubKey address with
-- SingleKey distribution. Actual size depends on CRC32 value which
-- is serialized using var-length encoding.
largestPubKeyAddressSingleKey :: NetworkMagic -> Address
largestPubKeyAddressSingleKey nm =
    makePubKeyAddress nm (IsBootstrapEraAddr False) goodPk

-- | Maximal size of PubKey address with SingleKey
-- distribution (78).
maxPubKeyAddressSizeSingleKey :: NetworkMagic -> Byte
maxPubKeyAddressSizeSingleKey = biSize . largestPubKeyAddressSingleKey

-- | Largest (considering size of serialized data) HD address with
-- BootstrapEra distribution. Actual size depends on CRC32 value which
-- is serialized using var-length encoding.
largestHDAddressBoot :: NetworkMagic -> Address
largestHDAddressBoot nm =
    case deriveLvl2KeyPair
             nm
             (IsBootstrapEraAddr True)
             (ShouldCheckPassphrase False)
             emptyPassphrase
             encSK
             maxBound
             maxBound of
        Nothing        -> error "largestHDAddressBoot failed"
        Just (addr, _) -> addr
  where
    encSK = noPassEncrypt goodSk

-- | Maximal size of HD address with BootstrapEra
-- distribution (76).
maxHDAddressSizeBoot :: NetworkMagic -> Byte
maxHDAddressSizeBoot = biSize . largestHDAddressBoot

-- Public key and secret key for which we know that they produce
-- largest addresses in all cases we are interested in. It was checked
-- manually.
goodSkAndPk :: (PublicKey, SecretKey)
goodSkAndPk = deterministicKeyGen $ BS.replicate 32 0

goodPk :: PublicKey
goodPk = fst goodSkAndPk

goodSk :: SecretKey
goodSk = snd goodSkAndPk


-- Encodes the `Address` __without__ the CRC32.
-- It's important to keep this function separated from the `encode`
-- definition to avoid that `encode` would call `crc32` and
-- the latter invoke `crc32Update`, which would then try to call `encode`
-- indirectly once again, in an infinite loop.
encodeAddr :: Address -> Encoding
encodeAddr Address {..} =
    encode addrRoot <> encode addrAttributes <> encode addrType

encodeAddrCRC32 :: Address -> Encoding
encodeAddrCRC32 Address{..} =
        case categoryM of 
            Nothing -> Bi.encodeCrcProtectedRaw (addrRoot, addrAttributes, addrType)
            Just _  -> Bi.encodeCrcProtected (addrRoot, addrAttributes, addrType)
      where
        categoryM = aaCategory $ attrData addrAttributes 

makePrisms ''Address

deriveSafeCopySimple 0 'base ''Address'
deriveSafeCopySimple 0 'base ''Address
