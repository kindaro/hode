{-# LANGUAGE ScopedTypeVariables #-}

module Hode.Rslt.Show (
  eShow -- ^ Rslt -> Expr -> Either String String
  , hashUnlessEmptyStartOrEnd -- ^ Int -> [String] -> [String]
  , exprFWithDepth -- ^ Fix (ExprFWith b) -> Fix (ExprFWith (Int,b))
  , Wrap(..)
  , wrapExprAtDepth -- ^ Int -> Fix (ExprFWith ())
                    --       -> Fix (ExprFWith (Int,Wrap))
  ) where

import           Data.Functor.Foldable
import qualified Data.List as L
import           Data.Text (strip, pack, unpack)

import Hode.Rslt.RLookup
import Hode.Rslt.RTypes
import Hode.Rslt.RUtil
import Hode.Util.Misc
import Hode.Util.UParse


-- | `hashUnlessEmptyStartOrEnd k js` adds `k` #-marks to every joint
-- in `js`, unless it's first or last and the empty string.
hashUnlessEmptyStartOrEnd :: Int -> [String] -> [String]
hashUnlessEmptyStartOrEnd k0 joints = case joints' of
  [] -> []
  s : ss ->   hashUnlessEmpty    k0 s
            : hashUnlessEmptyEnd k0 ss

  where
  joints' = map maybeParens joints where
    maybeParens :: String -> String
    maybeParens s = if hasMultipleWords s
      then "(" ++ s ++ ")" else s

  hash :: Int -> String -> String
  hash k s = replicate k '#' ++ s

  hashUnlessEmpty :: Int -> String -> String
  hashUnlessEmpty _ "" = ""
  hashUnlessEmpty k s = hash k s

  hashUnlessEmptyEnd :: Int -> [String] -> [String]
  hashUnlessEmptyEnd _ [] = []
  hashUnlessEmptyEnd k [s]      =  [hashUnlessEmpty k s]
  hashUnlessEmptyEnd k (s : ss) =   hash               k s
                                  : hashUnlessEmptyEnd k ss

eShow :: Rslt -> Expr -> Either String String
eShow r = prefixLeft "-> eShow" . para f where
  f :: Base Expr (Expr, Either String String) -> Either String String

  f e@(AddrF _) =
    prefixLeft ", called on Addr: "
    $ unAddr r (embed $ fmap fst e)
    >>= eShow r

  f (PhraseF w) = Right w

  f (ExprTpltF pairs) =
    prefixLeft ", called on ExprTplt: "
    $ ifLefts (map snd pairs)
    >>= Right . concat . L.intersperse " _ "

  f relf@(ExprRelF (Rel ms (ExprTplt js, _))) =
  -- The recursive argument (second member of the pair) is unused, hence
  -- not computed. Instead, each joint in `js` is `eShow`n separately.
    prefixLeft ", called on ExprRel: " $ do
    mss <- ifLefts $ map snd ms
    jss <- let rel = embed $ fmap fst relf
           in hashUnlessEmptyStartOrEnd (depth rel)
              <$> ifLefts ( map (eShow r) js )
    Right $ unpack . strip . pack $ concat
      $ map (\(m,j) -> m ++ " " ++ j ++ " ")
      $ zip ("" : mss) jss

  f (ExprRelF (Rel ms (a@(Addr _), _))) =
    prefixLeft ", called on Rel: " $ do
    tpltExpr <- unAddr r a
    eShow r $ ExprRel $ Rel (map fst ms) tpltExpr

  f x@(ExprRelF _) =
    Left $ ": ExprRel with non-Tplt for Tplt: "
    ++ show (embed $ fmap fst x)


-- | = New style: wrapping depth-3 Exprs in parens

-- | This isn't used, but it might be helpful
-- for understanding `wrapExprAtDepth`.
exprFWithDepth :: Fix (ExprFWith b) -> Fix (ExprFWith (Int,b))
exprFWithDepth (Fix (EFW x)) =
  Fix . EFW $ f x where
  f :: (     b , ExprF (Fix (ExprFWith      b)))
    -> ((Int,b), ExprF (Fix (ExprFWith (Int,b))))
  f (b, AddrF a)      = ((0,b), AddrF a)
  f (b, PhraseF p)    = ((0,b), PhraseF p)
  f (b, ExprTpltF js) = ((0,b), ExprTpltF $
                                map exprFWithDepth js)
  f (b, ExprRelF (Rel ms t)) =
    let msWithDepth = map exprFWithDepth ms
        maxMemberDepth =
          let g (Fix (EFW ((i,_),_))) = i
          in if null msWithDepth then 0
             else maximum $ map g msWithDepth
    in ( ( 1+maxMemberDepth, b)
       , ExprRelF $ Rel msWithDepth $ exprFWithDepth t)

data Wrap = Wrapped | Naked deriving (Show, Eq, Ord)

-- | Attaches a depth (Int) and a Wrap to each subExpr of an Expr.
-- Anything Wrapped will be shown in parens.
-- The depth of a Rel is the maximum nakedDepth of its members,
-- where nakedDepth is like normal depth, except Wrapped things
-- contribute 0 depth.
-- The depth of any non-Rel is 0.
-- A Rel of depth > maxDepth is Wrapped.
-- Templates are also Wrapped (which might not be necessary).

wrapExprAtDepth :: Int -> Fix (ExprFWith ())
                       -> Fix (ExprFWith (Int,Wrap))
wrapExprAtDepth maxDepth = g where
  g (Fix (EFW ((), x))) = Fix $ EFW $ f x where

    f ::              ExprF (Fix (ExprFWith ()))
      -> ((Int,Wrap), ExprF (Fix (ExprFWith (Int,Wrap))))
    f (AddrF a)      =
      ( (0,Naked), AddrF a)
    f (PhraseF p)    =
      ( (0,Naked), PhraseF p)

    f (ExprTpltF js) =
      ( (0,Wrapped)
      , ExprTpltF $
        map (wrapExprAtDepth maxDepth) js )
    f (ExprRelF (Rel ms t)) =
      ( (d, if d >= maxDepth then Wrapped else Naked)
      , ExprRelF $ Rel ms' $
        wrapExprAtDepth maxDepth t) where
      ms' = map (wrapExprAtDepth maxDepth) ms
      d = (+1) $ maximum $ map h ms' where
        h = nakedDepth . \(Fix (EFW (b,_))) -> b where
          nakedDepth :: (Int,Wrap) -> Int
          nakedDepth (_,Wrapped) = 0
          nakedDepth (i,_) = i
