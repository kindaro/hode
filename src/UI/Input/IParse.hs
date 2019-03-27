{-# LANGUAGE ScopedTypeVariables #-}

module UI.Input.IParse (pCommand) where

import           Text.Megaparsec

import Hash.Convert
import Hash.HLookup
import Hash.HParse
import Hash.HTypes
import Rslt.RTypes
import UI.ITypes
import Util.Misc
import Util.UParse


pCommand :: Rslt -> String -> Either String Command
pCommand r s =
  let (h,t) = splitAfterFirstLexeme s
  in case h of
    "/add"  -> pCommand_insert r t
    "/a"    -> pCommand_insert r t
    "/find" -> pCommand_find t
    "/f"    -> pCommand_find t
    "/load" -> pCommand_load t
    "/save" -> pCommand_save t
    _       -> Left $ "Commands must start with "
                 ++ "/add (or /a), /find (or /f), /load or /save."

pCommand_insert :: Rslt -> String -> Either String Command
pCommand_insert r s = CommandInsert <$>
  ( prefixLeft "pCommand_insert"
    $ mapLeft show (parse pExpr "doh!" s)
    >>= pExprToHExpr
    >>= hExprToExpr r )

-- | `pCommand_find` looks for any naked `/it` sub-expressions.
-- (Here naked means not inside an /eval expression.) If there are
-- any, the `PExpr` must be wrapped in a `PEval` constructor.
pCommand_find :: String -> Either String Command
-- PITFALL: Don't add an implicit Eval at the top of every search parsed in
-- the UI, because an Eval will return nothing if there are no Its below.
pCommand_find s = do
  (e1 :: PExpr) <- prefixLeft "pCommand_find"
    $ mapLeft show (parse pExpr "doh!" s)
  let e2 = case pathsToIts_pExpr e1 of
             [] -> e1
             _ -> PEval e1
  CommandFind s <$> pExprToHExpr e2

pCommand_load :: String -> Either String Command
pCommand_load s = CommandLoad <$>
  ( prefixLeft "pCommand_load"
    $ mapLeft show (parse filepath "doh!" s) )

pCommand_save :: String -> Either String Command
pCommand_save s = CommandSave <$>
  ( prefixLeft "pCommand_save"
    $ mapLeft show (parse filepath "doh!" s) )