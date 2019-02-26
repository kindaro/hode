{-# LANGUAGE ScopedTypeVariables #-}

module UI.IParse where

import           Data.Set (Set)
import qualified Data.Set as S
import           Text.Megaparsec
import           Text.Megaparsec.Char (string)

import Hash.Convert
import Hash.HLookup
import Hash.HParse
import Hash.HTypes
import Qseq.QTypes
import Rslt.Edit
import Rslt.RLookup
import Rslt.RTypes
import Rslt.Show
import UI.ITypes
import Util.Misc
import Util.UParse


pCommand_insert :: Rslt -> String -> Either String Command
pCommand_insert r s = CommandInsert <$>
  ( prefixLeft "pCommand_insert"
    $ mapLeft show (parse p "doh!" s)
    >>= pExprToHExpr
    >>= hExprToExpr r )
  where p :: Parser PExpr
        p = lexeme (string "/insert" <|> string "/add")
            >> pExpr

pCommand_find :: String -> Either String Command
pCommand_find s = CommandFind <$>
  ( prefixLeft "pCommand_find"
    $ mapLeft show (parse p "doh!" s)
    >>= pExprToHExpr )
  where p :: Parser PExpr
        p = lexeme (string "/find")
            >> pExpr

pCommand_load :: String -> Either String Command
pCommand_load s = CommandLoad <$>
  ( prefixLeft "pCommand_load"
    $ mapLeft show (parse p "doh!" s) )
  where p :: Parser Folder
        p = lexeme (string "/load") >> filepath

pCommand_save :: String -> Either String Command
pCommand_save s = CommandSave <$>
  ( prefixLeft "pCommand_save"
    $ mapLeft show (parse p "doh!" s) )
  where p :: Parser Folder
        p = lexeme (string "/save") >> filepath


-- | = Functions from an `Rslt` and a parsed `String`,
-- to search, insert, show.
-- Theoretically, one could maintain an Rslt using GHCI with just these,
-- without ever using the TUI.

pInsert :: Rslt -> String -> Either String (Rslt, Addr)
pInsert r s = prefixLeft "pInsert"
  $ mapLeft show (parse pExpr "doh!" s)
  >>= pExprToHExpr
  >>= hExprToExpr r
  >>= exprToAddrInsert r

pFindAddrs :: Rslt -> String -> Either String (Set Addr)
pFindAddrs r s = prefixLeft "pFindAddrs"
  $ mapLeft show (parse pExpr "doh!" s)
  >>= pExprToHExpr
  >>= hExprToAddrs r (mempty :: Subst Addr)

pFindStrings :: Rslt -> String -> Either String (Set String)
pFindStrings r s = do
  (as :: Set Addr) <- prefixLeft "pFindExprs"
                      $ pFindAddrs r s
  (es :: Set Expr) <- ifLefts_set "pFindExprs"
                      $ S.map ( addrToExpr r ) as
  (ss :: Set String) <- ifLefts_set "pFindExprs"
                        $ S.map (eShow r) es
  return ss

pFindStringsIO :: Rslt -> String -> IO ()
pFindStringsIO r s =
  case (pFindStrings r s :: Either String (Set String))
  of Left err -> putStrLn err
     Right ss -> mapM_ putStrLn ss

