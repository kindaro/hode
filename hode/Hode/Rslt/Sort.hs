-- | PITFALL: This algorithm makes sense only on a
-- graph-like subset of an Rslt -- one in which:
--   (1) all "edges" are binary `Rel`s
--   (2) edges never involve another edge
--   (3) the "edge label" (`Tplt`) `e` to sort by
--       plays no `Role` but `Tplt`
--   (4) none of the `Expr`s the user wants to sort
--       is a `Rel` with `e` as its `Tplt`
--
-- PITFALL: Some of these functions were written
-- to handle multiple `Tplt`s, but then I lost interest.

{-# LANGUAGE
ScopedTypeVariables,
TupleSections #-}

module Hode.Rslt.Sort (
    Kahn(..)
  , kahnSort -- ^  Rslt -> (BinOrientation, TpltAddr) -> [Addr]
             -- -> Either String [Addr]

   -- | = Internals
  , kahnRecurse -- ^  (BinOrientation, TpltAddr) -> Kahn
                -- -> Either String Kahn
  , kahnIterate -- ^  (BinOrientation, TpltAddr) -> Kahn
                -- -> Either String Kahn

  , restrictRsltForSort
    -- ^  [Addr]             -- ^ the `Expr`s to sort
    -- -> [TpltAddr]         -- ^ how to sort
    -- -> Rslt               -- ^ the original `Rslt`
    -- -> Either String Rslt
      -- ^ the `Expr`s, every `Tplt` in the `BinTpltOrder,
      -- every `Rel` involving those `Tplt`s,
      -- and every member of those `Rel`s
  , allRelsInvolvingTplts -- ^  Rslt -> [TpltAddr]
                          -- -> Either String (Set RelAddr)
  , allNormalMembers      -- ^  Rslt -> [RelAddr]
                          -- -> Either String [RelAddr]

  , allTops -- ^  Rslt
            -- -> (BinOrientation, TpltAddr)
            -- -> [Addr] -- ^ candidates
            -- -> Either String [Addr]
  , isTop -- ^ Rslt -> (BinOrientation, TpltAddr) -> Addr
          -- -> Either String Bool

  , partitionRelated -- ^ Rslt -> TpltAddr
                     -- -> [Addr] -- ^ candidates
                     -- -> Either String ([Addr],[Addr])
  , isRelated -- ^ Rslt -> TpltAddr -> Addr
              -- -> Either String Bool

  , justUnders -- ^ (BinOrientation, TpltAddr) -> Rslt -> Addr
               -- -> Either String (Set Addr)
  , deleteHostsThenDelete -- ^ Addr -> Rslt -> Either String Rslt
  , uses_as_tplt -- ^ TpltAddr -> Addr -> Bool
  ) where

import qualified Data.List      as L
import           Data.Map (Map)
import qualified Data.Map       as M
import           Data.Maybe
import           Data.Set (Set)
import qualified Data.Set       as S
import           Control.Monad (foldM)

import Hode.Hash.Lookup hiding (connections)
import Hode.Hash.Types
import Hode.Rslt.Edit (deleteIfUnused)
import Hode.Rslt.Edit.Initial (_deleteInternalMentionsOf_unsafe)
import Hode.Rslt.Index
import Hode.Rslt.Lookup
import Hode.Rslt.Binary
import Hode.Rslt.Types
import Hode.Util.Misc


data Kahn = Kahn
  { kahnRslt   :: Rslt -- ^ A subset of the original `Rslt`.
    -- It shrinks (via `deleteHostsThenDelete`)
    -- as the algorithm progresses (see `kahnIterate`).
  , kahnTops   :: [Addr]
  , kahnSorted :: [Addr] }
  deriving (Eq,Ord,Show)

-- | If `kahnSort r (bo,t) as == (sorted,isol)`,
-- then `sorted` are sorted w/r/t `(bo,t)`,
-- and nothing in `isol` is in a `t`-relationship.
--
-- PITFALL: `sorted` might not be a connected (via `t`) set.
--
-- Note: this is depth-first search.
-- (For BFS, reverse the order of the expression
-- `newTops ++ tops` in `kahnIterate`.)

kahnSort :: Rslt -> (BinOrientation, TpltAddr) -> [Addr]
         -> Either String ([Addr],[Addr])
kahnSort r (bo,t) as =
-- TODO speed: this calls `restrictRsltForSort` and `allRelsInvolvingTplts`, but `restrictRsltForSort` also calls `allRelsInvolvingTplts`, with the same arguments. I don't know whether GHC will optimize that away.
  prefixLeft "kahnSort:" $ do
  rels :: Set Addr <- allRelsInvolvingTplts r [t]
  r1 :: Rslt <- restrictRsltForSort as [t] r
  let nodes0 = M.keys $ _addrToRefExpr r1
  (nodes1,isolated) <-
    partitionRelated r1 t nodes0

  tops :: [Addr] <- allTops r1 (bo,t) nodes1
  Kahn r2 _ res <- kahnRecurse (bo,t) $ Kahn r1 tops []
  case null $ S.intersection rels $
       S.fromList $ M.keys $ _addrToRefExpr r2 of
    True -> Right ( filter (flip elem $ S.fromList as) $ reverse res
                  , filter (flip elem $ S.fromList as) $ isolated )
    False -> Left "data has at least one cycle."


-- | = Internals

-- | Splitting kahnRecurse from kahnIterate
-- might (I don't know) be slower,
-- but it lets me test a single iteration.
kahnRecurse :: (BinOrientation, TpltAddr) -> Kahn
            -> Either String Kahn
kahnRecurse bt k =
  prefixLeft "kahnRecurse:" $
  case kahnTops k of
    [] -> Right k
    _ -> kahnIterate bt k >>= kahnRecurse bt

kahnIterate :: (BinOrientation, TpltAddr) -> Kahn
            -> Either String Kahn
kahnIterate _ k@(Kahn _ [] _) =
  Right k
kahnIterate (bo,t) (Kahn r (top:tops) acc) =
  prefixLeft "kahnIterate:" $ do
  jus :: Set Addr <- justUnders (bo,t) r top
  r1 :: Rslt <- deleteHostsThenDelete top t r
  newTops :: [Addr] <- allTops r1 (bo,t) $
                       S.toList jus
  Right $ Kahn r1 (newTops ++ tops) (top : acc)

restrictRsltForSort ::
     [Addr]     -- ^ the `Expr`s to sort
  -> [TpltAddr] -- ^ how to sort
  -> Rslt       -- ^ the original `Rslt`
  -> Either String Rslt -- ^ the `Expr`s to sort, the `Tplt`s to sort by,
  -- every `Rel` involving those `Tplt`s, and every member of those `Rel`s
restrictRsltForSort es ts r =
  prefixLeft "restrictRsltForSort:" $ do
  rels :: Set RelAddr  <- allRelsInvolvingTplts r ts
  mems :: [MemberAddr] <- allNormalMembers r $ S.toList rels
  let refExprs = M.restrictKeys (_addrToRefExpr r) $
                 S.unions [ S.fromList es,
                            S.fromList ts,
                            S.fromList mems,
                            rels ]
  Right $ mkRslt refExprs

-- | `allRelsInvolvingTplts r ts` finds every `Rel`
-- that uses a member of `ts` as a `Tplt`.
allRelsInvolvingTplts ::
  Rslt -> [TpltAddr] -> Either String (Set RelAddr)
allRelsInvolvingTplts r ts =
  prefixLeft "allRelsInvolvingTplts:" $ do
  hostRels :: [Set (Role, RelAddr)] <-
    ifLefts $ map (isIn r) ts
  Right $ S.unions $
    map ( S.map snd .
          S.filter ((==) (RoleInRel' RoleTplt) . fst) )
    hostRels

-- | `allNormalMembers r rs` finds every non-`Tplt`
-- member of anything in `rs`.
allNormalMembers ::
  Rslt -> [RelAddr] -> Either String [RelAddr]
allNormalMembers r rels =
  prefixLeft "allNormalMembers:" $ do
  members :: [Map Role Addr] <-
    ifLefts $ map (has r) rels
  Right $ concatMap
    ( M.elems . ( flip M.withoutKeys
                  $ S.singleton $ RoleInRel' RoleTplt) )
    members

-- | Everything that satisfies `isTop`.
allTops :: Rslt
        -> (BinOrientation, TpltAddr)
        -> [Addr] -- ^ candidates
        -> Either String [Addr]
allTops r (bo,t) as =
  prefixLeft "allTops:" $
  let withIsTop :: Addr -> Either String (Bool, Addr)
      withIsTop a = (,a) <$> isTop r (bo,t) a
  in map snd . filter fst <$> mapM withIsTop as

-- | "Top" means "earliest".
-- `isTop r (ort,t) a` tests whether,
-- with respect to `t` under the orientation `ort`,
-- no `Expr` in `r` should precede the one at `a`.
-- For instance, if `orient` is `LeftEarlier`,
-- and `a` is on the right side of some relationship in `r`
-- using `t` as its `Tplt`, then the result is `False`.
isTop :: Rslt -> (BinOrientation, TpltAddr) -> Addr
      -> Either String Bool
isTop r (ort,t) a =
  prefixLeft "isTop:" $ do
  let roleOfLater = RoleInRel' $ RoleMember $
        case ort of LeftEarlier  -> 2
                    RightEarlier -> 1
  relsInWhichItIsLater :: Set Addr <-
    S.filter (uses_as_tplt r t) <$>
    hExprToAddrs r mempty
    ( HMap $ M.singleton roleOfLater $  HExpr $ ExprAddr a )
  Right $ null relsInWhichItIsLater

-- | If `partitionRelated r t as == (reld,isol)`,
-- then each member of `reld` is in at least one `t`-relationship,
-- while no member of `isol` is.
-- PITFALL: `reld` might not be connected set.
partitionRelated :: Rslt -> TpltAddr
                 -> [Addr] -- ^ candidates
                 -> Either String ([Addr],[Addr])
partitionRelated r t as =
  prefixLeft "partitionRelated:" $ do
  let withIsRelated :: Addr -> Either String (Bool, Addr)
      withIsRelated a = (,a) <$> isRelated r t a
  (areRelated, isolated) <-
    L.partition fst <$> mapM withIsRelated as
  Right (map snd areRelated, map snd isolated)

-- | `isRelated r t a` is `True` if and only if
-- `a` is in at least one `t`-relationship.
isRelated :: Rslt -> TpltAddr -> Addr
          -> Either String Bool
isRelated r t a =
  -- TODO ? speed: `partitionRelated` calls this a lot.
  -- Each time, it has to run `hExprToAddrs` on the `HMap`.
  -- It could be faster to move that into `partitionRelated`.
  prefixLeft "isRelated:" $ do
  connections :: Set Addr <- --`t`-relationships involving `a`
    S.filter (uses_as_tplt r t) <$>
    ( hExprToAddrs r mempty $ HMemberHosts $ HExpr $ ExprAddr a )
  Right $ if null connections then False else True

-- | `justUnders (bo,t) r a` returns the `Addr`s that
-- lie just beneath `a`, where the menaing of "beneath"
-- depends on `bo` and `t`.
justUnders :: (BinOrientation, TpltAddr) -> Rslt -> Addr
           -> Either String (Set Addr)
justUnders (bo,t) r a0 =
  prefixLeft "justUnders:" $ do
  let (earlier :: Int, later :: Int) =
        -- TODO ? isn't this backwards?
        case bo of  LeftEarlier -> (1,2)
                    RightEarlier  -> (2,1)
      laterMember :: Addr -> Maybe Addr
      laterMember a =
        case M.lookup a $ _addrToRefExpr r of
          Just (Rel' (Rel [left,right] _)) ->
            case later of 1 -> Just left
                          2 -> Just right
                          _ -> error "impossible"
          _ -> Nothing
  relsUsing_t_inWhich_a0_IsEarlier :: Set Addr <-
    S.filter (uses_as_tplt r t) <$>
    ( hExprToAddrs r mempty $ HMap $ M.singleton
      ( RoleInRel' $ RoleMember earlier)
      $ HExpr $ ExprAddr a0 )
  Right $ S.map fromJust $
    S.filter isJust $
    S.map laterMember relsUsing_t_inWhich_a0_IsEarlier

-- | `deleteHostsThenDelete t a r` removes from `r` every
-- rel in which `a` is a member, and then removes `a`.
-- PITFALL: Could put `r` into an invalid state
-- (see `_deleteInternalMentionsOf_unsafe`),
-- such that the deleted `Expr` is a member of `Expr` still present.
-- I believe that's okay if we're merely using `r` to sort.
deleteHostsThenDelete ::
  Addr -> TpltAddr -> Rslt -> Either String Rslt
deleteHostsThenDelete a t r =
  prefixLeft "deleteHostsThenDelete:" $ do
  hosts :: Set Addr <-
    S.filter (uses_as_tplt r t) <$>
    hExprToAddrs r mempty
    ( -- No need to check which member it is --
      -- the template is binary, and the node is top.)
      HMemberHosts $ HExpr $ ExprAddr a )
  foldM (flip deleteIfUnused) r hosts >>=
    _deleteInternalMentionsOf_unsafe a

-- | PITFALL: Cannot use an HExpr for this, because `t` may  have been
-- deleted from `r` (because  it was among the things being sorted).
uses_as_tplt :: Rslt -> TpltAddr -> Addr -> Bool
uses_as_tplt r t0 a =
  case M.lookup a $ _addrToRefExpr r of
    Just (Rel' (Rel _ t)) -> t == t0
    _                     -> False
