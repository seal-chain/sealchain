{-# LANGUAGE TemplateHaskell #-}

module Seal.Infra.Shutdown.Types
       ( ShutdownContext (..)
       , shdnIsTriggered, shdnFInjects
       ) where

import           Universum

import           Control.Lens (makeLenses)
import           Seal.Infra.InjectFail (FInjects)

data ShutdownContext = ShutdownContext
    { _shdnIsTriggered :: !(TVar Bool)
    , _shdnFInjects    :: !(FInjects IO)
    -- ^ If this flag is `True`, then workers should stop.
    }

makeLenses ''ShutdownContext
