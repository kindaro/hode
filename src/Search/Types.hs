module Search.Types where

import           Data.Map (Map)
import qualified Data.Map       as M
import           Data.Set (Set)
import qualified Data.Set       as S


-- | The type variables `sp` and `e` below stand for a space and the
-- elements of that space. They could be reified via womething like this:
--{-# LANGUAGE MultiParamTypeClasses #-}
--{-# LANGUAGE FunctionalDependencies #-}
--class Space e sp | sp -> e
--instance Space e (Graph e)


type Var = String
  -- ^ When a `Query` creates a `Var`, the result has no `varDets`.
  -- However, sometimes a Var is created by subsetting an earlier one.
  -- In that case, suppose it decomposes as `v@(Var _ (source, dets))`.
  -- "source" is the earlier Var, and "dets" is a set of variables
  -- that were calculated based on source's earlier calculation.

data Query e sp = QFind  (Find       e sp)
                | QTest  (Test       e sp)
                | QVTest (VarTest    e sp)
                | QJunct (Junction   e sp)
                | QQuant (Quantifier e sp)

data Find e sp    = Find {
    findFunction    :: sp -> Subst e -> Either String (Set e)
  , findUses        :: Set Var }
  -- ^ If `findFunction` doesn't use the `Subst`, `findUses` should be empty.
data Test e sp    = Test {
    testFunction    :: sp -> Subst e -> e -> Either String Bool
  , testUses        :: Set Var }
  -- ^ If `condFunction` doesn't use the `Subst`,`condDeps` should be empty.
data VarTest e sp = VarTest {
    varTestFunction :: Possible e -> sp -> Subst e -> Either String Bool
  , varTestUses     :: Set Var }
  -- ^ If `*Function` doesn't use the `Subst`, `varTestUses` should be empty.

data Junction e sp = And {clauses :: [Query e sp] } -- ^ order not important
                   | Or  {clauses :: [Query e sp] } -- ^ order not important

data Quantifier e sp =
    ForSome { name :: Var, source :: Var, goal :: Query e sp }
  | ForAll  { name :: Var, source :: Var, goal :: Query e sp
            , _conditions :: [Query e sp] -- ^ PITFALL: partial function.
              -- `conditions` is a total version.
            }
  -- ^ The `conditions` field lets you narrow the possibilities considered.
  -- Rather than requiring all x to satisfy y, you might want to require
  -- that all x which satisfy y also satisfy z. In that case, you would
  -- put y in the `conditions` field. That would be a testlike query, but
  -- the same method applies to findlike ones.

conditions :: Quantifier e sp -> [Query e sp]
conditions   (ForSome _ _ _)  = []
conditions q@(ForAll _ _ _ _) = _conditions q

type Subst e    = Map Var e
type CondElts e = Map e (Set (Subst e))
  -- ^ The set of solutions to a query: which `Elts` solve it, and which
  -- values of earlier-computed input variables permit each solution.
  -- Each Subst is a set of determinants leading to the associated Elt.
  -- Uses `Set` because multiple `Subst`s might obtain the same `Elt`.
  -- ^ PITFALL: If `Elt` is possible without any determining bindings, then
  -- the `Set` should include an empty `Map`. The `Set` should not be empty.
type Possible e = Map Var (CondElts e)
