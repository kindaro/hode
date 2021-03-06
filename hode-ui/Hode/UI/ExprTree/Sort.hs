{-# LANGUAGE ScopedTypeVariables #-}

module Hode.UI.ExprTree.Sort (
    sortFocusAndPeers                -- ^ (BinOrientation, TpltAddr)
                                     -- -> St -> Either String St
  , addSelections_toSortedRegion      -- ^ St -> Either String St
  , removeSelections_fromSortedRegion -- ^ St -> Either String St
  , raiseSelection_inSortedRegion     -- ^ St -> Either String St
  , lowerSelection_inSortedRegion     -- ^ St -> Either String St
  , pointedListOf_exprRowPTrees_withSameFocus
    -- ^ Porest ExprRow -> [PTree ExprRow] -> Either String (Porest ExprRow)
  ) where

import           Control.Lens hiding (re, below)
import           Data.Foldable (toList)
import qualified Data.List             as L
import qualified Data.List.PointedList as P
import           Data.Maybe
import           Data.Set (Set)
import qualified Data.Set              as S

import Hode.Hash.Lookup
import Hode.PTree
import Hode.Rslt.Binary
import Hode.Rslt.Edit
import Hode.Rslt.Sort
import Hode.Rslt.Types
import Hode.UI.CycleBuffer
import Hode.UI.Types.State
import Hode.UI.Types.Views
import Hode.UI.Window (showReassurance)
import Hode.Util.Misc


-- | `sortFocusAndPeers (bo, t) st` finds the focused expr `e`
-- in the focused buffer of `st`, and its `peers` in the view.
-- and sorts them all according to `(bo,t)`.
-- It also sets the childSort field of their parents to `Just (bo,t)`
sortFocusAndPeers ::
  (BinOrientation, TpltAddr) -> St -> Either String St
sortFocusAndPeers (bo, t) st =
  prefixLeft "sortFocusAndPeers: " $ do
  peers :: Porest ExprRow <-
    case st ^? stFocusPeers of Just x  -> Right x
                               Nothing -> Left $ "Focused expr has no peers -- probably because it's the root of the view."
  let r :: Rslt = st ^. appRslt
      mas :: [Maybe Addr] =
        map (^? pTreeLabel . exprRow_addr) $ toList peers
  as :: [Addr] <-
    let f :: Maybe Addr -> Either String Addr
        f Nothing = Left $ "Sort failed. Probably because the focused node is a view-gropuiing node, as opposed to an expression in the graph. Try moving the cursor and re-executing that command."
        f (Just a) = Right a
    in mapM f mas

  (sorted :: [Addr], isol :: [Addr]) <-
    kahnSort r (bo,t) as
  let sortedSet :: Set Addr = S.fromList sorted
      order :: [Addr]       = sorted ++ isol
      peers1 :: Porest ExprRow = -- sort
        sortPList_asList
        ( fromJust
          . (^? pTreeLabel . exprRow_addr))
        order peers
  peers2 :: Porest ExprRow <- let -- modify _boolProps
    f :: PTree ExprRow -> Either String (PTree ExprRow)
    f er = do
      a :: Addr <- maybe (Left "peers2: something has no Addr.") Right
        $ er ^? pTreeLabel . viewExprNode . _VenExpr . viewExpr_Addr
      Right $ er & ( pTreeLabel . boolProps . inSortGroup
                     .~ elem a sortedSet )
    in mapM f peers1

  Right $ st &
    ( stSet_focusedBuffer . bufferExprRowTree . setParentOfFocusedSubtree
      . pMTrees . _Just                     .~ peers2 ) &
    ( stSet_focusedBuffer . bufferExprRowTree . setParentOfFocusedSubtree
      . pTreeLabel . otherProps . childSort .~ Just (bo,t) )

-- ^ `addSelections_toSortedRegion st`
-- adds all the selected peers of the currently focused node
-- to the set of its peers that are sorted. It adds relationships
-- to the graph, such that the new nodes end up at the bottom of the sorted
-- region, in the same order (relative to each other) as they had before.
-- It also reorders the appearance of those expressions in the buffer.
--
-- PITFALL: Only tested by hand. Here's how:
--   r = nInserts (mkRslt mempty) ["a # b","c","d","e","f","(/t /_ x /_) #is transitive"]
--   st <- uiFromRslt r
--   Then run these commands
--     /f a | b | c | d | e | f
--     /sl (/t /_ x /_)
--   Then select (`M-X`) the expressions d and e.
--   Then include them in the sort (`M-i`).
--   The display should now read "a,b,d,e,c,f", and a-d should be
--      colored differently from c and f in the how-it's-sorted column.

addSelections_toSortedRegion :: St -> Either String St
addSelections_toSortedRegion _st =
  prefixLeft "addSelections_toSortedRegion: " $ do

  -- fetch stuff
  _peers :: Porest ExprRow <-
    case _st ^? stFocusPeers of Just x  -> Right x
                                Nothing -> Left $ "Focused expr has no peers -- probably because it's the root of the view."
  case _peers ^. P.focus . pTreeLabel . viewExprNode of
    VenExpr _ -> Right ()
    _ -> Left $ "Focused node is not an Expr in the graph. (Instead it's probably a grouping node.)"
  (bo :: BinOrientation, t :: TpltAddr) <-
    let errMsg = "Focused node and its peers have not been sorted."
    in maybe (Left errMsg) Right
       $ _st ^? stFocusGroupOrder
  let peerErs :: [PTree ExprRow] = toList _peers
      _r :: Rslt = _st ^. appRslt

  -- Partition the list into:
  -- `unseld` : rows not in the sort, to stay out of it
  -- `seld` : rows to be added to the sort
  -- `inSort` : rows already in the sort
  -- (`outSort` is only used to create `unseld` and `seld`.)
  let inSort, outSort, _seld, unseld :: [PTree ExprRow]
      (inSort, outSort) =
        L.partition (^. pTreeLabel . boolProps . inSortGroup) peerErs
      (_seld,   unseld)  =
        L.partition (^. pTreeLabel . boolProps . selected) outSort

  if null _seld then Left "Nothing is selected here."
    else Right ()
  _seld <- Right $ _seld &
    traversed . pTreeLabel . boolProps . inSortGroup .~ True

  -- add new relationships to the `Rslt`
  let inSortAs :: [Addr] = inSort ^.. traversed . pTreeLabel . exprRow_addr
      seldAs   :: [Addr] = _seld  ^.. traversed . pTreeLabel . exprRow_addr
  _r :: Rslt <- insertChain (bo,t) seldAs _r
  _r :: Rslt <- case lastOf traversed inSortAs of
    Nothing -> Right _r
    Just (a :: Addr) ->
      -- connect (last of old sorted) to (first of new sorted)
      let re :: RefExpr = case bo of
            LeftEarlier  -> Rel' $ Rel [a,head seldAs] t
            RightEarlier -> Rel' $ Rel [head seldAs,a] t
      in insert re _r

  _peers <- -- reorder the ExprRows
    pointedListOf_exprRowPTrees_withSameFocus
    _peers $ inSort ++ _seld ++ unseld
  Right $ _st
    & appRslt .~ _r
    & ( stSet_focusedBuffer . bufferExprRowTree
        . setPeersOfFocusedSubtree . _Just
        .~ _peers )
    & showReassurance "Selections have been added to the order that currently orders the focused expression and its peers."

removeSelections_fromSortedRegion :: St -> Either String St
removeSelections_fromSortedRegion _st =
  prefixLeft "removeSelections_fromSortedRegion: " $ do

  -- fetch stuff
  _peers :: Porest ExprRow <-
    case _st ^? stFocusPeers of Just x  -> Right x
                                Nothing -> Left $ "Focused expr has no peers -- probably because it's the root of the view."
  case _peers ^. P.focus . pTreeLabel . viewExprNode of
    VenExpr _ -> Right ()
    _ -> Left $ "Focused node is not an Expr in the graph. (Instead it's probably a grouping node.)"
  t :: TpltAddr <-
    let errMsg = "Focused node and its peers have not been sorted."
    in maybe (Left errMsg) (Right . snd)
       $ _st ^? stFocusGroupOrder
  let peerErs :: [PTree ExprRow] = toList _peers
      _r :: Rslt = _st ^. appRslt

  -- Partition the list into:
  -- `unseld` : rows in the sort, to stay there
  -- `seld` : rows to be removed from the sort
  -- `outSort` : rows already not part of the sort
  -- (`inSort` is only used to create `unseld` and `seld`.)
  let inSort, outSort, _seld, unseld :: [PTree ExprRow]
      (inSort, outSort) =
        L.partition (^. pTreeLabel . boolProps . inSortGroup) peerErs
      (_seld,  unseld)  =
        L.partition (^. pTreeLabel . boolProps . selected) inSort

  if null _seld then Left "Nothing is selected here."
    else Right ()
  _seld <- Right $ _seld &
    traversed . pTreeLabel . boolProps . inSortGroup .~ False

  let unseldAs :: [Addr] = unseld ^.. traversed . pTreeLabel . exprRow_addr
      seldAs   :: [Addr] = _seld  ^.. traversed . pTreeLabel . exprRow_addr

  -- Delete relationships from the `Rslt`
  _r <- separateSimply t unseldAs seldAs _r
  _r <- separateSimplyMutually t seldAs _r
  _conns :: [[Addr]] <-
    connections _r SearchLeftward  t seldAs (S.fromList unseldAs)
  _conns :: [[Addr]] <-
    (_conns ++) <$>
    connections _r SearchRightward t seldAs (S.fromList unseldAs)
    -- TODO : If there are any connections, this is inefficient --
    --   it finds them all, present the user with one of them,
    --   and discards the rest. Once the user breaks one and tries again,
    --   Hode will search for all remaining connections again.
    --   (`removeSelections_fromSortedRegion` repeats some other tasks too,
    --   but they are not likely to be expensive.)

  if null _conns
    then do
      _peers <- -- reorder the ExprRows
        pointedListOf_exprRowPTrees_withSameFocus
        _peers $ unseld ++ _seld ++ outSort
      Right $ _st
        & appRslt .~ _r
        & ( stSet_focusedBuffer . bufferExprRowTree
            . setPeersOfFocusedSubtree . _Just
            .~ _peers )
        & showReassurance "Selections have been removed from the order that currently orders the focused expression and its peers."

    else do
      b :: Buffer <-
        bufferFromPath _st ProblematicChain (t, head _conns)
      _st :: St <- return $
        case _st ^. stGetTopLevelBuffer_byQuery ProblematicChain
        of Nothing -> _st & insertBuffer_byQuery ProblematicChain
           _       -> _st
      Right $ _st
        & stSetTopLevelBuffer_byQuery ProblematicChain .~ b
        & showReassurance "You asked Hode to remove the selected expressions from the ordering that currently orders the focused expression and its peers, but a chain of length > 1 connects them. You can find it in the ProblematicChain buffer. Please break that chain and try again."

-- | Consider a buffer in which the focused node's peers appear,
-- reading from top to bottom, as A, B, C, D, E, F.
-- They have been sorted, and A through E are in the sort,
-- while F is not. C and D are selected.
-- If the user runs `raiseSelection_inSortedRegion`,
-- then the selected expressions C and D will rise by one space in the list.
-- That is, B will be disconnected from C and D
-- (if they are connected, which they might not be),
-- and then connected on the other side of (that is, below) D.
-- PITFALL: B will end up connected to D alone, not to both C and D.

raiseSelection_inSortedRegion :: St -> Either String St
raiseSelection_inSortedRegion _st =
  prefixLeft "removeSelections_fromSortedRegion: " $ do
  -- fetch stuff
  _peers :: Porest ExprRow <-
    case _st ^? stFocusPeers of Just x  -> Right x
                                Nothing -> Left $ "Focused expr has no peers -- probably because it's the root of the view."
  case _peers ^. P.focus . pTreeLabel . viewExprNode of
    VenExpr _ -> Right ()
    _ -> Left $ "Focused node is not an Expr in the graph. (Instead it's probably a grouping node.)"
  (bo :: BinOrientation, t :: TpltAddr) <-
    let errMsg = "Focused node and its peers have not been sorted."
    in maybe (Left errMsg) Right
       $ _st ^? stFocusGroupOrder
  let peerErs :: [PTree ExprRow] = toList _peers
      _r :: Rslt = _st ^. appRslt

  -- Partition the list into:
  -- `unseld` : rows in the sort, to stay there
  -- `seld` : rows to be removed from the sort
  -- `outSort` : rows already not part of the sort
  -- (`inSort` is only used to create `unseld` and `seld`.)
  let inSort, outSort :: [PTree ExprRow]
      (inSort, outSort) =
        L.partition (^. pTreeLabel . boolProps . inSortGroup) peerErs
  ( _above :: [PTree ExprRow],
    _seld  :: [PTree ExprRow],
    below  :: [PTree ExprRow]) <-
    case beforeDuringAfter (^. pTreeLabel . boolProps .selected ) inSort
    of Right x -> Right x
       Left _ -> Left "Among the focused expression's peers, than one contiguous subset are selected. Please deselect something; at most one contiguous subset at a time can be shifted up in the order."

  case null _above of
    True -> Right _st -- can't get any higher
    False -> do
      if null _seld then Left "Nothing is selected here."
        else Right ()

      -- `crosser`, the last element of `_above`, will be moved
      -- to the other side of (i.e. above) the selected expressions.
      ( _above :: [PTree ExprRow],
        crosser :: PTree ExprRow) <-
        (_2 %~ head) <$> -- Safe because _above is not null.
        Right (splitAt (length _above - 1) _above)
      let crosserA :: Addr =
            maybe (error "impossible: we checked that the focused node is an Expr, so the crosser should be one too.") id $
            crosser                  ^?              pTreeLabel . exprRow_addr
          seldAs  :: [Addr] = _seld  ^.. traversed . pTreeLabel . exprRow_addr

      -- Hopefully, after deleting all direct connections from crosser
      -- to seld, they will be disconnected.
      _r <- separateSimply t [crosserA] seldAs _r
      _conns :: [[Addr]] <-
        let sd :: SearchDir = case bo of
              LeftEarlier  -> SearchRightward
              RightEarlier -> SearchLeftward
        in connections _r sd  t [crosserA] (S.fromList seldAs)
      if null _conns

        then do
          _peers <- -- reorder the ExprRows
            pointedListOf_exprRowPTrees_withSameFocus
            _peers $ _above ++ _seld ++ (crosser : below) ++ outSort
          _r :: Rslt <- let
            re :: RefExpr = case bo of
              LeftEarlier  -> Rel' $ Rel [last seldAs, crosserA] t
              RightEarlier -> Rel' $ Rel [crosserA, last seldAs] t
            in insert re _r
          Right $ _st
            & appRslt .~ _r
            & ( stSet_focusedBuffer . bufferExprRowTree
                . setPeersOfFocusedSubtree . _Just
                .~ _peers )
            & showReassurance "Selected expressions have been bumped up in the order currently ordering the focused expression."

        else do
          b :: Buffer <-
            bufferFromPath _st ProblematicChain (t, head _conns)
          _st :: St <- return $
            case _st ^. stGetTopLevelBuffer_byQuery ProblematicChain
            of Nothing -> _st & insertBuffer_byQuery ProblematicChain
               _       -> _st
          Right $ _st
            & stSetTopLevelBuffer_byQuery ProblematicChain .~ b
            & showReassurance "You asked Hode to move the selected expressions up in the order that currently orders the focused expression and its peers, but a chain of length > 1 currently makes that impossible. You can find it in the ProblematicChain buffer. Please break that chain and try again."


-- | Consider a buffer in which the focused node's peers appear,
-- reading from top to bottom, as A, B, C, D, E, F.
-- They have been sorted, and A through E are in the sort,
-- while F is not. B and C are selected.
-- If the user runs `lowerSelection_inSortedRegion`,
-- then the selected expressions B and C will fall by one space in the list.
-- That is, D will be disconnected from B and C
-- (if they are connected, which they might not be),
-- and then connected on the other side of (that is, above) B.
-- PITFALL: D will end up connected to B alone, not to both B and C.

lowerSelection_inSortedRegion :: St -> Either String St
lowerSelection_inSortedRegion _st =
  prefixLeft "removeSelections_fromSortedRegion: " $ do
  -- fetch stuff
  _peers :: Porest ExprRow <-
    case _st ^? stFocusPeers of Just x  -> Right x
                                Nothing -> Left $ "Focused expr has no peers -- probably because it's the root of the view."
  case _peers ^. P.focus . pTreeLabel . viewExprNode of
    VenExpr _ -> Right ()
    _ -> Left $ "Focused node is not an Expr in the graph. (Instead it's probably a grouping node.)"
  (bo :: BinOrientation, t :: TpltAddr) <-
    let errMsg = "Focused node and its peers have not been sorted."
    in maybe (Left errMsg) Right
       $ _st ^? stFocusGroupOrder
  let peerErs :: [PTree ExprRow] = toList _peers
      _r :: Rslt = _st ^. appRslt

  -- Partition the list into:
  -- `unseld` : rows in the sort, to stay there
  -- `seld` : rows to be removed from the sort
  -- `outSort` : rows already not part of the sort
  -- (`inSort` is only used to create `unseld` and `seld`.)
  let inSort, outSort :: [PTree ExprRow]
      (inSort, outSort) =
        L.partition (^. pTreeLabel . boolProps . inSortGroup) peerErs
  ( above  :: [PTree ExprRow],
    _seld  :: [PTree ExprRow],
    _below :: [PTree ExprRow]) <-
    case beforeDuringAfter (^. pTreeLabel . boolProps .selected ) inSort
    of Right x -> Right x
       Left _ -> Left "Among the focused expression's peers, than one contiguous subset are selected. Please deselect something; at most one contiguous subset at a time can be shifted down in the order."

  case null _below of
    True -> Right _st -- can't get any lower
    False -> do
      if null _seld then Left "Nothing is selected here."
        else Right ()

      -- `crosser`, the first element of `_below`, will be moved
      -- to the other side of (i.e. above) the selected expressions.
      ( crosser ::  PTree ExprRow,
        _below  :: [PTree ExprRow] ) <-
        (_1 %~ head) <$> -- Safe because _above is not null.
        Right (splitAt 1 _below)
      let crosserA :: Addr =
            maybe (error "impossible: we checked that the focused node is an Expr, so the crosser should be one too.") id $
            crosser                  ^?              pTreeLabel . exprRow_addr
          seldAs  :: [Addr] = _seld  ^.. traversed . pTreeLabel . exprRow_addr

      -- Hopefully, after deleting all direct connections from crosser
      -- to seld, they will be disconnected.
      _r <- separateSimply t [crosserA] seldAs _r
      _conns :: [[Addr]] <-
        let sd :: SearchDir = case bo of
              LeftEarlier  -> SearchLeftward
              RightEarlier -> SearchRightward
        in connections _r sd  t [crosserA] (S.fromList seldAs)
      if null _conns

        then do
          _peers <- -- reorder the ExprRows
            pointedListOf_exprRowPTrees_withSameFocus
            _peers $ above ++ (crosser : _seld) ++ _below ++ outSort
          _r :: Rslt <- let
            re :: RefExpr = case bo of
              LeftEarlier  -> Rel' $ Rel [crosserA, last seldAs] t
              RightEarlier -> Rel' $ Rel [last seldAs, crosserA] t
            in insert re _r
          Right $ _st
            & appRslt .~ _r
            & ( stSet_focusedBuffer . bufferExprRowTree
                . setPeersOfFocusedSubtree . _Just
                .~ _peers )
            & showReassurance "Selected expressions have been bumped down in the order currently ordering the focused expression."

        else do
          b :: Buffer <-
            bufferFromPath _st ProblematicChain (t, head _conns)
          _st :: St <- return $
            case _st ^. stGetTopLevelBuffer_byQuery ProblematicChain
            of Nothing -> _st & insertBuffer_byQuery ProblematicChain
               _       -> _st
          Right $ _st
            & stSetTopLevelBuffer_byQuery ProblematicChain .~ b
            & showReassurance "You asked Hode to move the selected expressions down in the order that currently orders the focused expression and its peers, but a chain of length > 1 currently makes that impossible. You can find it in the ProblematicChain buffer. Please break that chain and try again."


-- | `pointedListOf_exprRowPTrees_withSameFocus focusModel pters`
-- returns `pters` in the form of a `Porest`,
-- focused on the element with the same address `focusModel`'s focus.
--
-- todo ? untested

pointedListOf_exprRowPTrees_withSameFocus
  :: Porest ExprRow -> [PTree ExprRow] -> Either String (Porest ExprRow)
pointedListOf_exprRowPTrees_withSameFocus focusModel pters =
  prefixLeft "pointedListOf_exprRowPTrees_withSameFocus: " $ do
  let pterAddr :: PTree ExprRow -> Either String Addr =
        maybe (Left "ExprRow should have an address. It's probably a grouping node (a VenFork), whereas it should be an expression from the graph (a VenExpr).") Right
        . (^? pTreeLabel . viewExprNode . _VenExpr . viewExpr_Addr)
  foc :: Addr <-
    focusModel ^. P.focus & pterAddr
  let (above :: [PTree ExprRow], rest :: [PTree ExprRow]) =
        span ((/= Right foc) . pterAddr) pters
  case rest of
    [] ->
      Left "No ExprRow in `pters` has the same address as the focus of `focusModel`."
    focus : below ->
      Right $ P.PointedList (reverse above) focus below
