-- | This module provides 'KeyConfig' and associated functions. A
-- 'KeyConfig' is the basis for the custom keybinding system in this
-- library.
--
-- To get started, see 'newKeyConfig'. Once a 'KeyConfig' has been
-- constructed, see 'Brick.Keybindings.KeyHandlerMap.keyDispatcher'.
module Brick.Keybindings.KeyConfig
  ( KeyConfig
  , newKeyConfig
  , BindingState(..)

  -- * Specifying bindings
  , Binding(..)
  , ToBinding(..)
  , fn
  , meta
  , ctrl
  , shift

  -- * Querying KeyConfigs
  , firstDefaultBinding
  , firstActiveBinding
  , allDefaultBindings
  , allActiveBindings

  -- * Misc
  , keyConfigEvents
  , lookupKeyConfigBindings
  )
where

import Data.List (nub)
import qualified Data.Map.Strict as M
import Data.Maybe (fromMaybe, listToMaybe)
import qualified Graphics.Vty as Vty

import Brick.Keybindings.KeyEvents

-- | A key binding.
--
-- The easiest way to express 'Binding's is to use the helper functions
-- in this module that work with instances of 'ToBinding', e.g.
--
-- @
-- let ctrlB = 'ctrl' \'b\'
--     shiftX = 'shift' \'x\'
--     ctrlMetaK = 'ctrl' $ 'meta' \'k\'
--     -- Or with Vty keys directly:
--     ctrlDown = 'ctrl' 'Graphics.Vty.Input.KDown'
-- @
data Binding =
    Binding { kbKey :: Vty.Key
            -- ^ The key itself.
            , kbMods :: [Vty.Modifier]
            -- ^ The list of modifiers. Order is not significant.
            } deriving (Eq, Show, Ord)

-- | An explicit configuration of key bindings for a key event.
data BindingState =
    BindingList [Binding]
    -- ^ Bind the event to the specified list of bindings.
    | Unbound
    -- ^ Disable all bindings for the event, including default bindings.
    deriving (Show, Eq, Ord)

-- | A configuration of custom key bindings. A 'KeyConfig'
-- stores everything needed to resolve a key event into one or
-- more key bindings. Make a 'KeyConfig' with 'newKeyConfig',
-- then use it to dispatch to 'KeyEventHandler's with
-- 'Brick.Keybindings.KeyHandlerMap.keyDispatcher'.
--
-- Make a new 'KeyConfig' with 'newKeyConfig'.
--
-- A 'KeyConfig' stores:
--
-- * A collection of named key events, mapping the event type @e@ to
--   'Text' labels.
-- * For each event @e@, optionally store a list of default key bindings
--   for that event.
-- * An optional customized binding list for each event, setting the
--   event to either 'Unbound' or providing explicit overridden bindings
--   with 'BindingList'.
data KeyConfig e =
    KeyConfig { keyConfigBindingMap :: M.Map e BindingState
              -- ^ The map of custom bindings for events with custom
              -- bindings.
              , keyConfigEvents :: KeyEvents e
              -- ^ The base mapping of events and their names that is
              -- used in this configuration.
              , keyConfigDefaultBindings :: M.Map e [Binding]
              -- ^ A mapping of events and their default key bindings,
              -- if any.
              }
              deriving (Show, Eq)

-- | Build a 'KeyConfig' with the specified 'KeyEvents' event-to-name
-- mapping, list of default bindings by event, and list of custom
-- bindings by event.
newKeyConfig :: (Ord e)
             => KeyEvents e
             -- ^ The base mapping of key events and names to use.
             -> [(e, [Binding])]
             -- ^ Default bindings by key event, such as from a
             -- configuration file or embedded code. Optional on a
             -- per-event basis.
             -> [(e, BindingState)]
             -- ^ Custom bindings by key event, such as from a
             -- configuration file. Explicitly setting an event to
             -- 'Unbound' here has the effect of disabling its default
             -- bindings. Optional on a per-event basis.
             -> KeyConfig e
newKeyConfig evs defaults bindings =
    KeyConfig { keyConfigBindingMap = M.fromList bindings
              , keyConfigEvents = evs
              , keyConfigDefaultBindings = M.fromList defaults
              }

-- | Look up the binding state for the specified event. This returns
-- 'Nothing' when the event has no explicitly configured custom
-- 'BindingState'.
lookupKeyConfigBindings :: (Ord e) => KeyConfig e -> e -> Maybe BindingState
lookupKeyConfigBindings kc e = M.lookup e $ keyConfigBindingMap kc

-- | A convenience function to return the first result of
-- 'allDefaultBindings', if any.
firstDefaultBinding :: (Show e, Ord e) => KeyConfig e -> e -> Maybe Binding
firstDefaultBinding kc ev = do
    bs <- M.lookup ev (keyConfigDefaultBindings kc)
    case bs of
        (b:_) -> Just b
        _ -> Nothing

-- | Returns the list of default bindings for the specified event,
-- irrespective of whether the event has been explicitly configured with
-- other bindings or set to 'Unbound'.
allDefaultBindings :: (Ord e) => KeyConfig e -> e -> [Binding]
allDefaultBindings kc ev =
    fromMaybe [] $ M.lookup ev (keyConfigDefaultBindings kc)

-- | A convenience function to return the first result of
-- 'allActiveBindings', if any.
firstActiveBinding :: (Show e, Ord e) => KeyConfig e -> e -> Maybe Binding
firstActiveBinding kc ev = listToMaybe $ allActiveBindings kc ev

-- | Return all active key bindings for the specified event. This
-- returns customized bindings if any have been set in the 'KeyConfig',
-- no bindings if the event has been explicitly set to 'Unbound', or the
-- default bindings if the event is absent from the customized bindings.
allActiveBindings :: (Show e, Ord e) => KeyConfig e -> e -> [Binding]
allActiveBindings kc ev = nub foundBindings
    where
        defaultBindings = allDefaultBindings kc ev
        foundBindings = case lookupKeyConfigBindings kc ev of
            Just (BindingList bs) -> bs
            Just Unbound -> []
            Nothing -> defaultBindings

-- | The class of types that can form the basis of 'Binding's.
--
-- This is provided to make it easy to write and modify bindings in less
-- verbose ways.
class ToBinding a where
    -- | Binding constructor.
    bind :: a -> Binding

instance ToBinding Vty.Key where
    bind k = Binding { kbMods = [], kbKey = k }

instance ToBinding Char where
    bind = bind . Vty.KChar

instance ToBinding Binding where
    bind = id

addModifier :: (ToBinding a) => Vty.Modifier -> a -> Binding
addModifier m val =
    let b = bind val
    in b { kbMods = nub $ m : kbMods b }

-- | Add Meta to a binding.
meta :: (ToBinding a) => a -> Binding
meta = addModifier Vty.MMeta

-- | Add Ctrl to a binding.
ctrl :: (ToBinding a) => a -> Binding
ctrl = addModifier Vty.MCtrl

-- | Add Shift to a binding.
shift :: (ToBinding a) => a -> Binding
shift = addModifier Vty.MShift

-- | Function key binding.
fn :: Int -> Binding
fn = bind . Vty.KFun