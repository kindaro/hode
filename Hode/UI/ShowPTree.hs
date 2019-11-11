{-# LANGUAGE ScopedTypeVariables #-}

module Hode.UI.ShowPTree where

import           Data.Foldable (toList)
import           Lens.Micro

import qualified Brick.Types          as B
import           Brick.Widgets.Core

import Hode.Util.PTree


-- | To show `String`s, set `b2w = Brick.Widgets.Core.strWrap`.
-- To show `ColorString`s, use `b2s = Hode.Brick.attrStringWrap`
porestToWidget :: forall a b n.
     (b -> B.Widget n)
  -> (a -> b)      -- ^ shows the columns corresponding to each node
  -> (a -> b)      -- ^ shows the nodes that will be arranged like a tree
  -> (a -> Bool) -- ^ whether to hide a node's children
  -> (PTree a -> B.Widget n -> B.Widget n)
     -- ^ to show the focused node differently
     -- (it could be used for other stuff too)
  -> Porest a -- ^ The Porest to show
  -> B.Widget n
porestToWidget b2w showColumns showIndented isFolded style p0 =
  fShow p where

  p :: Porest (Int, a) = fmap writeLevels p0

  fShow :: Porest (Int,a) -> B.Widget n
  fShow = vBox . map recursiveWidget . toList

  recursiveWidget :: PTree (Int,a) -> B.Widget n
  recursiveWidget pt =
    oneTreeRowWidget pt <=> rest where
    rest = case pt ^. pMTrees of
             Nothing -> emptyWidget
             Just pts ->
               case isFolded $ snd $ _pTreeLabel pt of
               True -> emptyWidget
               False -> fShow pts

  oneTreeRowWidget :: PTree (Int,a) -> B.Widget n
  oneTreeRowWidget t0 =
    let t :: PTree a  = fmap snd t0
        a :: a        = _pTreeLabel t
        indent :: Int = fst $ _pTreeLabel t0
    in style t $ hBox
       [ b2w $ showColumns a
       , padLeft (B.Pad $ 2 * indent) $
         b2w $ showIndented $ _pTreeLabel t ]
