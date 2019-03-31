{-# LANGUAGE ScopedTypeVariables #-}

module Test.Hash.TParse where

import qualified Data.Map as M
import           Text.Megaparsec
import           Test.HUnit

import Hash.Convert
import Hash.HParse
import Hash.HTypes
import Hash.HUtil
import Rslt.RTypes


test_module_hash_parse :: Test
test_module_hash_parse = TestList [
    TestLabel "test_parse_rels" test_parse_rels
  , TestLabel "test_parse_pExpr" test_parse_pExpr
  , TestLabel "test_parse_hExpr" test_parse_hExpr
  ]

test_parse_hExpr :: Test
test_parse_hExpr = TestCase $ do
  assertBool "1" $
    ( either (Left . show) Right
      ( parse pExpr "doh!" "/hash /_ #e w" )
      >>= pExprToHExpr )
    == ( Right $ HMap $ M.fromList
         [ ( RoleTplt
           , HExpr $ ExprTplt [ Phrase "",Phrase "e",Phrase "" ] )
         , ( RoleMember 2
           , HExpr $ Phrase "w" ) ] )

test_parse_pExpr :: Test
test_parse_pExpr = TestCase $ do
  assertBool "addr" $ parse pAddr "wut" "/addr 34 "
    == Right (Addr 34)
  assertBool "word" $ parse pPhrase "wut" "sammich bagel 1234"
    == Right (PExpr $ Phrase "sammich bagel 1234")

  assertBool "map" $ parse pMap "wut"
    "/map (1 /hash a) (2 /hash b) (tplt sees (whenever there is) because)"
    == Right
    ( PMap $ M.fromList
      [ ( RoleMember 1, PExpr $ Phrase "a" )
      , ( RoleMember 2, PExpr $ Phrase "b" )
      , ( RoleTplt, PExpr $ ExprTplt $ map Phrase
          ["sees","whenever there is","because"] )
      ] )

  assertBool "any" $ parse pAny "any" "/_ "
    == Right Any
  assertBool "var" $ parse pVar "wut" "/var x1 "
    == Right (PVar "x1")
  assertBool "it nothing" $ parse pIt "wut" "/it "
    == Right (It Nothing)
  assertBool "it $ just a # b" $ parse pIt "wut" "/it= /hash a # b" == Right
    ( It $ Just $ PRel
      ( Open 1 [ PNonRel $ PExpr $ Phrase "a"
               , PNonRel $ PExpr $ Phrase "b" ]
        [""] ) )

  assertBool "eval $ just a # b" $ parse pEval "wut" "/eval /hash a # b"
    == Right
    ( PEval $ PRel
      ( Open 1 [ PNonRel $ PExpr $ Phrase "a"
               , PNonRel $ PExpr $ Phrase "b" ]
        [""] ) )

  assertBool "par, simplest" $ parse pPar "wut" "/par a" == Right
    (PPar $ Par [] "a")

  assertBool "par, balanced, one sub-Expr" $
    parse pPar "wut" "/par a (/hash x # y) b"
    == Right
    ( PPar ( Par [ ( "a"
                   , PRel $ ( Open 1 [ PNonRel $ PExpr $ Phrase "x"
                                     , PNonRel $ PExpr $ Phrase "y" ]
                              [""] ) ) ]
             "b" ) )

  assertBool "par, balanced, two sub-Exprs" $
    ( simplifyPExpr <$> parse pPar "wut"
      "/par a a (/hash x x #(j j) y y) b b (/hash z z) c d" )
    == Right
    ( PPar ( Par [ ( "a a"
                   , PRel $ ( Open 1 [ PNonRel $ PExpr $ Phrase "x x"
                                     , PNonRel $ PExpr $ Phrase "y y" ]
                              ["j j"] ) )
                 , ( "b b", PExpr $ Phrase "z z" )
                 ]
             "c d" ) )

  assertBool "par, left-absent, two sub-Exprs" $
    ( simplifyPExpr <$> parse pPar "wut"
      "/par (/hash x x #(j j) y y) b b (/hash z z) c d" )
    == Right
    ( PPar ( Par [ ( ""
                   , PRel $ ( Open 1 [ PNonRel $ PExpr $ Phrase "x x"
                                     , PNonRel $ PExpr $ Phrase "y y" ]
                              ["j j"] ) )
                 , ( "b b", PExpr $ Phrase "z z" )
                 ]
             "c d" ) )

  assertBool "par, right-absent, two sub-Exprs" $
    ( simplifyPExpr <$> parse pPar "wut"
      "/par (/hash x x #(j j) y y) b b (/hash z z)" )
    == Right
    ( PPar ( Par [ ( ""
                   , PRel $ ( Open 1 [ PNonRel $ PExpr $ Phrase "x x"
                                     , PNonRel $ PExpr $ Phrase "y y" ]
                              ["j j"] ) )
                 , ( "b b", PExpr $ Phrase "z z" )
                 ]
             "" ) )

  assertBool "par, middle-absent, two sub-Exprs" $
    ( simplifyPExpr <$> parse pPar "wut"
      "/par (/hash x x #(j j) y y) (/hash z z)" )
    == Right
    ( PPar ( Par [ ( ""
                   , PRel $ ( Open 1 [ PNonRel $ PExpr $ Phrase "x x"
                                     , PNonRel $ PExpr $ Phrase "y y" ]
                              ["j j"] ) )
                 , ( "", PExpr $ Phrase "z z" )
                 ]
             "" ) )

test_parse_rels :: Test
test_parse_rels = TestCase $ do
  assertBool "1 level" $ parse pRel "wut" "a b #(w x) c d"
    == Right ( Open 1
               [ pnrPhrase "a b", pnrPhrase "c d"]
               [ "w x" ] )

  assertBool "1 level 2 joints" $ parse pRel "wut" "I #am ##because I #think"
    == Right ( Open 2
               [ Open 1
                 [ pnrPhrase "I", Absent]
                 [ "am" ]
               , Open 1
                 [pnrPhrase "I", Absent]
                 ["think"]
               ]
               [ "because" ] )

  assertBool "2 levels 2 joints" $ parse pRel "wut"
    "I #think ##therefore I #am thinking ##so #like yeah man"
    == Right ( Open 2 [ Open 1 [ pnrPhrase "I"
                               , Absent] [ "think"]
                      , Open 1 [ pnrPhrase "I"
                               , pnrPhrase "thinking"] [ "am"]
                      , Open 1 [ Absent
                               , pnrPhrase "yeah man"] [ "like"]]
               [ "therefore", "so"] )

  assertBool "3 levels" $ parse pRel "wut"
    "I #think ##therefore I #am thinking ###so #like yeah man"
    == Right ( Open 3
               [ Open 2
                 [ Open 1 [ pnrPhrase "I", Absent ] [ "think" ]
                 , Open 1 [ pnrPhrase "I", pnrPhrase "thinking" ]
                   [ "am" ] ]
                 [ "therefore" ]
               , Open 1 [ Absent, pnrPhrase "yeah man"]
                 [ "like"] ]
               [ "so" ] )

  assertBool "\\, 1 level" $ parse pRel "wut"
    "a \\ b"
    == Right ( PNonRel $ PDiff ( PExpr $ Phrase "a" )
                               ( PExpr $ Phrase "b" ) )

  assertBool "&, 1 level" $ parse pRel "wut"
    "a & b"
    == Right ( PNonRel $ PAnd [ PExpr $ Phrase "a"
                              , PExpr $ Phrase "b" ] )

  assertBool "& under #, 1 level" $ parse pRel "wut" "a & b ## c"
    == Right
    ( Open 2 [ PNonRel $ PAnd [ PExpr $ Phrase "a"
                              , PExpr $ Phrase "b" ]
             , PNonRel $ PExpr $ Phrase "c" ]
      [""] )

  assertBool "& over #, 1 level" $ parse pRel "wut" "a && b # c"
    == Right
    ( PNonRel $ PAnd [ PExpr $ Phrase "a"
                     , PRel $ Open 1 [ PNonRel $ PExpr $ Phrase "b"
                                     , PNonRel $ PExpr $ Phrase "c" ]
                       [""] ] )

  assertBool "2 levels of &, arities 2 and 3"
    $ parse pRel "wut" "a & b && c & d && e"
    == Right ( PNonRel $ PAnd
               $ map (PExpr . Phrase) ["a", "b", "c", "d", "e"] )

  assertBool "or, 1 levels" $ parse pRel "wut"
    "a | b"
    == Right ( PNonRel $ POr [ PExpr $ Phrase "a"
                             , PExpr $ Phrase "b" ] )

  assertBool "or, 2 levels" $ parse pRel "wut"
    "a | b || c | d"
    == Right ( PNonRel $ POr $ map (PExpr . Phrase) ["a","b","c","d"] )

  assertBool "3 levels of &, | and #"
    $ parse pRel "wut" "a # b && c | d ||| a ## b # c"
    == Right
    ( PNonRel
      ( POr
        [ PAnd
          [ PRel
            ( Open 1
              [ PNonRel ( PExpr ( Phrase "a"))
              , PNonRel ( PExpr ( Phrase "b"))]
              [ ""])
          , POr [ PExpr ( Phrase "c")
                , PExpr ( Phrase "d")]]
        , PRel ( Open 2 [ PNonRel ( PExpr ( Phrase "a"))
                        , Open 1 [ PNonRel ( PExpr ( Phrase "b"))
                                 , PNonRel ( PExpr ( Phrase "c"))]
                          [ ""]]
                 [ ""])]))

  assertBool "3 levels of \\, &, | and #, where the L in EInfixL matters"
    $ parse pRel "wut" "a # b \\\\ c | d ||| a && b \\\\ c"
    == Right
    ( PNonRel ( POr [ PDiff ( PRel ( Open 1
                                     [ PNonRel $ PExpr $ Phrase "a"
                                     , PNonRel $ PExpr $ Phrase "b" ]
                                     [""] ) )
                      ( POr [ PExpr $ Phrase "c"
                            , PExpr $ Phrase "d" ] )
                    , PDiff ( PAnd [ PExpr $ Phrase "a"
                                   , PExpr $ Phrase "b" ] )
                      ( PExpr $ Phrase "c" ) ] ) )
