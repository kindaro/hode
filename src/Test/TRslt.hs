module Test.TRslt where

import           Data.List
import           Data.Map (Map)
import qualified Data.Map       as M
import           Data.Maybe
import           Data.Set (Set)
import qualified Data.Set       as S
import           Test.HUnit hiding (Test)

import           Space.Rslt
import           Space.Rslt.RTypes
import           Space.Rslt.Index
import           Space.Rslt.Index.Positions
import           Space.Rslt.Index.ImgLookup
import qualified Test.Rslt.RData as D


test_module_rslt = TestList [
  TestLabel "test_invertPositions" test_invertPositions
  , TestLabel "test_variety" test_variety
  , TestLabel "test_holdsPosition" test_holdsPosition
  , TestLabel "test_imgLookup" test_imgLookup
  , TestLabel "test_checkDb" test_checkDb
  ]

test_checkDb = TestCase $ do
  assertBool "1" $ M.toList (relsWithoutMatchingTplts   D.badExprs D.index)
    == [(1001, Rel [1,2] 5), (1002, Rel [1, 2] $ -1000)]
  assertBool "2" $ M.toList (collectionsWithAbsentAddrs D.badExprs D.index)
    == [(1002, [-1000])]

test_imgLookup = TestCase $ do
  assertBool "1" $ (imgLookup D.exprs $ ImgOfAddr 0)              == Just 0
  assertBool "2" $ (imgLookup D.exprs $ ImgOfAddr $ -10000)       == Nothing
  assertBool "3" $ (imgLookup D.exprs $ ImgOfExpr $ Word "needs") == Just 3
  assertBool "4" $ (imgLookup D.exprs $ ImgOfExpr $ Tplt [0,3,0]) == Just 4
  assertBool "5" $ Just 4 ==
    imgLookup D.exprs ( ImgOfTplt [ ImgOfAddr 0
                                  , ImgOfExpr $ Word "needs"
                                  , ImgOfExpr $ Word ""] )

  assertBool "6" $ Just 5 ==
    imgLookup D.exprs ( ImgOfRel [ ImgOfAddr 1
                                 , ImgOfExpr $ Word "oxygen"]
                        $ ImgOfAddr 4 )
  assertBool "7" $ Nothing ==
    imgLookup D.exprs ( ImgOfRel [ ImgOfAddr 1
                                 , ImgOfExpr $ Word "oxygen"]
                        $ ImgOfAddr 6 )

test_holdsPosition = TestCase $ do
  assertBool "1" $ holdsPosition D.rslt (RoleMember 1, 4) == Just 0
  assertBool "2" $ holdsPosition D.rslt (RoleMember 2, 4) == Just 3
  assertBool "3" $ holdsPosition D.rslt (RoleMember 2, 5) == Just 2
  assertBool "4" $ holdsPosition D.rslt (RoleMember 1, 5) == Just 1
  assertBool "5" $ holdsPosition D.rslt (RoleTplt, 5) == Just 4
  assertBool "6" $ holdsPosition D.rslt (RoleTplt, 6) == Nothing

test_variety = TestCase $ do
  assertBool "1" $ variety D.rslt 3 == Just (Word',0)
  assertBool "2" $ variety D.rslt 4 == Just (Tplt',2)
  assertBool "3" $ variety D.rslt 5 == Just (Rel',2)
  assertBool "4" $ variety D.rslt 6 == Just (Par',1)
  assertBool "5" $ variety D.rslt (-133) == Nothing

test_invertPositions = TestCase $ do
  let ips = positionsHeldByAll [ (1,  [ (RoleMember 1, 11 )
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
