{-# LANGUAGE LambdaCase,
ScopedTypeVariables #-}

module Hode.UI.ExprTree (
  -- | * inserting layers of nodes
    insertSearchResults_atFocus  -- ^ St -> Either String St

  , insertMembers_atFocus -- ^ St ->    Either String St

  , insertHosts_atFocus   -- ^ St ->    Either String St
  , groupHostRels_atFocus -- ^ St ->    Either String [(HostFork, [Addr])]
  , groupHostRels  -- ^ Rslt -> Addr -> Either String [(HostFork, [Addr])]

  , addrsToExprRows
    -- ^ St
    -- Set Addr -- ^ show these (can be empty) as `Addr`s,
    --            -- not (complex) `Expr`s
    -- [Addr] -- ^ each of these becomes a `ExprRow`
    -- Either String (Porest ExprRow)
  ) where

import           Control.Lens hiding (has, folded)
import           Data.Foldable (toList)
import           Data.Map (Map)
import qualified Data.List             as L
import qualified Data.List.PointedList as P
import qualified Data.Map              as M
import           Data.Set (Set)
import qualified Data.Set              as S

import Hode.NoUI
import Hode.PTree
import Hode.Rslt.Lookup
import Hode.Rslt.Types
import Hode.UI.Util
import Hode.UI.Util.String
import Hode.UI.Types.State
import Hode.UI.Types.Views
import Hode.Util.Misc


-- | * inserting layers of nodes

-- TODO : much in common with `insertMembers_atFocus`
insertSearchResults_atFocus :: St -> Either String St
insertSearchResults_atFocus st =
  prefixLeft "insertSearchResults_atFocus:" $ do
  a :: Addr <- resultWindow_focusAddr st
  as :: Set Addr <- searchResults_at (st ^. appRslt) a
  leaves :: Porest ExprRow <-
    -- The new subtree has depth two. This is the second level.
    addrsToExprRows st mempty $ S.toList as
  let new :: PTree ExprRow =
        pTreeLeaf ( exprRow_from_viewExprNode $ VenFork $ ViewFork
                    { _viewForkCenter = Just a
                    , _viewForkSortTplt = Nothing
                    , _viewForkType = VFSearch } )
        & pMTrees .~ Just leaves
  Right $ st & ( stSetFocused_ViewExprNode_Tree
                 %~ insertUnder_andFocus new )

searchResults_at :: Rslt -> Addr -> Either String (Set Addr)
searchResults_at r a =
  prefixLeft "searchResults_at:" $ do
  ss :: [String] <- addrToExpr r a >>= flatten r
  nFindAddrs r $ concat $ L.intersperse " " ss

insertMembers_atFocus :: St -> Either String St
insertMembers_atFocus st =
  prefixLeft "insertMembers_atFocus:" $ do
  a            <- resultWindow_focusAddr st
  as :: [Addr] <- M.elems <$> has (st ^. appRslt) a
  leaves :: Porest ExprRow <-
    -- The new subtree has depth two. This is the second level.
    addrsToExprRows st (S.singleton a) as
  let new :: PTree ExprRow =
        pTreeLeaf ( ExprRow
                    { _viewExprNode = VenFork $ ViewFork
                      { _viewForkCenter = Just a
                      , _viewForkSortTplt = Nothing
                      , _viewForkType = VFMembers }
                    , _numColumnProps = mempty
                    , _boolProps = BoolProps
                      { _inSortGroup = False
                      , _selected = False }
                    , _otherProps = OtherProps { _folded = False
                                               , _childSort = Nothing } } )
        & pMTrees .~ Just leaves
  Right $ st & ( stSetFocused_ViewExprNode_Tree
                 %~ insertUnder_andFocus new )

insertHosts_atFocus :: St -> Either String St
insertHosts_atFocus st =
  prefixLeft "insertHosts_atFocus:" $ do
  groups :: [(ViewFork, [Addr])] <-
    groupHostRels_atFocus st
  newTrees :: [PTree ExprRow] <-
    ifLefts $ map (hostGroup_to_forkTree st) groups
  oldTrees :: Maybe (Porest ExprRow) <-
    let errMsg = "focused ViewExprNode not found."
    in maybe (Left errMsg) Right $ st ^?
       stGetFocused_ViewExprNode_Tree . pMTrees
  let oldTrees' :: [PTree ExprRow]
      oldTrees' = maybe [] toList oldTrees
      insert :: PTree ExprRow -> PTree ExprRow
      insert foc = foc & pMTrees .~
                   P.fromList (foldr (:) oldTrees' newTrees)
  Right $ st & stSetFocused_ViewExprNode_Tree %~ insert

groupHostRels_atFocus ::
  St -> Either String [(ViewFork, [Addr])]
groupHostRels_atFocus st =
  prefixLeft "groupHostRels_atFocus:" $ do
  a :: Addr <- maybe
    (Left "Buffer or focused ViewExprNode not found.")
    Right $ st ^? stGetFocused_ViewExprNode_Tree .
      pTreeLabel . viewExprNode . _VenExpr . viewExpr_Addr
  groupHostRels (st ^. appRslt) a

groupHostRels ::
  Rslt -> Addr -> Either String [(ViewFork, [Addr])]
groupHostRels r a0 =
  prefixLeft "groupHostRels:" $ do
  ras :: [(Role, HostAddr)] <-
    S.toList <$> isIn r a0
  vs :: [ExprCtr] <-
    map fst <$> ifLefts (map (variety r . snd) ras)
  let ravs :: [((Role,HostAddr),ExprCtr)]
        = zip ras vs

      ( tplt_ras :: [(Role,TpltAddr)],
        rel_ras  :: [(Role,RelAddr)] ) =
        -- Separate `ras` into `Tplt`s and `Rel`s
        both %~ map fst $ L.partition isTplt ravs
        where
          isTplt :: ((Role,HostAddr),ExprCtr) -> Bool
          isTplt = (\case TpltCtr -> True; _ -> False) . snd

      maybeInsertTpltHosts :: [(ViewFork, [Addr])]
                         -> [(ViewFork, [Addr])]
        -- There is at most one `TpltHostFork`.
        = if null tplt_ras then id
          else (:) ( ViewFork
                     { _viewForkCenter = Just a0
                     , _viewForkSortTplt = Nothing
                     , _viewForkType = VFTpltHosts }
                   , map snd tplt_ras )

  rel_tplts :: [TpltAddr] <-
    -- The `Tplt`s used by the `rel_ras`.
    -- Each implies at least one `RelHostFork`.
    let tpltOf :: RelAddr -> Either String TpltAddr
        tpltOf a = prefixLeft "tpltOf:" $
                   fills r (RoleInRel' RoleTplt, a)
    in ifLefts $ map (tpltOf . snd) rel_ras

  let rel_groups :: Map (Role,TpltAddr) [RelAddr]
      rel_groups =
        foldr f M.empty $
        (zip rel_ras rel_tplts :: [( (Role,RelAddr),
                                     TpltAddr )] )
        where
          f ::    ((Role, RelAddr), TpltAddr)
            -> Map (Role, TpltAddr) [RelAddr]
            -> Map (Role, TpltAddr) [RelAddr]
          f ((role,a),t) m =
            -- efficient: `a` is prepended, not appended.
            M.insertWith (++) (role,t) [a] m

      mkRelFork :: ((Role, TpltAddr),[RelAddr])
                -> (ViewFork, [RelAddr])
      mkRelFork ((role,t),as) =
        (relHosts, as)
        where
          relHosts = ViewFork
            { _viewForkCenter = Just a0
            , _viewForkSortTplt = Nothing
            , _viewForkType = VFRelHosts $ RelHostGroup
              { _memberHostsRole = role
              , _memberHostsTplt = tplt t } }
            where tplt :: Addr -> Tplt Expr
                  tplt a = es
                    where Right (ExprTplt es) = addrToExpr r a

  Right $ maybeInsertTpltHosts
    $ map mkRelFork
    $ M.toList rel_groups

-- | `hostGroup_to_forkTree st (hf, as)` makes 2-layer tree.
-- `hf` is the root.
-- The `ViewExpr`s creates from `as` form the other layer.
hostGroup_to_forkTree :: St -> (ViewFork, [Addr])
                      -> Either String (PTree ExprRow)
hostGroup_to_forkTree st (hf, as) =
  prefixLeft "hostGroup_to_forkTree:" $ do
  if null as then Left "There are no host Exprs to show."
             else Right ()
  a <- resultWindow_focusAddr st

  topOfNew :: ExprRow <-
    exprRow_from_viewExprNode' st $
    VenFork hf
  leaves :: Porest ExprRow <-
    addrsToExprRows st (S.singleton a) as
  Right $ PTree {
      _pTreeLabel    = topOfNew
    , _pTreeHasFocus = False
    , _pMTrees       = Just leaves }

-- | Creates a flat (depth 1) `Porest`.
-- For insertion beneath a forking `ViewExprNode`.
addrsToExprRows ::
     St
  -> Set Addr -- ^ show these (can be empty) as `Addr`s,
              -- not (complex) `Expr`s
  -> [Addr] -- ^ each of these becomes a `ExprRow`
  -> Either String (Porest ExprRow)
addrsToExprRows st showAsAddr as =
  prefixLeft "addrsToExprRows:" $ do
  let r  :: Rslt        = st ^. appRslt
      vo :: ViewOptions = st ^. viewOptions
  leaves0 :: [ViewExprNode] <-
    let f = mkViewExpr r vo showAsAddr
    in map VenExpr <$> ifLefts (map f as)
  leaves1 :: [ExprRow] <- ifLefts $
    map (exprRow_from_viewExprNode' st) leaves0
  let leaves2 :: [PTree ExprRow] =
        map pTreeLeaf leaves1
  maybe (Left "Nothing to show.") Right
    $ P.fromList leaves2
