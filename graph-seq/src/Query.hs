module Query where

import           Data.Map (Map)
import qualified Data.Map       as M
import           Data.Set (Set)
import qualified Data.Set       as S

import Types


-- | `couldBind Q = Vs` <=> `Q` could depend on a binding of any var in `Vs`.
-- `willBind` would be a nice thing to define if it were possible, but
-- (without way more data and processing) it is not.
couldBind :: Query -> Set Var
couldBind (QFind _)       = S.empty
couldBind (QCond _)       = S.empty
couldBind (QOr  qs)       = S.unions $ map couldBind qs
couldBind (QAnd qs)       = S.unions $ map couldBind qs
couldBind (ForSome vfs q) = S.union vs $   couldBind q
  where vs = S.map varFuncName vfs
couldBind (ForAll  _   q) =                couldBind q

-- | Every `QAnd` must include something `findable`, and
-- every `QOr` must be nonempty and consist entirely of `findable` things.
findable :: Query -> Bool
findable (QFind _)          = True
findable (QCond _)          = False
findable (QAnd qs)          = or  $ map findable qs
findable (QOr     [])       = False
findable (QOr     qs@(_:_)) = and $ map findable qs
findable (ForSome vfs q)    = findable q
findable (ForAll  _   q)    = findable q

validExistentials :: Query -> Bool
validExistentials (ForSome vfs q)
  = S.disjoint (S.map varFuncName vfs) (couldBind q)
validExistentials (QAnd qs) = snd $ foldl f (S.empty, True) qs
  where f :: (Set Var, Bool) -> Query -> (Set Var, Bool)
        f (_, False) _ = (S.empty, False) -- short circuit (roughly)
        f (vs, True) q = if S.disjoint vs $ couldBind q
                         then (S.union vs $ couldBind q, True)
                         else (S.empty, False)
validExistentials _ = True

runQuery :: Data
         -> Result -- ^ how earlier `Var`s have been bound
         -> Subst  -- ^ these are drawn from the input `Result`
         -> Var    -- ^ what we want to bind
         -> Query  -- ^ how we want to bind it
         -> DepValues

runQuery d r s v (QFind (Find find deps)) =
  let found = find d s             :: Set Elt
      used = M.restrictKeys s deps :: Subst
  in M.fromSet (const $ S.singleton used) found
