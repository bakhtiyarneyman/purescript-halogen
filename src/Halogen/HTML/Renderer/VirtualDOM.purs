module Halogen.HTML.Renderer.VirtualDOM (renderHTML) where

import Prelude

import Control.Monad.Eff (Eff)

import Data.Exists (runExists)
import Data.ExistsR (runExistsR)
import Data.Foldable (foldl, foldMap)
import Data.Traversable (traverse)
import Data.Function.Uncurried (runFn2)
import Data.Maybe (Maybe(..), maybe)
import Data.Monoid (mempty)
import Data.Nullable (toNullable)

import Halogen.Effects (HalogenEffects)
import Halogen.HTML.Core (HTML(..), Prop(..), PropF(..), HandlerF(..), runNamespace, runTagName, runPropName, runAttrName, runEventName, lowerFuse)
import Halogen.HTML.Events.Handler (runEventHandler)
import Halogen.Internal.VirtualDOM as V

-- | Render a `HTML` document to a virtual DOM node
-- |
-- | The first argument is an event handler.
renderHTML
  :: forall p i m eff
   . Monad m
  => (i -> Eff (HalogenEffects eff) Unit)
  -> (p -> m V.VTree)
  -> HTML p i
  -> m V.VTree
renderHTML driver handleSlot = go
  where
  go = case _ of
    Text s ->
      pure $ V.vtext s
    Element ns name props els -> do
      els' <- traverse go els
      pure $ V.vnode
        (toNullable $ runNamespace <$> ns)
        (runTagName name)
        (toNullable $ foldl findKey Nothing props)
        (foldMap (renderProp driver) props) els'
    Slot p ->
      handleSlot p
    Fuse bc ->
      go (lowerFuse bc)

renderProp
  :: forall i eff
   . (i -> Eff (HalogenEffects eff) Unit)
  -> Prop i
  -> V.Props
renderProp driver = case _ of
  Prop e ->
    runExists renderPropF e
  Attr ns name value ->
    let attrName = maybe "" (\ns' -> runNamespace ns' <> ":") ns <> runAttrName name
    in runFn2 V.attr attrName value
  Handler e ->
    runExistsR (renderHandlerProp driver) e
  Ref f ->
    V.refProp (driver <<< f)
  _ ->
    mempty

renderPropF :: forall a. PropF a -> V.Props
renderPropF (PropF key value _) = runFn2 V.prop (runPropName key) value

renderHandlerProp
  :: forall i eff a
   . (i -> Eff (HalogenEffects eff) Unit)
  -> HandlerF i a
  -> V.Props
renderHandlerProp driver (HandlerF name k) =
  runFn2 V.handlerProp (runEventName name)
    \ev -> runEventHandler ev (k ev) >>= maybe (pure unit) driver

findKey :: forall i. Maybe String -> Prop i -> Maybe String
findKey _ (Key k) = Just k
findKey r _ = r
