{-# LANGUAGE DataKinds, GADTs, RankNTypes, ScopedTypeVariables, TypeOperators #-}
module Diffing.Interpreter
( diffTerms
, diffSyntaxTerms
) where

import Analysis.Decorator
import Control.Applicative (Alternative(..))
import Control.Monad.Free.Freer
import Data.Align.Generic
import Data.Diff
import Data.Functor.Classes
import Data.Hashable (Hashable)
import Data.Maybe (fromMaybe)
import Data.Record
import Data.Term
import Data.Text (Text)
import Diffing.Algorithm
import Diffing.Algorithm.RWS
import Info hiding (Empty, Return)
import Syntax (Syntax(Leaf))


-- | Diff two Syntax terms recursively.
diffSyntaxTerms :: (HasField fields1 Category, HasField fields2 Category)
                => Term Syntax (Record fields1) -- ^ A term representing the old state.
                -> Term Syntax (Record fields2) -- ^ A term representing the new state.
                -> Diff Syntax (Record fields1) (Record fields2)
diffSyntaxTerms = decoratingWith comparableByCategory (equalTerms comparableByCategory) getLabel getLabel

-- | Diff two à la carte terms recursively.
diffTerms :: (Diffable syntax, Eq1 syntax, Foldable syntax, Functor syntax, GAlign syntax, Show1 syntax, Traversable syntax)
          => Term syntax (Record fields1)
          -> Term syntax (Record fields2)
          -> Diff syntax (Record fields1) (Record fields2)
diffTerms = decoratingWith comparableTerms equivalentTerms constructorNameAndConstantFields constructorNameAndConstantFields

-- | Diff two terms by decorating with feature vectors computed using the supplied labelling algebra, and stripping the feature vectors from the resulting diff.
decoratingWith :: (Hashable label, Diffable syntax, GAlign syntax, Traversable syntax)
               => ComparabilityRelation syntax (Record (FeatureVector ': fields1)) (Record (FeatureVector ': fields2)) -- ^ A relation on terms used to determine comparability and equality.
               -> (Term syntax (Record (FeatureVector ': fields1)) -> Term syntax (Record (FeatureVector ': fields2)) -> Bool) -- ^ A relation used to determine term equivalence.
               -> (forall a. TermF syntax (Record fields1) a -> label)
               -> (forall a. TermF syntax (Record fields2) a -> label)
               -> Term syntax (Record fields1)
               -> Term syntax (Record fields2)
               -> Diff syntax (Record fields1) (Record fields2)
decoratingWith comparability equivalence getLabel1 getLabel2 t1 t2 = stripDiff (diffTermsWith comparability equivalence (defaultFeatureVectorDecorator getLabel1 t1) (defaultFeatureVectorDecorator getLabel2 t2))

-- | Diff a pair of terms recurisvely, using the supplied continuation and 'ComparabilityRelation'.
diffTermsWith :: forall syntax fields1 fields2
              .  (Diffable syntax, GAlign syntax, Traversable syntax)
              => ComparabilityRelation syntax (Record (FeatureVector ': fields1)) (Record (FeatureVector ': fields2)) -- ^ A relation on terms used to determine comparability and equality.
              -> (Term syntax (Record (FeatureVector ': fields1)) -> Term syntax (Record (FeatureVector ': fields2)) -> Bool) -- ^ A relation used to determine term equivalence.
              -> Term syntax (Record (FeatureVector ': fields1)) -- ^ A term representing the old state.
              -> Term syntax (Record (FeatureVector ': fields2)) -- ^ A term representing the new state.
              -> Diff syntax (Record (FeatureVector ': fields1)) (Record (FeatureVector ': fields2)) -- ^ The resulting diff.
diffTermsWith comparable eqTerms t1 t2 = fromMaybe (replacing t1 t2) (runAlgorithm comparable eqTerms (diff t1 t2))

-- | Run an 'Algorithm' to completion in an 'Alternative' context using the supplied comparability & equivalence relations.
runAlgorithm :: forall syntax fields1 fields2 m result
             .  (Diffable syntax, GAlign syntax, Traversable syntax, Alternative m, Monad m)
             => ComparabilityRelation syntax (Record (FeatureVector ': fields1)) (Record (FeatureVector ': fields2)) -- ^ A relation on terms used to determine comparability and equality.
             -> (Term syntax (Record (FeatureVector ': fields1)) -> Term syntax (Record (FeatureVector ': fields2)) -> Bool) -- ^ A relation used to determine term equivalence.
             -> Algorithm
               (Term syntax (Record (FeatureVector ': fields1)))
               (Term syntax (Record (FeatureVector ': fields2)))
               (Diff syntax (Record (FeatureVector ': fields1)) (Record (FeatureVector ': fields2)))
               result
             -> m result
runAlgorithm comparable eqTerms = go
  where go :: forall result
           .  Algorithm
             (Term syntax (Record (FeatureVector ': fields1)))
             (Term syntax (Record (FeatureVector ': fields2)))
             (Diff syntax (Record (FeatureVector ': fields1)) (Record (FeatureVector ': fields2)))
             result
           -> m result
        go = iterFreerA (\ yield step -> case step of
          Diffing.Algorithm.Diff t1 t2 -> go (algorithmForTerms t1 t2) <|> pure (replacing t1 t2) >>= yield
          Linear (Term (In ann1 f1)) (Term (In ann2 f2)) -> merge (ann1, ann2) <$> galignWith (go . diffThese) f1 f2 >>= yield
          RWS as bs -> traverse (go . diffThese) (rws comparable eqTerms as bs) >>= yield
          Delete a -> yield (deleting a)
          Insert b -> yield (inserting b)
          Replace a b -> yield (replacing a b)
          Empty -> empty
          Alt a b -> yield a <|> yield b)

-- | Compute the label for a given term, suitable for inclusion in a _p_,_q_-gram.
getLabel :: HasField fields Category => TermF Syntax (Record fields) a -> (Category, Maybe Text)
getLabel (In h t) = (Info.category h, case t of
  Leaf s -> Just s
  _ -> Nothing)


-- | Test whether two terms are comparable by their Category.
comparableByCategory :: (HasField fields1 Category, HasField fields2 Category) => ComparabilityRelation syntax (Record fields1) (Record fields2)
comparableByCategory (In a _) (In b _) = category a == category b