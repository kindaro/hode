{-# LANGUAGE ScopedTypeVariables #-}

module Graph where

import           Data.Map (Map)
import qualified Data.Map       as M
import           Data.Set (Set)
import qualified Data.Set       as S

import Types


graph :: [( Int, [Int] )] -> Data
graph pairs = Graph g $ invertMapToSet g where
  g = M.fromList $ map f pairs
  f (a,b) = (a, S.fromList b)

invertMapToSet :: forall a. Ord a => Map a (Set a) -> Map a (Set a)
invertMapToSet = foldl addInversion M.empty . M.toList where
  addInversion :: M.Map a ( Set a )
               ->     ( a,  Set a )
               -> M.Map a ( Set a )

  addInversion m (a1, as) -- a1 maps to each a in as
    = S.foldl f m as where
      f :: M.Map  a (S.Set a)
        ->        a
        -> M.Map  a (S.Set a)
      f m a = M.insertWith S.union a (S.singleton a1) m -- each a maps to a1