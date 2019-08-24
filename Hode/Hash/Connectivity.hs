{-# LANGUAGE ScopedTypeVariables,
TupleSections #-}

module Hode.Hash.Connectivity (
  transitiveRelsRightward, transitiveRelsLeftward,
    -- ^ Rslt
    -- -> Rslt
    -- -> Addr -- ^ a binary `Tplt`
    -- -> [Addr] -- ^ places to maybe finish
    -- -> [Addr] -- ^ places to start
    -- -> Either String [(Addr,Addr)]
  rightwardReachable, leftwardReachable,
    -- ^ Rslt
    -- -> Addr -- ^ a binary `Tplt`
    -- -> Addr -- ^ a starting `Expr`
    -- -> Either String [Addr]
  ) where

import qualified Data.List as L
import           Data.Map (Map)
import qualified Data.Map as M
import           Data.Set (Set)
import qualified Data.Set as S

import Hode.Hash.HLookup
import Hode.Hash.HTypes
import Hode.Rslt.RLookup
import Hode.Rslt.RTypes
import Hode.Util.Misc


-- | = Searching from a fixed set toward a fixed target.
-- For instance, given sets S and T, find the set {(s,t) | s in S, t in T,
-- and there exists a chain s < n1 < n2 < n3 < ... < t of length 2 or more}.

transitiveRelsRightward, transitiveRelsLeftward ::
     Rslt
  -> Addr -- ^ a binary `Tplt`
  -> [Addr] -- ^ places to maybe finish
  -> [Addr] -- ^ places to start
  -> Either String [(Addr,Addr)]
transitiveRelsRightward = transitiveRels True
transitiveRelsLeftward  = transitiveRels False

transitiveRels :: Bool -- ^ whether to search rightward
  -> Rslt
  -> Addr -- ^ a binary `Tplt`
  -> [Addr] -- ^ places to maybe finish
  -> [Addr] -- ^ places to start
  -> Either String [(Addr,Addr)]
transitiveRels b r t es ss =
  concat <$>
  ifLefts (map (transitiveRels1 b r t es) ss)

transitiveRels1 :: Bool -- ^ whether to search rightward
  -> Rslt
  -> Addr -- ^ a binary `Tplt`
  -> [Addr] -- ^ places to maybe finish
  -> Addr -- ^ the place to start
  -> Either String [(Addr,Addr)]
transitiveRels1 b r t fs s =
  prefixLeft "transitiveRels: " $ do
  found <- L.intersect fs <$> reachable b r t [s]
  Right $ map (if b then (s,) else (,s)) found

-- | = Searching from a fixed set of `Expr`s toward no particular target.
-- For instance, given set S, find the set T = {t s.t. t > s for some s in S}.

-- | `rightwardReachable r s t` finds all the expressions reachable from `s`,
-- by moving rightward. `s` starts as member 1 and we look for member2,
-- then each of those becomes member 1 and we look for new member 2, etc.)

rightwardReachable, leftwardReachable ::
  Rslt
  -> Addr -- ^ a binary `Tplt`
  -> [Addr] -- ^ starting `Expr`s
  -> Either String [Addr]
rightwardReachable = reachable True
leftwardReachable  = reachable False

-- | Not for export.
reachable :: Bool -- ^ whether to search rightward
          -> Rslt
          -> Addr -- ^ a binary `Tplt`
          -> [Addr] -- ^ starting `Expr`s
          -> Either String [Addr]
reachable rightward r t as = prefixLeft "reachable: " $ do
  verifyBinaryTemplate r t
  f [] as
  where
    f :: [Addr] -> [Addr] -> Either String [Addr]
    f explored [] = Right explored
    f explored (a:morePending) =
      prefixLeft ("f of " ++ show a) $ do
        s <- immediateNeighbors r rightward t [a]
        f (a:explored) $ S.toList s ++ morePending
        -- I believe this gives DFS,
        -- and flipping the ++ would change it to BFS.


-- | = Utilities

verifyBinaryTemplate :: Rslt -> Addr -> Either String ()
verifyBinaryTemplate r t = do
  v <- variety r t
  if v == (TpltCtr,2) then Right () else Left $
    "Expr at address " ++ show t ++ " not a binary template."

immediateNeighbors :: Rslt
                   -> Bool -- ^ whether searching rightward
                   -> Addr -- ^ a binary `Tplt`
                   -> [Addr] -- ^ starting `Expr`s
                   -> Either String (Set Addr)
immediateNeighbors r rightward t as =
  let (start, toward) = case rightward of
        True -> (1,2)
        False -> (2,1)
  in hExprToAddrs r mempty $
     HEval ( HMap $ M.fromList
             [ ( RoleMember start
               , HOr $ map (HExpr . Addr) as )
             , ( RoleTplt, HExpr $ Addr t ) ] )
     [[ RoleMember toward ]]
