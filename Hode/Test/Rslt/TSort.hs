{-# LANGUAGE ScopedTypeVariables #-}

module Hode.Test.Rslt.TSort where

import qualified Data.Set       as S
import           Test.HUnit

import Hode.Rslt.Index
import Hode.Rslt.BinTypes
import Hode.Rslt.Sort
import Hode.UI.NoUI


test_module_rslt_sort :: Test
test_module_rslt_sort = TestList [
  TestLabel "test_nothingIsGreater" test_nothingIsGreater,
  TestLabel "test_allRelsInvolvingTplts" test_allRelsInvolvingTplts,
  TestLabel "test_allNormalMembers" test_allNormalMembers
  ]

test_allNormalMembers :: Test
test_allNormalMembers = TestCase $ do
  let Right r = nInserts (mkRslt mempty) [ "0 #a 1",
                                           "1 #b 2",
                                           "2 #b 3" ]
      Right rel_01 = head . S.toList <$> nFindAddrs r "0 #a 1"
      Right rel_12 = head . S.toList <$> nFindAddrs r "1 #b 2"
      Right num_0  = head . S.toList <$> nFindAddrs r "0"
      Right num_1  = head . S.toList <$> nFindAddrs r "1"
      Right num_2  = head . S.toList <$> nFindAddrs r "2"
  assertBool "all normal members of 0 #a 1"
    $ (S.fromList <$> allNormalMembers r [rel_01])
    == Right (S.fromList [num_0, num_1])
  assertBool "all normal members of (0 #a 1) and (1 #b 2)"
    $ (S.fromList <$> allNormalMembers r [rel_01, rel_12])
    == Right (S.fromList [num_0, num_1, num_2])

test_allRelsInvolvingTplts :: Test
test_allRelsInvolvingTplts = TestCase $ do
  let Right r = nInserts (mkRslt mempty) [ "0 #a 1",
                                           "2 #b 3",
                                           "4 #b 5" ]
      Right tplt_a = head . S.toList <$> nFindAddrs r "/t /_ a /_"
      Right tplt_b = head . S.toList <$> nFindAddrs r "/t /_ b /_"
      Right rel_a  = head . S.toList <$> nFindAddrs r "0 #a 1"
      Right rel_b1 = head . S.toList <$> nFindAddrs r "2 #b 3"
      Right rel_b2 = head . S.toList <$> nFindAddrs r "4 #b 5"

  assertBool "all rels involving _ #b _" $
    allRelsInvolvingTplts r [tplt_b] ==
    Right (S.fromList [rel_b1, rel_b2])
  assertBool "all rels involving _ (#a|#b) _" $
    allRelsInvolvingTplts r [tplt_a,tplt_b] ==
    Right (S.fromList [rel_a, rel_b1, rel_b2])

test_nothingIsGreater :: Test
test_nothingIsGreater = TestCase $ do
  let Right r = nInserts (mkRslt mempty) [ "0 # 1", "1 # 2" ]
      Right t = head . S.toList <$> nFindAddrs r "/t /_ \"\" /_"
      Right number_0 = head . S.toList <$> nFindAddrs r "0"
      Right number_1 = head . S.toList <$> nFindAddrs r "1"
      Right number_2 = head . S.toList <$> nFindAddrs r "2"

  assertBool "If left is bigger, 0 is maximal." $ Right True ==
    maximal r (LeftIsBigger, t) number_0
  assertBool "If right is bigger, it's not." $ Right False ==
    maximal r (RightIsBigger, t) number_0

  assertBool "If left is bigger, 2 is not maximal." $ Right False ==
    maximal r (LeftIsBigger, t) number_2
  assertBool "If right is bigger, then it is." $ Right True ==
    maximal r (RightIsBigger, t) number_2

  assertBool "1 is not maximal under either orientation." $ Right False ==
    maximal r (LeftIsBigger, t) number_1
  assertBool "Ditto." $ Right False ==
    maximal r (RightIsBigger, t) number_1