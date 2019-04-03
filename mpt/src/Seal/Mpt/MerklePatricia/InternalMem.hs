{-# LANGUAGE OverloadedStrings #-}

module Seal.Mpt.MerklePatricia.InternalMem 
 ( MPMem(..)
 , unsafePutKeyValMem
 , unsafeGetKeyValsMem
 , unsafeGetAllKeyValsMem
 , unsafeDeleteKeyMem
 , getNodeDataMem
 , putNodeDataMem
 , MPKey
 , MPVal
 , keyToSafeKeyMem
 ) where

import           Universum hiding(map)
import qualified Data.ByteString as B
import           Data.ByteArray (convert)
import           Crypto.Hash as Crypto
import           Data.List
import qualified Data.Map as Map
import           Data.Maybe
import qualified Data.NibbleString as N

import           Seal.Binary.Class (serialize', decodeFull')

import           Seal.Mpt.MerklePatricia.NodeData
import           Seal.Mpt.MerklePatricia.StateRoot
import           Seal.Mpt.MerklePatricia.Utils

type MPMap = Map.Map B.ByteString B.ByteString

data MPMem = MPMem {
    mpMap       :: MPMap,
    mpStateRoot :: StateRoot
  } deriving Show


unsafePutKeyValMem::Monad m=>MPMem->MPKey->MPVal->m MPMem
unsafePutKeyValMem db key val = do
  dbNodeData <- getNodeDataMem db (PtrRef $ mpStateRoot db)
  dbPutNodeData <- putKV_NodeDataMem db key val dbNodeData
  putNodeDataMem (fst dbPutNodeData) (snd dbPutNodeData)

unsafeGetKeyValsMem::Monad m=>MPMem->MPKey->m [(MPKey,MPVal)]
unsafeGetKeyValsMem db =
  let dbNodeRef = PtrRef $ mpStateRoot db
  in getKeyVals_NodeRefMem db dbNodeRef

unsafeGetAllKeyValsMem::Monad m=>MPMem->m [(MPKey,MPVal)]
unsafeGetAllKeyValsMem db = unsafeGetKeyValsMem db N.empty

unsafeDeleteKeyMem::Monad m=>MPMem->MPKey->m MPMem
unsafeDeleteKeyMem db key = do
  dbNodeData <- getNodeDataMem db (PtrRef $ mpStateRoot db)
  dbDeleteNodeData <- deleteKey_NodeDataMem db key dbNodeData
  putNodeDataMem (fst dbDeleteNodeData) (snd dbDeleteNodeData)

keyToSafeKeyMem::N.NibbleString->N.NibbleString
keyToSafeKeyMem key =
  N.EvenNibbleString . convert $ (Crypto.hash keyByteString :: Crypto.Digest Crypto.Keccak_256)
  where
    N.EvenNibbleString keyByteString = key

-----

putKV_NodeDataMem::Monad m=>MPMem->MPKey->MPVal->NodeData-> m (MPMem,NodeData)

putKV_NodeDataMem db key val EmptyNodeData =
  return $ (db,ShortcutNodeData key (Right val))

putKV_NodeDataMem db key val (FullNodeData options nodeValue)
  | options `slotIsEmpty` N.head key =
    do
      tailNode <- newShortcutMem db (N.tail key) $ Right val
      return $ (fst tailNode, FullNodeData (replace options (N.head key) (snd tailNode)) nodeValue)

  | otherwise =
      do
        let conflictingNodeRef = options!!fromIntegral (N.head key)
        newNode <- putKV_NodeRefMem db (N.tail key) val conflictingNodeRef
        return $ (fst newNode, FullNodeData (replace options (N.head key) (snd newNode)) nodeValue)

putKV_NodeDataMem db key1 val1 (ShortcutNodeData key2 val2)
  | key1 == key2 =
    case val2 of
      Right _  -> return $ (db, ShortcutNodeData key1 $ Right val1)
      Left ref -> do
        newNodeRef <- putKV_NodeRefMem db key1 val1 ref
        return $ (fst newNodeRef, ShortcutNodeData key2 (Left . snd $ newNodeRef))

  | N.null key1 = do
      newNodeRef <- newShortcutMem db (N.tail key2) val2
      return $ (fst newNodeRef, FullNodeData (list2Options 0 [(N.head key2, snd newNodeRef)]) $ Just val1)

  | key1 `N.isPrefixOf` key2 = do
      tailNode <- newShortcutMem db (N.drop (N.length key1) key2) val2
      modifiedTailNode <- putKV_NodeRefMem (fst tailNode) "" val1 (snd tailNode)
      return $ (fst modifiedTailNode, ShortcutNodeData key1 $ Left (snd modifiedTailNode))

  | key2 `N.isPrefixOf` key1 =
    case val2 of
      Right val -> putKV_NodeDataMem db key2 val (ShortcutNodeData key1 $ Right val1)
      Left ref  -> do
        newNode <- putKV_NodeRefMem db (N.drop (N.length key2) key1) val1 ref
        return $ (fst newNode, ShortcutNodeData key2 $ Left (snd newNode))

  | N.head key1 == N.head key2 =
    let (commonPrefix, suffix1, suffix2) =
          getCommonPrefix (N.unpack key1) (N.unpack key2)
    in do
      nodeAfterCommonBeforePut <- newShortcutMem db (N.pack suffix2) val2
      nodeAfterCommon <- putKV_NodeRefMem (fst nodeAfterCommonBeforePut)
                                          (N.pack suffix1)
                                          val1
                                          (snd nodeAfterCommonBeforePut)

      return $ (fst nodeAfterCommon,
                ShortcutNodeData (N.pack commonPrefix) $ Left (snd nodeAfterCommon))

  | otherwise = do
      tailNode1 <- newShortcutMem db (N.tail key1) $ Right val1
      tailNode2 <- newShortcutMem (fst tailNode1) (N.tail key2) val2
      return $ (fst tailNode2, FullNodeData
          (list2Options 0 $ sortBy (compare `on` fst) [(N.head key1, snd tailNode1),
                                                       (N.head key2, snd tailNode2)])
           Nothing)

-----

getKeyVals_NodeDataMem::Monad m=>MPMem->NodeData->MPKey->m [(MPKey, MPVal)]

getKeyVals_NodeDataMem _ EmptyNodeData _ = return []

getKeyVals_NodeDataMem db (FullNodeData {choices=cs}) "" = do
  partialKVs <- sequence $ (\ref -> getKeyVals_NodeRefMem db ref "") <$> cs
  return $ concatMap
    (uncurry $ map . (prependToKey . N.singleton)) (zip [0..] partialKVs)

getKeyVals_NodeDataMem db (FullNodeData {choices=cs}) key
  | ref == emptyRef = return []
  | otherwise = fmap (prependToKey $ N.singleton $ N.head key) <$>
                getKeyVals_NodeRefMem db ref (N.tail key)
  where ref = cs !! fromIntegral (N.head key)

getKeyVals_NodeDataMem db ShortcutNodeData{nextNibbleString=s, nextVal=Left ref} key
  | key `N.isPrefixOf` s = prependNext ""
  | s `N.isPrefixOf` key = prependNext $ N.drop (N.length s) key
  | otherwise = return []
  where prependNext key' = fmap (prependToKey s) <$> getKeyVals_NodeRefMem db ref key'

getKeyVals_NodeDataMem _ ShortcutNodeData{nextNibbleString=s, nextVal=Right val} key =
  return $
    if key `N.isPrefixOf` s
    then [(s,val)]
    else []

-----

deleteKey_NodeDataMem::Monad m=>MPMem->MPKey->NodeData-> m (MPMem,NodeData)

deleteKey_NodeDataMem db _ EmptyNodeData = return (db,EmptyNodeData)

deleteKey_NodeDataMem db key nd@(FullNodeData options val)
  | N.null key = return $ (db,FullNodeData options Nothing)

  | options `slotIsEmpty` N.head key = return (db,nd)

  | otherwise = do
    let nodeRef = options!!fromIntegral (N.head key)
    newNodeRef <- deleteKey_NodeRefMem db (N.tail key) nodeRef
    let newOptions = replace options (N.head key) (snd newNodeRef)
    simplify_NodeDataMem db $ FullNodeData newOptions val

deleteKey_NodeDataMem db key1 nd@(ShortcutNodeData key2 (Right _)) =
  return $
    if key1 == key2
    then (db,EmptyNodeData)
    else (db,nd)

deleteKey_NodeDataMem db key1 nd@(ShortcutNodeData key2 (Left ref))
  | key2 `N.isPrefixOf` key1 = do
    newNodeRef <- deleteKey_NodeRefMem db (N.drop (N.length key2) key1) ref
    simplify_NodeDataMem (fst newNodeRef) $ ShortcutNodeData key2 $ Left (snd newNodeRef)

  | otherwise = return (db, nd)

-----

putKV_NodeRefMem::Monad m=>MPMem->MPKey->MPVal->NodeRef->m (MPMem,NodeRef)
putKV_NodeRefMem db key val nodeRef = do
  nodeData <- getNodeDataMem db nodeRef
  db' <- putKV_NodeDataMem db key val nodeData
  nodeData2NodeRefMem (fst db') (snd db')


getKeyVals_NodeRefMem::Monad m=>MPMem->NodeRef->MPKey->m [(MPKey, MPVal)]
getKeyVals_NodeRefMem db ref key = do
  nodeData <- getNodeDataMem db ref
  getKeyVals_NodeDataMem db nodeData key

--TODO- This is looking like a lift, I probably should make NodeRef some sort of MonadFail....

deleteKey_NodeRefMem::Monad m=>MPMem->MPKey->NodeRef->m (MPMem,NodeRef)
deleteKey_NodeRefMem db key nodeRef = do
  ref <- getNodeDataMem db nodeRef
  db'<- deleteKey_NodeDataMem db key ref

  nodeData2NodeRefMem (fst db') ref

-----

bytes2NodeData::Monad m => B.ByteString->m NodeData
bytes2NodeData bytes | B.null bytes = return $ EmptyNodeData
bytes2NodeData bytes = assertEitherSuccess $ decodeFull' $ B.pack $ B.unpack bytes


getNodeDataMem::Monad m=>MPMem->NodeRef->m NodeData
getNodeDataMem _ (SmallRef x) = assertEitherSuccess $ decodeFull' x
--getNodeDataMem db (PtrRef ptr@(StateRoot p)) = do
getNodeDataMem db (PtrRef (StateRoot p)) = do
  --let bytes = fromMaybe (error $ "Missing StateRoot in call to getNodeData: " ++ formatStateRoot ptr)
  let bytes =  fromJust                  (Map.lookup p (mpMap db))

  bytes2NodeData bytes

putNodeDataMem::Monad m=>MPMem->NodeData->m MPMem
putNodeDataMem db nd = do
  let bytes = serialize' nd
      ptr = convert (Crypto.hash bytes :: Crypto.Digest Crypto.Keccak_256)
      map' = Map.insert ptr bytes (mpMap db)
  return $ MPMem { mpMap = map', mpStateRoot = StateRoot ptr }


simplify_NodeDataMem::Monad m=>MPMem->NodeData->m (MPMem,NodeData)
simplify_NodeDataMem db EmptyNodeData = return (db,EmptyNodeData)
simplify_NodeDataMem db nd@(ShortcutNodeData key (Left ref)) = do
  refNodeData <- getNodeDataMem db ref
  case refNodeData of
    (ShortcutNodeData key2 v2) -> return $ (db,ShortcutNodeData (key `N.append` key2) v2)
    _                          -> return (db,nd)
simplify_NodeDataMem db (FullNodeData options Nothing) = do
    case options2List options of
      [(n, nodeRef)] ->
          simplify_NodeDataMem db $ ShortcutNodeData (N.singleton n) $ Left nodeRef
      _ -> return $ (db,FullNodeData options Nothing)
simplify_NodeDataMem db x = return (db,x)

newShortcutMem::Monad m=>MPMem->MPKey->Either NodeRef MPVal->m (MPMem,NodeRef)
newShortcutMem db "" (Left ref) = return (db,ref)
newShortcutMem db key val       = nodeData2NodeRefMem db $ ShortcutNodeData key val

nodeData2NodeRefMem::Monad m=>MPMem->NodeData->m (MPMem,NodeRef)
nodeData2NodeRefMem db nodeData =
  case serialize' nodeData of
    bytes | B.length bytes < 32 -> return $ (db,SmallRef bytes)
    _ -> do
      new <- putNodeDataMem db nodeData
      return (new, PtrRef . mpStateRoot $ new)

list2Options::N.Nibble->[(N.Nibble, NodeRef)]->[NodeRef]
list2Options start [] = replicate (fromIntegral $ 0x10 - start) emptyRef
list2Options start x | start > 15 =
  error $
  "value of 'start' in list2Option is greater than 15, it is: " <> show start
  <> ", second param is " <> show x
list2Options start ((firstNibble, firstPtr):rest) =
    replicate (fromIntegral $ firstNibble - start) emptyRef ++ [firstPtr] ++ list2Options (firstNibble+1) rest

options2List::[NodeRef]->[(N.Nibble, NodeRef)]
options2List theList = filter ((/= emptyRef) . snd) $ zip [0..] theList

prependToKey::MPKey->(MPKey, MPVal)->(MPKey, MPVal)
prependToKey prefix (key, val) = (prefix `N.append` key, val)

replace::Integral i=>[a]->i->a->[a]
replace lst i newVal = left ++ [newVal] ++ right
            where
              (left, _:right) = splitAt (fromIntegral i) lst

slotIsEmpty::[NodeRef]->N.Nibble->Bool
slotIsEmpty [] _ =
  error "slotIsEmpty was called for value greater than the size of the list"
slotIsEmpty (x:_) 0 | x == emptyRef = True
slotIsEmpty _ 0 = False
slotIsEmpty (_:rest) n = slotIsEmpty rest (n-1)


getCommonPrefix::Eq a=>[a]->[a]->([a], [a], [a])
getCommonPrefix (c1:rest1) (c2:rest2)
  | c1 == c2 = prefixTheCommonPrefix c1 (getCommonPrefix rest1 rest2)
  where
    prefixTheCommonPrefix c (p, x, y) = (c:p, x, y)
getCommonPrefix x y = ([], x, y)

