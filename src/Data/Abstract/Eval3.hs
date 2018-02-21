{-# LANGUAGE MultiParamTypeClasses, Rank2Types, GADTs, TypeOperators, DefaultSignatures, UndecidableInstances #-}
{-# LANGUAGE TypeApplications #-}
module Data.Abstract.Eval3
( Eval
, EvalEnv
, Evaluatable(..)
, runEval
, runEvalEnv
-- , step
, MonadGC(..)
, MonadFail(..)
, Recursive(..)
, Base
) where

import Control.Monad.Effect.Reader
import Control.Monad.Effect.State
import Control.Monad.Effect.GC
import Control.Monad.Effect.Exception
import Control.Monad.Effect.Internal
import Control.Monad.Fail
import Data.Abstract.Environment
import Data.Abstract.FreeVariables
import Data.Abstract.Value
import Data.Functor.Classes
import Data.Proxy
import Data.Term
import Data.Functor.Foldable (Base, Recursive(..), project)
import Prelude hiding (fail)
import Control.Monad.Effect hiding (run)


-- a local and global environment binding variable names to addresses.
-- class EvalEnv v m where
--   askEnv :: m (Environment (LocationFor v) v)
--   localEnv :: (Environment (LocationFor v) v -> Environment (LocationFor v) v) -> m v -> m v
--
--   modifyEnv :: (Environment (LocationFor v) v -> Environment (LocationFor v) v) -> m ()
--   getEnv :: m (Environment (LocationFor v) v)
--
--   step :: forall term. (Eval term v m (Base term), Recursive term) => term -> m v
--
-- instance ( Reader (Environment (LocationFor v) v) :< fs
--          , State (Environment (LocationFor v) v) :< fs
--          )
--          => EvalEnv v (Eff fs) where
--   askEnv = ask
--   localEnv = local
--
--   modifyEnv f = get >>= put . f
--   getEnv = get
--
--   step = eval . project

data EvalEnv v where
  AskEnv :: EvalEnv (Environment (LocationFor v) v)
  LocalEnv :: (Environment (LocationFor v) v -> Environment (LocationFor v) v) -> EvalEnv v -> EvalEnv v

  ModifyEnv :: (Environment (LocationFor v) v -> Environment (LocationFor v) v) -> EvalEnv ()
  GetEnv :: EvalEnv (Environment (LocationFor v) v)

  -- Step :: (forall term. (Recursive term) => term) -> EvalEnv v

-- step :: forall term es v. (EvalEnv :< es, Eval (Base term) term :< es, Recursive term) => term -> Eff es v
-- step = eval . project

runEvalEnv :: Eff (EvalEnv ': es) v -> Eff es v
runEvalEnv = undefined

data Eval constr term v where
  Eval :: constr term -> Eval constr term v

runEval :: Evaluatable constr term a => Eff (Eval constr term ': es) a -> Eff es a
runEval (Val a) = pure a
runEval (E u q) = case decompose u of
  Right (Eval term)      -> eval term
  Left  u'       -> E u' $ tsingleton (runEval . apply q)

class Evaluatable constr term v where
  eval :: constr term -> Eff es v
  default eval :: (Exc Prelude.String :< es, Show1 constr) => (constr term -> Eff es v)
  eval expr = throwError $ "Eval unspecialized for " ++ liftShowsPrec (const (const id)) (const id) 0 expr ""

instance (Recursive t, Evaluatable (Base t) t v) => Evaluatable [] t v where
  eval = undefined

-- | The 'Eval' class defines the necessary interface for a term to be evaluated. While a default definition of 'eval' is given, instances with computational content must implement 'eval' to perform their small-step operational semantics.
-- class Monad m => Eval term v m constr where
--   eval :: constr term -> m v
--
--   default eval :: (MonadFail m, Show1 constr) => (constr term -> m v)
--   eval expr = fail $ "Eval unspecialized for " ++ liftShowsPrec (const (const id)) (const id) 0 expr ""

-- | If we can evaluate any syntax which can occur in a 'Union', we can evaluate the 'Union'.
-- instance (Monad m, Apply (Eval t v m) fs) => Eval t v m (Union fs) where
--   eval = apply (Proxy :: Proxy (Eval t v m)) eval
--
-- -- | Evaluating a 'TermF' ignores its annotation, evaluating the underlying syntax.
-- instance (Monad m, Eval t v m s) => Eval t v m (TermF s a) where
--   eval In{..} = eval termFOut

-- | '[]' is treated as an imperative sequence of statements/declarations s.t.:
--
--   1. Each statement’s effects on the store are accumulated;
--   2. Each statement can affect the environment of later statements (e.g. by yielding under 'localEnv'); and
--   3. Only the last statement’s return value is returned.
--
--   This also allows e.g. early returns to be implemented in the middle of a list, by means of a statement returning instead of yielding. Therefore, care must be taken by 'Eval' instances in general to yield and not simply return, or else they will unintentionally short-circuit control and skip the rest of the scope.
-- instance ( Monad m
--          , Ord (LocationFor v)
--          , AbstractValue v
--          , Recursive t
--          , FreeVariables t
--          , EvalEnv v m
--          , Eval t v m (Base t)
--
--          , Show (LocationFor v)
--          )
--          => Eval t v m [] where
--   eval []     = pure unit -- Return unit value if this is an empty list of terms
--   eval [x]    = step x    -- Return the value for the last term
--   eval (x:xs) = do
--     _ <- step @v x         -- Evaluate the head term
--     env <- getEnv @v       -- Get the global environment after evaluation since
--                            -- it might have been modified by the 'step'
--                            -- evaluation above ^.
--
--     -- Finally, evaluate the rest of the terms, but do so by calculating a new
--     -- environment each time where the free variables in those terms are bound
--     -- to the global environment.
--     localEnv (const (bindEnv (freeVariables1 xs) env)) (eval xs)
