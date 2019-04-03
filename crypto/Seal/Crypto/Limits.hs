
module Seal.Crypto.Limits
       ( mlAbstractHash
       , mlDecShare
       , mlEncShare
       , mlPublicKey
       , mlSecret
       , mlXSignature
       , mlSignature
       , mlVssPublicKey
       ) where

import           Universum

import qualified Seal.Crypto.Wallet as CC
import           Crypto.Hash.IO (HashAlgorithm, hashDigestSize)

import           Seal.Binary.Limit (Limit)
import           Seal.Crypto (AbstractHash, DecShare, EncShare, PublicKey,
                     Secret, Signature (..), VssPublicKey)

mlAbstractHash :: forall algo a . HashAlgorithm algo => Limit (AbstractHash algo a)
mlAbstractHash = fromIntegral (hashDigestSize (error "AbstractHash limit" :: algo) + 4)

mlDecShare :: Limit DecShare
mlDecShare = 103 --4+35+64 TODO: might be outdated

mlEncShare :: Limit EncShare
mlEncShare = 103

mlPublicKey :: Limit PublicKey
mlPublicKey = 66

mlSecret :: Limit Secret
mlSecret = 35

mlXSignature :: Limit CC.XSignature
mlXSignature = 66

mlSignature :: Limit (Signature a)
mlSignature = Signature <$> mlXSignature

mlVssPublicKey :: Limit VssPublicKey
mlVssPublicKey = 35
