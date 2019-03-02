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
import           Data.Maybe
import           Data.Tree as T
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
type Path = [Int]

data Window = Window { _windowPath :: Path
                     , _windowEditor :: B.Editor String Path
                     }
makeLenses ''Window

data St = St {
    _windows :: [Tree Window]
  , _focus :: Path
  }
makeLenses ''St


-- | = functions

main :: IO St
main = mainFrom aState

mainFrom :: St -> IO St
mainFrom = B.defaultMain app

aState :: St
aState = let
  pw :: Path -> Window
  pw p = Window { _windowPath = p
                , _windowEditor =
                  B.editor p (Just 1) $ show $ reverse p }

  pt :: Path -> Tree Int -> Tree Window
  pt p (Node i []) = Node (pw $ i : p) []
  pt p (Node i ns) = Node (pw $ i : p)
                    $ map (pt $ i : p) ns

  in St { _focus = [0,1,1]
        , _windows = map (pt [])
          [ Node 0 [ Node 0 []
                   , Node 1 [ Node 0 []
                            , Node 1 [] ] ]
          , Node 1 [ Node 0 [ Node 0 [ Node 0 []
                                     , Node 1 [ Node 0 []
                                              , Node 1 [] ] ]
                            , Node 1 [] ]
                   , Node 1 [ Node 0 []
                            , Node 1 [ Node 0 []
                                     , Node 1 [] ] ] ] ]
        }

app :: B.App St e Path
app = B.App
  { B.appDraw         = appDraw
  , B.appChooseCursor = appChooseCursor
  , B.appHandleEvent  = appHandleEvent
  , B.appStartEvent   = return
  , B.appAttrMap      = const appAttrMap
  }

treeDraw :: St -> Tree Window -> B.Widget Path
treeDraw st (Node (Window p e) ws) =
  B.renderEditor (str . unlines) (reverse p == st ^. focus) e
  <=> padLeft (B.Pad 2) (vBox $ map (treeDraw st) ws)

appDraw :: St -> [B.Widget Path]
appDraw st = [vBox $ map (treeDraw st) $ st ^. windows]

-- | Ignore the list; this app needs cursor locations to be in a tree (or
-- maybe a map, keys of which are first drawn from a tree in the `St`).
appChooseCursor ::
  St -> [B.CursorLocation Path] -> Maybe (B.CursorLocation Path)
appChooseCursor _ _ = Nothing

appHandleEvent ::
  St -> B.BrickEvent Path e -> B.EventM Path (B.Next St)
appHandleEvent st _ = B.halt st

appAttrMap :: B.AttrMap
appAttrMap = B.attrMap B.defAttr
    [ (B.editAttr,        B.white `on` B.black)
    , (B.editFocusedAttr, B.black `on` B.yellow)
    ]

stFocusWindow :: St -> Maybe Window
stFocusWindow st = let foc = st ^. focus in
  -- TODO : head bad (used twice here).
  -- Maps would be better than lists to build a tree.
  case foc of
    [] -> Nothing
    path -> go path topWindow where
      topWindow = Node (error "impossible") (st ^. windows)
      go :: [Int] -> Tree Window -> Maybe Window
      go []       (Node w _)  = Just w
      go (i : is) (Node _ ts) = go is nextWindow where
        nextWindow = head $ filter f ts where
          f :: Tree Window -> Bool
          f (Node (Window i' _) _) = i == head i'