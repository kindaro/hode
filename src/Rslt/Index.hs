-- | Minus mkRslt, these gory details are not
-- part of the Rslt interface.

{-# LANGUAGE ScopedTypeVariables #-}

module Rslt.Index where

import           Data.Maybe
import           Data.Map (Map)
import qualified Data.Map       as M
import           Data.Set (Set)
import qualified Data.Set       as S

import Rslt.RTypes
import Rslt.RUtil


mkRslt :: Map Addr RefExpr -> Rslt
mkRslt es = go es' where
  es' :: Map Addr RefExpr
  es' = if not $ M.null es
        then es else M.singleton 0 $ Phrase' ""
  go :: Map Addr RefExpr -> Rslt
  go m = let
    (hasMap :: Map Addr (Map Role Addr)) =
      M.filter (not . M.null)
      $ M.map (M.fromList . refExprPositions)
      $ m
    in Rslt {
      _addrToRefExpr = m
    , _refExprToAddr = imgDb m
    , _variety = M.map refExprVariety m
    , _has = hasMap
    , _isIn = foldl invertAndAddPositions M.empty
              $ M.toList $ M.map M.toList hasMap
    }


-- | == Given an expression, look up an address.

imgDb :: Map Addr RefExpr -> Map RefExpr Addr
imgDb = M.fromList . catMaybes . map f . M.toList where
  f (addr, expr) = case expr of
    Par' _ _ -> Nothing
    _        -> Just (expr, addr)


-- | == Given an address, look up what it's connected to.
-- The following two functions are in a sense inverses.

-- | `refExprPositions e` gives every pair `(r,a)` such that a plays the role
-- r in e.

refExprPositions :: RefExpr -> [(Role,Addr)]
refExprPositions expr =
  let r :: (Int, Addr) -> (Role, Addr)
      r (n,a) = (RoleMember n, a)
  in case expr of
    Phrase' _      -> []
    Tplt' mas    ->                 map r (zip [1..]           mas)
    Rel'  mas ta -> (RoleTplt,ta) : map r (zip [1..]           mas)
    Par'  sas _  ->                 map r (zip [1..] $ map snd sas)


-- | `invertAndAddPositions m (a, ras)` is meant for the case where m is a map
-- from addresses to the set of roles they play in other expressions, ras is
-- the set of roles in a, and a is not a key of m.

invertAndAddPositions :: Map Addr (Set (Role, Addr))
                      -> (Addr,       [(Role, Addr)])
                      -> Map Addr (Set (Role, Addr))
invertAndAddPositions fm0 (a1, ras) = foldl f fm0 ras where
  f :: Map Addr (Set (Role, Addr))
    ->               (Role, Addr)
    -> Map Addr (Set (Role, Addr))
  f fm (r,a) = M.insertWith S.union a newData fm
    where newData :: Set (Role, Addr)
          newData = S.singleton (r,a1)
