-- | Goal: Windows can contain windows, and subwindows can scroll
-- within their parent window.
-- To start there is only one window, an editor with a single number.
-- The user can put a "contents" sub-window (itself not an editor)
-- in that editor, or any later-created editor.
-- A contents subwindow can contain more editors.
-- The user can scroll to the previous, next, parent, or first
-- (or better: most recently accessed) child of any editor.
-- A line containing an ellipsis appears at the start or the end of
-- any set of contiguous subwindows, to indicate that more are off-screen.

{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TemplateHaskell #-}

module UI.ScrollNest where

import           Control.Monad.IO.Class (liftIO)
import           Data.Tree
import qualified Data.Tree as T
import           Lens.Micro
import           Lens.Micro.TH

import qualified Brick.Main as B
import qualified Brick.Types as B
import           Brick.Widgets.Core
import qualified Brick.Widgets.Center as B
import qualified Brick.Widgets.Edit as B
import qualified Brick.AttrMap as B
import qualified Brick.Focus as B
import           Brick.Util (on)
import qualified Graphics.Vty as B


-- | A path from the top window to the given window
-- The top window has the name [].
type Name = [Int] 

data Window = Window Name

data St = St {
    _windows :: Tree Window
  , _focus :: Name
  }

makeLenses ''St


-- | = functions

main :: IO St
main = mainFrom $ St { _windows = T.Node (Window []) []
                     , _focus = [] }

mainFrom :: St -> IO St
mainFrom = B.defaultMain app

app :: B.App St e Name
app = B.App
  { B.appDraw         = appDraw
  , B.appChooseCursor = appChooseCursor
  , B.appHandleEvent  = appHandleEvent
  , B.appStartEvent   = return
  , B.appAttrMap      = const appAttrMap
  }

appDraw :: St -> [B.Widget n]
appDraw = error "?"

-- | Ignore the list; this app needs cursor locations to be in a tree (or
-- maybe a map, they keys of which come from some tree field of the `St`).
appChooseCursor ::
  St -> [B.CursorLocation Name] -> Maybe (B.CursorLocation Name)
appChooseCursor _ _ = Nothing

appHandleEvent ::
  St -> B.BrickEvent Name e -> B.EventM Name (B.Next St)
appHandleEvent st _ = B.continue st

appAttrMap :: B.AttrMap
appAttrMap = B.attrMap B.defAttr
    [ (B.editAttr,        B.white `on` B.blue)
    , (B.editFocusedAttr, B.black `on` B.yellow)
    ]
