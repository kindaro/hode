{-# LANGUAGE ScopedTypeVariables #-}

module Hode.Test.Rslt.RProgram where

import qualified Data.Map       as M
import qualified Data.Set       as S
import qualified Test.HUnit as T
import           Test.HUnit hiding (Test, test)

import           Hode.Hash.Lookup
import           Hode.Hash.Types
import qualified Hode.Rslt.Lookup  as R
import           Hode.Rslt.Lookup hiding (exprToAddr)
import           Hode.Rslt.Types
import           Hode.Qseq.Types
import           Hode.Qseq.Query
import           Hode.Qseq.MkLeaf
import qualified Hode.Test.Rslt.RData as D


vs :: String -> Var
vs = VarString

test_module_rsltProgram :: T.Test
test_module_rsltProgram = TestList [
    TestLabel "test_rslt_query" test_rslt_query
  , TestLabel "test_rslt_hash_query" test_rslt_hash_query
  ]


test_rslt_hash_query :: T.Test
test_rslt_hash_query = TestCase $ do
  assertBool "<any> #like <any>" $ runProgram D.b2
    [ ( (vs "a"), QFind $ hFind $ HMap $ M.fromList
                  [ ( RoleInRel' RoleTplt, HExpr $ ExprAddr 8 ) ] ) ]
    == Right ( M.singleton (vs "a") $
               M.fromList [ ( 1, S.singleton M.empty)
                          , (10, S.singleton M.empty)
                          , (12, S.singleton M.empty)
                          , (19, S.singleton M.empty) ] )

  assertBool "fish #like <any>" $ runProgram D.b2
    [ ( (vs "a"), QFind $ hFind $ HMap $ M.fromList
                  [ ( RoleInRel' RoleTplt, HExpr $ ExprAddr 8 )
                  , ( RoleInRel' $ RoleMember 1, HExpr $ ExprAddr 2 )
                  ] ) ]
    == Right ( M.singleton (vs "a") $
               M.fromList [ ( 1, S.singleton M.empty)
                          , (10, S.singleton M.empty) ] )

  assertBool "<any> #like (<it> #is exercise)" $ runProgram D.b2
    [ ( (vs "a"), QFind $ hFind $ HMap $ M.fromList
                  [ ( RoleInRel' RoleTplt, HExpr $ ExprAddr 8 )
                  , ( RoleInRel' $ RoleMember 2
                    , HEval ( HMap $ M.fromList
                              [ ( RoleInRel' RoleTplt, HExpr $ ExprAddr 15)
                              , ( RoleInRel' $ RoleMember 2,
                                  HExpr $ Phrase "exercise") ] )
                      $ [[ RoleMember 1 ]]
                    ) ] ) ]
    == Right ( M.singleton (vs "a") $
               M.fromList [ (10, S.singleton M.empty)
                          , (12, S.singleton M.empty) ] )

  assertBool "<it> #like (<it> #is exercise)" $ runProgram D.b2
    [ ( (vs "a")
      , QFind $ hFind $ HEval
        ( HMap $ M.fromList
          [ ( RoleInRel' RoleTplt, HExpr $ ExprAddr 8 )
          , ( RoleInRel' $ RoleMember 2
            , HEval
              ( HMap $ M.fromList
                [ ( RoleInRel' RoleTplt, HExpr $ ExprAddr 15)
                , ( RoleInRel' $ RoleMember 2,
                    HExpr $ Phrase "exercise") ] )
              $ [[ RoleMember 1 ]]
            ) ] )
        [[ RoleMember 1 ]] ) ]
    == Right ( M.singleton (vs "a") $
               M.fromList [ (2, S.singleton M.empty)
                          , (11, S.singleton M.empty) ] )

  assertBool "<it> #need <any> && <any> #need <it>" $ runProgram D.b2
    [ ( (vs "a")
      , QFind $ hFind $ HAnd
        [ ( HEval ( HMap $ M.fromList -- <it> #need <any>
                    [ ( RoleInRel' RoleTplt, HExpr $ ExprAddr 7 ) ] )
            [[ RoleMember 1 ]] )
        , ( HEval ( HMap $ M.fromList -- <any> #need <it>
                    [ ( RoleInRel' RoleTplt, HExpr $ ExprAddr 7 ) ] )
            [[ RoleMember 2 ]] ) ] ) ]
    == Right ( M.singleton (vs "a") $
               M.fromList [ (2, S.singleton M.empty) ] )

  assertBool ( "another way to sayt he same thing:\n"
               ++ "a <- <it> #need <any>\n"
               ++ "b <- <any> #need <it>" )
    $ runProgram D.b2
    [ ( (vs "a"), QFind $ hFind
                  ( HEval ( HMap $ M.fromList -- <it> #need <any>
                            [ ( RoleInRel' RoleTplt, HExpr $ ExprAddr 7 ) ] )
                    [[ RoleMember 1 ]]  ) )

    , ( (vs "b"),
        ( QQuant $ ForSome (vs "a1") (vs "a") $ QJunct
          $ QAnd [ QFind $ hFind
                   ( HEval
                     ( HMap $ M.fromList -- <any> #need <it>
                       [ ( RoleInRel' RoleTplt, HExpr $ ExprAddr 7 ) ] )
                     [[ RoleMember 2 ]] )
                 , QTest $ mkTest (==) $ Right (vs "a1") ] ) )
    ]
    == Right
    ( M.fromList
      [ ((vs "a")
        , M.fromList [ (2, S.singleton M.empty)
                     , (17, S.singleton M.empty) ] )
      , ((vs "b")
        , M.fromList [ (2, S.singleton $ M.singleton (vs "a1") 2) ] ) ] )

  assertBool ( "nl <- everything that needs something and likes something\n"
               ++ "  (i.e. <it> #like <any> && <it> #need <any>\n"
               ++ "n <- whatever any (nl) needs\n"
               ++ "l <- whatever any (nl) likes\n"
               ++ ( "res <- the subset of nl such that nothing it likes"
                    ++ " is something it needs\n" ) )
    $ runProgram D.b2
      [ ( (vs "nl") -- "<it> #need <any> && <it> #like <any>"
          , QFind $ hFind $ HAnd
            [ ( HEval
                ( HMap $ M.singleton (RoleInRel' RoleTplt) $
                  HExpr $ ExprAddr 7 )
                [[ RoleMember 1 ]] )
            , ( HEval
                ( HMap $ M.singleton (RoleInRel' RoleTplt) $
                  HExpr $ ExprAddr 8 )
                [[ RoleMember 1 ]] ) ] )

        , ( (vs "n") -- for all nl1 in nl, "x #need <it>"
          , QQuant $ ForSome (vs "nl1") (vs "nl") $ QFind $ hFind $ HEval
            ( HMap $ M.fromList
              [ ( RoleInRel' $ RoleTplt, HExpr $ ExprAddr 7 )
              , ( RoleInRel' $ RoleMember 1, HVar (vs "nl1") ) ] )
            [[ RoleMember 2 ]] )

        , ( (vs "l") -- for all nl1 in nl, "x #like <it>"
          , QQuant $ ForSome (vs "nl1") (vs "nl") $ QFind $ hFind $ HEval
            ( HMap $ M.fromList
              [ ( RoleInRel' $ RoleTplt, HExpr $ ExprAddr 8 )
              , ( RoleInRel' $ RoleMember 1, HVar (vs "nl1") ) ] )
            [[ RoleMember 2 ]] )

        , ( (vs "res") -- for all nl1 in nl, no n(nl1) is equal to any l(nl1)
          -- If I uncomment the QQuants and the mkVTestCompare, it finds things.
          , QQuant $ ForSome (vs "nl2") (vs "nl")
            $ QJunct $ QAnd
            [ QFind $ hFind $ HVar (vs "nl2")
            , QQuant $ ForAll (vs "n1") (vs "n")
              ( QVTest $ mkVTestIO' (vs "nl2",vs "nl1") (vs "n1",vs "n") )
              $ QQuant $ ForAll (vs "l1") (vs "l")
              ( QVTest $ mkVTestIO' (vs "nl2",vs "nl1") (vs "l1",vs "l") )
              $ QVTest $ ( mkVTestCompare (/=) (Right (vs "n1"))
                           (Right (vs "l1")))
            ] )
        ]

    == Right
    ( M.fromList
      [ ((vs "nl"), M.fromList [ (2, S.singleton M.empty) -- fish
                               , (17, S.singleton M.empty) ] ) -- dolphins
      , ((vs "n"), M.fromList
          [ ( 3, S.singleton $ M.singleton (vs "nl1") 2) -- water (fish need it)
          , ( 2 -- fish (dolphins need it)
            , S.singleton $ M.singleton (vs "nl1") 17) ] )
      , ((vs "l"), M.fromList
          [ ( 3, S.fromList
                 [ M.singleton (vs "nl1") 2 -- water (fish like it)
                 , M.singleton (vs "nl1") 17 ] ) -- water (dolphins like it)
          , ( 6, S.singleton $ M.singleton (vs "nl1") 2) -- jumping (fish like it)
          ] )
      , ((vs "res"), M.singleton 17 $ S.singleton $ M.singleton (vs "nl2") 17 )
      -- dolphins are the only thing that likes something, needs something,
      -- and likes nothing that it needs
      ] )

test_rslt_query :: T.Test
test_rslt_query = TestCase $ do

  assertBool "1" $ runProgram D.rslt
    [ ( (vs "a"), QFind $ mkFind
        $ \sp -> S.singleton <$> R.exprToAddr sp (ExprAddr 0) ) ]
    == Right ( M.singleton (vs "a")
               $ M.singleton 0 $ S.singleton M.empty )

  assertBool "2" $ runProgram D.rslt
    [ ((vs "a"), QFind $ mkFind
        $ \sp -> S.singleton <$> addrToRefExpr sp 0 ) ]
    == Right ( M.singleton (vs "a")
               $ M.singleton (Phrase' "") $ S.singleton M.empty )
