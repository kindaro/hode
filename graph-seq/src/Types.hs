{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE FunctionalDependencies #-}
module Types where

import           Data.Map (Map)
import qualified Data.Map       as M
import           Data.Set (Set)
import qualified Data.Set       as S


class Space e sp | sp -> e
type Elt = Int    -- TODO ? make generic
type Data = Graph -- TODO ? make generic

data Graph = Graph { -- TODO Move to Graph once generic
    graphNodes    :: Set Elt             -- ^ good for disconnected graphs
  , graphChildren :: Map Elt (Set Elt)   -- ^ keys are parents
  , graphParents  :: Map Elt (Set Elt) } -- ^ keys are children
  deriving (Show, Eq, Ord)
instance Space Int Graph

type Var = String
  -- ^ When a `Query` creates a `Var`, the result has no `varDets`.
  -- However, sometimes a Var is created by subsetting an earlier one.
  -- In that case, suppose it decomposes as `v@(Var _ (source, dets))`.
  -- "source" is the earlier Var, and "dets" is a set of variables
  -- that were calculated based on source's earlier calculation.

data Source = Source  { source :: Var }
            | Source' { source :: Var
                      , dets :: (Set Var) }

data Find e sp = Find { findFunction          :: sp -> Subst e -> Set e
                      , findDets              :: Set Var }
  -- ^ If `findFunction` doesn't use the `Subst`, `findDets` should be empty.
data Test e sp = Test {  testFunction         :: sp -> Subst e ->    e -> Bool
                       , testDets             :: Set Var }
  -- ^ If `condFunction` doesn't use the `Subst`, `condDeps` should be empty.
data VarTest e sp = VarTest { varTestFunction :: sp -> Subst e         -> Bool
                            , varTestDets     :: Set Var }
  -- ^ If `*Function` doesn't use the `Subst`, `*Dets` should be empty.

data Query e sp = QFind    (Find    e sp)
                | QTest    (Test    e sp)
                | QVarTest (VarTest e sp)
                | QAnd               [Query e sp] -- ^ order not important
                | QOr                [Query e sp] -- ^ order not important
                | ForAll  Var Source (Query e sp)
                | ForSome Var Source (Query e sp)

type Subst e    = Map Var e
type CondElts e = Map e (Set (Subst e))
  -- ^ The set of solutions to a query: which `Elts` solve it, and which
  -- values of earlier-computed input variables permit each solution.
  -- Each Subst is a set of determinants leading to the associated Elt.
  -- Uses `Set` because multiple `Subst`s might obtain the same `Elt`.
  -- ^ PITFALL: If `Elt` is possible without any determining bindings, then
  -- the `Set` should include an empty `Map`. The `Set` should not be empty.
type Possible e = Map Var (CondElts e)
