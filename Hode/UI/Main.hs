{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TupleSections #-}

module Hode.UI.Main where

import qualified Data.List.PointedList as P
import qualified Data.Map             as M
import           Lens.Micro

import qualified Brick.Main           as B
import qualified Brick.Types          as B
import           Brick.Widgets.Core
import qualified Brick.Widgets.Center as B
import qualified Brick.Widgets.Edit   as B
import qualified Brick.AttrMap        as B
import qualified Brick.Focus          as B
import           Brick.Util (on)
import qualified Graphics.Vty         as V

import Hode.Brick
import Hode.Rslt.Index (mkRslt)
import Hode.Rslt.RTypes
import Hode.UI.Input
import Hode.UI.ITypes
import Hode.UI.IUtil
import Hode.UI.ShowPTree
import Hode.UI.String
import Hode.Util.PTree


ui :: IO St
ui = uiFromRslt $ mkRslt mempty

uiFromSt :: St -> IO St
uiFromSt = B.defaultMain app

uiFromRslt :: Rslt -> IO St
uiFromRslt = B.defaultMain app . emptySt

app :: B.App St e BrickName
app = B.App
  { B.appDraw         = appDraw
  , B.appChooseCursor = appChooseCursor
  , B.appHandleEvent  = appHandleEvent
  , B.appStartEvent   = return
  , B.appAttrMap      = const appAttrMap
  }


-- | The focused subview is recalculated at each call to `appDisplay`.
-- Each `ViewExprNodeTree`'s `viewIsFocused` field is `False` outside of `appDisplay`.
appDraw :: St -> [B.Widget BrickName]
appDraw st0 = [w] where
  w = B.center $
    (if st0 ^. showingErrorWindow then errorWindow else mainWindow)
    <=> optionalWindows

  st = st0 & stSetFocusedBuffer .~ b
           & ( searchBuffers . _Just . P.focus
               . setFocusedSubtree . pTreeHasFocus .~ True )
           & stSetFocused_ViewExprNode_Tree . pTreeHasFocus .~ True
  (b :: Buffer) = maybe err id $  st0 ^? stGetFocused_Buffer . _Just where
      err = error "Focused Buffer not found."

  mainWindow = case st ^. showingInMainWindow of
    SearchBuffers  -> bufferWindow
    CommandHistory -> commandHistoryWindow
    Results        -> resultWindow

  optionalWindows =
    ( if (st ^. showingOptionalWindows) M.! Reassurance
      then reassuranceWindow else emptyWidget ) <=>
    ( if (st ^. showingOptionalWindows) M.! Commands
      then commandWindow else emptyWidget )

  commandHistoryWindow, commandWindow, errorWindow, resultWindow, reassuranceWindow, bufferWindow :: B.Widget BrickName

  commandHistoryWindow =
    strWrap $ unlines $ map show $ st0 ^. commandHistory

  commandWindow = vLimit 1
    ( B.withFocusRing (st^.focusRing)
      (B.renderEditor $ str . unlines) (st^.commands) )

  errorWindow = vBox
    [ strWrap $ st ^. uiError
    , padTop (B.Pad 2) $ strWrap $ "(To escape this error message, press Alt-R (to go to Results), Alt-B (SearchBuffers), or Alt-H (command History)." ]

  reassuranceWindow = withAttr (B.attrName "reassurance")
    $ strWrap $ st0 ^. reassurance

  focusStyle :: PTree a -> B.Widget BrickName
                        -> B.Widget BrickName
  focusStyle bt = visible .  withAttr (B.attrName x) where
    x = if not $ bt ^. pTreeHasFocus
        then "unfocused result"
        else  "focused result"

  bufferWindow = case st ^. searchBuffers of
    Nothing -> str "There are no results to show. Add one with M-S-t."
    Just p ->
      viewport (BrickMainName SearchBuffers) B.Vertical $
      porestToWidget (const "") _bufferQuery (const True) focusStyle p

  resultWindow = case b ^. bufferRowPorest of
    Nothing -> str "There are no results to show (yet)."
    Just p -> let showNode = show_ViewExprNode' . _viewExprNode
                  getFolded = _folded . _otherProps
                  showColumns :: BufferRow -> AttrString
                  showColumns bfr =
                    concatMap ((:[]) . (, textColor) . show) $
                    M.elems $ _columnProps bfr
      in viewport (BrickMainName Results) B.Vertical $
         porestToWidget' attrStringWrap showColumns
         showNode getFolded focusStyle p


appChooseCursor :: St -> [B.CursorLocation BrickName]
                -> Maybe (B.CursorLocation BrickName)
appChooseCursor = B.focusRingCursor (^. focusRing)


appHandleEvent :: St -> B.BrickEvent BrickName e
               -> B.EventM BrickName (B.Next St)
appHandleEvent st (B.VtyEvent ev) = case ev of
  V.EvKey V.KEsc [V.MMeta] -> B.halt st

  -- command window
  V.EvKey (V.KChar 'x') [V.MMeta] -> parseAndRunCommand st

  -- switch main window content
  V.EvKey (V.KChar 'H') [V.MMeta] -> B.continue
    $ st & showingInMainWindow .~ CommandHistory
         & showingErrorWindow .~ False
  V.EvKey (V.KChar 'B') [V.MMeta] -> B.continue
    $ st & showingInMainWindow .~ SearchBuffers
         & showingErrorWindow .~ False
  V.EvKey (V.KChar 'R') [V.MMeta] -> B.continue
    $ st & showingInMainWindow .~ Results
         & showingErrorWindow .~ False
  -- Brick-focus-related stuff. So far unneeded.
    -- PITFALL: The focused `Window` is distinct from the focused
    -- widget within the `mainWindow`.
    -- V.EvKey (V.KChar '\t') [] -> B.continue $ st & focusRing %~ B.focusNext
    -- V.EvKey V.KBackTab []     -> B.continue $ st & focusRing %~ B.focusPrev

  _ -> case st ^. showingInMainWindow of
    Results       -> handleKeyboard_atResultsWindow      st ev
    SearchBuffers -> handleKeyboard_atBufferWindow st ev
    _             -> handleUncaughtInput                  st ev


appHandleEvent st _ = B.continue st


appAttrMap :: B.AttrMap
appAttrMap = let
  gray (k :: Int) = V.rgbColor k k k
  black     = gray 0
  --gray1   = gray 1 -- PITFALL: Vty offers darker non-black grays.
  --  -- See VTY issue https://github.com/jtdaugherty/vty/issues/172
  white     = gray 255
  darkBlue  = V.rgbColor 0 0 (1::Int)
  darkGreen = V.rgbColor 0 1 (0::Int)
  in B.attrMap V.defAttr
    [ (B.editAttr                    , V.black `on` V.red) -- unused
    , (B.editFocusedAttr             , white   `on` darkBlue)
    , (B.attrName "reassurance"      , white   `on` darkGreen)
    , (B.attrName "unfocused result" , white   `on` black)
    , (B.attrName "focused result"   , white   `on` darkGreen)
    ]