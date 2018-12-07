module Test.Data where

import qualified Data.Map as M

import Rslt
import Index


files :: Files
files = M.fromList
  [ (0, Word "")
  , (1, Word "dog")
  , (2, Word "oxygen")
  , (3, Word "needs")
  , (4, Tplt [0,3,0])
  , (5, Rel [1,2] 4)
  , (6, Par [("The first relationship in this graph is ", 5)] ".")
  ]

badFiles :: Files
badFiles = foldl (\fm (k,v) -> M.insert k v fm) files newData where
  newData = [ (1001, Rel [1,2] 5)
            , (1002, Rel [1,2] (-1000))
            ]

index :: Index
index = mkIndex files
