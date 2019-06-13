-- | = Functions from an `Rslt` and a parsed `String`,
-- to search, insert, show.
-- Theoretically, one could maintain an Rslt using GHCI with just these,
-- without ever using the TUI.

{-# LANGUAGE ScopedTypeVariables #-}

module Hode.UI.NoUI where

import           Data.Set (Set)
import qualified Data.Set as S
import           Text.Megaparsec

import Hode.Hash.Convert
import Hode.Hash.HLookup
import Hode.Hash.HParse
import Hode.Qseq.QTypes
import Hode.Rslt.Edit
import Hode.Rslt.RLookup
import Hode.Rslt.RTypes
import Hode.Rslt.Show
import Hode.Util.Misc


pInsert :: Rslt -> String -> Either String (Rslt, Addr)
pInsert r s = prefixLeft "-> pInsert"
  $ mapLeft show (parse pExpr "doh!" s)
  >>= pExprToHExpr r
  >>= hExprToExpr r
  >>= exprToAddrInsert r

pFindAddrs :: Rslt -> String -> Either String (Set Addr)
pFindAddrs r s = prefixLeft "-> pFindAddrs"
  $ mapLeft show (parse pExpr "doh!" s)
  >>= pExprToHExpr r
  >>= hExprToAddrs r (mempty :: Subst Addr)

pFindStrings :: Rslt -> String -> Either String (Set String)
pFindStrings r s = prefixLeft "-> pFindExprs" $ do
  (as :: Set Addr)   <- pFindAddrs r s
  (es :: Set Expr)   <- ifLefts_set $ S.map ( addrToExpr r ) as
  (ss :: Set String) <- ifLefts_set $ S.map (eShow r) es
  return ss

pFindStringsIO :: Rslt -> String -> IO ()
pFindStringsIO r s =
  case (pFindStrings r s :: Either String (Set String))
  of Left err -> putStrLn err
     Right ss -> mapM_ putStrLn ss