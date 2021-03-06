{-# LANGUAGE FlexibleContexts      #-}
{-# LANGUAGE FlexibleInstances     #-}
{-# LANGUAGE LambdaCase            #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE RankNTypes            #-}
{-# LANGUAGE RecordWildCards       #-}
{-# LANGUAGE TypeApplications      #-}

module Main where

import           Control.Applicative (empty)
import           Control.Concurrent (threadDelay)
import           Control.Exception (throwIO)
import           Control.Exception.Safe (throwString)
import           Control.Monad (unless)

import           Data.Functor.Contravariant (contramap)
import           Data.Text (Text)
import           GHC.IO.Encoding (setLocaleEncoding, utf8)
import           Options.Applicative.Simple (simpleOptions)
import           System.Random (mkStdGen)

import           Bench.Network.Commons (MeasureEvent (..), Ping (..), Pong (..),
                     loadLogConfig, logMeasure)
import qualified Network.Transport.TCP as TCP
import           Node (ConversationActions (..), Listener (..), NodeAction (..),
                     defaultNodeEnvironment, noReceiveDelay, node,
                     simpleNodeEndPoint)
import           Node.Message.Binary (binaryPacking)
import           Seal.Util.Trace (Severity (..), Trace, wlogTrace)
import           Seal.Util.Wlog (removeAllHandlers)
import           ReceiverOptions (Args (..), argsParser)

main :: IO ()
main = do
    (Args {..}, ()) <-
        simpleOptions
            "bench-receiver"
            "Server utility for benches"
            "Use it!"
            argsParser
            empty

    lh <- loadLogConfig logsPrefix logConfig
    setLocaleEncoding utf8

    transport <- do
        transportOrError <-
            TCP.createTransport (TCP.defaultTCPAddr "127.0.0.1" (show port))
            TCP.defaultTCPParameters
        either throwIO return transportOrError

    let prng = mkStdGen 0

    node logTrace (simpleNodeEndPoint transport) (const noReceiveDelay) (const noReceiveDelay) prng binaryPacking () defaultNodeEnvironment $ \_ ->
        NodeAction (const [pingListener noPong]) $ \_ -> do
            threadDelay (duration * 1000000)
    removeAllHandlers lh
  where

    logTrace :: Trace IO (Severity, Text)
    logTrace = wlogTrace "receiver"

    logTrace' :: Trace IO Text
    logTrace' = contramap ((,) Info) logTrace

    pingListener noPong =
        Listener $ \_ _ cactions -> do
            (mid, payload) <- recv cactions maxBound >>= \case
                Just (Ping mid payload) -> return (mid, payload)
                _ -> throwString "Expected a ping"
            logMeasure logTrace' PingReceived mid payload
            unless noPong $ do
                logMeasure logTrace' PongSent mid payload
                send cactions (Pong mid payload)
