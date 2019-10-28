{-# LANGUAGE ScopedTypeVariables #-}

module Hode.Rslt.Sort where

import           Data.Map (Map)
import qualified Data.Map       as M
import           Data.Set (Set)
import qualified Data.Set       as S

import Hode.Hash.HLookup
import Hode.Hash.HTypes
import Hode.Rslt.Index
import Hode.Rslt.RLookup
import Hode.Rslt.BinTypes
import Hode.Rslt.RTypes
import Hode.Util.Misc


-- | `allRelsInvolvingTplts r ts` finds every `Rel`
-- that uses a member of `ts` as a `Tplt`.
allRelsInvolvingTplts ::
  Rslt -> [TpltAddr] -> Either String (Set RelAddr)
allRelsInvolvingTplts r ts =
  prefixLeft "allRelsInvolvingTplts: " $ do
  hostRels :: [Set (Role, RelAddr)] <-
    ifLefts $ map (isIn r) ts
  Right $ S.unions $
        map ( S.map snd .
              S.filter ((==) RoleTplt . fst) )
        hostRels

-- | `allNormalMembers r rs` finds every non-`Tplt`
-- member of anything in `rs`.
allNormalMembers ::
  Rslt -> [RelAddr] -> Either String [RelAddr]
allNormalMembers r rels =
  prefixLeft "allNormalMembers: " $ do
  members :: [Map Role Addr] <-
    ifLefts $ map (has r) rels
  Right $ concatMap
    ( M.elems .
      flip M.withoutKeys (S.singleton RoleTplt) )
    members

restrictRsltForSort ::
     [Addr]     -- ^ the `Expr`s to sort
  -> [TpltAddr] -- ^ how to sort
  -> Rslt       -- ^ the original `Rslt`
  -> Either String Rslt -- ^ the `Expr`s, every `Tplt` in the `BinTpltOrder`,
  -- every `Rel` involving those `Tplt`s, and every member of those `Rel`s
restrictRsltForSort es ts r =
  prefixLeft "restrictRsltForSort: " $ do
  rels :: Set RelAddr  <- allRelsInvolvingTplts r ts
  mems :: [MemberAddr] <- allNormalMembers r $ S.toList rels
  let refExprs = M.restrictKeys (_addrToRefExpr r) $
                 S.unions [ S.fromList $ es ++ ts ++ mems,
                            rels ]
  Right $ mkRslt refExprs

-- | `maximal r (orient,t) a` tests whether,
-- with respect to `t` under the orientation `ort`,
-- no `Expr` in `r` is greater than the one at `a`.
-- For instance, if `ort` is `LeftIsBigger`,
-- and `a` is on the right side of some relationship using
-- `t` as its `Tplt`, then the result is `False`.
maximal :: Rslt -> (BinOrientation, TpltAddr) -> Addr
        -> Either String Bool
maximal r (ort,t) a =
  prefixLeft "maximal: " $ do
  let roleIfLesser = case ort of
        LeftIsBigger  -> RoleMember 2
        RightIsBigger -> RoleMember 1
  relsInWhichItIsLesser <- hExprToAddrs r mempty $
    HMap $ M.fromList [ (RoleTplt,     HExpr $ Addr t),
                        (roleIfLesser, HExpr $ Addr a) ]
  Right $ null relsInWhichItIsLesser
