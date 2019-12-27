{-# LANGUAGE ScopedTypeVariables
#-}

module Hode.UI.CycleBreaker where

import           Control.Lens
import qualified Data.Set as S
import qualified Data.List.PointedList as P

import Hode.Hash.HLookup
import Hode.PTree.Initial
import Hode.Rslt.Binary
import Hode.Rslt.RTypes
import Hode.UI.ExprTree
import Hode.UI.IUtil
import Hode.UI.Types.Names
import Hode.UI.Types.State
import Hode.UI.Types.Views
import Hode.UI.Window
import Hode.Util.Misc


-- | If the focused buffer has cycles recorded in `bufferCycles`,
-- this recomputes them.
updateBlockingCycles :: St -> Either String St
-- TODO ? This is inefficient -- it recomputes all cycles each time.
updateBlockingCycles st =
  case st ^. blockingCycles of
  Nothing -> Right st
  Just cs0 -> do
    let uniqueKernels :: [(TpltAddr,Addr)] =
          S.toList . S.fromList -- discard duplicates
          $ map (_2 %~ head) cs0
        ci (tplt, start) = cyclesInvolving
          (st ^. appRslt) SearchLeftward tplt start
    cs1 :: [Cycle] <-
      concat <$> mapM ci uniqueKernels
    Right $ st & blockingCycles .~ Just cs1

-- | Updates the cycle buffer to reflect what is now in
-- the focused buffer's `bufferCycles` field.
updateCycleBuffer :: St -> Either String St
updateCycleBuffer st =
  prefixLeft "cycleBuffer:" $ do
  case st ^. blockingCycles of
    Just (c:_) -> do
      cb <- cycleBreaker_fromAddrs st c
      Right ( st & stSet_cycleBuffer .~ cb
              & showingInMainWindow .~ CycleBreaker
              & showReassurance "Please break this cycle." )
    _ -> Right -- applies both to Just [] and to Nothing
      ( st & stSet_cycleBuffer .~ emptyCycleBreaker
        & showingInMainWindow .~ Results
        & blockingCycles .~ Nothing
        & showReassurance "No cycles identified." )

cycleBreaker_fromAddrs :: St -> Cycle -> Either String Buffer
cycleBreaker_fromAddrs st (t,c) = do
  p :: Porest ExprRow <-
    (P.focus . pTreeHasFocus .~ True)
    <$> addrsToExprRows st mempty (t:c)
  Right $ Buffer { _bufferQuery = CycleView
                 , _bufferRowPorest = Just p }
