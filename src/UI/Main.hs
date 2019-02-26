-- | Based on the demos in the programs/ folder of Brick,
-- particularly `EditDemo.hs`.

{-# LANGUAGE ScopedTypeVariables #-}

module UI.Main where

import           Lens.Micro

import qualified Brick.Main as B
import qualified Brick.Types as T
import           Brick.Widgets.Core
import qualified Brick.Widgets.Center as C
import qualified Brick.Widgets.Edit as E
import qualified Brick.AttrMap as A
import qualified Brick.Focus as F
import           Brick.Util (on)
import qualified Graphics.Vty as V

import Rslt.RTypes
import UI.IParse
import UI.ITypes
import UI.State


appDraw :: St -> [T.Widget Name]
appDraw st = [w] where
  resultWindow = F.withFocusRing (st^.focusRing)
    (E.renderEditor (str . unlines)) (st^.results)
  commandWindow = F.withFocusRing (st^.focusRing)
    (E.renderEditor (str . unlines)) (st^.commands)
  w = C.center
    $ resultWindow <=> vLimit 3 commandWindow

appHandleEvent ::
  St -> T.BrickEvent Name e -> T.EventM Name (T.Next St)
appHandleEvent st (T.VtyEvent ev) = case ev of
  V.EvKey V.KEsc []         -> B.halt st
  V.EvKey (V.KChar '\t') [] -> B.continue $ st & focusRing %~ F.focusNext
  V.EvKey V.KBackTab []     -> B.continue $ st & focusRing %~ F.focusPrev

  V.EvKey (V.KChar 'x') [V.MMeta] ->
    let cmd = unlines $ E.getEditContents $ st ^. commands
    in case pCommand (st ^. appRslt) cmd of
      Left s1  -> B.continue $ editor_replaceText results (lines s1) st
      Right c -> case runCommand c st of
        Left s2 -> B.continue $ editor_replaceText results (lines s2) st
        Right st' -> st'

  _ -> B.continue =<< case F.focusGetCurrent (st^.focusRing) of
    Just Results -> T.handleEventLensed
      st results E.handleEditorEvent ev
    Just Commands -> T.handleEventLensed
      st commands E.handleEditorEvent ev
    Nothing -> return st
appHandleEvent st _ = B.continue st

appAttrMap :: A.AttrMap
appAttrMap = A.attrMap V.defAttr
    [ (E.editAttr,        V.white `on` V.blue)
    , (E.editFocusedAttr, V.black `on` V.yellow)
    ]

appChooseCursor ::
  St -> [T.CursorLocation Name] -> Maybe (T.CursorLocation Name)
appChooseCursor = F.focusRingCursor (^.focusRing)

app :: B.App St e Name
app = B.App
  { B.appDraw         = appDraw
  , B.appChooseCursor = appChooseCursor
  , B.appHandleEvent  = appHandleEvent
  , B.appStartEvent   = return
  , B.appAttrMap      = const appAttrMap
  }

ui :: Rslt -> IO St
ui = B.defaultMain app . initialState
