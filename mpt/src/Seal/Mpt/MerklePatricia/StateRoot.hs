{-# LANGUAGE DeriveGeneric              #-}
{-# LANGUAGE TypeApplications           #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE OverloadedStrings          #-}

module Seal.Mpt.MerklePatricia.StateRoot 
 ( StateRoot(..)
 , emptyTriePtr
 , sha2StateRoot
 , unboxStateRoot
 , formatStateRoot
 ) where

import           Universum hiding (get, put, sequence_, decodeUtf8)

import           Control.Monad
import           Crypto.Hash as Crypto
import qualified Data.ByteString.Base16 as B16
import           Data.ByteArray (convert)

import           Data.Binary hiding(decode,encode)
import qualified Data.ByteString as B
import qualified Data.Text as T
import           Data.Text.Encoding (decodeUtf8)

import           Seal.Binary.Class 

-- | Internal nodes are indexed in the underlying database by their 256-bit SHA3 hash.
-- This types represents said hash.
--
-- The stateRoot is of this type,
-- (ie- the pointer to the full set of key/value pairs at a particular time in history), and
-- will be of interest if you need to refer to older or parallel version of the data.

newtype StateRoot = StateRoot B.ByteString deriving (Show, Eq, Read, Generic, IsString)

formatStateRoot :: StateRoot -> String
formatStateRoot (StateRoot sr) = T.unpack .  decodeUtf8 . B16.encode $ sr

instance Binary StateRoot where
  put (StateRoot x) = sequence_ $ put <$> B.unpack x
  get = StateRoot <$> B.pack <$> replicateM 32 get
{-  
instance Bi StateRoot where
  encode = genericEncode
  decode = genericDecode
-}      

instance Bi StateRoot where
    encode (StateRoot x) = encode x
    decode = StateRoot <$> decode

  
{-instance RLPSerializable StateRoot where
    rlpEncode (StateRoot x) = rlpEncode x
    rlpDecode x = StateRoot $ rlpDecode x-}


-- | The stateRoot of the empty database.
emptyTriePtr::StateRoot
emptyTriePtr =
  let root = 0::Integer
      rootHash = convert $ (Crypto.hash . serialize' $ root :: Crypto.Digest Crypto.Keccak_256)
  in StateRoot rootHash
{--
emptyTriePtr::StateRoot
emptyTriePtr =
  let root = rlpEncode (0::Integer)
      rootHash = convert $ (Crypto.hash . rlpSerialize $ root :: Crypto.Digest Crypto.Keccak_256)
  in StateRoot rootHash
--}

sha2StateRoot::Digest Crypto.Keccak_256 -> StateRoot
sha2StateRoot = StateRoot . convert

unboxStateRoot :: StateRoot -> B.ByteString
unboxStateRoot (StateRoot b) = b
