{-# LANGUAGE ScopedTypeVariables
, TupleSections
, ViewPatterns #-}

module Hode.PTree.Modify (
  -- | *** `PointedList`
    prevIfPossible, nextIfPossible -- ^ PointedList a ->        PointedList a
  , nudgePrev, nudgeNext           -- ^ PointedList a ->        PointedList a
  , filterPList     -- ^ (a -> Bool) -> PointedList a -> Maybe (PointedList a)
  , insertLeft_noFocusChange  -- ^ a -> PointedList a ->        PointedList a
  , sortPList_asList -- ^  (a -> b) -> [b]
                     --              -> PointedList a ->        PointedList a

  -- | *** `PTree` and `Porest`
  , writeLevels         -- ^ PTree a -> PTree (Int,a)
  , insertLeaf_topNext    -- ^       a -> Porest a -> Porest a
  , insertLeaf_next       -- ^       a -> Porest a -> Porest a
  , insertUnder_andFocus  -- ^ PTree a -> PTree a -> PTree a
  , deleteInPorest      -- ^ Porest a -> Maybe (Porest a)
  , deleteInPTree       -- ^ PTree a -> PTree a
  , nudgeFocus_inPTree  -- ^ Direction -> PTree a -> PTree a
  , nudgeFocus_inPorest -- ^ Direction -> Porest a -> Porest a
  , nudgeInPorest       -- ^ Direction -> Porest a -> Porest a
  , nudgeInPTree        -- ^ Direction -> PTree a -> PTree a
  ) where

import Prelude hiding (pred)

import           Control.Arrow ((>>>))
import           Control.Lens
import           Data.Foldable (toList)
import qualified Data.List             as L
import           Data.Map (Map)
import qualified Data.Map              as M
import qualified Data.List.PointedList as P

import Hode.PTree.Initial


-- | *** `PointedList`

prevIfPossible, nextIfPossible :: PointedList a -> PointedList a
prevIfPossible l = maybe l id $ P.previous l
nextIfPossible l = maybe l id $ P.next     l

nudgePrev, nudgeNext :: PointedList a -> PointedList a
nudgePrev p@(PointedList []     _ _)      = p
nudgePrev   (PointedList (a:as) f bs)     =
             PointedList as     f (a:bs)
nudgeNext p@(PointedList _      _ [])     = p
nudgeNext   (PointedList as     f (b:bs)) =
             PointedList (b:as) f bs

filterPList :: (a -> Bool) -> PointedList a -> Maybe (PointedList a)
filterPList pred (PointedList as b cs) = let
  pl0 = map (False,) (reverse as) ++ [(True,b)] ++ map (False,) cs
  l = filter (pred . snd) $ toList pl0
  i = if pred b then length $ takeWhile (not . fst) l
      else 0 -- if the focus disappeared, reset it to start of list
  in case P.fromList $ map snd l of
       Nothing  -> Nothing
       Just pl1 -> P.moveTo i pl1

insertLeft_noFocusChange :: a -> PointedList a -> PointedList a
insertLeft_noFocusChange a =
  P.tryNext . P.insertLeft a

-- | PITFALL: ASSUMES both `bs` and `fmap f as` are duplicate-free.
--
-- `sortPList_asList f bs as` is a `PointedList a`
-- in which `as` has the same order as `bs`.
-- Anything in `as` and not in `bs` will be at the end,
-- in the same order as before.
-- The order of duplicates (under `f`) in `as` is also unchanged.
sortPList_asList :: forall a b. Ord b
  => (a -> b) -> [b] -> PointedList a -> PointedList a
sortPList_asList f bs as = let
  ranks :: Map b Int =
    M.fromList $ zip bs [0..]
  g :: a -> Either Int Int =
    maybe (Right 0) Left . -- Left < Right, so it comes first
    flip M.lookup ranks . f
  sorted :: [a] =
    L.sortOn g $ toList as
  foc_b :: b =
    f $ as ^. P.focus
  (prefix, focus : suffix) = L.span ((/=) foc_b . f) sorted
  in P.PointedList (reverse prefix) focus suffix


-- | *** `PTree` and `Porest`

-- | The root has level 0, its children level 1, etc.
writeLevels :: PTree a -> PTree (Int,a)
writeLevels = f 0 where
  f :: Int -> PTree a -> PTree (Int, a)
  f i pt = pt
    { _pTreeLabel = (i, _pTreeLabel pt)
    , _pMTrees = fmap (fmap $ f $ i+1) $ _pMTrees pt }
      -- The outer fmap reaches into the Maybe,
      -- and the inner reaches into the PointedList.

-- | I suspect `insertLeaf_next` dominates this function.
-- Always inserts a new top-level tree.
insertLeaf_topNext :: a -> Porest a -> Porest a
insertLeaf_topNext a =
  P.focus . pTreeHasFocus .~ False >>>
  P.insertRight (pTreeLeaf a)      >>> -- moves focus to `a`
  P.focus . pTreeHasFocus .~ True

-- | `insertLeaf_next` inserts a new leaf after the current focus,
-- which can be at any level in the tree.
insertLeaf_next :: forall a. a -> Porest a -> Porest a
insertLeaf_next a f =
  let go :: Porest a -> Porest a =
        P.focus . pTreeHasFocus .~ False
        >>> P.insertRight (pTreeLeaf a) -- no `PTree` is changed
        >>> P.focus . pTreeHasFocus .~ True
  in f & case f ^. P.focus . pTreeHasFocus
         of True  -> go
            False -> P.focus . pMTrees . _Just %~ go

-- | Inserts `newFocus` as a child of `oldFocus`,
-- and focuses on the newcomer.
insertUnder_andFocus :: forall a. PTree a -> PTree a -> PTree a
insertUnder_andFocus newFocus oldFocus =
  let ts'' :: [PTree a] =
        let m = newFocus & pTreeHasFocus .~ True
        in case _pMTrees oldFocus of
             Nothing -> [m]
             Just ts ->
               let ts' = ts & P.focus . pTreeHasFocus .~ False
               in m : toList ts'
  in oldFocus & pTreeHasFocus .~ False
              & pMTrees .~ P.fromList ts''

deleteInPorest :: Porest a -> Maybe (Porest a)
deleteInPorest p =
  case p ^. P.focus . pTreeHasFocus
  of True ->  (P.focus . pTreeHasFocus .~ True)
              <$> P.deleteLeft p
     False -> Just $ p & P.focus %~ deleteInPTree

deleteInPTree :: forall a. PTree a -> PTree a
deleteInPTree t =
  case t ^? getPeersOfFocusedSubtree
  of Nothing              -> t -- you can't delete the root
     Just (p :: Porest a) -> t &
       setPeersOfFocusedSubtree .~ deleteInPorest p

nudgeFocus_inPTree :: Direction -> PTree a -> PTree a
nudgeFocus_inPTree ToRoot t =
  case t ^? getParentOfFocusedSubtree . _Just of
    Nothing -> t & pTreeHasFocus .~ True
    Just st -> let
      st' = st & pMTrees . _Just . P.focus . pTreeHasFocus .~ False
               &                             pTreeHasFocus .~ True
      in t & setParentOfFocusedSubtree .~ st'

nudgeFocus_inPTree ToLeaf t =
  case t ^? getFocusedSubtree . _Just . pMTrees . _Just
  of Nothing -> t
     Just ts -> let ts' = ts & P.focus . pTreeHasFocus .~ True
                in t & setFocusedSubtree . pMTrees .~ Just ts'
                     & setFocusedSubtree . pTreeHasFocus .~ False

nudgeFocus_inPTree ToPrev t =
  case t ^? getPeersOfFocusedSubtree
  of Nothing -> t -- happens at the top of the tree
     Just ts -> let ts' = ts & P.focus . pTreeHasFocus .~ False
                             & prevIfPossible
                             & P.focus . pTreeHasFocus .~ True
       in t & setParentOfFocusedSubtree . pMTrees .~ Just ts'

nudgeFocus_inPTree ToNext t =
  case t ^? getPeersOfFocusedSubtree
  of Nothing -> t -- happens at the top of the tree
     Just ts -> let ts' = ts & P.focus . pTreeHasFocus .~ False
                             & nextIfPossible
                             & P.focus . pTreeHasFocus .~ True
       in t & setParentOfFocusedSubtree . pMTrees .~ Just ts'

nudgeFocus_inPorest :: Direction -> Porest a -> Porest a
nudgeFocus_inPorest d p =
  case p ^. P.focus . pTreeHasFocus
  of False -> p & P.focus %~ nudgeFocus_inPTree d
     True -> case d of
       ToRoot   -> p -- it's already as `ToRoot` as it can be
       ToLeaf -> p & P.focus %~ nudgeFocus_inPTree d
       ToNext -> p & P.focus . pTreeHasFocus .~ False
                     & nextIfPossible
                     & P.focus . pTreeHasFocus .~ True
       ToPrev -> p & P.focus . pTreeHasFocus .~ False
                     & prevIfPossible
                     & P.focus . pTreeHasFocus .~ True

nudgeInPorest :: forall a. Direction -> Porest a -> Porest a
-- PITFALL: Not tested, but it's exactly the same idiom as
-- `nudgeFocus_inPorest`, which is tested.
nudgeInPorest dir p =
  case p ^. P.focus . pTreeHasFocus
  of False -> p & P.focus %~ nudgeInPTree dir
     True -> case dir of
               ToPrev -> nudgePrev p
               ToNext -> nudgeNext p
               _       -> p -- you can only nudge across the same level

nudgeInPTree :: forall a. Direction -> PTree a -> PTree a
nudgeInPTree dir =
  setPeersOfFocusedSubtree . _Just
  %~ nudgeInPorest dir
