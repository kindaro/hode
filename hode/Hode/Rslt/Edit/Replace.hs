{-# LANGUAGE ScopedTypeVariables #-}

module Hode.Rslt.Edit.Replace (
    replaceRefExpr  -- ^      RefExpr -> Addr -> Rslt -> Either String Rslt
  , replaceInRole  -- ^ Role -> Addr -> Addr -> Rslt -> Either String Rslt
  , substitute     -- ^         Addr -> Addr -> Rslt -> Either String Rslt
  ) where

import           Data.Map (Map)
import qualified Data.Map       as M
import           Data.Set (Set)
import qualified Data.Set       as S

import Hode.Rslt.Lookup
import Hode.Rslt.Types
import Hode.Rslt.Util
import Hode.Rslt.Valid
import Hode.Util.Misc
import Hode.Rslt.Edit.Initial


-- | `replaceRefExpr re oldAddr r0` deletes the `Expr` at `oldAddr`,
-- creates or finds the `RefExpr` to replace it,
-- and substitutes the new one for the old one everywhere it appeared.
replaceRefExpr :: RefExpr -> Addr -> Rslt -> Either String Rslt
replaceRefExpr re oldAddr r0 =
  prefixLeft "replaceRefExpr:" $
  case refExprToAddr r0 re of
    Right newAddr -> do
      r2 <- substitute oldAddr newAddr r0
      deleteIfUnused oldAddr r2
    Left _ -> do
      newAddr <- nextAddr r0
      _       <- validRefExpr r0 re
      r1      <- insertAt newAddr re r0
      r2      <- substitute oldAddr newAddr r1
      deleteIfUnused oldAddr r2

replaceInRole :: Role -> Addr -> HostAddr -> Rslt -> Either String Rslt
-- PITFALL: Mutually recursive with `substitute`.
replaceInRole spot new host r =
  prefixLeft "replaceInRole:" $ do
  _                          <- addrToRefExpr r new
  oldHostRefExpr             <- addrToRefExpr r host
  (hostHas :: Map Role Addr) <- has r host
  (old :: Addr) <- let
    err = Left $ "RefExpr at " ++ show host
          ++ " includes no position " ++ show spot ++ "."
    in maybe err Right $ M.lookup spot hostHas

  (newHostRefExpr :: RefExpr) <-
    _replaceInRefExpr r spot new oldHostRefExpr
  (newIsAlreadyIn :: Set (Role,Addr)) <- isIn r new

  Right $ r {
      _addrToRefExpr = M.insert host newHostRefExpr
                       $ _addrToRefExpr r
    , _refExprToAddr = M.insert newHostRefExpr host
                       $ M.delete oldHostRefExpr
                       $ _refExprToAddr r

    , _has    = M.adjust (M.insert spot new) host $ _has r

    , _isIn   =   M.filter (not . null)
      -- PITFALL: delete before inserting. Otherwise, replacing something
      -- with itself is not the identity operation.
                . M.insert new (S.insert (spot, host) newIsAlreadyIn)
      -- PITFALL: We can't adjust the value at new; it might not exist.
                . M.adjust (S.delete (spot, host)) old
                $ _isIn r
    }

-- | `substitute old new r0` substitutes `new` for `old`
-- in every host that used to hold `old`.
substitute :: Addr -> Addr -> Rslt -> Either String Rslt
-- PITFALL: Mutually recursive with `replaceInRole`.
substitute old new r0 =
  prefixLeft "substitute:" $ do
  (roles :: Set (Role, Addr)) <- isIn r0 old
  let f :: Either String Rslt -> (Role, Addr) -> Either String Rslt
      f e@(Left _) _ = e
      f (Right r) (role,host) = replaceInRole role new host r
  S.foldl f (Right r0) roles
