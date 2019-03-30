{-# LANGUAGE ScopedTypeVariables #-}

module UI.VTree.String (
    resultsText        -- ^ St -> [String]
  ) where

import           Data.Foldable (toList)
import qualified Data.Vector           as V
import           Lens.Micro

import Rslt.RLookup
import Rslt.RTypes
import Rslt.Show
import UI.ITypes
import Util.Misc
import UI.String
import Util.PTree
import Util.VTree


resultsText :: St -> [String]
resultsText st = maybe [] (f 0) b where
  b :: Maybe (VTree RsltView)
  b = st ^? stBuffer st . bufferView

  f :: Int -> VTree RsltView -> [String]
  f i v = indent (vShow $ v ^. vTreeLabel)
    : concatMap (f $ i+1) (V.toList $ v ^. vTrees)
    where indent :: String -> String
          indent s = replicate (2*i) ' ' ++ s
