module Seal.Chain.Ssc.Proof
       ( SscProof (..)
       , mkSscProof
       , VssCertificatesHash
       ) where

import           Universum

import           Data.SafeCopy (base, deriveSafeCopySimple)
import           Fmt (genericF)
import qualified Formatting.Buildable as Buildable

import           Seal.Binary.Class (Cons (..), Field (..), deriveIndexedBi)
import           Seal.Core.Common (StakeholderId)
import           Seal.Crypto (Hash, hash)

import           Seal.Chain.Ssc.CommitmentsMap
import           Seal.Chain.Ssc.OpeningsMap
import           Seal.Chain.Ssc.Payload
import           Seal.Chain.Ssc.SharesMap
import           Seal.Chain.Ssc.VssCertificate
import           Seal.Chain.Ssc.VssCertificatesMap
import           Seal.Util.Util (cborError)

-- Note: we can't use 'VssCertificatesMap', because we serialize it as
-- a 'HashSet', but in the very first version of mainnet this map was
-- serialized as a 'HashMap' (and 'VssCertificatesMap' was just a type
-- alias for that 'HashMap').
--
-- Alternative approach would be to keep 'instance Bi VssCertificatesMap'
-- the same as it was in mainnet.
type VssCertificatesHash = Hash (HashMap StakeholderId VssCertificate)

-- | Proof that SSC payload is correct (it's included into block header)
data SscProof
    = CommitmentsProof
        !(Hash CommitmentsMap)
        !VssCertificatesHash
    | OpeningsProof
        !(Hash OpeningsMap)
        !VssCertificatesHash
    | SharesProof
        !(Hash SharesMap)
        !VssCertificatesHash
    | CertificatesProof
        !VssCertificatesHash
    deriving (Eq, Show, Generic)

instance Buildable SscProof where
    build = genericF

instance NFData SscProof

-- | Create proof (for inclusion into block header) from 'SscPayload'.
mkSscProof :: SscPayload -> SscProof
mkSscProof payload =
    case payload of
        CommitmentsPayload comms certs ->
            proof CommitmentsProof comms certs
        OpeningsPayload openings certs ->
            proof OpeningsProof openings certs
        SharesPayload shares certs     ->
            proof SharesProof shares certs
        CertificatesPayload certs      ->
            CertificatesProof (hash $ getVssCertificatesMap certs)
  where
    proof constr hm (getVssCertificatesMap -> certs) =
        constr (hash hm) (hash certs)

-- TH-generated instances go to the end of the file

deriveIndexedBi ''SscProof [
    Cons 'CommitmentsProof [
        Field [| 0 :: Hash CommitmentsMap |],
        Field [| 1 :: VssCertificatesHash |] ],
    Cons 'OpeningsProof [
        Field [| 0 :: Hash OpeningsMap    |],
        Field [| 1 :: VssCertificatesHash |] ],
    Cons 'SharesProof [
        Field [| 0 :: Hash SharesMap      |],
        Field [| 1 :: VssCertificatesHash |] ],
    Cons 'CertificatesProof [
        Field [| 0 :: VssCertificatesHash |] ]
    ]

deriveSafeCopySimple 0 'base ''SscProof
