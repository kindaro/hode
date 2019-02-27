module Test.Rslt.TIndex_and_Valid where

import           Data.Either
import qualified Data.Map       as M
import qualified Data.Set       as S
import           Test.HUnit

import           Rslt.RTypes
import           Rslt.Index
import           Rslt.RValid
import qualified Test.Rslt.RData as D


test_module_rslt_index_and_valid :: Test
test_module_rslt_index_and_valid = TestList [
    TestLabel "test_invertPositions" test_invertPositions
  , TestLabel "test_checkDb" test_checkDb
  , TestLabel "test_validRefExpr" test_validRefExpr
  , TestLabel "test_validExpr" test_validExpr
  ]

test_validExpr :: Test
test_validExpr = TestCase $ do
  let meh = error "irrelevant"
  assertBool "1" $ Right () == validExpr D.big (Addr 0)
  assertBool "1" $ isLeft $    validExpr D.big (Addr 100)
  assertBool "2" $ Right () == validExpr meh   (Phrase "a b c")
  assertBool "2" $ Right () == validExpr meh   (Phrase "a b c")
  assertBool "Rel, invalid member" $ isLeft
    $  validExpr D.big (Rel [ Addr 100 ] $ Addr 101 )
  assertBool "Rel, false template" $ isLeft
    $  validExpr D.big ( Rel [ Addr 0, Addr 0 ] $ Addr 0 )
  assertBool "Rel, arity mismatch" $ isLeft
    $  validExpr D.big ( Rel [] $ Addr 4 )
  assertBool "Rel"                 $ Right ()
    == validExpr D.big ( Rel [Addr 0] $ Addr 4 )

test_validRefExpr :: Test
test_validRefExpr = TestCase $ do
  -- TODO : test for what kind of Left, not just whether it is Left.
  -- Could do in a future-proof manner by using enum error types rather
  -- than strings, (But I checked by hand in GHCI; each `validRefExpr ...`
  -- expression below produces the correct kind of complaint.)
  assertBool "good Rel" $ isRight $ validRefExpr D.rslt (Rel' [1,2] $ 4)
  assertBool "absent members" $ isLeft $ validRefExpr D.rslt (Rel' [100,200] $ 4)
  assertBool "absent template" $ isLeft $ validRefExpr D.rslt (Rel' [1,2] $ 44)
  assertBool "arity mismatch" $ isLeft $ validRefExpr D.rslt (Rel' [] $ 4)
  assertBool "tplt not a tplt" $ isLeft $ validRefExpr D.rslt (Rel' [4] $ 0)
  assertBool "word" $ isRight $ validRefExpr D.rslt (Phrase' "meh")

test_checkDb :: Test
test_checkDb = TestCase $ do
  assertBool "1" $ M.toList (relsWithoutMatchingTplts $ mkRslt D.badRefExprs)
    == [(1001, Rel' [1,2] 5), (1002, Rel' [1, 2] $ -1000)]
  assertBool "2" $ M.toList (collectionsWithAbsentAddrs $ mkRslt D.badRefExprs)
    == [(1002, [-1000])]

test_invertPositions :: Test
test_invertPositions = TestCase $ do
  let ips = foldl invertAndAddPositions M.empty
        [ (1,  [ (RoleMember 1, 11 )
               , (RoleMember 2, 22 ) ] )
        , (11, [ (RoleMember 1, 1  )
               , (RoleMember 2, 22 ) ] )
        , (3,  [ (RoleMember 1, 1  ) ] )
        ]
  assertBool "1" $ ips == M.fromList [(1,  S.fromList [(RoleMember 1,3  )
                                                      ,(RoleMember 1,11 )])
                                     ,(11, S.fromList [(RoleMember 1,1  )])
                                     ,(22, S.fromList [(RoleMember 2,1  )
                                                      ,(RoleMember 2,11 )])]
