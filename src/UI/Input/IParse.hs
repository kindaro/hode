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
    "/add"     -> pCommand_insert  r t
    "/a"       -> pCommand_insert  r t
    "/find"    -> pCommand_find    r t
    "/f"       -> pCommand_find    r t
    "/replace" -> pCommand_replace r t
    "/r"       -> pCommand_replace r t
    "/delete"  -> pCommand_delete  r t
    "/d"       -> pCommand_delete  r t
    "/load"    -> pCommand_load     t
    "/save"    -> pCommand_save     t
    _          -> Left $ "Unrecognized start of command."

pCommand_insert :: Rslt -> String -> Either String Command
pCommand_insert r s = CommandInsert <$>
  ( prefixLeft "pCommand_insert"
    $ mapLeft show (parse _pHashExpr "doh 1!" s)
    >>= pExprToHExpr r
    >>= hExprToExpr r )

pCommand_replace :: Rslt -> String -> Either String Command
pCommand_replace r s = prefixLeft "pCommand_replace" $ do
  (a,px) <- let p :: Parser (Addr, PExpr)
                p = do a <- fromIntegral <$> lexeme integer
                       px <- _pHashExpr
                       return (a,px)
    in mapLeft show $ parse p "doh 2!" s
  e <- pExprToHExpr r px >>= hExprToExpr r
  Right $ CommandReplace a e

pCommand_delete :: Rslt -> String -> Either String Command
pCommand_delete r s = prefixLeft "pCommand_delete" $ do
  a <- let p = fromIntegral <$> lexeme integer
       in mapLeft show $ parse p "doh 2!" s
  Right $ CommandDelete a

-- | `pCommand_find` looks for any naked `/it` sub-expressions.
-- (Here naked means not inside an /eval expression.) If there are
-- any, the `PExpr` must be wrapped in a `PEval` constructor.
pCommand_find :: Rslt -> String -> Either String Command
-- PITFALL: Don't add an implicit Eval at the top of every search parsed in
-- the UI, because an Eval will return nothing if there are no Its below.
pCommand_find r s = prefixLeft "pCommand_find" $ do
  (e1 :: PExpr) <- mapLeft show (parse _pHashExpr "doh 3!" s)
  CommandFind s <$> pExprToHExpr r e1

pCommand_load :: String -> Either String Command
pCommand_load s = CommandLoad <$>
  ( prefixLeft "pCommand_load"
    $ mapLeft show (parse filepath "doh 4!" s) )

pCommand_save :: String -> Either String Command
pCommand_save s = CommandSave <$>
  ( prefixLeft "pCommand_save"
    $ mapLeft show (parse filepath "doh 5!" s) )
