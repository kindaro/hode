{-# LANGUAGE ScopedTypeVariables #-}
module Test.TRel where

import           Data.Map (Map)
import qualified Data.Map       as M
import           Data.Maybe
import           Data.Set (Set)
import qualified Data.Set       as S
import           Test.HUnit hiding (Test)

import Space.Graph
import Program
import Query
import RelExperim
import Types


test_module_Rel = TestList [
  TestLabel "test_renameIns" test_renameIn
  , TestLabel "test_renameOut" test_renameOut
  , TestLabel "test_restrictToMatchIns" test_restrictToMatchIns
  ]

thinking = let (a, b, c, i, o ) = ("a", "b", "c", "i", "o" )
               (a1,b1,c1,i1,o1) = ("a1","b1","c1","i1","o1")
               (a2,b2,c2,i2,o2) = ("a2","b2","c2","i2","o2")
  in varPossibilities
  ( M.fromList [ (a, ( M.fromList
                       [ ( "aVal", ( S.singleton
                                     $ M.fromList [(i,"iVal")] ) ) ] ) )
               , (o, ( M.fromList
                       [ ( "oVal", ( S.singleton
                                     $ M.fromList [(a1,"aVal")] ) ) ] ) ) ] )
  ( M.fromList [(i1,"iVal"),(o1,"oVal")] :: Subst String )
  ( TSource
    [ TVarPlan a a2 [i1] [a1] ]
    [ i1 ]
    [ (o,o1) ] )

test_restrictToMatchIns = TestCase $ do
  let meh = error "whatever"
  assertBool "1" $ restrictToMatchIns
    (TSource [] ["a1","b1"] [])   -- most args don't matter here
    (TVarPlan "" "" ["a","b"] []) -- most args don't matter here
    (M.fromList [("a1",1),("b1",1)] :: Subst Int)
    (M.fromList [ ( 1, S.fromList [ M.fromList [("a",1),("b",1),("c",1)]
                                  , M.fromList [("a",2),("b",2)] ] )
                , ( 2, S.fromList [ M.fromList [("a",2),("b",2)] ] ) ]
      :: CondElts Int)
    == Right ( M.fromList [ ( 1, S.singleton
                              $ M.fromList [("a",1),("b",1),("c",1)] ) ] )

test_renameOut = TestCase $ do
  let meh = error "whatev"
  assertBool "1" $ renameOut
    (TSource meh [] [("a","a1")])
    "a1" == Right "a"

test_renameIn = TestCase $ do
  let meh = error "whatev"
  assertBool "1" $ renameIn
    (TSource meh ["a1","b1"] meh)
    (TVarPlan meh meh ["a","b"] meh)
    "a1" == Right "a"
