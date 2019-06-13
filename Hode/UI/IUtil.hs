{-# LANGUAGE ScopedTypeVariables #-}

module Hode.UI.IUtil (
    unEitherSt             -- ^ Either String St -> St -> St

  , emptySt                -- ^ Rslt -> St
  , emptyBuffer            -- ^                                 Buffer
  , buffer_from_bufferRowTree -- ^ PTree ViewExprNode -> Either String Buffer
  ) where

import qualified Data.List.PointedList as P
import qualified Data.Map              as M
import           Lens.Micro

import qualified Brick.Focus           as B
import qualified Brick.Widgets.Edit    as B

import Hode.Brick
import Hode.Hash.HTypes
import Hode.Rslt.RTypes
import Hode.Qseq.QTypes (Var(..))
import Hode.UI.ITypes
import Hode.UI.Window
import Hode.Util.PTree


unEitherSt :: St -> Either String St -> St
unEitherSt old (Left s) = old & showError s
unEitherSt _ (Right new) = new & showingErrorWindow .~ False

emptySt :: Rslt -> St
emptySt r = St {
    _focusRing = B.focusRing [BrickOptionalName Commands]
  , _searchBuffers = Just $ porestLeaf emptyBuffer
                          & P.focus . pTreeHasFocus .~ True
  , _columnHExprs = -- TODO : This is a hack. In TODO.org,
      -- see the section called  (HExpr: add a symbol for "involves")
      [ HOr [ HMap $ M.singleton RoleTplt $ HVar VarRowNode
            , HMap $ M.singleton (RoleMember 1) $ HVar VarRowNode
            , HMap $ M.singleton (RoleMember 2) $ HVar VarRowNode
            , HMap $ M.singleton (RoleMember 3) $ HVar VarRowNode ] ]
  , _uiError   = ""
  , _reassurance = "It's all good."
  , _commands  = B.editor (BrickOptionalName Commands) Nothing ""
  , _commandHistory = []
  , _appRslt   = r
  , _showingErrorWindow = False
  , _showingInMainWindow = Results
  , _showingOptionalWindows = M.fromList [ (Commands   , True)
                                         , (Reassurance, True) ]
  }

emptyBuffer :: Buffer
emptyBuffer = Buffer {
    _bufferQuery = "(empty buffer)"
  , _bufferRowPorest =
    Just $ porestLeaf $ bufferRow_from_viewExprNode $ VQuery
    "There are no search results to show here (yet)." }

-- | TODO : This ought to handle `VMember`s and `VCenterRole`s too.
buffer_from_bufferRowTree :: PTree BufferRow -> Either String Buffer
buffer_from_bufferRowTree vt = do
  let (br :: BufferRow) = vt ^. pTreeLabel
  vr :: ViewExpr <- case br ^. viewExprNode of
    VExpr x -> Right x
    _ -> Left $ "buffer_from_bufferRowTree called from a non-VExpr."
  Right $ Buffer {
      _bufferQuery     = unAttrString $ vr ^. viewResult_String
    , _bufferRowPorest = P.fromList [vt]
    }