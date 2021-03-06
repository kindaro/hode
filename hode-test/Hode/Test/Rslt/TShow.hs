{-# LANGUAGE ScopedTypeVariables #-}

module Hode.Test.Rslt.TShow where

import           Data.Either
import qualified Data.Set as S
import           Data.Functor.Foldable
import           Test.HUnit

import           Hode.Brick
import           Hode.Rslt.Types
import           Hode.Rslt.Show
import           Hode.Rslt.ShowColor
import           Hode.Rslt.Show.Util
import qualified Hode.Test.Rslt.RData as D


test_module_rslt_show :: Test
test_module_rslt_show = TestList [
    TestLabel "test_eShow" test_eShow
  , TestLabel "test_parenExprAtDepth" test_parenExprAtDepth
  , TestLabel "test_eParenShowExpr" test_eParenShowExpr
  , TestLabel "test_eParenShowAddr" test_eParenShowAddr
  , TestLabel "test_eParenShowColorExpr" test_eParenShowColorExpr
  ]

test_eParenShowColorExpr :: Test
test_eParenShowColorExpr = TestCase $ do
  assertBool "show a Tplt" $
    ( colorStrip . colorConsolidate <$>
      ( eParenShowColorExpr 2 (error "") $
        ExprTplt $ Tplt Nothing [Phrase "is"] Nothing ) )
    == Right [("_ is _", TextColor)]
  assertBool "a depth-1 Rel" $
    ( colorConsolidate <$>
      ( eParenShowColorExpr 2 (error "") $
        ExprRel $ Rel [Phrase "love", Phrase "good"]
        $ ExprTplt $ Tplt Nothing [Phrase "is"] Nothing ) )
    == Right [("love "  , TextColor),
              ("#"      , SepColor),
              ("is good", TextColor) ]

test_eParenShowAddr :: Test
test_eParenShowAddr = TestCase $ do
  let sa k = eParenShowAddr k D.rslt_rightCapped
      se k = eParenShowExpr k D.rslt_rightCapped
  mapM_ (\a -> assertBool "" ( sa 3 mempty a ==
                               se 3 (ExprAddr a) ) )
        [0..6]
  assertBool "show dog as Addr" $
    sa 3 (S.singleton 1) 1 == Right "@1"
  assertBool "show dog as Addr in Rel" $
    sa 3 (S.singleton 1) 5 == Right "@1 #needs oxygen #@1"
  assertBool "including a Rel's Tplt in showAsAddr set: no effect"
    $ sa 3 (S.singleton 4) 5 == Right "dog #needs oxygen #dog"

test_eParenShowExpr :: Test
test_eParenShowExpr = TestCase $ do
  let f k = eParenShowExpr k D.rslt_rightCapped
  assertBool "hi" $ f   2  (Phrase "hi") == Right "hi"
  assertBool "hi" $ f (-1) (Phrase "hi") == Right "hi"
  assertBool "rel with no tplt" $ isLeft $ f 2 $
    ExprRel $ Rel [Phrase "trees", Phrase "CO2"] $ Phrase ""

  let eat = ExprTplt $ Tplt Nothing [Phrase "eat"] Nothing
  assertBool "tplt" $ f 2 eat == Right "_ eat _"

  let tIn = ExprTplt $ Tplt Nothing [Phrase "in"] Nothing
      dog = ExprTplt $ Tplt Nothing []
            $ Just $ Phrase ", dog"
      r1  = ExprRel $ Rel [Phrase "trees", Phrase "CO2"] eat
      r2  = ExprRel $ Rel
        [ ExprRel $ Rel [Phrase "trees", Phrase "Earth"] tIn
        , Phrase "CO2" ] eat

  assertBool "depth-1 rel, max depth 2" $ f 2 r1 ==
    Right "trees #eat CO2"
  assertBool ( "depth-1 rel, max depth 0" ++
               " (the outermost layer is never wrapped)" )
    $ f 2 r1 == Right "trees #eat CO2"
  assertBool "depth-1 rel, max depth 2" $ f 2 r2 ==
    Right "trees #in Earth ##eat CO2"
  assertBool "depth-1 rel, max depth 1" $ f 1 r2 ==
    Right "(trees #in Earth) #eat CO2"
  assertBool "Rel arity 2, Tplt arity 1. (PITFALL: Whether an Expr is valid is beyond eParenShowExpr's purview; for that, use Hode.Rslt.Valid.validExpr)."
    $ isRight $ f 2 $
    ExprRel $ Rel [Phrase "trees", Phrase "CO2"] dog

-- | `test_exprFWithDepth` might make this easier to understand.
-- Currently it is stored at earlier-work/Rslt/Show/JustInCase.hs.
-- That demo code, however, surely broke when Tplt changed
-- from a synonym for [] to something more complex, during
-- commit 8d163edd7381afa8955eacfd6683ff090db4688a
-- Date:   Sat Sep 14 20:00:12 2019 -0500
test_parenExprAtDepth :: Test
test_parenExprAtDepth = TestCase $ do

  let fe0 :: Bool ->  Fix (ExprFWith Bool)
      fe  :: Bool -> [Fix (ExprFWith Bool)]
                  ->  Fix (ExprFWith Bool)
      fe0 b = Fix $ EFW ( b, ExprAddrF 0 )
      fe b ms = Fix $ EFW
        ( b, ExprRelF $ Rel ms $ fe0 $ not b )

  -- like fe, but with depth and wrappedness
  let dw0 :: Bool ->  Fix (ExprFWith (Bool,(Int,Parens)))
      dw  :: (Bool,(Int,Parens))
        -> [Fix (ExprFWith (Bool,(Int,Parens)))]
        ->  Fix (ExprFWith (Bool,(Int,Parens)))
      dw0 b = Fix $ EFW ( ( b
                          , (0,Naked) )
                        , ExprAddrF 0 )
      dw (b,ip) ms = Fix $ EFW
        ( (b,ip),
          ExprRelF $ Rel ms $ dw0 $ not b )

  assertBool "" $ parenExprAtDepth 2 (fe0 True)
    == dw0 True
  assertBool "" $ parenExprAtDepth 3 (fe0 True)
    == dw0 True
  assertBool "" $ parenExprAtDepth 2
    (fe True [fe0 False]) ==
    dw (True,(1,Naked)) [dw0 False]
  assertBool "" $ parenExprAtDepth 3
    ( fe True           [ fe False             [fe0 True]
                        , fe0 False ] ) ==
    dw (True,(2,Naked)) [ dw (False,(1,Naked)) [dw0 True]
                        , dw0 False]
  assertBool "" $ parenExprAtDepth 2
    ( fe True              [ fe False             [fe0 True]
                           , fe0 False ] ) ==
    dw (True,(2,InParens)) [ dw (False,(1,Naked)) [dw0 True]
                           , dw0 False]

test_eShow :: Test
test_eShow = TestCase $ do
  assertBool "1" $ eShow D.rslt (Phrase "hello") == Right "hello"
  assertBool "2" $ eShow D.rslt
    (ExprTplt $ fmap Phrase $ Tplt (Just "a") ["b"] (Just "c"))
    == Right "a _ b _ c"
  assertBool "3" $ eShow D.rslt
    ( ExprRel $ Rel
      [Phrase "a", Phrase "b"]
      $ ExprTplt $ fmap Phrase $
      Tplt Nothing ["="] Nothing )
    == Right "a #= b"
